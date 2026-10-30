import CoreML
import CryptoKit
import Foundation
import Vision

struct PoseKeypoint: Equatable {
    var point: CGPoint // normalized image coordinates, bottom-left origin
    var score: Float  // heatmap response, not a medical probability
}
struct UpperBodyPose {
    var nose: PoseKeypoint
    var neck: PoseKeypoint
    var rightShoulder: PoseKeypoint
    var leftShoulder: PoseKeypoint
    var rightElbow: PoseKeypoint?
    var leftElbow: PoseKeypoint?
}

/// Final-stage heatmaps + Part Affinity Fields from Lightweight OpenPose (Osokin 2018 / Cao 2017).
/// Selects the upper-body tree belonging to the ONE already observed face; does not invent missing joints.
enum OpenPoseDecoder {
    struct Grid {
        let values: MLMultiArray
        let channels: Int, height: Int, width: Int
        private let cs: Int, ys: Int, xs: Int
        init?(_ array: MLMultiArray) {
            let shape = array.shape.map(\.intValue), strides = array.strides.map(\.intValue)
            guard shape.count >= 3, shape.dropLast(3).allSatisfy({ $0 == 1 }) else { return nil }
            let i = shape.count - 3
            values = array; channels = shape[i]; height = shape[i + 1]; width = shape[i + 2]
            cs = strides[i]; ys = strides[i + 1]; xs = strides[i + 2]
            guard channels > 0, height > 1, width > 1 else { return nil }
        }
        func at(_ c: Int, _ x: Int, _ y: Int) -> Float {
            guard c >= 0, c < channels, x >= 0, x < width, y >= 0, y < height else { return 0 }
            let offset = c * cs + y * ys + x * xs
            switch values.dataType {
            case .float32: return values.dataPointer.assumingMemoryBound(to: Float.self)[offset]
            case .double: return Float(values.dataPointer.assumingMemoryBound(to: Double.self)[offset])
            case .float16: return Float(values.dataPointer.assumingMemoryBound(to: Float16.self)[offset])
            default: return 0
            }
        }
    }
    struct Peak {
        let x: Int, y: Int
        let score: Float
    }
    static func decode(heatmaps: MLMultiArray, pafs: MLMultiArray, face: CGRect, imageSize: CGSize) -> UpperBodyPose? {
        guard let heat = Grid(heatmaps), let paf = Grid(pafs), heat.channels == 19, paf.channels == 38,
              heat.width == paf.width, heat.height == paf.height, imageSize.width > 0, imageSize.height > 0 else { return nil }
        // Vision .scaleFit adds padding; undo it rather than stretching inferred anatomy.
        let input = CGSize(width: 456, height: 256)
        let scale = min(input.width / imageSize.width, input.height / imageSize.height)
        let content = CGSize(width: imageSize.width * scale / input.width, height: imageSize.height * scale / input.height)
        let padding = CGPoint(x: (1 - content.width) / 2, y: (1 - content.height) / 2)
        func point(_ peak: Peak) -> CGPoint {
            CGPoint(x: (CGFloat(peak.x) / CGFloat(heat.width) - padding.x) / content.width,
                    y: 1 - (CGFloat(peak.y) / CGFloat(heat.height) - padding.y) / content.height)
        }
        func keypoint(_ peak: Peak) -> PoseKeypoint { PoseKeypoint(point: point(peak), score: peak.score) }
        func peaks(_ channel: Int) -> [Peak] {
            var found: [Peak] = []
            for y in 0..<heat.height {
                for x in 0..<heat.width {
                    let value = heat.at(channel, x, y)
                    guard value.isFinite, value > 0.15,
                          value >= heat.at(channel, x - 1, y), value >= heat.at(channel, x + 1, y),
                          value >= heat.at(channel, x, y - 1), value >= heat.at(channel, x, y + 1) else { continue }
                    let peak = Peak(x: x, y: y, score: value), p = point(peak)
                    if (0.015...0.985).contains(p.x), (0.015...0.985).contains(p.y) { found.append(peak) }
                }
            }
            var selected: [Peak] = []
            for peak in found.sorted(by: { $0.score > $1.score }) {
                if selected.allSatisfy({ hypot(Double($0.x - peak.x), Double($0.y - peak.y)) >= 2 }) { selected.append(peak) }
                if selected.count == 8 { break }
            }
            return selected
        }
        // Same PAF channel layout, 10-sample line integral, 0.05 affinity and >80% agreement as upstream.
        func affinity(_ a: Peak, _ b: Peak, _ cx: Int, _ cy: Int) -> Float? {
            let dx = Float(b.x - a.x), dy = Float(b.y - a.y), length = hypot(dx, dy)
            guard length > 1 else { return nil }
            var sum: Float = 0, positive = 0
            for n in 0..<10 {
                let t = Float(n) / 9
                let x = Int((Float(a.x) + dx * t).rounded()), y = Int((Float(a.y) + dy * t).rounded())
                let agreement = (paf.at(cx, x, y) * dx + paf.at(cy, x, y) * dy) / length
                guard agreement.isFinite else { return nil }
                if agreement > 0.05 { positive += 1 }; sum += agreement
            }
            return positive >= 9 && sum > 0 ? sum / 10 : nil
        }
        let faceRegion = face.insetBy(dx: -face.width * 0.45, dy: -face.height * 0.25)
        let noses = peaks(0).filter { faceRegion.contains(point($0)) }
        let necks = peaks(1), rights = peaks(2), lefts = peaks(5)
        var best: (Peak, Peak, Peak, Peak, Float)?
        for nose in noses {
            for neck in necks {
                let np = point(neck)
                guard np.y < face.midY, abs(np.x - face.midX) < max(0.12, face.width),
                      let headPAF = affinity(neck, nose, 28, 29) else { continue }
                for right in rights {
                    guard let rpaf = affinity(neck, right, 12, 13) else { continue }
                    for left in lefts {
                        guard let lpaf = affinity(neck, left, 20, 21) else { continue }
                        let r = point(right), l = point(left)
                        guard r.x < np.x, l.x > np.x, l.x - r.x > 0.12,
                              abs(r.y - np.y) < 0.20, abs(l.y - np.y) < 0.20,
                              r.y < face.midY, l.y < face.midY else { continue }
                        let score = headPAF + rpaf + lpaf + nose.score + neck.score + right.score + left.score
                        if best == nil || score > best!.4 { best = (nose, neck, right, left, score) }
                    }
                }
            }
        }
        guard let (nose, neck, right, left, _) = best else { return nil }
        func elbow(_ shoulder: Peak, channel: Int, pafX: Int, pafY: Int) -> PoseKeypoint? {
            peaks(channel).compactMap { peak -> (Peak, Float)? in
                guard let a = affinity(shoulder, peak, pafX, pafY) else { return nil }; return (peak, a + peak.score)
            }.max(by: { $0.1 < $1.1 }).map { keypoint($0.0) }
        }
        return UpperBodyPose(nose: keypoint(nose), neck: keypoint(neck), rightShoulder: keypoint(right), leftShoulder: keypoint(left),
            rightElbow: elbow(right, channel: 3, pafX: 14, pafY: 15), leftElbow: elbow(left, channel: 6, pafX: 22, pafY: 23))
    }
}

final class OpenPoseDetector {
    private var visionModel: VNCoreMLModel?
    private let sourceOverride: URL?
    private let cacheOverride: URL?
    init(source: URL? = nil, cache: URL? = nil) { sourceOverride = source; cacheOverride = cache }
    func prepare() throws {
        guard visionModel == nil else { return }
        guard let source = sourceOverride ?? Bundle.main.url(forResource: "StillPose", withExtension: "mlmodel") else {
            throw NSError(domain: "Still.Posture", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少坐姿模型，请重新安装完整应用。"])
        }
        let hash = SHA256.hash(data: try Data(contentsOf: source)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let root = cacheOverride ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Still/PoseModels")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let compiled = root.appendingPathComponent("StillPose-\(hash).mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let temp = try MLModel.compileModel(at: source)
            defer { try? FileManager.default.removeItem(at: temp) }
            try FileManager.default.copyItem(at: temp, to: compiled)
        }
        let config = MLModelConfiguration(); config.computeUnits = .all
        visionModel = try VNCoreMLModel(for: MLModel(contentsOf: compiled, configuration: config))
    }
    func detect(in buffer: CVPixelBuffer, face: CGRect) throws -> UpperBodyPose? {
        try prepare()
        let request = VNCoreMLRequest(model: visionModel!)
        request.imageCropAndScaleOption = .scaleFit
        try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])
        let features = request.results as? [VNCoreMLFeatureValueObservation] ?? []
        guard let heat = features.first(where: { $0.featureName == "heatmaps" })?.featureValue.multiArrayValue,
              let paf = features.first(where: { $0.featureName == "pafs" })?.featureValue.multiArrayValue else { return nil }
        return OpenPoseDecoder.decode(heatmaps: heat, pafs: paf, face: face,
            imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
    }
}

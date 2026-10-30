import CoreML
import CoreVideo
import CryptoKit
import Foundation
import Testing
@testable import Still

struct OpenPoseTests {
    private func tensor(_ channels: Int) throws -> MLMultiArray {
        let value = try MLMultiArray(shape: [1, NSNumber(value: channels), 32, 57], dataType: .float32)
        value.dataPointer.initializeMemory(as: Float.self, repeating: 0, count: value.count)
        return value
    }
    private func set(_ t: MLMultiArray, _ channel: Int, _ x: Int, _ y: Int, _ v: Float) {
        t[[0, NSNumber(value: channel), NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: v)
    }
    private func fixture() throws -> (MLMultiArray, MLMultiArray) {
        let heat = try tensor(19), paf = try tensor(38)
        for (c,x,y) in [(0,28,12),(1,28,20),(2,18,20),(5,38,20)] { set(heat,c,x,y,0.9) }
        for y in 0..<32 { for x in 0..<57 { set(paf,12,x,y,-1); set(paf,20,x,y,1); set(paf,29,x,y,-1) } }
        return (heat,paf)
    }
    private let face = CGRect(x: 0.4, y: 0.5, width: 0.2, height: 0.2)
    @Test func binary16DecodingMatchesIEEE754() {
        let values: [(UInt16, Float)] = [
            (0x0000, 0),
            (0x8000, -0),
            (0x0001, 0x1p-24),
            (0x3555, 0.33325195),
            (0x3c00, 1),
            (0xc000, -2),
            (0x7bff, 65504)
        ]
        for (bits, expected) in values {
            #expect(OpenPoseDecoder.float16Value(bits) == expected)
        }
        #expect(OpenPoseDecoder.float16Value(0x7c00) == .infinity)
        #expect(OpenPoseDecoder.float16Value(0xfc00) == -.infinity)
        #expect(OpenPoseDecoder.float16Value(0x7e00).isNaN)
    }
    @Test @MainActor func manualCameraPauseSurvivesRestartInItsOwnSettingsDomain() {
        let name = "local.still.tests.pause." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = PostureMonitor(defaults: defaults)
        first.togglePause()
        #expect(first.paused)
        let reopened = PostureMonitor(defaults: defaults)
        #expect(reopened.paused)
        first.shutdown(); reopened.shutdown()
    }
    @Test func shouldersRequireMatchingHeatmapsAndPartAffinityFields() throws {
        let (heat,paf) = try fixture()
        let result = OpenPoseDecoder.decode(heatmaps: heat, pafs: paf, face: face, imageSize: CGSize(width: 456,height: 256))
        #expect(result != nil)
        #expect(result!.leftShoulder.point.x > result!.rightShoulder.point.x)
        #expect(result!.leftElbow == nil)
        for y in 0..<32 { for x in 0..<57 { set(paf,12,x,y,1) } }
        #expect(OpenPoseDecoder.decode(heatmaps: heat,pafs: paf,face: face,imageSize: CGSize(width: 456,height: 256)) == nil)
    }
    @Test func missingJointsAndUnrelatedFaceCannotProduceASkeleton() throws {
        let (heat,paf) = try fixture()
        #expect(OpenPoseDecoder.decode(heatmaps: heat,pafs: paf,face: CGRect(x: 0.8,y: 0.7,width: 0.1,height: 0.1),imageSize: CGSize(width:456,height:256)) == nil)
        set(heat,5,38,20,0.01)
        #expect(OpenPoseDecoder.decode(heatmaps: heat,pafs: paf,face: face,imageSize: CGSize(width:456,height:256)) == nil)
    }
    @Test func bundledModelHasRecordedDigestAndRejectsBlankImage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Resources/Models/StillPose.mlmodel")
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Resources/Models/SOURCE.json"))) as! [String:Any]
        let hash = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x",$0) }.joined()
        #expect(hash == record["modelSHA256"] as? String)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let model = OpenPoseDetector(source: source,cache: cache)
        try model.prepare()
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil,456,256,kCVPixelFormatType_32BGRA,[kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,&buffer) == kCVReturnSuccess)
        let pixel = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixel,[])
        memset(CVPixelBufferGetBaseAddress(pixel),128,CVPixelBufferGetBytesPerRow(pixel) * CVPixelBufferGetHeight(pixel))
        CVPixelBufferUnlockBaseAddress(pixel,[])
        #expect(try model.detect(in: pixel,face: face) == nil)
    }
}

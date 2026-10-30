import Foundation

/// Camera-normalized observations, not physical angles of the cervical spine.
public struct PostureSample: Equatable {
    public var hasShoulders: Bool
    public var time: Double
    public var faceHeight: Double
    public var shoulderWidth: Double
    public var neckHeight: Double
    public var headRoll: Double
    public var shoulderRoll: Double
    public var pitch: Double
    public var yaw: Double
    public var centerX: Double
    public var centerY: Double
    public var confidence: Double
    public init(time: Double, faceHeight: Double, shoulderWidth: Double, neckHeight: Double,
                headRoll: Double, shoulderRoll: Double, pitch: Double, yaw: Double = 0,
                centerX: Double = 0.5, centerY: Double = 0.4, confidence: Double = 1, hasShoulders: Bool = true) {
        self.hasShoulders = hasShoulders; self.time = time; self.faceHeight = faceHeight; self.shoulderWidth = shoulderWidth
        self.neckHeight = neckHeight; self.headRoll = headRoll; self.shoulderRoll = shoulderRoll
        self.pitch = pitch; self.yaw = yaw; self.centerX = centerX; self.centerY = centerY; self.confidence = confidence
    }
    public var usable: Bool {
        [time, faceHeight, shoulderWidth, neckHeight, headRoll, shoulderRoll, pitch, yaw, centerX, centerY, confidence].allSatisfy(\.isFinite)
        && faceHeight > 0.06 && (!hasShoulders || shoulderWidth > 0.12) && confidence >= 0.6 && abs(yaw) < 20 && abs(pitch) < 40
    }
}

public enum PostureIssue: String, CaseIterable {
    case headTilt, shoulderTilt, loweredHead, possibleForwardLean
    public var title: String {
        switch self {
        case .headTilt: return "持续歪头"
        case .shoulderTilt: return "肩线倾斜"
        case .loweredHead: return "持续低头"
        case .possibleForwardLean: return "疑似探头"
        }
    }
    public var playfulMessage: String {
        switch self {
        case .headTilt: return "脑袋不用歪，代码也不会自己变对。放松一下，回到舒服的位置。"
        case .shoulderTilt: return "肩膀怎么开始单边加班了？放松双肩，换个舒服的姿势。"
        case .loweredHead: return "下巴先别急着下班。抬眼看看屏幕，再活动一下脖子。"
        case .possibleForwardLean: return "屏幕不会跑，脖子不用先到场。靠回椅背，顺手把字放大点。"
        }
    }
}

public struct PostureAssessment {
    public enum State: Equatable { case uncalibrated, calibrating, unavailable, aligned, deviation }
    public var state: State
    public var issues: [PostureIssue] = []
    public var calibrationProgress: Double = 0
    public var deviationSeconds: Double = 0
    public var shouldAlert = false
}

/// Conservative, individually calibrated 2D cues. Thresholds are product heuristics, not clinical cutoffs.
public struct PostureEngine {
    public static let calibrationSeconds: Double = 4
    public private(set) var baseline: PostureSample?
    public private(set) var assessment = PostureAssessment(state: .uncalibrated)
    private var calibrating = false
    private var samples: [PostureSample] = []
    private var shoulderSamples: [PostureSample] = []
    private var lastTime: Double?
    private var badSince: Double?
    private var previousIssues: [PostureIssue] = []
    private var lastAlert: Double?
    public var sustainSeconds: Double = 12
    public var cooldownSeconds: Double = 60
    public init() {}

    public mutating func beginCalibration() {
        baseline = nil; calibrating = true; samples = []; resetEvidence()
        assessment = PostureAssessment(state: .calibrating)
    }
    public mutating func reset() { self = PostureEngine() }
    public mutating func resetEvidence() {
        lastTime = nil; badSince = nil; previousIssues = []; shoulderSamples = []; samples = []
    }
    public mutating func ingest(_ sample: PostureSample?) -> PostureAssessment {
        guard let s = sample, s.usable else {
            if calibrating { samples = [] }
            resetEvidence(); assessment = PostureAssessment(state: .unavailable)
            return assessment
        }
        if let lastTime, s.time <= lastTime || s.time - lastTime > 2 {
            badSince = nil; previousIssues = []; shoulderSamples = []; if calibrating { samples = [] }
        }
        lastTime = s.time
        if calibrating {
            // The reference itself must be frontal and approximately level.
            guard abs(s.headRoll) < 10, (!s.hasShoulders || abs(s.shoulderRoll) < 10), abs(s.pitch) < 20 else {
                samples = []; assessment = PostureAssessment(state: .calibrating); return assessment
            }
            if let first = samples.first,
               abs(s.faceHeight / first.faceHeight - 1) > 0.06 || abs(s.headRoll - first.headRoll) > 5
                || abs(s.pitch - first.pitch) > 6 || (s.hasShoulders && first.hasShoulders && abs(s.shoulderRoll - first.shoulderRoll) > 5)
                || abs(s.centerX - first.centerX) > 0.03 || abs(s.centerY - first.centerY) > 0.03 {
                samples = []
            }
            samples.append(s)
            let elapsed = s.time - samples[0].time
            assessment = PostureAssessment(state: .calibrating, calibrationProgress: min(1, elapsed / Self.calibrationSeconds))
            if elapsed >= Self.calibrationSeconds && samples.count >= 6 {
                func median(_ key: KeyPath<PostureSample, Double>) -> Double { let a = samples.map { $0[keyPath: key] }.sorted(); return a[a.count / 2] }
                let shoulders = samples.allSatisfy(\.hasShoulders)
                baseline = PostureSample(time: s.time, faceHeight: median(\.faceHeight), shoulderWidth: median(\.shoulderWidth),
                    neckHeight: median(\.neckHeight), headRoll: median(\.headRoll), shoulderRoll: median(\.shoulderRoll),
                    pitch: median(\.pitch), centerX: median(\.centerX), centerY: median(\.centerY), hasShoulders: shoulders)
                calibrating = false; samples = []; resetEvidence(); lastAlert = nil
                assessment = PostureAssessment(state: .aligned)
            }
            return assessment
        }
        guard baseline != nil else { assessment = PostureAssessment(state: .uncalibrated); return assessment }
        // Translation and common scale changes do not change roll/pitch or normalized body ratios.
        // Preserve the reference while the user moves naturally; do not learn sustained bad posture.
        if baseline?.hasShoulders == false {
            if s.hasShoulders, let b = baseline, abs(s.headRoll - b.headRoll) < 5,
               abs(s.pitch - b.pitch) < 5, abs(s.shoulderRoll) < 10 {
                if let first = shoulderSamples.first,
                   s.time - first.time > 8 || abs(s.shoulderRoll - first.shoulderRoll) > 4 { shoulderSamples = [] }
                shoulderSamples.append(s)
                if let first = shoulderSamples.first, s.time - first.time >= 4, shoulderSamples.count >= 6 {
                    func median(_ key: KeyPath<PostureSample, Double>) -> Double {
                        let values = shoulderSamples.map { $0[keyPath: key] }.sorted(); return values[values.count / 2]
                    }
                    baseline?.faceHeight = median(\.faceHeight)
                    baseline?.shoulderWidth = median(\.shoulderWidth)
                    baseline?.neckHeight = median(\.neckHeight)
                    baseline?.shoulderRoll = median(\.shoulderRoll)
                    baseline?.hasShoulders = true; shoulderSamples = []
                }
            } else { shoulderSamples = [] }
        }
        let b = baseline!
        let shoulders = s.hasShoulders && b.hasShoulders
        var issues: [PostureIssue] = []
        if abs(s.headRoll - b.headRoll) > 12 { issues.append(.headTilt) }
        if shoulders && abs(s.shoulderRoll - b.shoulderRoll) > 10 { issues.append(.shoulderTilt) }
        let headDrop = shoulders ? b.neckHeight / b.shoulderWidth - s.neckHeight / s.shoulderWidth : 0
        let pitchChange = s.pitch - b.pitch // Vision pitch is positive when nodding down.
        if shoulders ? (headDrop > 0.12 && pitchChange > 12) : pitchChange > 15 { issues.append(.loweredHead) }
        // Distance alone is insufficient: require head/shoulder ratio increase AND a second cue.
        let relativeHeadScale = shoulders ? (s.faceHeight / s.shoulderWidth) / (b.faceHeight / b.shoulderWidth) : 1
        if shoulders && relativeHeadScale > 1.20 && (headDrop > 0.10 || pitchChange > 10) { issues.append(.possibleForwardLean) }
        if issues.isEmpty {
            badSince = nil; previousIssues = []; assessment = PostureAssessment(state: .aligned)
        } else {
            if issues != previousIssues { badSince = s.time }
            previousIssues = issues
            let seconds = max(0, s.time - (badSince ?? s.time))
            let alert = seconds >= sustainSeconds && (lastAlert == nil || s.time - lastAlert! >= cooldownSeconds)
            if alert { lastAlert = s.time }
            assessment = PostureAssessment(state: .deviation, issues: issues, deviationSeconds: seconds, shouldAlert: alert)
        }
        return assessment
    }
}

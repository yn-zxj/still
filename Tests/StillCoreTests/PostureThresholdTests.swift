import Foundation
import Testing
@testable import StillCore

struct PostureThresholdTests {
    private func sample(_ time: Double) -> PostureSample {
        PostureSample(time: time, faceHeight: 0.18, shoulderWidth: 0.4, neckHeight: 0.22, headRoll: 0, shoulderRoll: 0, pitch: 0)
    }
    private func calibrated(_ thresholds: PostureThresholds = PostureThresholds(), shoulders: Bool = true) -> PostureEngine {
        var engine = PostureEngine(thresholds: thresholds); engine.beginCalibration()
        for n in 0...16 {
            var s = sample(Double(n) * 0.5); s.hasShoulders = shoulders
            _ = engine.ingest(s)
        }
        return engine
    }
    @Test func oldAndPartialSettingsKeepDefaultsAndCustomValuesRoundTrip() throws {
        let old = try JSONDecoder().decode(MonitorSettings.self, from: Data("{}".utf8))
        #expect(old.postureThresholds == PostureThresholds())
        let partial = try JSONDecoder().decode(MonitorSettings.self,
            from: Data(#"{"postureThresholds":{"headTiltDegrees":8,"sustainSeconds":3,"loweredHeadDrop":0.08}}"#.utf8))
        #expect(partial.postureThresholds.headTiltDegrees == 8)
        #expect(partial.postureThresholds.loweredHeadDrop == 0.08)
        #expect(partial.postureThresholds.cooldownSeconds == 60)
        #expect(try JSONDecoder().decode(MonitorSettings.self, from: JSONEncoder().encode(partial)) == partial)
    }
    @Test func invalidInputCannotSaveAndCorruptNumericSettingsHaveFiniteBounds() throws {
        for field in PostureThreshold.allCases {
            #expect(field.parsed("") == nil)
            #expect(field.parsed("NaN") == nil)
            #expect(field.parsed("inf") == nil)
            #expect(field.parsed(String(field.range.upperBound + 1)) == nil)
            #expect(field.parsed(String(field.range.lowerBound - 1)) == nil)
            #expect(field.normalized(.nan).isFinite)
            #expect(field.normalized(.infinity).isFinite)
        }
        #expect(PostureThreshold.observationGraceSeconds.parsed("1,5") == 1.5)
        #expect(PostureThreshold.headTiltDegrees.parsed("12.5") == nil)
        #expect(PostureThreshold.loweredHeadDrop.parsed("0.123") == nil)
        let value = try JSONDecoder().decode(PostureThresholds.self,
            from: Data(#"{"sustainSeconds":-20,"cooldownSeconds":9999,"loweredHeadDrop":0}"#.utf8))
        #expect(value.sustainSeconds == 1)
        #expect(value.cooldownSeconds == 600)
        #expect(value.loweredHeadDrop == 0.01)
    }
    @Test func angularAndRatioEditsChangeActualClassification() {
        let cases: [(PostureThreshold, Double, PostureIssue, (inout PostureSample) -> Void)] = [
            (.headTiltDegrees, 25, .headTilt, { $0.headRoll = 18 }),
            (.shoulderTiltDegrees, 25, .shoulderTilt, { $0.shoulderRoll = 18 }),
            (.loweredPitchDegrees, 25, .loweredHead, { $0.pitch = 18; $0.neckHeight -= 0.08 }),
            (.loweredHeadDrop, 0.30, .loweredHead, { $0.pitch = 18; $0.neckHeight -= 0.08 }),
            (.forwardScalePercent, 50, .possibleForwardLean, { $0.faceHeight *= 1.3; $0.pitch = 12 }),
            (.forwardPitchDegrees, 25, .possibleForwardLean, { $0.faceHeight *= 1.3; $0.pitch = 12 }),
            (.forwardHeadDrop, 0.30, .possibleForwardLean, { $0.faceHeight *= 1.3; $0.neckHeight -= 0.06 })
        ]
        for (field, value, issue, mutate) in cases {
            var original = calibrated(), s = sample(9); mutate(&s)
            #expect(original.ingest(s).issues.contains(issue))
            var settings = PostureThresholds(); settings[field] = value
            var customized = calibrated(settings)
            #expect(!customized.ingest(s).issues.contains(issue))
        }
        var settings = PostureThresholds(); settings.headOnlyPitchDegrees = 25
        var original = calibrated(shoulders: false), customized = calibrated(settings, shoulders: false)
        var s = sample(9); s.hasShoulders = false; s.pitch = 18
        #expect(original.ingest(s).issues.contains(.loweredHead))
        #expect(!customized.ingest(s).issues.contains(.loweredHead))
    }
    @Test func editedTimingControlsRealAlertsAndCooldown() {
        var settings = PostureThresholds(); settings.sustainSeconds = 2; settings.cooldownSeconds = 5
        var engine = calibrated(settings), times: [Double] = []
        for t in 9...16 {
            var s = sample(Double(t)); s.headRoll = 18
            if engine.ingest(s).shouldAlert { times.append(s.time) }
        }
        #expect(times == [11, 16])
        engine.reset()
        #expect(engine.baseline == nil)
        #expect(engine.thresholds == settings)
    }
    @Test func editsKeepCalibrationAndLastAlertButDiscardOldEvidence() {
        var engine = calibrated()
        for t in 9...21 { var s = sample(Double(t)); s.headRoll = 18; _ = engine.ingest(s) }
        #expect(engine.assessment.shouldAlert)
        let reference = engine.baseline
        var settings = PostureThresholds(); settings.sustainSeconds = 1; settings.cooldownSeconds = 10
        engine.updateThresholds(settings, at: 22)
        #expect(engine.baseline == reference)
        #expect(engine.assessment.deviationSeconds == 0)
        #expect(!engine.assessment.shouldAlert)
        #expect(engine.assessment.cooldownRemaining == 9)
        for t in 22...30 { var s = sample(Double(t)); s.headRoll = 18; #expect(!engine.ingest(s).shouldAlert) }
        var s = sample(31); s.headRoll = 18
        #expect(engine.ingest(s).shouldAlert)
    }
    @Test func editedRecognitionLimitsApplyToTheEngine() {
        var settings = PostureThresholds(); settings.maxYawDegrees = 30; settings.maxPitchDegrees = 50
        var original = calibrated(), customized = calibrated(settings), s = sample(9)
        s.yaw = 25; s.pitch = 45
        #expect(!s.usable)
        #expect(s.isUsable(with: settings))
        #expect(original.ingest(s).state == .unavailable)
        #expect(customized.ingest(s).state != .unavailable)
    }
    @Test func zeroGraceDiscardsUnknownEvidenceWithoutBlockingNormalFrameCadence() {
        var settings = PostureThresholds(); settings.observationGraceSeconds = 0; settings.sustainSeconds = 2
        var engine = calibrated(settings)
        for t in 9...10 { var s = sample(Double(t)); s.headRoll = 18; _ = engine.ingest(s) }
        _ = engine.ingest(nil, at: 10.5)
        var s = sample(11); s.headRoll = 18
        #expect(engine.ingest(s).deviationSeconds == 0)
        s.time = 12; #expect(!engine.ingest(s).shouldAlert)
        s.time = 13; #expect(engine.ingest(s).shouldAlert)
    }
}

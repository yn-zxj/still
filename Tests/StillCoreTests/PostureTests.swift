import Foundation
import Testing
@testable import StillCore

struct PostureTests {
    func sample(_ time: Double) -> PostureSample {
        PostureSample(time: time, faceHeight: 0.18, shoulderWidth: 0.4, neckHeight: 0.22,
                      headRoll: 0, shoulderRoll: 0, pitch: 0)
    }
    func calibrated() -> PostureEngine {
        var engine = PostureEngine(); engine.beginCalibration()
        for n in 0...16 { _ = engine.ingest(sample(Double(n) * 0.5)) }
        return engine
    }
    @Test func noAssessmentBeforeStableFourSecondCalibration() {
        var engine = PostureEngine()
        #expect(engine.ingest(sample(0)).state == .uncalibrated)
        engine.beginCalibration()
        for n in 0...7 { _ = engine.ingest(sample(Double(n) * 0.5)) }
        #expect(engine.baseline == nil)
        #expect(engine.ingest(sample(4)).state == .aligned)
        #expect(engine.baseline != nil)
    }
    @Test func missingPeopleAndMotionResetCalibration() {
        var engine = PostureEngine(); engine.beginCalibration()
        for n in 0...5 { _ = engine.ingest(sample(Double(n) * 0.5)) }
        _ = engine.ingest(nil)
        for n in 6...12 { _ = engine.ingest(sample(Double(n) * 0.5)) }
        #expect(engine.baseline == nil)
        var moved = sample(6.5); moved.centerX += 0.08
        #expect(engine.ingest(moved).calibrationProgress == 0)
        #expect(engine.baseline == nil)
    }
    @Test func lowConfidenceTurnedFacesAndInvalidSamplesCannotAlert() {
        for mutation in [0, 1, 2] {
            var engine = calibrated()
            for t in 9...40 {
                var s = sample(Double(t)); s.headRoll = 20
                if mutation == 0 { s.confidence = 0.3 }
                if mutation == 1 { s.yaw = 35 }
                if mutation == 2 { s.faceHeight = .nan }
                let result = engine.ingest(s)
                #expect(result.state == .unavailable)
                #expect(!result.shouldAlert)
            }
        }
    }
    @Test func shortGlanceIsIgnoredAndSustainedTiltAlertsAfterTwelveSeconds() {
        var engine = calibrated()
        for t in 9...20 {
            var s = sample(Double(t)); s.headRoll = 18
            #expect(!engine.ingest(s).shouldAlert)
        }
        var s = sample(21); s.headRoll = 18
        let result = engine.ingest(s)
        #expect(result.shouldAlert)
        #expect(result.issues == [.headTilt])
        #expect(!engine.ingest(s).shouldAlert) // Repeated timestamp resets evidence.
    }
    @Test func noPersonAndFrameGapCannotAccumulateBadPostureTime() {
        var engine = calibrated()
        for t in 9...19 { var s = sample(Double(t)); s.headRoll = 20; _ = engine.ingest(s) }
        _ = engine.ingest(nil)
        var s = sample(40); s.headRoll = 20
        #expect(!engine.ingest(s).shouldAlert)
        #expect(engine.assessment.deviationSeconds == 0)
        s.time = 50
        #expect(engine.ingest(s).deviationSeconds == 0)
    }
    @Test func wholeBodyDistanceAndFaceSizeAloneDoNotImplyForwardHead() {
        var engine = calibrated()
        var s = sample(9)
        s.faceHeight *= 1.15; s.shoulderWidth *= 1.15; s.neckHeight *= 1.15
        #expect(engine.ingest(s).state == .aligned)
        s = sample(10); s.faceHeight *= 1.25
        #expect(!engine.ingest(s).issues.contains(.possibleForwardLean))
        s.time = 11; s.pitch = 15
        #expect(engine.ingest(s).issues.contains(.possibleForwardLean))
    }
    @Test func headOnlyCalibrationWorksWithoutInventingShoulderMeasurements() {
        var engine = PostureEngine(); engine.beginCalibration()
        func face(_ t: Double) -> PostureSample {
            var s = sample(t); s.hasShoulders = false; s.shoulderWidth = 0; s.neckHeight = 0; return s
        }
        for n in 0...16 { _ = engine.ingest(face(Double(n) * 0.5)) }
        #expect(engine.baseline?.hasShoulders == false)
        #expect(engine.assessment.state == .aligned)
        for t in 9...21 {
            var s = face(Double(t)); s.headRoll = 20; s.shoulderRoll = 30; s.faceHeight *= 1.25
            let result = engine.ingest(s)
            #expect(!result.issues.contains(.shoulderTilt))
            #expect(!result.issues.contains(.possibleForwardLean))
        }
        #expect(engine.assessment.shouldAlert)
        #expect(engine.assessment.issues == [.headTilt])
    }
    @Test func missingShouldersDoNotInvalidateHeadCalibrationOrDivideByZero() {
        var engine = PostureEngine(); engine.beginCalibration()
        for n in 0...16 {
            var s = sample(Double(n) * 0.5)
            if n % 2 == 0 { s.hasShoulders = false; s.shoulderWidth = 0; s.neckHeight = 0 }
            _ = engine.ingest(s)
        }
        #expect(engine.baseline?.hasShoulders == false)
        var s = sample(9); s.pitch = 20; s.hasShoulders = false; s.shoulderWidth = 0
        let result = engine.ingest(s)
        #expect(result.issues == [.loweredHead])
        #expect(result.deviationSeconds.isFinite)
    }
    @Test func lookingUpIsNotClassifiedAsLookingDown() {
        var engine = calibrated(); var s = sample(9)
        s.neckHeight -= 0.08; s.pitch = -20
        #expect(!engine.ingest(s).issues.contains(.loweredHead))
        s.time = 10; s.pitch = 20
        #expect(engine.ingest(s).issues.contains(.loweredHead))
    }
    @Test func normalTranslationAndDistanceChangesKeepTheCalibration() {
        var engine = calibrated(); var s = sample(9)
        s.shoulderWidth *= 1.4; s.faceHeight *= 1.4; s.neckHeight *= 1.4
        s.centerX += 0.2; s.centerY -= 0.2
        #expect(engine.ingest(s).state == .aligned)
        #expect(!engine.assessment.shouldAlert)
    }
    @Test func reliableShouldersCanJoinAnExistingHeadReferenceWithoutRecalibrating() {
        var engine = PostureEngine(); engine.beginCalibration()
        for n in 0...8 {
            var s = sample(Double(n) * 0.5); s.hasShoulders = false; s.shoulderWidth = 0; s.neckHeight = 0
            _ = engine.ingest(s)
        }
        #expect(engine.baseline?.hasShoulders == false)
        for n in 9...18 { _ = engine.ingest(sample(Double(n) * 0.5)) }
        #expect(engine.baseline?.hasShoulders == true)
        #expect(engine.baseline?.headRoll == 0)
        #expect(engine.assessment.state == .aligned)
    }
    @Test func automaticShoulderReferenceCannotBridgeAnUnobservedGap() {
        var engine = PostureEngine(); engine.beginCalibration()
        for n in 0...8 {
            var s = sample(Double(n) * 0.5); s.hasShoulders = false; s.shoulderWidth = 0
            _ = engine.ingest(s)
        }
        for n in 9...14 { _ = engine.ingest(sample(Double(n) * 0.5)) }
        _ = engine.ingest(sample(10))
        #expect(engine.baseline?.hasShoulders == false)
    }
    @Test func headOnlyDistanceAndPositionChangesDoNotRequireAnotherCalibration() {
        var engine = PostureEngine(); engine.beginCalibration()
        for n in 0...8 {
            var s = sample(Double(n) * 0.5); s.hasShoulders = false; s.shoulderWidth = 0
            _ = engine.ingest(s)
        }
        for scale in [0.55, 1.2, 1.8] {
            var s = sample(10 + scale); s.hasShoulders = false; s.shoulderWidth = 0
            s.faceHeight *= scale; s.centerX += 0.22; s.centerY -= 0.2
            #expect(engine.ingest(s).state == .aligned)
            #expect(engine.baseline != nil)
        }
    }
    @Test func distanceChangesCannotResetEvidenceOrLearnSustainedBadPosture() {
        var engine = calibrated()
        for t in 9...21 {
            var s = sample(Double(t)); s.headRoll = 20
            let scale = t % 2 == 0 ? 0.6 : 1.5
            s.faceHeight *= scale; s.shoulderWidth *= scale; s.neckHeight *= scale
            _ = engine.ingest(s)
        }
        #expect(engine.assessment.shouldAlert)
        #expect(engine.baseline?.headRoll == 0)
    }
    @Test func alertCooldownAndRecoveryWork() {
        var engine = calibrated(); var alerts = 0
        for t in 9...100 {
            var s = sample(Double(t)); s.shoulderRoll = 15
            if engine.ingest(s).shouldAlert { alerts += 1 }
        }
        #expect(alerts == 2)
        #expect(engine.ingest(sample(101)).state == .aligned)
        #expect(engine.assessment.issues.isEmpty)
        engine.reset()
        #expect(engine.baseline == nil)
    }
    @Test func aSecondFluctuatingIssueCannotResetPersistentTilt() {
        var engine = calibrated()
        for t in 9...21 {
            var s = sample(Double(t)); s.headRoll = 20; s.shoulderRoll = t % 2 == 0 ? 15 : 0
            _ = engine.ingest(s)
        }
        #expect(engine.assessment.shouldAlert)
        #expect(engine.assessment.alertIssue == .headTilt)
        #expect(engine.assessment.deviationSeconds == 12)
    }
    @Test func reminderMustDescribeTheMatureIssueInsteadOfANewHigherPriorityIssue() {
        var engine = calibrated()
        for t in 9...20 { var s = sample(Double(t)); s.shoulderRoll = 15; _ = engine.ingest(s) }
        var s = sample(21); s.shoulderRoll = 15; s.headRoll = 20
        let result = engine.ingest(s)
        #expect(result.shouldAlert)
        #expect(result.issues.first == .headTilt)
        #expect(result.alertIssue == .shoulderTilt)
        #expect(result.cooldownRemaining == 60)
        s.time = 22
        #expect(engine.ingest(s).cooldownRemaining == 59)
    }
    @Test func shortUnknownFramePausesEvidenceWithoutCountingTheGap() {
        var engine = calibrated()
        for t in 9...18 { var s = sample(Double(t)); s.headRoll = 20; _ = engine.ingest(s) }
        #expect(engine.assessment.deviationSeconds == 9)
        #expect(!engine.ingest(nil, at: 18.5).shouldAlert)
        var s = sample(19); s.headRoll = 20
        #expect(engine.ingest(s).deviationSeconds == 9)
        for t in 20...21 { s.time = Double(t); #expect(!engine.ingest(s).shouldAlert) }
        s.time = 22
        #expect(engine.ingest(s).shouldAlert)
    }
    @Test func repeatedUnknownFramesCannotKeepOldEvidenceAlive() {
        var engine = calibrated()
        for t in 9...19 { var s = sample(Double(t)); s.headRoll = 20; _ = engine.ingest(s) }
        for n in 1...8 { #expect(!engine.ingest(nil, at: 19 + Double(n) * 0.5).shouldAlert) }
        var s = sample(23.5); s.headRoll = 20
        #expect(engine.ingest(s).deviationSeconds == 0)
        #expect(engine.baseline != nil)
    }
    @Test func missingShouldersPauseOnlyShoulderEvidenceAndCannotTriggerAnAlert() {
        var engine = calibrated()
        for t in 9...20 { var s = sample(Double(t)); s.shoulderRoll = 15; _ = engine.ingest(s) }
        var s = sample(20.5); s.hasShoulders = false; s.shoulderWidth = 0
        #expect(!engine.ingest(s).shouldAlert)
        s = sample(21); s.shoulderRoll = 15
        #expect(engine.ingest(s).deviationSeconds == 11)
        s.time = 22
        #expect(engine.ingest(s).alertIssue == .shoulderTilt)
    }
    @Test func differentShortMovementsAndRecoveryCannotCombineIntoAnAlert() {
        var engine = calibrated()
        for t in 9...16 { var s = sample(Double(t)); s.headRoll = 20; #expect(!engine.ingest(s).shouldAlert) }
        for t in 17...24 { var s = sample(Double(t)); s.shoulderRoll = 15; #expect(!engine.ingest(s).shouldAlert) }
        _ = engine.ingest(sample(25))
        var s = sample(26); s.shoulderRoll = 15
        #expect(engine.ingest(s).deviationSeconds == 0)
    }
    @Test func allReminderTypesHaveDistinctRotatingAndGentleCopy() {
        var rotation = PostureMessageRotation()
        var playful = Set<String>(), gentle = Set<String>()
        for issue in PostureIssue.allCases {
            let messages = (0..<3).map { _ in rotation.message(for: issue, playful: true) }
            #expect(Set(messages).count == 3)
            #expect(rotation.message(for: issue, playful: true) == messages.first)
            playful.formUnion(messages)
            gentle.insert(rotation.message(for: issue, playful: false))
        }
        #expect(playful.count == 12)
        #expect(gentle.count == 4)
    }
    @Test func featureSettingsMigrateAndPersistWithoutEnablingCamera() throws {
        let old = try JSONDecoder().decode(MonitorSettings.self, from: Data("{}".utf8))
        #expect(!old.postureEnabled)
        #expect(old.posturePlayful)
        #expect(old.automaticUpdateChecks)
        var enabled = old; enabled.postureEnabled = true; enabled.posturePlayful = false; enabled.automaticUpdateChecks = false
        #expect(try JSONDecoder().decode(MonitorSettings.self, from: JSONEncoder().encode(enabled)) == enabled)
    }
    @Test func versionsCompareNumericallyAndRejectPrereleases() {
        #expect(ReleaseVersion("v0.10.0")! > ReleaseVersion("0.4.9")!)
        #expect(ReleaseVersion("0.4") == ReleaseVersion("0.4.0"))
        #expect(ReleaseVersion("v0.4.0-beta.1") == nil)
        #expect(ReleaseVersion("../0.4.0") == nil)
        #expect(ReleaseVersion("1..2") == nil)
        #expect(ReleaseVersion("-1.2.0") == nil)
    }
}

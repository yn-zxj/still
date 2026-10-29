import Foundation
import Testing
@testable import StillCore

struct CourseTests {
    func sample(_ t: Double) -> ActivitySample { .init(date: Date(timeIntervalSince1970: t), monotonic: t, idleSeconds: 0, available: true) }
    func catalog(filename: String = "lesson.mp4") -> Data {
        Data("""
        [{"schemaVersion":1,"id":"test","title":"自制测试课程","source":{"application":"测试"},"displayDurationMinutes":1,"difficulty":"简单","description":"测试","actions":[{"order":1,"phase":"练习","name":"未补齐动作","quantityText":null}],"actionsComplete":false,"media":{"filename":"\(filename)"}}]
        """.utf8)
    }
    @Test func catalogPreservesMissingFields() throws {
        let c = try Course.decodeCatalog(catalog())[0]
        #expect(c.contraindications == nil)
        #expect(c.source.provider == nil)
        #expect(!c.actionsComplete)
    }
    @Test func rejectsPathTraversalAndDuplicateIDs() {
        #expect(throws: CourseError.self) { try Course.decodeCatalog(catalog(filename: "../private.mp4")) }
        #expect(throws: CourseError.self) { try Course.decodeCatalog(catalog(filename: "/tmp/test.mp4")) }
        let one = String(data: catalog(), encoding: .utf8)!.dropFirst().dropLast()
        #expect(throws: CourseError.self) { try Course.decodeCatalog(Data("[\(one),\(one)]".utf8)) }
    }
    @Test func playbackIgnoresPauseSeekAndLongGap() {
        var p = CourseProgress(duration: 30)
        p.observe(position: 1, playing: true)
        p.observe(position: 2, playing: false)
        p.observe(position: 20, playing: true)
        p.observe(position: 21, playing: true)
        #expect(p.elapsed == 2)
        #expect(!p.completed)
        p.observe(position: .nan, playing: true)
        #expect(p.elapsed == 2)
    }
    @Test func guidedRestDoesNotCompleteOnWallClock() {
        var engine = UsageEngine(); engine.tick(sample(0)); engine.tick(sample(10))
        engine.startGuidedRest(sample(10), duration: 5)
        engine.tick(sample(200))
        #expect(engine.restRemaining == 5)
        #expect(engine.breaks.last?.outcome == .inProgress)
        engine.updateGuidedRest(elapsed: 2, completed: false, sample: sample(201))
        #expect(engine.restRemaining == 3)
        engine.interruptRest(sample(202))
        #expect(engine.breaks.last?.outcome == .interrupted)
        #expect(!engine.guidedRest)
    }
    @Test func guidedCompletionRequiresPlaybackEvidence() {
        var e = UsageEngine(); e.startGuidedRest(sample(0), duration: 10)
        e.updateGuidedRest(elapsed: 1, completed: true, sample: sample(10))
        #expect(e.completionSerial == 0)
        e.updateGuidedRest(elapsed: 10, completed: true, sample: sample(20))
        #expect(e.completionSerial == 1)
        #expect(e.breaks.last?.outcome == .completed)
        #expect(!e.guidedRest)
        e.updateGuidedRest(elapsed: 10, completed: true, sample: sample(21))
        #expect(e.completionSerial == 1)
    }
    @Test func heartRateSupports8And16BitAndContact() {
        #expect(HeartRateMeasurement.decode(Data([0, 72]))?.bpm == 72)
        #expect(HeartRateMeasurement.decode(Data([1, 4, 1]))?.bpm == 260)
        #expect(HeartRateMeasurement.decode(Data([6, 72]))?.contactDetected == true)
        #expect(HeartRateMeasurement.decode(Data([4, 72])) == nil)
        #expect(HeartRateMeasurement.decode(Data([0, 0])) == nil)
        #expect(HeartRateMeasurement.decode(Data([1, 255, 255])) == nil)
    }
    @Test func heartRateRejectsTruncatedOptionalData() {
        for bytes: [UInt8] in [[], [0], [1,72], [8,72], [16,72,1], [32,72], [0,72,7]] { #expect(HeartRateMeasurement.decode(Data(bytes)) == nil) }
        #expect(HeartRateMeasurement.decode(Data([24,72,0,0,1,4]))?.bpm == 72)
    }
    @Test func watchCommandsAreBoundToCurrentSession() {
        let id = UUID(); let token = String(id.uuidString.prefix(8))
        #expect(WatchProtocol.command(Data("\(token)|pause".utf8), sessionID: id) == .pause)
        #expect(WatchProtocol.command(Data("\(token)|end".utf8), sessionID: nil) == nil)
        #expect(WatchProtocol.command(Data("DEADBEEF|resume".utf8), sessionID: id) == nil)
        #expect(WatchProtocol.command(Data("\(token)|other".utf8), sessionID: id) == nil)
    }
}

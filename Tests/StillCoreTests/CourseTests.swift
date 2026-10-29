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
        #expect(c.coverURL == nil)
        #expect(!c.actionsComplete)
        #expect(c.actions[0].thumbnail == nil)
    }
    @Test func decodesThumbnailWithoutChangingActionOrder() throws {
        let data = String(data: catalog(), encoding: .utf8)!
            .replacingOccurrences(of: "\"quantityText\":null", with: "\"quantityText\":null,\"thumbnail\":\"action.png\"")
        let action = try Course.decodeCatalog(Data(data.utf8))[0].actions[0]
        #expect(action.order == 1)
        #expect(action.thumbnail == "action.png")
        #expect(action.quantityText == nil)
    }
    @Test func rejectsUnsafeThumbnailPathsAndReservedCatalogName() throws {
        for path in ["../action.png", "/tmp/action.png", "courses.json", "..", ""] {
            var records = try #require(JSONSerialization.jsonObject(with: catalog()) as? [[String: Any]])
            var actions = try #require(records[0]["actions"] as? [[String: Any]])
            actions[0]["thumbnail"] = path; records[0]["actions"] = actions
            let data = try JSONSerialization.data(withJSONObject: records)
            #expect(throws: CourseError.self) { try Course.decodeCatalog(data) }
        }
    }
    @Test func rejectsPathTraversalAndDuplicateIDs() {
        #expect(throws: CourseError.self) { try Course.decodeCatalog(catalog(filename: "../private.mp4")) }
        #expect(throws: CourseError.self) { try Course.decodeCatalog(catalog(filename: "/tmp/test.mp4")) }
        let one = String(data: catalog(), encoding: .utf8)!.dropFirst().dropLast()
        #expect(throws: CourseError.self) { try Course.decodeCatalog(Data("[\(one),\(one)]".utf8)) }
    }
    @Test func remoteOnlyMediaAndImagesRoundTrip() throws {
        var records = try #require(JSONSerialization.jsonObject(with: catalog()) as? [[String: Any]])
        records[0]["media"] = ["url": "https://cdn.example.test/video.mp4?version=2"]
        records[0]["coverURL"] = "https://cdn.example.test/cover.jpg"
        var actions = try #require(records[0]["actions"] as? [[String: Any]])
        actions[0]["thumbnailURL"] = "https://cdn.example.test/action.jpg"
        records[0]["actions"] = actions
        let courses = try Course.decodeCatalog(JSONSerialization.data(withJSONObject: records))
        #expect(courses[0].coverURL?.url.path == "/cover.jpg")
        #expect(courses[0].media?.filename == nil)
        #expect(courses[0].actions[0].thumbnailURL?.url.host == "cdn.example.test")
        #expect(try Course.decodeCatalog(JSONEncoder().encode(courses)) == courses)
    }
    @Test func localMediaWinsAndMissingFileFallsBackToRemote() throws {
        let media = try JSONDecoder().decode(Course.Media.self, from: Data("""
        {"filename":"lesson.mp4","url":"https://cdn.example.test/lesson.mp4"}
        """.utf8))
        let root = URL(fileURLWithPath: "/tmp/course-test")
        #expect(media.playbackURL(in: root, fileExists: { _ in true }) == root.appendingPathComponent("lesson.mp4"))
        #expect(media.playbackURL(in: root, fileExists: { _ in false }) == media.url?.url)
        let localOnly = try Course.decodeCatalog(catalog())[0].media!
        #expect(localOnly.playbackURL(in: root, fileExists: { _ in false }) == nil)
    }
    @Test func rejectsInsecureOrCredentialBearingRemoteResources() throws {
        for invalid in ["http://cdn.example.test/a.mp4", "file:///tmp/a.mp4", "//cdn.example.test/a.mp4", "https:///", "https://demo@cdn.example.test/a.mp4", "https://cdn.example.test/a.mp4#fragment", "https://cdn.example.test/a b.mp4", "https://cdn.example.test:0/a.mp4", "https://cdn.example.test:99999/a.mp4", "https://cdn.example.test/\na.mp4"] {
            #expect(throws: CourseError.self) { try HTTPSResourceURL(invalid) }
            var records = try #require(JSONSerialization.jsonObject(with: catalog()) as? [[String: Any]])
            records[0]["media"] = ["url": invalid]
            #expect(throws: CourseError.self) { try Course.decodeCatalog(JSONSerialization.data(withJSONObject: records)) }
            records[0]["media"] = ["filename": "lesson.mp4"]
            var actions = try #require(records[0]["actions"] as? [[String: Any]])
            actions[0]["thumbnailURL"] = invalid; records[0]["actions"] = actions
            #expect(throws: CourseError.self) { try Course.decodeCatalog(JSONSerialization.data(withJSONObject: records)) }
            records[0]["actions"] = []; records[0]["coverURL"] = invalid
            #expect(throws: CourseError.self) { try Course.decodeCatalog(JSONSerialization.data(withJSONObject: records)) }
        }
    }
    @Test func emptyMediaIsInvalidButUnprovidedMediaIsAllowed() throws {
        var records = try #require(JSONSerialization.jsonObject(with: catalog()) as? [[String: Any]])
        records[0]["media"] = [:] as [String: String]
        #expect(throws: CourseError.self) { try Course.decodeCatalog(JSONSerialization.data(withJSONObject: records)) }
        records[0].removeValue(forKey: "media")
        #expect(try Course.decodeCatalog(JSONSerialization.data(withJSONObject: records))[0].media == nil)
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

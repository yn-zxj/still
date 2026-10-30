import Foundation
import Testing
@testable import Still
import StillCore

@MainActor
struct CourseManagementTests {
    private func record(_ id: String, media: [String: String], title: String = "自制课程") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": id, "title": title, "media": media])
    }
    @Test func minimalCourseAndJSONStringRoundTripWithoutActions() throws {
        let data = try record("web", media: ["webpage": "https://www.bilibili.com/video/BV1234567890"])
        let course = try Course.decodeCatalog(data)[0]
        #expect(course.actions.isEmpty)
        #expect(course.description.isEmpty)
        #expect(course.preparation == nil)
        #expect(course.media?.webpage?.url.host == "www.bilibili.com")
        let wrapped = try JSONEncoder().encode(String(decoding: data, as: UTF8.self))
        #expect(try Course.decodeCatalog(wrapped) == [course])
        #expect(try Course.decodeCatalog(JSONEncoder().encode([course])) == [course])
    }
    @Test func mergedImportsPreserveOtherCoursesAndNamespaceVideoFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source"), root = base.appendingPathComponent("installed")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("fixture-one".utf8).write(to: source.appendingPathComponent("same.mp4"))
        try CourseLibrary.merge(data: record("one", media: ["filename": "same.mp4"]), source: source, root: root)
        try Data("fixture-two".utf8).write(to: source.appendingPathComponent("same.mp4"))
        try CourseLibrary.merge(data: record("two", media: ["filename": "same.mp4"]), source: source, root: root)
        let json = root.appendingPathComponent("courses.json")
        var courses = try Course.decodeCatalog(Data(contentsOf: json))
        #expect(courses.count == 2)
        let first = try #require(courses[0].media?.filename), second = try #require(courses[1].media?.filename)
        #expect(first != second)
        #expect(try String(contentsOf: root.appendingPathComponent(first)) == "fixture-one")
        #expect(try String(contentsOf: root.appendingPathComponent(second)) == "fixture-two")
        try CourseLibrary.merge(data: record("two", media: ["webpage": "https://example.test/course"], title: "新标题"), source: source, root: root)
        courses = try Course.decodeCatalog(Data(contentsOf: json))
        #expect(courses.count == 2)
        #expect(courses[1].title == "新标题")
        let before = try Data(contentsOf: json)
        #expect(throws: CourseError.self) {
            try CourseLibrary.merge(data: record("bad", media: ["filename": "missing.mp4"]), source: source, root: root)
        }
        #expect(try Data(contentsOf: json) == before)
        let library = CourseLibrary(isUITest: true, rootOverride: root)
        try library.remove(courses[0])
        #expect(library.courses.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(first).path))
    }
    @Test func bilibiliUsesOfficialPlayerAndPreservesOriginalURL() throws {
        let data = try record("bili", media: ["webpage": "https://www.bilibili.com/video/BV1234567890?p=2"])
        let media = try #require(Course.decodeCatalog(data)[0].media)
        let player = try #require(media.webPlaybackURL)
        #expect(player.host == "player.bilibili.com")
        let query = URLComponents(url: player, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "bvid", value: "BV1234567890")))
        #expect(query.contains(URLQueryItem(name: "page", value: "2")))
        #expect(media.webpage?.url.host == "www.bilibili.com")
        let other = try #require(Course.decodeCatalog(record("other", media: ["webpage": "https://bilibili.com.example.test/video/BV1234567890"]))[0].media)
        #expect(other.webPlaybackURL?.host == "bilibili.com.example.test")
    }

    @Test func coursesAreOptionalAndSettingSurvivesRestart() throws {
        var settings = MonitorSettings()
        #expect(!settings.coursesEnabled)
        settings.coursesEnabled = true
        #expect(try JSONDecoder().decode(MonitorSettings.self, from: JSONEncoder().encode(settings)).coursesEnabled)
        #expect(!(try JSONDecoder().decode(MonitorSettings.self, from: Data("{}".utf8))).coursesEnabled)
    }
}

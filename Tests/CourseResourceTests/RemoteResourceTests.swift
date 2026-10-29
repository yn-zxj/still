import AppKit
import Foundation
import Testing
@testable import Still
import StillCore

private final class ImageProtocol: URLProtocol {
    static var count = 0
    static var status = 200
    static var payload = Data()
    static var contentLength: Int?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(Self.contentLength ?? Self.payload.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor
struct RemoteResourceTests {
    private func imageData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
    private func loader(payload: Data, status: Int = 200, contentLength: Int? = nil) -> RemoteCourseImages {
        ImageProtocol.count = 0; ImageProtocol.payload = payload; ImageProtocol.status = status; ImageProtocol.contentLength = contentLength
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ImageProtocol.self]
        return RemoteCourseImages(session: URLSession(configuration: config))
    }
    @Test func imageDownloadsDecodeAndReuseMemoryCache() async throws {
        let images = loader(payload: try imageData())
        let resource = try HTTPSResourceURL("https://example.test/action.png")
        let first = await images.image(for: resource)
        let second = await images.image(for: resource)
        #expect(first != nil)
        #expect(first === second)
        #expect(ImageProtocol.count == 1)
    }
    @Test func serverErrorsAndInvalidImagesRemainUnavailable() async throws {
        let resource = try HTTPSResourceURL("https://example.test/action.png")
        let rejected = loader(payload: try imageData(), status: 403)
        #expect(await rejected.image(for: resource) == nil)
        let invalid = loader(payload: Data("not an image".utf8))
        #expect(await invalid.image(for: resource) == nil)
        let tooLarge = loader(payload: try imageData(), contentLength: 9 * 1024 * 1024)
        #expect(await tooLarge.image(for: resource) == nil)
    }
    @Test func failedImageCanBeRetriedWithoutRestart() async throws {
        let images = loader(payload: Data())
        let resource = try HTTPSResourceURL("https://example.test/action.png")
        #expect(await images.image(for: resource) == nil)
        ImageProtocol.payload = try imageData()
        #expect(await images.image(for: resource) != nil)
        #expect(ImageProtocol.count == 2)
    }
    private func catalog(media: [String: String], thumbnail: String? = nil, thumbnailURL: String? = nil) throws -> Data {
        var action: [String: Any] = ["order": 1, "phase": "测试", "name": "自制动作"]
        action["thumbnail"] = thumbnail; action["thumbnailURL"] = thumbnailURL
        return try JSONSerialization.data(withJSONObject: [[
            "schemaVersion": 1, "id": "resource-test", "title": "自制资源测试", "source": ["application": "测试"],
            "displayDurationMinutes": 1, "difficulty": "简单", "description": "测试", "actions": [action], "actionsComplete": true, "media": media
        ]])
    }
    private func waitForImport(_ library: CourseLibrary) async throws {
        for _ in 0..<200 {
            if !library.importing { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Import did not finish")
    }
    @Test func remoteCatalogImportsAtomicallyWithoutDownloadingMedia() async throws {
        let fm = FileManager.default, base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let source = base.appendingPathComponent("source"), root = base.appendingPathComponent("installed")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let data = try catalog(media: ["filename": "optional.mp4", "url": "https://example.test/video.mp4"],
            thumbnail: "optional.png", thumbnailURL: "https://example.test/action.png")
        try data.write(to: source.appendingPathComponent("courses.json"))
        let library = CourseLibrary(isUITest: true, rootOverride: root)
        library.importFolder(source); try await waitForImport(library)
        #expect(library.error == nil)
        #expect(try fm.contentsOfDirectory(atPath: root.path) == ["courses.json"])
        #expect(library.mediaURL(for: try #require(library.courses.first))?.scheme == "https")
        // Adding local resources makes them preferred without changing the remote fallback.
        try Data("test file".utf8).write(to: source.appendingPathComponent("optional.mp4"))
        try imageData().write(to: source.appendingPathComponent("optional.png"))
        library.importFolder(source); try await waitForImport(library)
        #expect(library.error == nil)
        let course = try #require(library.courses.first)
        #expect(library.mediaURL(for: course)?.isFileURL == true)
        #expect(library.thumbnail(for: try #require(course.actions.first)) != nil)
        // A corrupt supplied file must not silently pass validation due to its remote fallback.
        try Data("bad image".utf8).write(to: source.appendingPathComponent("optional.png"))
        library.importFolder(source); try await waitForImport(library)
        #expect(library.error != nil)
        #expect(library.thumbnail(for: course.actions[0]) != nil)
        #expect(try Data(contentsOf: root.appendingPathComponent("courses.json")) == data)
    }
    @Test func missingLocalOnlyResourcesDoNotReplaceInstalledCatalog() async throws {
        let fm = FileManager.default, base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let source = base.appendingPathComponent("source"), root = base.appendingPathComponent("installed")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let good = try catalog(media: ["url": "https://example.test/video.mp4"])
        try good.write(to: source.appendingPathComponent("courses.json"))
        let library = CourseLibrary(isUITest: true, rootOverride: root)
        library.importFolder(source); try await waitForImport(library)
        #expect(library.error == nil)
        try catalog(media: ["filename": "absent.mp4"]).write(to: source.appendingPathComponent("courses.json"))
        library.importFolder(source); try await waitForImport(library)
        #expect(library.error != nil)
        #expect(try Data(contentsOf: root.appendingPathComponent("courses.json")) == good)
    }
}

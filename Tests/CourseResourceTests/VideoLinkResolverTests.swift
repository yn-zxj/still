import Foundation
import Testing
@testable import Still

private final class VideoPageProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let body: String
        if url.path == "/x/web-interface/view" {
            body = #"{"code":0,"data":{"title":"自制放松练习","desc":"我的说明","pic":"http://example.test/cover.jpg","cid":123,"duration":90,"pages":[{"page":1,"cid":123,"duration":90},{"page":2,"cid":456,"duration":120}]}}"#
        } else if url.path == "/x/player/playurl" {
            body = #"{"code":0,"data":{"durl":[{"url":"https://example.test/complete.mp4"}]}}"#
        } else { body = "" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
struct VideoLinkResolverTests {
    func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [VideoPageProtocol.self]
        return URLSession(configuration: config)
    }
    @Test func publicMetadataFindsVideoWithoutMistakingEmbedHTMLForMedia() {
        let base = URL(string: "https://example.test/courses/lesson")!
        let html = """
        <meta content='自制练习 &amp; 放松' property='og:title'>
        <meta property='og:image' content='../cover.jpg'>
        <meta property='og:description' content='跟着做 &amp; 放松'>
        <meta property="og:video" content="https://example.test/embed/player.html">
        <video><source src="../media/lesson.mp4?x=1&amp;y=2"></video>
        """
        let result = VideoLinkResolver.metadata(in: html, base: base)
        #expect(result.video?.absoluteString == "https://example.test/media/lesson.mp4?x=1&y=2")
        #expect(result.title == "自制练习 & 放松")
        #expect(result.cover?.absoluteString == "https://example.test/cover.jpg")
        #expect(result.description == "跟着做 & 放松")
        #expect(VideoLinkResolver.metadata(in: "<video src='http://example.test/a.mp4'>", base: base).video == nil)
        #expect(VideoLinkResolver.metadata(in: "<meta property='og:video' content='https://example.test/player.html'>", base: base).video == nil)
    }
    @Test func directMediaAndBilibiliMetadataUseNoExternalNetwork() async throws {
        let resolver = VideoLinkResolver(session: session(), parser: nil)
        let video = try await resolver.resolve("https://example.test/a.mp4")
        #expect(video.video == video.original)
        let page = try await resolver.resolve("https://www.bilibili.com/video/BV1234567890?p=2")
        #expect(page.video?.path == "/complete.mp4")
        #expect(page.title == "自制放松练习")
        #expect(page.cover?.scheme == "https")
        #expect(page.duration == 120)
        #expect(page.headers["Referer"] == "https://www.bilibili.com/")
        let fallback = try await resolver.resolve("https://www.bilibili.com/video/not-a-video")
        #expect(fallback.video == nil)
        #expect(fallback.message.contains("官方播放器"))
    }
    @Test func parserKeepsMetadataButRejectsSplitAudioDRMAndUnsafeURLs() throws {
        let page = URL(string: "https://example.test/lesson")!
        let object: [String: Any] = ["title": "练习", "description": "说明", "duration": 90,
            "thumbnail": "https://example.test/cover.jpg", "formats": [
                ["url": "https://example.test/video.mp4", "ext": "mp4", "vcodec": "avc1", "acodec": "none"],
                ["url": "https://example.test/drm.mp4", "ext": "mp4", "vcodec": "avc1", "acodec": "aac", "has_drm": true],
                ["url": "http://example.test/unsafe.mp4", "ext": "mp4", "vcodec": "avc1", "acodec": "aac"]]]
        let result = try VideoParser.decode(JSONSerialization.data(withJSONObject: object), original: page)
        #expect(result.video == nil); #expect(result.title == "练习"); #expect(result.duration == 90)
        #expect(result.cover?.path == "/cover.jpg")
        var valid = object
        valid["formats"] = [["url": "https://example.test/complete.mp4", "ext": "mp4", "vcodec": "avc1", "acodec": "aac",
            "http_headers": ["Referer": "https://example.test/", "Cookie": "private", "Authorization": "secret", "Origin": "bad\r\ninjection"]]]
        let complete = try VideoParser.decode(JSONSerialization.data(withJSONObject: valid), original: page)
        #expect(complete.video?.path == "/complete.mp4")
        #expect(complete.headers == ["Referer": "https://example.test/"])
    }
    @Test func parserInstallerOnlyAcceptsOfficialStableUniversalReleaseAssets() throws {
        let prefix = "https://github.com/yt-dlp/yt-dlp/releases/"
        var manifest: [String: Any] = ["tag_name": "2026.10.26", "html_url": prefix + "tag/2026.10.26", "draft": false, "prerelease": false,
            "assets": ["yt-dlp_macos", "SHA2-256SUMS"].map { ["name": $0, "size": 123, "browser_download_url": prefix + "download/2026.10.26/" + $0] as [String: Any] }]
        let result = try VideoParserInstaller.validatedAssets(JSONSerialization.data(withJSONObject: manifest))
        #expect(result.binary.name == "yt-dlp_macos")
        manifest["html_url"] = "https://example.test/fake"
        #expect(throws: (any Error).self) { try VideoParserInstaller.validatedAssets(JSONSerialization.data(withJSONObject: manifest)) }
    }
}

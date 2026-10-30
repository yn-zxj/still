import Foundation
import StillCore

struct VideoLinkResolution: Equatable {
    let original: URL
    let video: URL?
    let title: String?
    let message: String
    var cover: URL? = nil
    var description: String? = nil
    var duration: Double? = nil
    var headers: [String: String] = [:]
}

/// Reads only public page metadata. No cookies, browser profiles, injected scripts
/// or private platform endpoints; direct stream URLs are optional, never assumed.
struct VideoLinkResolver {
    let session: URLSession
    let parser: URL?
    init(session: URLSession? = nil, parser: URL? = VideoParser.locate()) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: config, delegate: VideoPageRedirectPolicy(), delegateQueue: nil)
        self.parser = parser
    }
    func resolve(_ input: String) async throws -> VideoLinkResolution {
        let original = try HTTPSResourceURL(input).url
        let host = original.host?.lowercased() ?? ""
        if ["bilibili.com", "www.bilibili.com", "m.bilibili.com", "b23.tv"].contains(host) {
            if let result = try? await BilibiliCourseResolver(session: session).resolve(original) { return result }
            if let parser, let result = try? await VideoParser.resolve(original, executable: parser) { return result }
            return .init(original: original, video: nil, title: nil, message: "已识别 B 站来源，将使用官方播放器。无需手动查找视频地址。")
        }
        if ["mp4", "m4v", "mov", "m3u8"].contains(original.pathExtension.lowercased()) {
            return .init(original: original, video: original, title: nil, message: "已识别视频直链，播放时会检查可用性。")
        }
        if let parser, let result = try? await VideoParser.resolve(original, executable: parser) { return result }
        var request = URLRequest(url: original)
        request.setValue("Still-Course-Link/0.6", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CourseError.invalidMedia }
        guard response.statusCode == 200 else {
            return .init(original: original, video: nil, title: nil, message: "网站返回 HTTP \(response.statusCode)，保留网页播放。")
        }
        if response.mimeType?.hasPrefix("video/") == true || response.mimeType?.contains("mpegurl") == true {
            return .init(original: original, video: response.url ?? original, title: nil, message: "已识别视频资源。")
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= 2 * 1024 * 1024 { break }
        }
        let html = String(decoding: data, as: UTF8.self)
        let result = Self.metadata(in: html, base: response.url ?? original)
        return .init(original: original, video: result.video, title: result.title,
                     message: result.video == nil ? "已读取网页信息，未发现完整视频直链，保留网页播放。" : "已找到网页提供的视频地址；保存后可直接播放。",
                     cover: result.cover, description: result.description)
    }

    static func metadata(in html: String, base: URL) -> (video: URL?, title: String?, cover: URL?, description: String?) {
        func matches(_ pattern: String, in text: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
                guard $0.numberOfRanges > 1, $0.range(at: 1).location != NSNotFound else { return nil }
                return ns.substring(with: $0.range(at: 1))
            }
        }
        func attribute(_ name: String, in tag: String) -> String? {
            matches("(?:^|\\s)" + name + "\\s*=\\s*[\"'](.*?)[\"']", in: tag).first
        }
        func decoded(_ value: String) -> String {
            value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        }
        var title: String?
        var cover: URL?
        var description: String?
        var candidates: [String] = []
        for tag in matches("(<meta\\b[^>]*>)", in: html) {
            let property = (attribute("property", in: tag) ?? attribute("name", in: tag) ?? "").lowercased()
            guard let content = attribute("content", in: tag) else { continue }
            if property == "og:title" { title = decoded(content) }
            if property == "og:image" { cover = safeURL(decoded(content), relativeTo: base) }
            if property == "og:description" || (property == "description" && description == nil) { description = decoded(content) }
            if ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"].contains(property) { candidates.append(decoded(content)) }
        }
        for tag in matches("(<(?:video|source)\\b[^>]*>)", in: html) {
            if let src = attribute("src", in: tag) { candidates.append(decoded(src)) }
        }
        // Embed-player HTML URLs are not native video streams.
        let urls: [URL] = candidates.compactMap { URL(string: $0, relativeTo: base)?.absoluteURL }
        let extensions = Set(["mp4", "m4v", "mov", "m3u8"])
        let video = urls.first { url in
            guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil else { return false }
            return extensions.contains(url.pathExtension.lowercased())
        }
        return (video, title, cover, description)
    }

    static func safeURL(_ value: String?, relativeTo base: URL? = nil) -> URL? {
        guard let value, let url = URL(string: value, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.user == nil, url.password == nil,
              url.host != nil else { return nil }
        return url
    }
}

private final class VideoPageRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil else { completionHandler(nil); return }
        var clean = request; clean.setValue(nil, forHTTPHeaderField: "Authorization"); clean.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(clean)
    }
}

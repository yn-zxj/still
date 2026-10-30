// Adapted from ucmao/media-parser BilibiliParser (MIT).
// See Resources/VideoParser/LICENSE-media-parser.txt and docs/COURSE_LIBRARY.md.
import Foundation
import StillCore

struct BilibiliCourseResolver {
    let session: URLSession
    func resolve(_ input: URL) async throws -> VideoLinkResolution {
        var page = input
        if page.host?.lowercased() == "b23.tv" {
            let (_, response) = try await session.data(from: page)
            guard let redirected = response.url, ["bilibili.com", "www.bilibili.com", "m.bilibili.com"].contains(redirected.host?.lowercased() ?? "") else { throw CourseError.invalidMedia }
            page = redirected
        }
        guard let bvid = page.path.split(separator: "/").first(where: { $0.range(of: #"^BV[a-zA-Z0-9]{10}$"#, options: .regularExpression) != nil }) else { throw CourseError.invalidMedia }
        let info = try await get("/x/web-interface/view", ["bvid": String(bvid)], userAgent: "okhttp/4.9.3")
        let pages = info["pages"] as? [[String: Any]] ?? []
        let requested = Int(URLComponents(url: page, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "p" })?.value ?? "1") ?? 1
        let selected = pages.first { ($0["page"] as? Int) == requested }
        let cid = selected?["cid"] as? Int ?? (requested == 1 ? info["cid"] as? Int : nil)
        var video: URL?
        if let cid,
           let play = try? await get("/x/player/playurl", ["bvid": String(bvid), "cid": String(cid), "otype": "json", "fnver": "0", "fnval": "3", "player": "3", "qn": "112", "platform": "html5", "high_quality": "1"], userAgent: "Mozilla/5.0"),
           let parts = play["durl"] as? [[String: Any]], parts.count == 1 {
            video = VideoLinkResolver.safeURL(parts.first?["url"] as? String)
        }
        var cover = info["pic"] as? String
        if cover?.hasPrefix("http://") == true { cover = "https://" + String(cover!.dropFirst(7)) }
        return .init(original: page, video: video, title: info["title"] as? String,
                     message: video == nil ? "已识别 B 站课程信息，使用官方播放器。" : "已识别 B 站课程信息和完整音画视频。",
                     cover: VideoLinkResolver.safeURL(cover), description: info["desc"] as? String,
                     duration: selected?["duration"] as? Double ?? info["duration"] as? Double,
                     headers: ["Referer": "https://www.bilibili.com/", "User-Agent": "Mozilla/5.0"])
    }
    private func get(_ path: String, _ parameters: [String: String], userAgent: String) async throws -> [String: Any] {
        var components = URLComponents(string: "https://api.bilibili.com" + path)!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["code"] as? Int == 0, let result = object["data"] as? [String: Any] else { throw CourseError.invalidMedia }
        return result
    }
}

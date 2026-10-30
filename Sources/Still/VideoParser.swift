import Foundation
import Combine
import StillCore

/// yt-dlp runs as an optional user-local component. No shell, user configuration,
/// plugins, browser cookies or credential extraction are used.
enum VideoParser {
    static var installationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Still/VideoParser/yt-dlp")
    }
    static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [installationURL, home.appendingPathComponent(".local/bin/yt-dlp"),
                URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), URL(fileURLWithPath: "/usr/local/bin/yt-dlp")]
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static func resolve(_ original: URL, executable: URL) async throws -> VideoLinkResolution {
        let output = try await HAPIProcessRunner.run(executable, ["--ignore-config", "--no-plugin-dirs", "--no-cache-dir",
            "--no-playlist", "--skip-download", "--dump-single-json", "--ignore-no-formats-error",
            "--socket-timeout", "10", "--retries", "0", "--no-warnings", "--", original.absoluteString], 45)
        guard output.status == 0 else { throw CourseError.invalidMedia }
        return try decode(output.stdout, original: original)
    }
    static func decode(_ data: Data, original: URL) throws -> VideoLinkResolution {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["_type"] as? String != "playlist" else { throw CourseError.invalidMedia }
        // A DASH video-only stream would silently lose audio in AVPlayer. Only
        // select a single supported MP4 containing both streams; otherwise embed.
        let formats = object["formats"] as? [[String: Any]] ?? [object]
        let combined = formats.filter {
            guard let v = $0["vcodec"] as? String, v != "none",
                  let a = $0["acodec"] as? String, a != "none",
                  $0["ext"] as? String == "mp4",
                  ($0["has_drm"] as? Bool) != true,
                  ($0["protocol"] as? String).map({ ["https", "http"].contains($0) }) ?? true,
                  VideoLinkResolver.safeURL($0["url"] as? String) != nil else { return false }
            return v.hasPrefix("avc") || v.hasPrefix("h264") || v.hasPrefix("hev") || v.hasPrefix("hvc")
        }.max { ($0["height"] as? Double ?? 0) < ($1["height"] as? Double ?? 0) }
        let video = VideoLinkResolver.safeURL(combined?["url"] as? String)
        // Only non-secret playback headers are used, in memory, for this load.
        let rawHeaders = combined?["http_headers"] as? [String: String] ?? object["http_headers"] as? [String: String] ?? [:]
        let headers = rawHeaders.filter { ["user-agent", "referer", "origin"].contains($0.key.lowercased()) && !$0.value.contains("\r") && !$0.value.contains("\n") }
        return .init(original: original, video: video, title: object["title"] as? String,
                     message: video == nil ? "已识别课程信息；此来源使用网页播放。" : "已识别课程信息和完整音画视频。",
                     cover: VideoLinkResolver.safeURL(object["thumbnail"] as? String),
                     description: object["description"] as? String, duration: object["duration"] as? Double, headers: headers)
    }
}

enum VideoParserError: LocalizedError {
    case invalidDownload
    var errorDescription: String? { "解析组件下载或校验失败，请检查网络后重试。" }
}

@MainActor
final class VideoParserInstaller: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var installed = VideoParser.locate() != nil

    func install() {
        guard !busy else { return }
        busy = true; message = "正在下载并校验解析组件…"
        Task {
            defer { busy = false }
            do {
                _ = try await Self.download()
                installed = true; message = "解析组件已就绪，可以识别链接。"
            } catch { message = error.localizedDescription }
        }
    }

    nonisolated static func validatedAssets(_ data: Data) throws -> (binary: HAPIReleaseAsset, sums: HAPIReleaseAsset) {
        let release = try JSONDecoder().decode(HAPIReleaseManifest.self, from: data)
        guard !release.draft, !release.prerelease,
              release.tagName.range(of: #"^\d{4}\.\d{2}\.\d{2}$"#, options: .regularExpression) != nil,
              release.htmlURL.absoluteString == "https://github.com/yt-dlp/yt-dlp/releases/tag/" + release.tagName,
              let binary = release.asset(named: "yt-dlp_macos"), let sums = release.asset(named: "SHA2-256SUMS") else { throw VideoParserError.invalidDownload }
        for asset in [binary, sums] {
            guard asset.downloadURL.absoluteString == "https://github.com/yt-dlp/yt-dlp/releases/download/\(release.tagName)/\(asset.name)",
                  asset.size > 0, asset.size <= 100 * 1024 * 1024 else { throw VideoParserError.invalidDownload }
        }
        return (binary, sums)
    }
    nonisolated static func download() async throws -> URL {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: HAPIRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!)
        request.setValue("Still-Video-Parser-Installer", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2 * 1024 * 1024 else { throw VideoParserError.invalidDownload }
        let assets = try validatedAssets(data)
        let (sums, sumResponse) = try await session.data(from: assets.sums.downloadURL)
        guard (sumResponse as? HTTPURLResponse)?.statusCode == 200, sums.count < 100 * 1024,
              let digest = HAPIReleaseClient.checksum(named: assets.binary.name, in: String(decoding: sums, as: UTF8.self)) else { throw VideoParserError.invalidDownload }
        let (file, fileResponse) = try await session.download(from: assets.binary.downloadURL)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (fileResponse as? HTTPURLResponse)?.statusCode == 200,
              Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1) == assets.binary.size,
              try HAPIReleaseClient.sha256(of: file) == digest else { throw VideoParserError.invalidDownload }
        let destination = VideoParser.installationURL
        let manager = FileManager.default
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        // Validate before replacing an existing working installation.
        let output = try await HAPIProcessRunner.run(file, ["--ignore-config", "--version"], 20)
        guard output.status == 0,
              String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: #"^\d{4}\.\d{2}\.\d{2}.*$"#, options: .regularExpression) != nil else { throw VideoParserError.invalidDownload }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if manager.fileExists(atPath: destination.path) { _ = try manager.replaceItemAt(destination, withItemAt: file) }
        else { try manager.moveItem(at: file, to: destination) }
        return destination
    }
}

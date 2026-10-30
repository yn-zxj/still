import AVFoundation
import Combine
import CryptoKit
import Foundation
import StillCore

/// Complete, validated files only. Lives outside the replaceable course catalog.
@MainActor
final class CourseVideoCache: ObservableObject {
    typealias Progress = @MainActor (Double?) -> Void
    typealias Downloader = (URL, @escaping Progress) async throws -> (URL, URLResponse)
    struct Entry: Codable {
        let version: Int
        let source: String
        let expectedSHA256: String?
        let sha256: String
        let bytes: Int64
    }
    @Published private(set) var byteCount: Int64 = 0
    let root: URL
    private let session: URLSession
    private let downloader: Downloader?
    private let diagnostics: ResourceDiagnostics?
    private var pending: [String: Task<URL, Error>] = [:]
    private var generation = UUID()
    private var observers: [String: [UUID: Progress]] = [:]
    private var fractions: [String: Double] = [:]

    init(root: URL, diagnostics: ResourceDiagnostics? = nil, downloader: Downloader? = nil) {
        self.root = root; self.downloader = downloader; self.diagnostics = diagnostics
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 3600
        config.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: config)
        refreshSize()
    }
    private func key(_ url: URL, _ expected: String?) -> String {
        SHA256.hash(data: Data((url.absoluteString + "\n" + (expected?.lowercased() ?? "")).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func cachedURL(for url: URL, expectedSHA256: String? = nil) -> URL? {
        let key = key(url, expectedSHA256)
        let file = root.appendingPathComponent(key + ".mp4")
        let meta = root.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: meta), data.count < 16_384,
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.version == 1,
              entry.source == url.absoluteString, entry.expectedSHA256 == expectedSHA256?.lowercased(),
              let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              entry.bytes > 0, Int64(values.fileSize ?? 0) == entry.bytes else { return nil }
        return file
    }
    func file(for url: URL, expectedSHA256: String? = nil, progress: @escaping Progress = { _ in }) async throws -> URL {
        _ = try HTTPSResourceURL(url.absoluteString)
        if let ready = cachedURL(for: url, expectedSHA256: expectedSHA256) { return ready }
        let key = key(url, expectedSHA256)
        let observer = UUID()
        observers[key, default: [:]][observer] = progress
        progress(fractions[key])
        defer { observers[key]?[observer] = nil }
        if let existing = pending[key] { return try await existing.value }
        let currentGeneration = generation, root = root, session = session, downloader = downloader
        let task = Task<URL, Error> { [self] in
            let fm = FileManager.default
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let stage = root.appendingPathComponent(".partial-" + UUID().uuidString + ".mp4")
            defer { try? fm.removeItem(at: stage) }
            let temporary: URL, response: URLResponse
            let report: Progress = { [weak self] value in
                guard let self, self.generation == currentGeneration else { return }
                self.fractions[key] = value
                self.observers[key]?.values.forEach { $0(value) }
            }
            if let downloader { (temporary, response) = try await downloader(url, report) }
            else {
                let delegate = VideoDownloadDelegate(progress: report)
                (temporary, response) = try await session.download(for: URLRequest(url: url), delegate: delegate)
            }
            defer { try? fm.removeItem(at: temporary) }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw ResourceRequestFailure.invalidResponse }
            guard http.statusCode == 200 else { throw ResourceRequestFailure.http(http.statusCode) }
            guard let finalURL = response.url, (try? HTTPSResourceURL(finalURL.absoluteString)) != nil else { throw VideoCacheError.invalidResponse }
            try fm.moveItem(at: temporary, to: stage)
            let expectedBytes = response.expectedContentLength
            let entry = try await Task.detached(priority: .utility) {
                let values = try stage.resourceValues(forKeys: [.fileSizeKey])
                let bytes = Int64(values.fileSize ?? 0)
                guard bytes > 0, expectedBytes < 0 || bytes == expectedBytes else { throw VideoCacheError.incomplete }
                let handle = try FileHandle(forReadingFrom: stage); defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                if let expectedSHA256, digest != expectedSHA256.lowercased() { throw VideoCacheError.invalidVideo }
                let asset = AVURLAsset(url: stage)
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration).seconds
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard playable, duration.isFinite, duration > 0, !tracks.isEmpty else { throw VideoCacheError.invalidVideo }
                return Entry(version: 1, source: url.absoluteString, expectedSHA256: expectedSHA256?.lowercased(), sha256: digest, bytes: bytes)
            }.value
            try Task.checkCancellation()
            guard currentGeneration == generation else { throw CancellationError() }
            let final = root.appendingPathComponent(key + ".mp4")
            if fm.fileExists(atPath: final.path) { _ = try fm.replaceItemAt(final, withItemAt: stage) }
            else { try fm.moveItem(at: stage, to: final) }
            do { try JSONEncoder().encode(entry).write(to: root.appendingPathComponent(key + ".json"), options: .atomic) }
            catch { try? fm.removeItem(at: final); throw error }
            refreshSize(); report(1)
            return final
        }
        pending[key] = task
        defer { if currentGeneration == generation { pending[key] = nil; fractions[key] = nil } }
        do { return try await task.value }
        catch {
            if !(error is CancellationError) { diagnostics?.record(kind: "video-cache", url: url, error: error) }
            throw error
        }
    }
    func cancelOtherDownloads(keeping url: URL, expectedSHA256: String?) {
        let keep = key(url, expectedSHA256)
        for (key, task) in pending where key != keep { task.cancel() }
    }
    func cancelAll() {
        generation = UUID(); pending.values.forEach { $0.cancel() }; pending = [:]; observers = [:]; fractions = [:]
    }
    func clear() throws {
        cancelAll()
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        refreshSize()
    }
    func refreshSize() {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        byteCount = files.filter { $0.pathExtension == "mp4" && !$0.lastPathComponent.hasPrefix(".") }
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

private final class VideoDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let progress: CourseVideoCache.Progress
    init(progress: @escaping CourseVideoCache.Progress) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil
        Task { @MainActor [progress] in progress(fraction) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { try? HTTPSResourceURL($0.absoluteString) } == nil ? nil : request)
    }
}

enum VideoCacheError: LocalizedError {
    case invalidResponse, incomplete, invalidVideo
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "视频暂时无法下载，请检查网络或资源地址后重试。"
        case .incomplete: return "视频未下载完整，请重试。"
        case .invalidVideo: return "视频校验失败，请重新缓存。"
        }
    }
}

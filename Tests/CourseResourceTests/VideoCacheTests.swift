import AVFoundation
import CryptoKit
import Foundation
import AVFoundation
import Testing
@testable import Still
import StillCore

@Suite(.serialized) @MainActor
struct VideoCacheTests {
    private let source = URL(string: "https://example.test/course.mp4")!
    private func base() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func payload() -> Data { Data(base64Encoded: fixture)! }
    private func response(_ url: URL, status: Int = 200, length: Int? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: length.map { ["Content-Length": String($0)] })!
    }
    private func download(_ root: URL, data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(UUID().uuidString + ".download")
        try data.write(to: file); return file
    }
    @Test func completeVideoIsReusedAfterRestartWithNoNetwork() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        var requests = 0
        let data = payload()
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, progress in
            requests += 1; progress(0.5)
            return (try download(root, data: data), response(url, length: data.count))
        }
        let result = try await cache.file(for: source)
        #expect(result.isFileURL)
        #expect(try Data(contentsOf: result) == data)
        #expect(cache.byteCount == data.count)
        let offline = CourseVideoCache(root: cache.root) { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(try await offline.file(for: source) == result)
        #expect(requests == 1)
        let asset = AVURLAsset(url: result)
        #expect(try await asset.load(.isPlayable))
    }
    @Test func concurrentOpensShareOneDownload() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        var requests = 0
        let data = payload()
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, _ in
            requests += 1
            try await Task.sleep(nanoseconds: 80_000_000)
            return (try download(root, data: data), response(url, length: data.count))
        }
        async let first = cache.file(for: source)
        async let second = cache.file(for: source)
        let urls = try await [first, second]
        #expect(urls[0] == urls[1])
        #expect(requests == 1)
    }
    @Test func errorsPartialResponsesAndBadVideoNeverBecomeReady() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        for (status, bytes, length) in [(403, payload(), payload().count), (206, payload(), payload().count),
                                        (200, payload(), payload().count + 100), (200, Data("bad mp4".utf8), 7)] {
            let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, _ in
                (try download(root, data: bytes), response(url, status: status, length: length))
            }
            await #expect(throws: (any Error).self) { try await cache.file(for: source) }
            #expect(cache.cachedURL(for: source) == nil)
            #expect(cache.byteCount == 0)
            #expect((try? FileManager.default.contentsOfDirectory(atPath: cache.root.path).isEmpty) == true)
        }
    }
    @Test func failedDownloadCanRetryAndChecksumMismatchIsRejected() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        let data = payload(); var requests = 0
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, _ in
            requests += 1
            if requests == 1 { throw URLError(.networkConnectionLost) }
            return (try download(root, data: data), response(url, length: data.count))
        }
        await #expect(throws: (any Error).self) { try await cache.file(for: source) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let result = try await cache.file(for: source, expectedSHA256: digest)
        #expect(FileManager.default.fileExists(atPath: result.path))
        await #expect(throws: (any Error).self) { try await cache.file(for: source, expectedSHA256: String(repeating: "0", count: 64)) }
        #expect(cache.cachedURL(for: source, expectedSHA256: digest) == result)
    }
    @Test func changedURLAndTruncatedLocalFileDoNotReuseOldEntry() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        let data = payload(); var requests = 0
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, _ in
            requests += 1; return (try download(root, data: data), response(url, length: data.count))
        }
        let first = try await cache.file(for: source)
        #expect(cache.cachedURL(for: URL(string: "https://example.test/course-v2.mp4")!) == nil)
        try Data(data.prefix(100)).write(to: first)
        #expect(cache.cachedURL(for: source) == nil)
        let repaired = try await cache.file(for: source)
        #expect(try Data(contentsOf: repaired) == data)
        #expect(requests == 2)
        try cache.clear()
        #expect(cache.cachedURL(for: source) == nil)
        #expect(cache.byteCount == 0)
    }
    @Test func clearingDuringDownloadPreventsLateRepopulation() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        let data = payload()
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, _ in
            // A transport that finishes after cancellation still must not commit its result.
            try? await Task.sleep(nanoseconds: 150_000_000)
            return (try download(root, data: data), response(url, length: data.count))
        }
        let task = Task { try await cache.file(for: source) }
        try await Task.sleep(nanoseconds: 30_000_000)
        try cache.clear()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(cache.cachedURL(for: source) == nil)
        #expect(cache.byteCount == 0)
    }

    @Test func switchingCoursesCancelsOldDownloadWithoutCommittingIt() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        let data = payload()
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, _ in
            try? await Task.sleep(nanoseconds: 80_000_000)
            return (try download(root, data: data), response(url, length: data.count))
        }
        let old = Task { try await cache.file(for: source) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let next = URL(string: "https://example.test/next.mp4")!
        cache.cancelOtherDownloads(keeping: next, expectedSHA256: nil)
        await #expect(throws: (any Error).self) { try await old.value }
        #expect(cache.cachedURL(for: source) == nil)
        _ = try await cache.file(for: next)
        #expect(cache.cachedURL(for: next) != nil)
    }

    private func course() throws -> Course {
        try Course.decodeCatalog(Data("""
        [{"schemaVersion":1,"id":"cache-test","title":"自制缓存测试","source":{"application":"测试"},"displayDurationMinutes":1,"difficulty":"简单","description":"自制素材","actions":[],"actionsComplete":false,"media":{"url":"https://example.test/course.mp4"}}]
        """.utf8))[0]
    }
    @Test func onlinePlaybackDoesNotWaitForBackgroundCache() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        let data = payload()
        let fixture = try download(root, data: data).appendingPathExtension("mp4")
        try data.write(to: fixture)
        var release: CheckedContinuation<Void, Never>?
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, progress in
            progress(0.5)
            await withCheckedContinuation { release = $0 }
            return (try download(root, data: data), response(url, length: data.count))
        }
        var playbackSource: URL?
        let player = CoursePlayer(cache: cache) { url in playbackSource = url; return AVURLAsset(url: fixture) }
        defer { player.shutdown() }
        var starts = 0
        player.onStart = { _ in starts += 1 }
        player.load(try course(), url: source)
        for _ in 0..<100 { if !player.loading { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(player.error == nil)
        #expect(playbackSource == source)
        #expect(!player.caching) // Merely browsing a course must not download a full video.
        #expect(!player.videoAvailableOffline)
        player.toggle()
        #expect(player.active)
        #expect(starts == 1)
        for _ in 0..<100 { if release != nil { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(player.caching)
        #expect(player.downloadProgress == 0.5)
        player.pause()
        release?.resume()
        for _ in 0..<100 { if !player.caching { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(player.videoAvailableOffline)
        #expect(!player.usingCachedVideo) // First playback keeps its stream and position.
        #expect(player.active)
        #expect(starts == 1)
        player.stop()
        #expect(!player.finished)
    }
    @Test func cacheFailureDoesNotBlockOnlinePlayback() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try download(root, data: payload()).appendingPathExtension("mp4")
        try payload().write(to: fixture)
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { _, _ in throw URLError(.notConnectedToInternet) }
        let player = CoursePlayer(cache: cache) { _ in AVURLAsset(url: fixture) }; defer { player.shutdown() }
        player.load(try course(), url: source)
        for _ in 0..<100 { if !player.loading { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(player.error == nil)
        player.toggle()
        for _ in 0..<100 { if player.cacheError != nil { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(player.error == nil)
        #expect(player.cacheError != nil)
        #expect(!player.videoAvailableOffline)
        #expect(player.playing)
        player.stop()
    }

    @Test func failedStreamCanRecoverThroughCompleteCache() async throws {
        let root = base(); defer { try? FileManager.default.removeItem(at: root) }
        let data = payload()
        let cache = CourseVideoCache(root: root.appendingPathComponent("cache")) { url, _ in
            (try download(root, data: data), response(url, length: data.count))
        }
        let player = CoursePlayer(cache: cache) { url in
            AVURLAsset(url: url.isFileURL ? url : root.appendingPathComponent("missing.mp4"))
        }
        defer { player.shutdown() }
        let course = try course()
        player.load(course, url: source)
        for _ in 0..<100 { if !player.loading { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(player.error != nil)
        player.playFromCache(course)
        for _ in 0..<200 { if player.playing { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(player.error == nil)
        #expect(player.playing)
        #expect(player.usingCachedVideo)
        player.stop()
    }

    // Self-generated 1 s, 160×96 solid-white H.264 fixture; no third-party media.
    private let fixture = "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"
}

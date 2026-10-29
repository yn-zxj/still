import AppKit
import ImageIO
import CryptoKit
import StillCore

/// Memory and optional persistent image cache. No account cookies or course API requests.
@MainActor
final class RemoteCourseImages {
    private let cache = NSCache<NSURL, NSImage>()
    private var pending: [HTTPSResourceURL: Task<Data?, Never>] = [:]
    private let session: URLSession
    private let diskRoot: URL?

    init(session: URLSession? = nil, diskRoot: URL? = nil) {
        self.diskRoot = diskRoot
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 160
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.httpMaximumConnectionsPerHost = 4
            self.session = URLSession(configuration: config)
        }
    }

    func image(for resource: HTTPSResourceURL) async -> NSImage? {
        if let image = cache.object(forKey: resource.url as NSURL) { return image }
        let filename = SHA256.hash(data: Data(resource.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let diskURL = diskRoot?.appendingPathComponent(filename + ".image")
        if let diskURL, let data = try? Data(contentsOf: diskURL), let (image, cost) = decode(data) {
            cache.setObject(image, forKey: resource.url as NSURL, cost: cost)
            return image
        }
        let session = session
        let task = pending[resource] ?? Task { try? await Self.fetch(resource, session: session) }
        pending[resource] = task
        let data = await task.value
        pending[resource] = nil
        if let image = cache.object(forKey: resource.url as NSURL) { return image }
        guard let data, let (image, cost) = decode(data) else { return nil }
        if let diskRoot, let diskURL {
            try? FileManager.default.createDirectory(at: diskRoot, withIntermediateDirectories: true)
            try? data.write(to: diskURL, options: .atomic)
        }
        cache.setObject(image, forKey: resource.url as NSURL, cost: cost)
        return image
    }
    private func decode(_ data: Data) -> (NSImage, Int)? {
        guard data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return (NSImage(cgImage: cgImage, size: .zero), cgImage.width * cgImage.height * 4)
    }

    nonisolated private static func fetch(_ resource: HTTPSResourceURL, session: URLSession) async throws -> Data {
        let maximumBytes = 8 * 1024 * 1024
        var request = URLRequest(url: resource.url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSOnlyRedirects())
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let finalURL = response.url, (try? HTTPSResourceURL(finalURL.absoluteString)) != nil,
              response.expectedContentLength <= maximumBytes else { throw CourseError.invalidThumbnail }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw CourseError.invalidThumbnail }
            data.append(byte)
        }
        return data
    }
}

private final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let safe = request.url.flatMap { try? HTTPSResourceURL($0.absoluteString) } != nil
        completionHandler(safe ? request : nil)
    }
}

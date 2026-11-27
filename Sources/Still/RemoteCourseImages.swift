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
    private let diagnostics: ResourceDiagnostics?
    private var failures: [HTTPSResourceURL: String] = [:]

    init(session: URLSession? = nil, diskRoot: URL? = nil, diagnostics: ResourceDiagnostics? = nil) {
        self.diskRoot = diskRoot; self.diagnostics = diagnostics
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

    func failure(for resource: HTTPSResourceURL) -> String? { failures[resource] }

    func cachedImage(for resource: HTTPSResourceURL) -> NSImage? {
        cache.object(forKey: resource.url as NSURL)
    }

    func image(for resource: HTTPSResourceURL) async -> NSImage? {
        if let image = cache.object(forKey: resource.url as NSURL) { return image }
        let filename = SHA256.hash(data: Data(resource.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let diskURL = diskRoot?.appendingPathComponent(filename + ".image")
        if let diskURL {
            if let decoded = await Task.detached(priority: .userInitiated, operation: { () -> (CGImage, Int)? in
                guard let data = try? Data(contentsOf: diskURL) else { return nil }
                return Self.decodeCGImage(data)
            }).value {
                let image = NSImage(cgImage: decoded.0, size: .zero)
                cache.setObject(image, forKey: resource.url as NSURL, cost: decoded.1)
                return image
            }
        }
        if let image = cache.object(forKey: resource.url as NSURL) { return image }
        let session = session
        let task = pending[resource] ?? Task<Data?, Never> {
            do { return try await Self.fetch(resource, session: session) }
            catch {
                failures[resource] = ResourceDiagnostics.message(error)
                diagnostics?.record(kind: "image", url: resource.url, error: error)
                return nil
            }
        }
        pending[resource] = task
        let data = await task.value
        pending[resource] = nil
        if let image = cache.object(forKey: resource.url as NSURL) { return image }
        guard let data else { return nil }
        let diskRoot = diskRoot
        guard let decoded = await Task.detached(priority: .userInitiated, operation: { () -> (CGImage, Int)? in
            guard let result = Self.decodeCGImage(data) else { return nil }
            if let diskRoot, let diskURL {
                try? FileManager.default.createDirectory(at: diskRoot, withIntermediateDirectories: true)
                try? data.write(to: diskURL, options: .atomic)
            }
            return result
        }).value else {
            failures[resource] = ResourceRequestFailure.invalidImage.localizedDescription
            diagnostics?.record(kind: "image", url: resource.url, error: ResourceRequestFailure.invalidImage)
            return nil
        }
        let image = NSImage(cgImage: decoded.0, size: .zero)
        failures[resource] = nil
        cache.setObject(image, forKey: resource.url as NSURL, cost: decoded.1)
        return image
    }

    nonisolated private static func decodeCGImage(_ data: Data) -> (CGImage, Int)? {
        guard data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return (cgImage, cgImage.width * cgImage.height * 4)
    }

    nonisolated private static func fetch(_ resource: HTTPSResourceURL, session: URLSession) async throws -> Data {
        let maximumBytes = 8 * 1024 * 1024
        var request = URLRequest(url: resource.url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSOnlyRedirects())
        guard let http = response as? HTTPURLResponse else { throw ResourceRequestFailure.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ResourceRequestFailure.http(http.statusCode) }
        guard let finalURL = response.url, (try? HTTPSResourceURL(finalURL.absoluteString)) != nil,
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

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

    func image(for resource: HTTPSResourceURL) async -> NSImage? {
        if let image = cache.object(forKey: resource.url as NSURL) { return image }
        let filename = SHA256.hash(data: Data(resource.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let diskURL = diskRoot?.appendingPathComponent(filename + ".image")
        if let diskURL, let data = try? Data(contentsOf: diskURL), let (image, cost) = decode(data) {
            cache.setObject(image, forKey: resource.url as NSURL, cost: cost)
            return image
        }
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
        guard let (image, cost) = decode(data) else {
            failures[resource] = ResourceRequestFailure.invalidImage.localizedDescription
            diagnostics?.record(kind: "image", url: resource.url, error: ResourceRequestFailure.invalidImage)
            return nil
        }
        failures[resource] = nil
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

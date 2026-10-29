import AppKit
import ImageIO
import StillCore

/// Per-library memory cache. No account cookies, credentials, or course API requests.
@MainActor
final class RemoteCourseImages {
    private let cache = NSCache<NSURL, NSImage>()
    private var pending: [HTTPSResourceURL: Task<Data?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession? = nil) {
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
        let session = session
        let task = pending[resource] ?? Task { try? await Self.fetch(resource, session: session) }
        pending[resource] = task
        let data = await task.value
        pending[resource] = nil
        if let image = cache.object(forKey: resource.url as NSURL) { return image }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: resource.url as NSURL, cost: cgImage.width * cgImage.height * 4)
        return image
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

import CryptoKit
import Foundation
import StillCore

/// Stores only resource host/hash and error codes, never URL queries, headers or account data.
@MainActor
final class ResourceDiagnostics {
    let root: URL
    init(root: URL) { self.root = root }
    static func message(_ error: Error) -> String {
        if let failure = error as? ResourceRequestFailure { return failure.localizedDescription }
        var current = error as NSError
        for _ in 0..<5 {
            if current.domain == NSURLErrorDomain {
                switch current.code {
                case NSURLErrorTimedOut: return "连接超时（-1001），请重试"
                case NSURLErrorNotConnectedToInternet: return "网络未连接（-1009）"
                case NSURLErrorNetworkConnectionLost: return "网络连接中断（-1005），请重试"
                case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "无法解析资源服务器（\(current.code)）"
                case NSURLErrorCannotConnectToHost: return "无法连接资源服务器（-1004）"
                case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate:
                    return "资源服务器的安全连接失败（\(current.code)）"
                case NSURLErrorCancelled: return "请求已取消"
                default: return "网络请求失败（\(current.code)）"
                }
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        if error is CourseError || error is VideoCacheError { return error.localizedDescription }
        return "资源读取失败（\(current.domain) \(current.code)）"
    }
    func record(kind: String, url: URL?, error: Error) {
        let e = error as NSError
        var entry: [String: Any] = ["time": Date().ISO8601Format(), "kind": kind, "domain": e.domain, "code": e.code, "reason": Self.message(error)]
        if let url {
            entry["host"] = url.isFileURL ? "local" : url.host
            entry["resource"] = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("resource-errors.jsonl")
        var previous = (try? Data(contentsOf: file)) ?? Data()
        if previous.count > 128 * 1024 { previous = Data() }
        previous.append(data); previous.append(10)
        try? previous.write(to: file, options: .atomic)
    }
}

enum ResourceRequestFailure: LocalizedError {
    case http(Int), invalidResponse, invalidImage
    var errorDescription: String? {
        switch self {
        case .http(let status): return "资源服务器返回 HTTP \(status)"
        case .invalidResponse: return "资源服务器返回了无效响应"
        case .invalidImage: return "返回的图片不完整或无法解码"
        }
    }
}

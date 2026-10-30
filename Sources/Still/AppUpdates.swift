import AppKit
import CryptoKit
import Security
import StillCore

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let id: Int64
        let name: String
        let size: Int64
        let state: String
    }
    let tagName: String
    let htmlURL: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url", body, draft, prerelease, assets }

    func archive(architecture: String) -> Asset? {
        assets.first {
            $0.state == "uploaded" && $0.size > 0 && $0.size <= 250 * 1024 * 1024
            && $0.name.range(of: "^Still-[0-9.]+-[0-9]+-(\(architecture)|universal|arm64-x86_64|x86_64-arm64)-macos\\.zip$", options: .regularExpression) != nil
        }
    }
    var valid: Bool {
        !draft && !prerelease && ReleaseVersion(tagName) != nil && htmlURL.scheme == "https"
        && htmlURL.host == "github.com" && htmlURL.path == "/yn-zxj/still/releases/tag/\(tagName)"
        && htmlURL.user == nil && htmlURL.password == nil && htmlURL.query == nil
    }
}

enum UpdateError: LocalizedError {
    case access, authorization, rateLimit, response(Int), invalidRelease, incompatible, checksum, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .access: return "仓库尚未公开、没有正式版本，或当前令牌无权读取。私有仓库请配置只读令牌，也可在浏览器中查看 Release。"
        case .authorization: return "GitHub 令牌已失效或没有读取权限，请重新配置。"
        case .rateLimit: return "GitHub 暂时限制了请求频率，请稍后检查。"
        case .response(let code): return "更新请求失败（HTTP \(code)），请稍后重试。"
        case .invalidRelease: return "Release 信息无效，未使用该版本。"
        case .incompatible: return "此版本没有适合这台 Mac 的安装包或校验文件。"
        case .checksum: return "安装包 SHA-256 校验未通过，请重新下载。"
        case .keychain(let status): return "钥匙串暂时不可用（\(status)），令牌未保存。"
        }
    }
}

/// Never forwards a repository credential to a CDN, nor allows an HTTP downgrade.
final class ReleaseRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static func redirected(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host,
              host == "api.github.com" || host == "github.com" || host.hasSuffix(".githubusercontent.com") else { return nil }
        var clean = request
        clean.setValue(nil, forHTTPHeaderField: "Authorization")
        clean.setValue(nil, forHTTPHeaderField: "Cookie")
        return clean
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.redirected(request))
    }
}

struct ReleaseClient {
    typealias Download = (URLRequest) async throws -> (URL, URLResponse)
    let session: URLSession
    let downloader: Download
    init(session: URLSession? = nil, downloader: Download? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 600
        let transport = session ?? URLSession(configuration: config, delegate: ReleaseRedirectPolicy(), delegateQueue: nil)
        self.session = transport
        self.downloader = downloader ?? { try await transport.download(for: $0) }
    }
    static let api = "https://api.github.com/repos/yn-zxj/still"
    func request(_ path: String, token: String?, binary: Bool = false) -> URLRequest {
        var request = URLRequest(url: URL(string: Self.api + path)!)
        request.setValue(binary ? "application/octet-stream" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Still-macOS", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }
    func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidRelease }
        switch http.statusCode {
        case 200: return
        case 401: throw UpdateError.authorization
        case 404: throw UpdateError.access
        case 403 where http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0": throw UpdateError.rateLimit
        default: throw UpdateError.response(http.statusCode)
        }
    }
    func latest(token: String?) async throws -> GitHubRelease {
        let (data, response) = try await session.data(for: request("/releases/latest", token: token))
        try validate(response)
        guard data.count < 2 * 1024 * 1024 else { throw UpdateError.invalidRelease }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard release.valid else { throw UpdateError.invalidRelease }
        return release
    }
    func checksum(_ asset: GitHubRelease.Asset, token: String?) async throws -> String {
        guard asset.id > 0, asset.size < 4096 else { throw UpdateError.checksum }
        let (data, response) = try await session.data(for: request("/releases/assets/\(asset.id)", token: token, binary: true))
        try validate(response)
        guard data.count < 4096, let text = String(data: data, encoding: .utf8),
              let hash = text.split(whereSeparator: \.isWhitespace).first,
              hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw UpdateError.checksum }
        return hash.lowercased()
    }
    func download(_ asset: GitHubRelease.Asset, checksum: String, token: String?, root: URL) async throws -> URL {
        guard asset.id > 0, asset.size > 0, asset.size <= 250 * 1024 * 1024,
              asset.name.range(of: "^Still-[0-9.]+-[0-9]+-[a-z0-9_-]+-macos\\.zip$", options: .regularExpression) != nil else { throw UpdateError.invalidRelease }
        let (temp, response) = try await downloader(request("/releases/assets/\(asset.id)", token: token, binary: true))
        defer { try? FileManager.default.removeItem(at: temp) }
        try Task.checkCancellation()
        try validate(response)
        let actualSize = try temp.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard actualSize == asset.size, actualSize <= 250 * 1024 * 1024 else { throw UpdateError.checksum }
        let handle = try FileHandle(forReadingFrom: temp)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == checksum else { throw UpdateError.checksum }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(asset.name)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
        } else { try FileManager.default.moveItem(at: temp, to: destination) }
        return destination
    }
}

enum UpdateCredential {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.still.app.github-updates", kSecAttrAccount as String: "yn-zxj/still"] }
    static func read() throws -> String? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw UpdateError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw UpdateError.keychain(status) }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw UpdateError.keychain(result) }
        } else if status != errSecSuccess { throw UpdateError.keychain(status) }
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var release: GitHubRelease?
    @Published private(set) var busy = false
    @Published private(set) var downloading = false
    @Published private(set) var message = "从 GitHub Release 获取正式版本。"
    @Published private(set) var lastChecked: Date?
    @Published private(set) var downloadedURL: URL?
    @Published private(set) var credentialMessage: String?
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.3"
    private let client = ReleaseClient()
    private var checkTask: Task<Void, Never>?
    var hasUpdate: Bool {
        guard let release, let remote = ReleaseVersion(release.tagName), let local = ReleaseVersion(currentVersion) else { return false }
        return remote > local
    }
    init() { lastChecked = UserDefaults.standard.object(forKey: "updates.lastChecked") as? Date }
    func saveToken(_ value: String) {
        do {
            try UpdateCredential.save(value.trimmingCharacters(in: .whitespacesAndNewlines))
            credentialMessage = value.isEmpty ? "已移除令牌，之后匿名检查公开版本。" : "令牌已保存在系统钥匙串。"
        } catch { credentialMessage = error.localizedDescription }
    }
    func checkAutomaticallyIfNeeded() {
        guard lastChecked == nil || Date().timeIntervalSince(lastChecked!) >= 24 * 3600 else { return }
        check()
    }
    func check() {
        guard !busy else { return }
        busy = true; message = "正在检查 GitHub Release…"; downloadedURL = nil
        checkTask = Task {
            do {
                let token = try UpdateCredential.read()
                let result = try await client.latest(token: token)
                release = result; lastChecked = Date()
                UserDefaults.standard.set(lastChecked, forKey: "updates.lastChecked")
                message = hasUpdate ? "发现 \(result.tagName)，可下载更新。" : "当前已是最新版本（\(currentVersion)）。"
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    func download() {
        guard let release, hasUpdate, !busy else { return }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard let asset = release.archive(architecture: architecture),
              let digestAsset = release.assets.first(where: { $0.name == asset.name + ".sha256" && $0.state == "uploaded" }) else {
            message = UpdateError.incompatible.localizedDescription; return
        }
        busy = true; downloading = true; message = "正在下载并校验 \(release.tagName)…"
        checkTask = Task {
            do {
                let token = try UpdateCredential.read()
                let hash = try await client.checksum(digestAsset, token: token)
                let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Still/Updates")
                downloadedURL = try await client.download(asset, checksum: hash, token: token, root: root)
                message = "安装包已通过校验。解压后退出息间，将新应用替换到原位置，再打开即可。"
            } catch { message = error.localizedDescription }
            busy = false; downloading = false
        }
    }
    func openReleasePage() { NSWorkspace.shared.open(release?.htmlURL ?? URL(string: "https://github.com/yn-zxj/still/releases/latest")!) }
    func revealDownload() { if let downloadedURL { NSWorkspace.shared.activateFileViewerSelecting([downloadedURL]) } }
}

import CryptoKit
import Foundation
import StillCore

struct HAPIReleaseAsset: Decodable, Equatable, Sendable {
    var name: String
    var size: Int64
    var downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name, size
        case downloadURL = "browser_download_url"
    }
}

struct HAPIReleaseManifest: Decodable, Equatable, Sendable {
    var tagName: String
    var htmlURL: URL
    var draft: Bool
    var prerelease: Bool
    var assets: [HAPIReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }

    var version: String? {
        guard tagName.range(of: #"^v[0-9]+(\.[0-9]+){1,3}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return String(tagName.dropFirst())
    }

    mutating func validate(for host: String) throws {
        guard !draft, !prerelease, let version, !version.isEmpty,
              htmlURL.scheme == "https", htmlURL.host == "github.com",
              htmlURL.user == nil, htmlURL.password == nil, htmlURL.query == nil,
              htmlURL.path == "/\(host)/releases/tag/\(tagName)" else {
            throw HAPIInstallError.invalidRelease
        }
        let prefix = "/\(host)/releases/download/\(tagName)/"
        guard assets.allSatisfy({
            $0.downloadURL.scheme == "https" && $0.downloadURL.host == "github.com"
                && $0.downloadURL.user == nil && $0.downloadURL.password == nil
                && $0.downloadURL.query == nil
                && $0.downloadURL.path.hasPrefix(prefix)
                && $0.downloadURL.lastPathComponent == $0.name
                && $0.size >= 0
        }) else {
            throw HAPIInstallError.invalidRelease
        }
    }

    func asset(named name: String) -> HAPIReleaseAsset? {
        assets.first { $0.name == name }
    }
}

enum HAPIInstallError: LocalizedError, Equatable {
    case access
    case rateLimit
    case response(Int)
    case invalidRelease
    case incompatible
    case checksum
    case unsafeArchive
    case extraction(String)
    case invalidBinary

    var errorDescription: String? {
        switch self {
        case .access: return "无法读取 HAPI 官方 Release，请检查网络后重试。"
        case .rateLimit: return "GitHub 暂时限制了下载频率，请稍后再试。"
        case .response(let code): return "HAPI 下载请求失败（HTTP \(code)）。"
        case .invalidRelease: return "HAPI Release 信息无效，已停止安装。"
        case .incompatible: return "最新版 HAPI 没有适合这台 Mac 的安装包。"
        case .checksum: return "HAPI 安装包 SHA-256 校验未通过，已停止安装。"
        case .unsafeArchive: return "HAPI 安装包结构异常，已停止安装。"
        case .extraction(let message): return "HAPI 解压失败：\(message)"
        case .invalidBinary: return "下载内容不是可运行的 hapi，已停止安装。"
        }
    }
}

struct HAPIReleaseClient {
    static let repository = "tiann/hapi"
    static let api = "https://api.github.com/repos/\(repository)"

    let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 900
        self.session = session ?? URLSession(
            configuration: configuration,
            delegate: HAPIRedirectPolicy(),
            delegateQueue: nil
        )
    }

    func latest() async throws -> HAPIReleaseManifest {
        var request = URLRequest(url: URL(string: Self.api + "/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Still-macOS-HAPI-Installer", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        guard data.count <= 2 * 1024 * 1024 else { throw HAPIInstallError.invalidRelease }
        var release = try JSONDecoder().decode(HAPIReleaseManifest.self, from: data)
        try release.validate(for: Self.repository)
        return release
    }

    func checksum(for assetName: String, checksums: HAPIReleaseAsset) async throws -> String {
        guard Self.trustedAsset(checksums, verifyingName: "checksums.txt") else {
            throw HAPIInstallError.invalidRelease
        }
        var request = URLRequest(url: checksums.downloadURL)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.setValue("Still-macOS-HAPI-Installer", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        guard data.count <= 8 * 1024,
              let text = String(data: data, encoding: .utf8),
              let digest = Self.checksum(named: assetName, in: text) else {
            throw HAPIInstallError.checksum
        }
        return digest
    }

    func download(_ asset: HAPIReleaseAsset, checksum: String, into folder: URL) async throws -> URL {
        guard Self.trustedAsset(asset), asset.size > 0, asset.size <= 150 * 1024 * 1024,
              checksum.count == 64, checksum.allSatisfy(\.isHexDigit) else {
            throw HAPIInstallError.invalidRelease
        }
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Still-macOS-HAPI-Installer", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await session.download(for: request)
        try validate(response)
        let actualSize = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard actualSize == asset.size else { throw HAPIInstallError.checksum }
        let actualChecksum = try await Task.detached(priority: .userInitiated) {
            try Self.sha256(of: temporary)
        }.value
        guard actualChecksum == checksum.lowercased() else {
            throw HAPIInstallError.checksum
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = folder.appendingPathComponent(asset.name)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return destination
    }

    static func checksum(named name: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields.last.map(String.init) == name else { continue }
            let digest = String(fields[0]).lowercased()
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { return nil }
            return digest
        }
        return nil
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw HAPIInstallError.invalidRelease }
        switch http.statusCode {
        case 200: return
        case 403 where http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0":
            throw HAPIInstallError.rateLimit
        case 404: throw HAPIInstallError.access
        default: throw HAPIInstallError.response(http.statusCode)
        }
    }

    private static func trustedAsset(_ asset: HAPIReleaseAsset,
                                     verifyingName name: String? = nil) -> Bool {
        let expected = name ?? asset.name
        return expected == asset.name
            && asset.downloadURL.scheme == "https"
            && asset.downloadURL.host == "github.com"
            && asset.downloadURL.user == nil
            && asset.downloadURL.password == nil
            && asset.downloadURL.query == nil
            && asset.downloadURL.path.hasPrefix("/\(repository)/releases/download/")
    }
}

final class HAPIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static func redirected(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host,
              host == "api.github.com" || host == "github.com" || host.hasSuffix(".githubusercontent.com") else {
            return nil
        }
        var clean = request
        clean.setValue(nil, forHTTPHeaderField: "Authorization")
        clean.setValue(nil, forHTTPHeaderField: "Cookie")
        return clean
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.redirected(request))
    }
}

enum HAPIInstallationState: Equatable {
    case idle
    case checking
    case downloading(version: String, bytes: Int64)
    case installing(version: String)
    case installed(version: String, url: URL)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .idle: return ""
        case .checking: return "正在查找 HAPI 官方最新版…"
        case .downloading(let version, let bytes):
            return "正在下载 HAPI \(version)（约 \(max(1, bytes / 1_048_576)) MB）…"
        case .installing(let version): return "正在校验并安装 HAPI \(version)…"
        case .installed(let version, _): return "HAPI \(version) 已安装。"
        case .failed(let message): return message
        }
    }
}

@MainActor
final class HAPIInstaller: ObservableObject {
    @Published private(set) var state: HAPIInstallationState = .idle

    private let home: URL
    private let client: HAPIReleaseClient
    private var task: Task<Void, Never>?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         client: HAPIReleaseClient = HAPIReleaseClient()) {
        self.home = home
        self.client = client
    }

    func install(completion: @escaping (URL, String) -> Void) {
        guard task == nil else { return }
        state = .checking
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("Still-HAPI-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: staging,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                defer { try? FileManager.default.removeItem(at: staging) }

                let release = try await client.latest()
                guard let version = release.version,
                      AgentActivityCoordinator.isAtLeast(version, "0.30.0") else {
                    throw HAPIInstallError.incompatible
                }
                let assetName: String
                #if arch(x86_64)
                assetName = "hapi-darwin-x64.tar.gz"
                #else
                assetName = "hapi-darwin-arm64.tar.gz"
                #endif
                guard let asset = release.asset(named: assetName),
                      let checksums = release.asset(named: "checksums.txt") else {
                    throw HAPIInstallError.incompatible
                }
                state = .downloading(version: version, bytes: asset.size)
                let digest = try await client.checksum(for: asset.name, checksums: checksums)
                let archive = try await client.download(asset, checksum: digest, into: staging)
                try Task.checkCancellation()
                state = .installing(version: version)
                let home = self.home
                let installed = try await Task.detached(priority: .userInitiated) {
                    try Self.installVerifiedArchive(archive, version: version, home: home)
                }.value
                let output = try await HAPIProcessRunner.run(installed, ["--version"], 15)
                let text = String(decoding: output.stdout + output.stderr, as: UTF8.self)
                let reported = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
                guard output.status == 0, HAPIReleaseManifest.isVersion(reported),
                      AgentActivityCoordinator.isAtLeast(reported, "0.30.0") else {
                    throw HAPIInstallError.invalidBinary
                }
                state = .installed(version: reported, url: installed)
                completion(installed, reported)
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated static func installVerifiedArchive(_ archive: URL, version: String, home: URL) throws -> URL {
        let folder = home
            .appendingPathComponent("Library/Application Support/Still/HAPI", isDirectory: true)
        let extraction = folder.appendingPathComponent(".extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extraction) }

        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        listing.arguments = ["-tzf", archive.path]
        let pipe = Pipe()
        listing.standardOutput = pipe
        listing.standardError = Pipe()
        try listing.run()
        let listingData = pipe.fileHandleForReading.readDataToEndOfFile()
        listing.waitUntilExit()
        guard listing.terminationStatus == 0,
              String(decoding: listingData, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init) == ["hapi"] else {
            throw HAPIInstallError.unsafeArchive
        }

        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extract.arguments = ["-xzf", archive.path, "-C", extraction.path, "hapi"]
        extract.standardOutput = FileHandle.nullDevice
        extract.standardError = Pipe()
        try extract.run()
        extract.waitUntilExit()
        guard extract.terminationStatus == 0 else {
            throw HAPIInstallError.extraction("tar 退出码 \(extract.terminationStatus)")
        }

        let candidate = extraction.appendingPathComponent("hapi")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw HAPIInstallError.invalidBinary
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: candidate.path)
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "com.apple.quarantine", candidate.path]
        xattr.standardOutput = FileHandle.nullDevice
        xattr.standardError = FileHandle.nullDevice
        do {
            try xattr.run()
            xattr.waitUntilExit()
        } catch {}

        let bin = folder.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bin,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = bin.appendingPathComponent("hapi")
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: candidate)
        } else {
            try FileManager.default.moveItem(at: candidate, to: destination)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
        let metadata: [String: String] = [
            "version": version,
            "installedAt": ISO8601DateFormatter().string(from: Date()),
            "source": "https://github.com/tiann/hapi/releases/tag/v\(version)"
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let metadataURL = folder.appendingPathComponent("install.json")
        try data.write(to: metadataURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
        return destination
    }
}

private extension HAPIReleaseManifest {
    static func isVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+(\.[0-9]+){1,3}$"#, options: .regularExpression) != nil
    }
}

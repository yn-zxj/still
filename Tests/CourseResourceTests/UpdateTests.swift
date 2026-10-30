import Foundation
import CryptoKit
import Testing
@testable import Still

private final class UpdateProtocol: URLProtocol {
    static var status = 200
    static var payload = Data()
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct UpdateTests {
    func client(status: Int = 200) -> ReleaseClient {
        UpdateProtocol.status = status
        UpdateProtocol.payload = Data(#"{"tag_name":"v0.4.3","html_url":"https://github.com/yn-zxj/still/releases/tag/v0.4.3","draft":false,"prerelease":false,"assets":[{"id":1,"name":"Still-0.4.3-10-arm64-macos.zip","size":1024,"state":"uploaded"},{"id":2,"name":"Still-0.4.3-10-x86_64-arm64-macos.zip","size":2048,"state":"uploaded"}]}"#.utf8)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [UpdateProtocol.self]
        return ReleaseClient(session: URLSession(configuration: config))
    }
    @Test func publicChecksAreAnonymousAndPrivateChecksUseOnlyExplicitToken() async throws {
        let client = client()
        let release = try await client.latest(token: nil)
        #expect(release.valid)
        #expect(release.archive(architecture: "arm64")?.id == 1)
        #expect(release.archive(architecture: "x86_64")?.id == 2)
        #expect(UpdateProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
        _ = try await client.latest(token: "test-fixture-token")
        #expect(UpdateProtocol.lastRequest?.url?.host == "api.github.com")
        #expect(UpdateProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-fixture-token")
    }
    @Test func universalArchiveIsUsableFromEitherArchitecture() throws {
        let json = #"{"tag_name":"v0.4.3","html_url":"https://github.com/yn-zxj/still/releases/tag/v0.4.3","draft":false,"prerelease":false,"assets":[{"id":7,"name":"Still-0.4.3-10-x86_64-arm64-macos.zip","size":4096,"state":"uploaded"}]}"#
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.archive(architecture: "arm64")?.id == 7)
        #expect(release.archive(architecture: "x86_64")?.id == 7)
    }
    @Test func private404AndExpiredTokensAreNotReportedAsUpToDate() async {
        for code in [401, 404, 500] {
            let client = client(status: code)
            await #expect(throws: (any Error).self) { try await client.latest(token: nil) }
        }
    }
    @Test func untrustedReleaseAndIncompleteArtifactsAreRejected() async throws {
        let client = client()
        var json = String(data: UpdateProtocol.payload, encoding: .utf8)!
        json = json.replacingOccurrences(of: "https://github.com/yn-zxj/still", with: "https://example.com/evil/repo")
        UpdateProtocol.payload = Data(json.utf8)
        await #expect(throws: (any Error).self) { try await client.latest(token: nil) }
        _ = self.client()
        let asset = GitHubRelease.Asset(id: 1, name: "x", size: 90, state: "uploaded")
        UpdateProtocol.payload = Data("not-a-checksum".utf8)
        await #expect(throws: (any Error).self) { try await client.checksum(asset, token: nil) }
    }
    @Test func verifiedDownloadsCommitOnlyMatchingLengthAndDigest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("self-authored-install-package-fixture".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let asset = GitHubRelease.Asset(id: 1, name: "Still-0.4.0-7-arm64-macos.zip", size: Int64(payload.count), state: "uploaded")
        var staging: URL?
        let client = ReleaseClient(downloader: { request in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let temp = root.appendingPathComponent(UUID().uuidString)
            try payload.write(to: temp); staging = temp
            return (temp, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
        })
        let destination = root.appendingPathComponent("installed")
        let file = try await client.download(asset, checksum: digest, token: nil, root: destination)
        #expect(try Data(contentsOf: file) == payload)
        let replacement = try await client.download(asset, checksum: digest, token: nil, root: destination)
        #expect(try Data(contentsOf: replacement) == payload)
        #expect(staging.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
        await #expect(throws: (any Error).self) {
            try await client.download(asset, checksum: String(repeating: "0", count: 64), token: nil, root: destination)
        }
        #expect(try Data(contentsOf: file) == payload) // Bad downloads never replace the existing archive.
        let truncated = GitHubRelease.Asset(id: 2, name: asset.name, size: asset.size + 10, state: "uploaded")
        await #expect(throws: (any Error).self) { try await client.download(truncated, checksum: digest, token: nil, root: destination) }
        let traversal = GitHubRelease.Asset(id: 3, name: "../outside.zip", size: asset.size, state: "uploaded")
        await #expect(throws: (any Error).self) { try await client.download(traversal, checksum: digest, token: nil, root: destination) }
    }
    @Test func credentialsNeverFollowRedirectsToAssetHosts() throws {
        var request = URLRequest(url: URL(string: "https://release-assets.githubusercontent.com/archive")!)
        request.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
        request.setValue("private-cookie", forHTTPHeaderField: "Cookie")
        let redirected = try #require(ReleaseRedirectPolicy.redirected(request))
        #expect(redirected.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(redirected.value(forHTTPHeaderField: "Cookie") == nil)
        for url in ["http://api.github.com/file", "https://attacker.example/file", "https://api.github.com.attacker.example/file"] {
            #expect(ReleaseRedirectPolicy.redirected(URLRequest(url: URL(string: url)!)) == nil)
        }
    }
}

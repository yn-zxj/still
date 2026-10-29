import Foundation
import Testing
@testable import Still
@MainActor struct ResourceDiagnosticsTests {
    @Test func nestedNetworkCauseRemainsVisible() {
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: URLError(.timedOut)])
        #expect(ResourceDiagnostics.message(error).contains("-1001"))
        #expect(ResourceDiagnostics.message(ResourceRequestFailure.http(403)).contains("403"))
    }
    @Test func logsNeverIncludeResourcePathQueryOrCredentials() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let logger = ResourceDiagnostics(root: root)
        logger.record(kind: "image", url: URL(string: "https://example.test/private-course?token=DO_NOT_STORE"), error: URLError(.networkConnectionLost))
        let text = try String(contentsOf: root.appendingPathComponent("resource-errors.jsonl"))
        #expect(text.contains("example.test"))
        #expect(text.contains("-1005"))
        #expect(!text.contains("private-course"))
        #expect(!text.contains("DO_NOT_STORE"))
    }
}

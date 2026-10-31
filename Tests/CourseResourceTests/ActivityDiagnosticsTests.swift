import Foundation
import StillCore
import Testing
@testable import Still

@MainActor
@Suite(.serialized)
struct ActivityDiagnosticsTests {
    @Test func recordsTimingAndBundleWithoutWindowContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("still-activity-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let diagnostics = ActivityDiagnostics(root: root)
        let signals = ActivitySignalSnapshot(
            date: Date(timeIntervalSince1970: 1_790_000_000),
            available: true,
            inactivityConfirmed: false,
            systemIdleSeconds: 2,
            keyboardIdleSeconds: 3,
            playbackIdleSeconds: 4,
            foregroundProcessIdleSeconds: 0.5,
            foregroundBundleID: "com.example.editor"
        )
        let sample = ActivitySample(
            date: signals.date,
            monotonic: 100,
            idleSeconds: 0.5,
            available: true,
            foregroundApplication: ForegroundApplication(
                bundleID: "com.example.editor",
                name: "must-not-be-logged"
            )
        )

        diagnostics.record(
            sample: sample,
            phase: .working,
            trackingPaused: false,
            settings: MonitorSettings(),
            signals: signals,
            fatiguePercent: 12
        )

        let text = try String(contentsOf: diagnostics.fileURL, encoding: .utf8)
        #expect(text.contains("\"foregroundApplication\":\"com.example.editor\""))
        #expect(text.contains("\"foregroundProcessIdleSeconds\":0.5"))
        #expect(!text.contains("must-not-be-logged"))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        #expect(object["bucket"] as? String == "tracking")
        #expect(object["fatiguePercent"] as? Int == 12)
    }

    @Test func omitsBundleWhenApplicationInsightsAreDisabled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("still-activity-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let diagnostics = ActivityDiagnostics(root: root)
        var settings = MonitorSettings()
        settings.applicationInsightsEnabled = false
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        diagnostics.record(
            sample: ActivitySample(date: now, monotonic: 1, idleSeconds: 0),
            phase: .working,
            trackingPaused: false,
            settings: settings,
            signals: ActivitySignalSnapshot(date: now, available: true, foregroundBundleID: "com.example.private"),
            fatiguePercent: 1
        )

        let text = try String(contentsOf: diagnostics.fileURL, encoding: .utf8)
        #expect(!text.contains("com.example.private"))
        #expect(text.contains("\"foregroundApplication\":\"disabled\""))
    }
}

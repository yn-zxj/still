import Foundation
import StillCore

struct ActivitySignalSnapshot: Equatable {
    var date = Date()
    var available = false
    var inactivityConfirmed = false
    var systemIdleSeconds: Double?
    var keyboardIdleSeconds: Double?
    var playbackIdleSeconds: Double?
    var foregroundProcessIdleSeconds: Double?
    var foregroundBundleID: String?
}

/// Writes privacy-safe state transitions and one-minute snapshots.
/// The log contains timing and bundle identifiers, never app names, window
/// titles, page addresses, image data, typed text or input payloads.
@MainActor
final class ActivityDiagnostics {
    let root: URL
    var fileURL: URL { root.appendingPathComponent("activity.jsonl") }

    private var previousBucket: String?
    private var previousPhase: EnginePhase?
    private var lastWrittenAt = Date.distantPast
    private let maximumBytes = 512 * 1024

    init(root: URL) {
        self.root = root
    }

    func record(
        sample: ActivitySample,
        phase: EnginePhase,
        trackingPaused: Bool,
        settings: MonitorSettings,
        signals: ActivitySignalSnapshot,
        fatiguePercent: Int
    ) {
        let bucket: String
        if trackingPaused || phase == .paused {
            bucket = "paused"
        } else if phase == .resting {
            bucket = "resting"
        } else if !sample.available {
            bucket = "unavailable"
        } else if sample.idleSeconds >= Double(settings.idleSeconds) {
            bucket = "away"
        } else {
            bucket = "tracking"
        }

        let now = Date()
        let transition = bucket != previousBucket || phase != previousPhase
        guard transition || now.timeIntervalSince(lastWrittenAt) >= 60 else { return }
        previousBucket = bucket
        previousPhase = phase
        lastWrittenAt = now

        var event: [String: Any] = [
            "time": now.ISO8601Format(),
            "bucket": bucket,
            "phase": phase.title,
            "available": sample.available,
            "inactivityConfirmed": sample.inactivityConfirmed,
            "idleSeconds": rounded(sample.idleSeconds),
            "idleThresholdSeconds": settings.idleSeconds,
            "fatiguePercent": fatiguePercent,
            "foregroundApplication": settings.applicationInsightsEnabled
                ? (signals.foregroundBundleID ?? "none")
                : "disabled"
        ]
        event["systemIdleSeconds"] = optionalDouble(signals.systemIdleSeconds)
        event["keyboardIdleSeconds"] = optionalDouble(signals.keyboardIdleSeconds)
        event["playbackIdleSeconds"] = optionalDouble(signals.playbackIdleSeconds)
        event["foregroundProcessIdleSeconds"] = optionalDouble(signals.foregroundProcessIdleSeconds)
        append(event)
    }

    private func append(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var content = (try? Data(contentsOf: fileURL)) ?? Data()
            if content.count > maximumBytes {
                content = content.suffix(maximumBytes / 2)
                if let firstNewline = content.firstIndex(of: 10) {
                    content = content.suffix(from: content.index(after: firstNewline))
                }
            }
            content.append(data)
            content.append(10)
            try content.write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics must never interfere with usage tracking.
        }
    }

    private func rounded(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 10).rounded() / 10
    }

    private func optionalDouble(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return rounded(value)
    }
}

import AppKit
import CoreGraphics
import Foundation
import StillCore

@MainActor
final class SystemActivityMonitor {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock().now
    private var observers: [NSObjectProtocol] = []
    private var suspendedReasons = Set<String>()
    var onChange: (() -> Void)?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason, suspended) in [
            (NSWorkspace.willSleepNotification, "system", true),
            (NSWorkspace.didWakeNotification, "system", false),
            (NSWorkspace.screensDidSleepNotification, "display", true),
            (NSWorkspace.screensDidWakeNotification, "display", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if suspended { self?.suspendedReasons.insert(reason) }
                    else { self?.suspendedReasons.remove(reason) }
                    self?.onChange?()
                }
            })
        }
        // Supplementary compatibility signal. Public sleep/session notifications remain active.
        // These distributed notification names are not a documented locking API; see README.
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if locked { self?.suspendedReasons.insert("lock") }
                    else { self?.suspendedReasons.remove("lock") }
                    self?.onChange?()
                }
            })
        }
    }

    func sample(includeForegroundApplication: Bool = false) -> ActivitySample {
        let elapsed = origin.duration(to: clock.now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        // kCGAnyInputEventType is the documented sentinel, not CGEventType.null (0).
        let anyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let foreground = includeForegroundApplication ? Self.foregroundApplication() : nil
        return ActivitySample(date: Date(), monotonic: seconds, idleSeconds: anyIdle.isFinite ? max(0, anyIdle) : .infinity,
                              available: suspendedReasons.isEmpty && Self.sessionAvailable(), foregroundApplication: foreground)
    }

    // Notifications describe transitions; these queries also cover startup while
    // asleep/locked and transitions whose notification was missed.
    private static func sessionAvailable() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else {
            return false
        }
        return displays.prefix(Int(count)).contains {
            CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0
        }
    }

    private static func foregroundApplication() -> ForegroundApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return ForegroundApplication(
            bundleID: application.bundleIdentifier ?? "",
            name: application.localizedName ?? application.bundleIdentifier ?? "未知应用"
        )
    }
}

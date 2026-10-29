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

    func sample() -> ActivitySample {
        let elapsed = origin.duration(to: clock.now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        // kCGAnyInputEventType is the documented sentinel, not CGEventType.null (0).
        let anyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return ActivitySample(date: Date(), monotonic: seconds, idleSeconds: anyIdle.isFinite ? max(0, anyIdle) : 0,
                              available: suspendedReasons.isEmpty)
    }
}

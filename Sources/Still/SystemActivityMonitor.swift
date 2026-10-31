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
        // Query keyboard, pointer and scrolling separately. Do not let unrelated
        // event classes make a stationary computer appear continuously active.
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let idle = InputActivityTiming.latest(types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        })
        let state = suspendedReasons.isEmpty ? Self.sessionState() : .inactive
        let foreground = includeForegroundApplication ? Self.foregroundApplication() : nil
        return ActivitySample(date: Date(), monotonic: seconds, idleSeconds: idle ?? 0,
            available: state == .available && idle != nil, foregroundApplication: foreground,
            inactivityConfirmed: state == .inactive)
    }

    private enum SessionState { case available, inactive, unknown }

    // Notifications describe transitions; queries also cover startup and missed
    // transitions. Failed queries must not manufacture a confirmed rest period.
    private static func sessionState() -> SessionState {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool else { return .unknown }
        guard onConsole, session["CGSSessionScreenIsLocked"] as? Bool != true else { return .inactive }
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success,
              count > 0 else { return .unknown }
        let online = displays.prefix(Int(count))
        if online.contains(where: { CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0 }) { return .available }
        return online.allSatisfy { CGDisplayIsAsleep($0) != 0 } ? .inactive : .unknown
    }

    private static func foregroundApplication() -> ForegroundApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return ForegroundApplication(
            bundleID: application.bundleIdentifier ?? "",
            name: application.localizedName ?? application.bundleIdentifier ?? "未知应用"
        )
    }
}

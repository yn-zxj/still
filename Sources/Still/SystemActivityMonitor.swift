import AppKit
import CoreGraphics
import Darwin
import Foundation
import StillCore

@MainActor
final class SystemActivityMonitor: ObservableObject {
    let playbackActivity = PlaybackActivityMonitor()
    let foregroundProcessActivity = ForegroundProcessActivityMonitor()
    @Published private(set) var keyboardAuthorized = false
    @Published private(set) var keyboardStatus = "使用基础检测"
    @Published private(set) var signalSnapshot = ActivitySignalSnapshot()
    private let keyboard = KeyboardActivityListener()
    private var permissionCheckedAt: Double = -.infinity
    private let bootSessionID = SystemActivityMonitor.readBootSessionID()
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

    func sample(includeForegroundApplication: Bool = false, allowAuxiliaryDetection: Bool = true) -> ActivitySample {
        let seconds = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9
        let awakeSeconds = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
        let date = Date()
        let powerTime = SystemPowerTime(bootSessionID: bootSessionID, date: date,
                                        continuousSeconds: seconds, awakeSeconds: awakeSeconds)
        // Query keyboard, pointer and scrolling separately. Do not let unrelated
        // event classes make a stationary computer appear continuously active.
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let systemIdle = InputActivityTiming.latest(types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        })
        let state = suspendedReasons.isEmpty ? Self.sessionState() : .inactive
        let available = state == .available
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmost?.processIdentifier == getpid() ? nil : frontmost?.processIdentifier
        refreshKeyboardPermission(enableMonitoring: available && allowAuxiliaryDetection)
        playbackActivity.update(available: available && allowAuxiliaryDetection)
        let now = ProcessInfo.processInfo.systemUptime
        foregroundProcessActivity.update(
            processID: frontmostPID,
            available: available && allowAuxiliaryDetection,
            at: now
        )
        let keyboardIdle = keyboard.lastActivity.map { max(0, now - $0) }
        let playbackIdle = allowAuxiliaryDetection ? playbackActivity.idleSeconds(at: now) : nil
        let processIdle = allowAuxiliaryDetection ? foregroundProcessActivity.idleSeconds(at: now) : nil
        let idle = InputActivityTiming.latest([systemIdle, keyboardIdle, playbackIdle, processIdle].compactMap { $0 })
        let foreground = includeForegroundApplication ? frontmost.flatMap(Self.foregroundApplication) : nil
        signalSnapshot = ActivitySignalSnapshot(
            date: date,
            available: available,
            inactivityConfirmed: state == .inactive,
            systemIdleSeconds: systemIdle,
            keyboardIdleSeconds: keyboardIdle,
            playbackIdleSeconds: playbackIdle,
            foregroundProcessIdleSeconds: processIdle,
            foregroundBundleID: frontmost?.bundleIdentifier
        )
        return ActivitySample(date: date, monotonic: seconds, idleSeconds: idle ?? 0,
            available: state == .available && idle != nil, foregroundApplication: foreground,
            inactivityConfirmed: state == .inactive, powerTime: powerTime)
    }

    private static func readBootSessionID() -> UUID? {
        var buffer = [CChar](repeating: 0, count: 64)
        var size = buffer.count
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0,
              size > 0, size <= buffer.count, buffer[size - 1] == 0 else { return nil }
        return UUID(uuidString: String(cString: buffer))
    }

    func requestKeyboardAuthorization() {
        _ = CGRequestListenEventAccess()
        permissionCheckedAt = -.infinity
        refreshKeyboardPermission()
        if !keyboardAuthorized { openKeyboardPrivacy() }
    }
    func openKeyboardPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    private func refreshKeyboardPermission(enableMonitoring: Bool = true) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - permissionCheckedAt >= 5 {
            permissionCheckedAt = now
            keyboardAuthorized = CGPreflightListenEventAccess()
        }
        guard keyboardAuthorized, enableMonitoring else {
            keyboard.stop()
            keyboardStatus = keyboardAuthorized ? "已授权 · 休息或屏幕不可用时暂停" : "使用基础检测"
            return
        }
        keyboardStatus = keyboard.start() ? "已运行 · 只记录键盘活动时间" : "辅助监听暂不可用 · 使用基础检测"
    }
    func shutdown() {
        playbackActivity.shutdown()
        foregroundProcessActivity.shutdown()
        keyboard.stop()
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

    private static func foregroundApplication(_ application: NSRunningApplication) -> ForegroundApplication? {
        return ForegroundApplication(
            bundleID: application.bundleIdentifier ?? "",
            name: application.localizedName ?? application.bundleIdentifier ?? "未知应用"
        )
    }
}

/// A passive session tap needs Input Monitoring, not permission to modify input.
/// Only event occurrence time is retained; the event payload is never inspected.
private final class KeyboardActivityListener {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryAt: Double = 0
    private let lock = NSLock()
    private var activity: Double?
    var lastActivity: Double? { lock.lock(); defer { lock.unlock() }; return activity }
    func start() -> Bool {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return true }
        guard ProcessInfo.processInfo.systemUptime >= retryAt else { return false }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context {
                    let listener = Unmanaged<KeyboardActivityListener>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = listener.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    } else if type == .keyDown || type == .keyUp || type == .flagsChanged {
                        listener.lock.lock()
                        listener.activity = ProcessInfo.processInfo.systemUptime
                        listener.lock.unlock()
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            retryAt = ProcessInfo.processInfo.systemUptime + 15
            return false
        }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        lock.lock(); activity = nil; lock.unlock()
    }
}

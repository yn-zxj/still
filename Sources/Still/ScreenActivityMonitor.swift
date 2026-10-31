import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import StillCore

/// Captures only the current foreground window at low resolution. No audio,
/// recording output, OCR, image files or network transport are created.
@MainActor
final class ScreenActivityMonitor: NSObject, ObservableObject {
    @Published private(set) var status = "未授权 · 仅使用键鼠活动"
    @Published private(set) var authorized = false
    @Published private(set) var lastActivityDate: Date?
    private var stream: SCStream?
    private var receiver: FrameReceiver?
    private var target: CGWindowID?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var retryAt: Double = 0
    private var permissionCheckedAt: Double = -.infinity
    private var lastVisualActivity: Double?
    private var enabled = false
    private var lastFrameAt: Double?

    func requestAuthorization() {
        _ = CGRequestScreenCaptureAccess()
        refreshPermission()
        if !authorized { openPrivacySettings() }
    }
    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func refreshPermission() {
        authorized = CGPreflightScreenCaptureAccess()
        permissionCheckedAt = ProcessInfo.processInfo.systemUptime
        if !authorized { stop(); status = "未授权 · 仅使用键鼠活动" }
    }
    func update(available: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - permissionCheckedAt >= 5 { refreshPermission() }
        enabled = available
        if !available { lastVisualActivity = nil; lastActivityDate = nil }
        guard available, authorized else {
            stop()
            if authorized { status = "已授权 · 休息或屏幕不可用时暂停" }
            return
        }
        guard let id = Self.foregroundWindow() else {
            stop(); status = "已授权 · 当前窗口不参与检测"; return
        }
        if let lastFrameAt, now - lastFrameAt > 12 {
            stop(); retryAt = now + 5; status = "画面暂未更新 · 使用键鼠活动"
        }
        guard now >= retryAt, id != target || stream == nil && task == nil else { return }
        stop(); target = id
        let request = generation
        status = "正在连接前台窗口…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard request == generation, enabled, authorized else { return }
                guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = 160; config.height = 90
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 600)
                config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
                let output = FrameReceiver { [weak self] activity in
                    Task { @MainActor in
                        guard let self, self.generation == request, self.enabled else { return }
                        self.lastFrameAt = ProcessInfo.processInfo.systemUptime
                        if let activity, activity != self.lastVisualActivity {
                            self.lastVisualActivity = activity
                            self.lastActivityDate = Date().addingTimeInterval(activity - ProcessInfo.processInfo.systemUptime)
                        }
                        self.status = "已运行 · 自动识别前台画面变化"
                    }
                }
                let capture = SCStream(filter: filter, configuration: config, delegate: output)
                try capture.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                self.receiver = output; self.stream = capture
                try await capture.startCapture()
                guard request == generation else { try? await capture.stopCapture(); return }
                lastFrameAt = ProcessInfo.processInfo.systemUptime
                status = "已运行 · 自动识别前台画面变化"
                task = nil
            } catch {
                guard request == generation else { return }
                stop(); retryAt = ProcessInfo.processInfo.systemUptime + 15
                status = "暂不可用 · 使用键鼠活动，可检查权限或重新打开息间"
            }
        }
    }
    func idleSeconds(at now: Double) -> Double? {
        guard enabled, let lastVisualActivity, now >= lastVisualActivity else { return nil }
        return now - lastVisualActivity
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        let old = stream; stream = nil; receiver = nil; target = nil; lastFrameAt = nil
        if let old { Task { try? await old.stopCapture() } }
    }
    func shutdown() { enabled = false; stop() }
    private enum CaptureError: Error { case noWindow }

    private static func foregroundWindow() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !["com.apple.loginwindow", "com.apple.dock", "com.apple.finder"].contains(app.bundleIdentifier ?? ""),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.first(where: { info in
            guard info[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double else { return false }
            return width >= 240 && height >= 140
        })?[kCGWindowNumber as String] as? CGWindowID
    }
}

private final class FrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "local.still.activity-frames", qos: .utility)
    private var evidence = ScreenActivityEvidence()
    private let receive: (Double?) -> Void
    init(receive: @escaping (Double?) -> Void) { self.receive = receive }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              raw == SCFrameStatus.complete.rawValue || raw == SCFrameStatus.idle.rawValue else { evidence.reset(); return }
        if raw == SCFrameStatus.idle.rawValue { receive(nil); return }
        guard let pixels = Self.fingerprint(sampleBuffer) else { evidence.reset(); return }
        evidence.observe(pixels, at: ProcessInfo.processInfo.systemUptime)
        receive(evidence.lastActivity)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { self.evidence.reset() } }
    static func fingerprint(_ buffer: CMSampleBuffer) -> [UInt8]? {
        guard let image = CMSampleBufferGetImageBuffer(buffer), CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(image) else { return nil }
        let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image), stride = CVPixelBufferGetBytesPerRow(image)
        guard width > 0, height > 0 else { return nil }
        let data = base.assumingMemoryBound(to: UInt8.self)
        return (0..<ScreenActivityEvidence.height).flatMap { y in
            (0..<ScreenActivityEvidence.width).map { x -> UInt8 in
                let index = (y * height / ScreenActivityEvidence.height) * stride + (x * width / ScreenActivityEvidence.width) * 4
                return UInt8((Int(data[index]) * 29 + Int(data[index+1]) * 150 + Int(data[index+2]) * 77) / 256)
            }
        }
    }
}

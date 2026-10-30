import AppKit
import AVFoundation
import Vision
import SwiftUI
import StillCore

struct PostureOverlay: Equatable {
    var contours: [[CGPoint]] = []
    var joints: [CGPoint] = []
    static let empty = PostureOverlay()
}

/// Session setup and Vision inference stay on the same serial queue. No image is saved or transmitted.
final class PostureCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let poseDetector = OpenPoseDetector()
    private let queue = DispatchQueue(label: "local.still.posture.camera", qos: .utility)
    private var lastFrame: Double = 0
    private var runningID = UUID()
    private var overlayEnabled = false
    var onOverlay: ((UUID, PostureOverlay) -> Void)?
    var onSample: ((UUID, PostureSample?) -> Void)?
    var onStatus: ((UUID, String?) -> Void)?
    var onAspect: ((UUID, Double) -> Void)?
    var onDevice: ((UUID, String) -> Void)?

    func setOverlayEnabled(_ enabled: Bool) { queue.async { [self] in overlayEnabled = enabled } }

    func start(id: UUID) {
        queue.async { [self] in
            runningID = id
            do {
                if session.inputs.isEmpty {
                    guard let device = AVCaptureDevice.default(for: .video) else {
                        onStatus?(id, "没有找到摄像头。连接摄像头后点击重新连接。"); return
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: queue)
                    session.beginConfiguration()
                    session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .vga640x480
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration(); onStatus?(id, "无法打开摄像头，请确认没有被其它应用独占。"); return
                    }
                    session.addInput(input); session.addOutput(output); session.commitConfiguration()
                    onDevice?(id, device.localizedName)
                }
                try poseDetector.prepare()
                session.startRunning()
                if let input = session.inputs.first as? AVCaptureDeviceInput {
                    let size = CMVideoFormatDescriptionGetDimensions(input.device.activeFormat.formatDescription)
                    if size.height > 0 { onAspect?(id, Double(size.width) / Double(size.height)) }
                }
                onStatus?(id, session.isRunning ? nil : "摄像头没有启动，请检查连接后重试。")
            } catch { onStatus?(id, "坐姿模型或摄像头加载失败：\(error.localizedDescription)") }
        }
    }
    func stop() {
        queue.async { [self] in
            session.stopRunning()
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= (overlayEnabled ? 0.25 : 0.5) else { return }
        lastFrame = now
        guard let image = CMSampleBufferGetImageBuffer(buffer) else { onSample?(runningID, nil); return }
        let faceRequest = VNDetectFaceRectanglesRequest()
        var drawing = PostureOverlay.empty
        defer { onOverlay?(runningID, drawing) }
        do {
            try VNImageRequestHandler(cvPixelBuffer: image, orientation: .up, options: [:]).perform([faceRequest])
            let faces = (faceRequest.results ?? []).filter { $0.confidence >= 0.6 }
            guard faces.count == 1, let face = faces.first,
                  let yaw = face.yaw?.doubleValue, let roll = face.roll?.doubleValue, let pitch = face.pitch?.doubleValue else {
                onSample?(runningID, nil); return
            }
            let box = face.boundingBox
            guard box.minX > 0.015, box.maxX < 0.985, box.minY > 0.015, box.maxY < 0.985 else {
                onSample?(runningID, nil); return
            }
            if overlayEnabled {
                let landmarks = VNDetectFaceLandmarksRequest()
                landmarks.inputFaceObservations = [face]
                try? VNImageRequestHandler(cvPixelBuffer: image, orientation: .up, options: [:]).perform([landmarks])
                if let parts = landmarks.results?.first?.landmarks {
                    for region in [parts.faceContour, parts.leftEye, parts.rightEye, parts.leftEyebrow,
                                   parts.rightEyebrow, parts.noseCrest, parts.medianLine, parts.outerLips].compactMap({ $0 }) {
                        let line = region.normalizedPoints.map { CGPoint(x: box.minX + CGFloat($0.x) * box.width, y: box.minY + CGFloat($0.y) * box.height) }
                        drawing.contours.append(line)
                        if let first = line.first { drawing.joints.append(first) }
                    }
                }
            }
            let aspect = Double(CVPixelBufferGetHeight(image)) / Double(CVPixelBufferGetWidth(image))
            // A cropped upper body may produce NO body observation even when the face is clear.
            // Keep honest head-only measurements; never invent shoulder landmarks to unblock calibration.
            var sample = PostureSample(time: now, faceHeight: box.height * aspect, shoulderWidth: 0, neckHeight: 0,
                headRoll: roll * 180 / .pi, shoulderRoll: 0, pitch: pitch * 180 / .pi, yaw: yaw * 180 / .pi,
                centerX: box.midX, centerY: box.midY, confidence: Double(face.confidence), hasShoulders: false)
            if let pose = try poseDetector.detect(in: image, face: box) {
                let left = pose.leftShoulder.point, right = pose.rightShoulder.point
                let centerY = (left.y + right.y) / 2
                let width = hypot(left.x - right.x, (left.y - right.y) * aspect)
                if width > 0.12, centerY > 0.015 {
                    let angle = atan2((left.y - right.y) * aspect, left.x - right.x) * 180 / .pi
                    sample.shoulderRoll = angle > 90 ? angle - 180 : angle < -90 ? angle + 180 : angle
                    sample.shoulderWidth = width; sample.neckHeight = (box.midY - centerY) * aspect
                    sample.hasShoulders = true
                    if overlayEnabled {
                        let neck = pose.neck.point, nose = pose.nose.point
                        drawing.contours += [[left, neck, right], [left, right], [neck, nose]]
                        drawing.joints += [left, neck, right, nose]
                        for (shoulder, elbow) in [(left, pose.leftElbow), (right, pose.rightElbow)] {
                            if let elbow { drawing.contours.append([shoulder, elbow.point]); drawing.joints.append(elbow.point) }
                        }
                    }
                }
            }
            onSample?(runningID, sample)
        } catch { onSample?(runningID, nil) }
    }
}

@MainActor
final class PostureMonitor: ObservableObject {
    @Published private(set) var overlay = PostureOverlay.empty
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var paused = false
    @Published private(set) var error: String?
    @Published private(set) var previewAspect: Double = 4 / 3
    @Published private(set) var cameraName = "Mac 摄像头"
    @Published private(set) var assessment = PostureEngine().assessment
    @Published private(set) var lastSample: PostureSample?
    let camera = PostureCamera()
    private let defaults: UserDefaults
    private var engine = PostureEngine()
    private var id = UUID()
    private var enabled = false
    private var available = true
    private var permissionPending = false
    private var staleTimer: Timer?
    private var lastFrameAt: Date?
    private var observers: [NSObjectProtocol] = []
    var baseline: PostureSample? { engine.baseline }
    var onPreview: (() -> Void)?
    func previewAlert() { onPreview?() }
    var onAlert: ((PostureIssue) -> Void)?
    var session: AVCaptureSession { camera.session }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paused = defaults.bool(forKey: "posture.paused.v1")
        camera.onOverlay = { [weak self] id, drawing in Task { @MainActor in
            guard let self, self.id == id, self.running else { return }; self.overlay = drawing
        } }
        camera.onSample = { [weak self] id, sample in Task { @MainActor in self?.receive(id: id, sample: sample) } }
        camera.onStatus = { [weak self] id, error in Task { @MainActor in
            guard let self, self.id == id, self.enabled, !self.paused, self.available else { return }
            self.starting = false; self.running = error == nil; self.error = error
            self.lastFrameAt = Date()
        } }
        camera.onAspect = { [weak self] id, aspect in Task { @MainActor in if self?.id == id { self?.previewAspect = aspect } } }
        camera.onDevice = { [weak self] id, name in Task { @MainActor in if self?.id == id { self?.cameraName = name } } }
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: camera.session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopCapture(); self?.error = "摄像头已中断。检查权限、连接或其它正在使用摄像头的应用，然后重新连接。"
                }
            })
        }
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running, let last = self.lastFrameAt, Date().timeIntervalSince(last) > 4 else { return }
                self.assessment = self.engine.ingest(nil); self.lastSample = nil; self.overlay = .empty
            }
        }
    }
    func configure(enabled: Bool, requestPermission: Bool = false) {
        self.enabled = enabled
        if !enabled { paused = false; defaults.set(false, forKey: "posture.paused.v1"); stopCapture(clearReference: true); return }
        if requestPermission { paused = false; defaults.set(false, forKey: "posture.paused.v1") }
        guard available, !paused else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCapture()
        case .notDetermined:
            guard requestPermission, !permissionPending else { error = "点击开启摄像头，允许息间使用相机后开始校准。"; return }
            permissionPending = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in Task { @MainActor in
                guard let self else { return }; self.permissionPending = false
                self.configure(enabled: self.enabled)
            } }
        default: error = "摄像头权限未开启。请在系统设置的「隐私与安全性 → 摄像头」中允许息间。"
        }
    }
    func setAvailable(_ value: Bool) {
        guard available != value else { return }
        available = value
        if value { configure(enabled: enabled) } else { stopCapture() }
    }
    func togglePause() {
        paused.toggle(); defaults.set(paused, forKey: "posture.paused.v1")
        if paused { stopCapture() } else { configure(enabled: enabled, requestPermission: true) }
    }
    func reconnect() { stopCapture(clearReference: true); configure(enabled: enabled, requestPermission: true) }
    private func startCapture() {
        guard !running, !starting else { return }
        error = nil; starting = true; id = UUID(); engine.resetEvidence()
        assessment = engine.assessment; camera.start(id: id)
    }
    private func stopCapture(clearReference: Bool = false) {
        id = UUID(); camera.stop(); running = false; starting = false
        if clearReference { engine.reset() } else { engine.resetEvidence() }
        lastSample = nil; overlay = .empty
        assessment = PostureEngine().assessment
    }
    func setPreviewVisible(_ visible: Bool) { camera.setOverlayEnabled(visible); if !visible { overlay = .empty } }
    func calibrate() { guard running else { return }; engine.beginCalibration(); assessment = engine.assessment }
    private func receive(id: UUID, sample: PostureSample?) {
        guard self.id == id, enabled, available, !paused, running else { return }
        lastFrameAt = Date(); lastSample = sample?.usable == true ? sample : nil
        assessment = engine.ingest(sample)
        if assessment.shouldAlert, let issue = assessment.issues.first { onAlert?(issue) }
    }
    func shutdown() { staleTimer?.invalidate(); camera.stop() }
    var statusTitle: String {
        if paused { return "监测已暂停" }
        if !available { return "休息或锁屏期间暂停" }
        if starting { return "正在打开摄像头" }
        if error != nil { return "等待摄像头" }
        guard running else { return "摄像头未开启" }
        switch assessment.state {
        case .uncalibrated: return "先记住你舒服的坐姿"
        case .calibrating: return "自然坐好，保持片刻"
        case .unavailable: return "请正对镜头，让面部完整入镜"
        case .aligned: return "与校准姿势接近"
        case .deviation: return assessment.issues.map(\.title).joined(separator: " · ")
        }
    }
}

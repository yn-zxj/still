import AppKit
import SwiftUI
import StillCore

@MainActor
private final class ReminderContentState: ObservableObject {
    @Published var course: Course?
    @Published var presentation: RestPresentation = .due
    @Published var previewDeadline: Date?
    let previewPlayer: CoursePlayer
    init(model: AppModel) { previewPlayer = CoursePlayer(cache: model.library.videoCache, diagnostics: model.library.diagnostics) }
}

enum ReminderManualClosePolicy {
    static func shouldSnooze(_ presentation: RestPresentation?) -> Bool {
        switch presentation {
        case .due?, .resting?: true
        default: false
        }
    }
}

@MainActor
final class ReminderWindowController {
    private let model: AppModel
    private let content: ReminderContentState
    private var panels: [RestPanel] = []
    private var current: RestPresentation?
    private var currentStyle: ReminderStyle = .mini
    private var appearance: NSAppearance?
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var previewTimer: Timer?
    private var trainingDisplayID: UInt32?
    static var windowLevel: NSWindow.Level { .screenSaver }

    init(model: AppModel) {
        self.model = model; content = ReminderContentState(model: model)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDisplays()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.raisePanels() }
        }
    }
    private func raisePanels() {
        guard !NSApplication.shared.isHidden else { return }
        for panel in panels { panel.level = Self.windowLevel; panel.orderFrontRegardless() }
    }
    func present(_ presentation: RestPresentation, style: ReminderStyle) {
        if style == .simple && presentation == .completed { close(); return }
        // A completed, automatically started break should dismiss its reminder
        // instead of replacing the countdown with a second completion panel.
        if presentation == .completed, current == .resting, content.course == nil {
            close()
            return
        }
        if presentation == .due && (current == .resting || current == .preview || content.course != nil) { return }
        let fresh = current == nil
        close()
        current = presentation; currentStyle = style; content.presentation = presentation
        if presentation != .completed { model.prepareRecommendation(preview: presentation == .preview, shuffle: fresh) }
        if style == .simple, presentation == .preview {
            content.previewDeadline = Date().addingTimeInterval(model.settings.restSeconds)
            previewTimer = Timer.scheduledTimer(withTimeInterval: model.settings.restSeconds, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
            if let previewTimer { RunLoop.main.add(previewTimer, forMode: .common) }
        }
        updateDisplays()
        if presentation == .preview || style != .simple && (style == .fullScreen || presentation == .resting) {
            NSApplication.shared.activate(ignoringOtherApps: true); panels.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func updateDisplays() {
        guard current != nil else { return }
        let displays = ReminderDisplay.current()
        let targets = ReminderDisplayLayout.targets(displays, trainingDisplayID: trainingDisplayID)
        // Keep the same hosting view/player when its monitor disappears. Recreating
        // a workout view would run its autoplay task again and lose paused state.
        if content.course != nil, let panel = panels.first {
            guard let display = targets.first else {
                panel.orderOut(nil)
                (content.presentation == .preview ? content.previewPlayer : model.coursePlayer).pause()
                return
            }
            trainingDisplayID = display.id; panel.displayID = display.id
            position(panel, on: display); panel.orderFrontRegardless()
            return
        }
        let ids = Set(targets.map(\.id))
        for panel in panels where !ids.contains(panel.displayID) { remove(panel) }
        panels.removeAll { !ids.contains($0.displayID) }
        for display in targets {
            let panel: RestPanel
            if let existing = panels.first(where: { $0.displayID == display.id }) { panel = existing }
            else {
                panel = makePanel(displayID: display.id)
                panels.append(panel)
            }
            position(panel, on: display); panel.orderFrontRegardless()
        }
    }

    private func makePanel(displayID: UInt32) -> RestPanel {
        let full = currentStyle == .fullScreen, simple = currentStyle == .simple
        let panel = RestPanel(contentRect: .zero,
            styleMask: full || simple ? [.borderless, .nonactivatingPanel] : [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.displayID = displayID
        panel.title = simple ? "息间 · 简洁提醒" : full ? "息间 · 全屏提醒" : "息间 · 休息"
        panel.appearance = appearance
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = Self.windowLevel
        panel.onEscape = { [weak self] in self?.dismissManually() }
        panel.contentView = NSHostingView(rootView: ReminderPanelContent(model: model, content: content, style: currentStyle,
            choose: { [weak self, weak panel] course in if let panel { self?.open(course, in: panel) } },
            back: { [weak self, weak panel] in if let panel { self?.back(in: panel) } },
            close: { [weak self] in self?.dismissManually() }))
        if simple {
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        } else if !full {
            panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
            panel.isMovableByWindowBackground = true
        }
        return panel
    }

    private func position(_ panel: RestPanel, on display: ReminderDisplay) {
        let size: NSSize
        if currentStyle == .simple {
            let textWidth = (SimpleRestView.message(model: model) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)]).width
            size = NSSize(width: min(860, max(260, ceil(textWidth) + 150)), height: 50)
        } else if content.course != nil { size = NSSize(width: 880, height: 760) }
        else { size = NSSize(width: 440, height: current == .completed ? 470 : model.settings.coursesEnabled ? 660 : 460) }
        panel.setFrame(ReminderDisplayLayout.frame(on: display, style: currentStyle, preferredSize: size), display: true)
    }

    private func remove(_ panel: RestPanel) {
        panel.orderOut(nil); panel.contentView = nil; panel.close()
    }
    private func open(_ course: Course, in panel: RestPanel) {
        guard model.settings.coursesEnabled else { return }
        trainingDisplayID = panel.displayID
        for other in panels where other !== panel { remove(other) }
        panels = [panel]
        let preview = content.presentation == .preview
        let player = preview ? content.previewPlayer : model.coursePlayer
        if !preview { model.inReminderTraining = true }
        if course.media?.webpage != nil {
            player.stop()
            if !preview { model.endRest() }
        } else if player.courseID != course.id || player.error != nil || player.finished {
            player.load(course, url: model.library.mediaURL(for: course))
        }
        content.course = course
        updateDisplays()
        NSApplication.shared.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    private func back(in panel: RestPanel) {
        let preview = content.presentation == .preview
        let player = preview ? content.previewPlayer : model.coursePlayer
        let wasActive = player.active
        let wasWeb = content.course?.media?.webpage != nil
        player.stop(); content.course = nil; model.inReminderTraining = false; trainingDisplayID = nil
        if !preview && (wasActive || wasWeb) {
            // Return to an actual running countdown, never a stale 00:00 view.
            model.startRest()
            return
        }
        model.prepareRecommendation(preview: preview, shuffle: true)
        updateDisplays()
    }
    func dismissIfDue() { if current == .due && content.course == nil { close() } }
    private func dismissManually() {
        if ReminderManualClosePolicy.shouldSnooze(current) { model.snooze() }
        close()
    }
    func applyAppearance(_ appearance: NSAppearance?) {
        self.appearance = appearance
        for panel in panels { panel.appearance = appearance }
    }
    func close() {
        previewTimer?.invalidate(); previewTimer = nil; content.previewDeadline = nil
        if let course = content.course {
            if content.presentation == .preview { content.previewPlayer.unload() }
            else { model.coursePlayer.pause(); model.library.selectedID = course.id }
        }
        model.inReminderTraining = false; content.course = nil
        for panel in panels { remove(panel) }
        panels.removeAll(); current = nil; trainingDisplayID = nil
    }
}

private struct ReminderPanelContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var content: ReminderContentState
    let style: ReminderStyle
    let choose: (Course) -> Void
    let back: () -> Void
    let close: () -> Void
    var body: some View {
        Group {
            if let course = content.course {
                ReminderWorkoutView(model: model, course: course,
                    player: content.presentation == .preview ? content.previewPlayer : model.coursePlayer,
                    preview: content.presentation == .preview, back: back, close: close)
            } else if style == .simple {
                SimpleRestView(model: model, previewDeadline: content.previewDeadline, close: close)
            } else if style == .fullScreen {
                FullScreenRestView(model: model, presentation: content.presentation, close: close, chooseCourse: choose)
            } else { RestView(model: model, presentation: content.presentation, close: close, chooseCourse: choose) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class RestPanel: NSPanel {
    var displayID: UInt32 = 0
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

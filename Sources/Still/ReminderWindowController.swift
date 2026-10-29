import AppKit
import SwiftUI
import StillCore

@MainActor
private final class ReminderContentState: ObservableObject {
    @Published var course: Course?
    @Published var presentation: RestPresentation = .due
    let previewPlayer: CoursePlayer
    init(model: AppModel) { previewPlayer = CoursePlayer(cache: model.library.videoCache, diagnostics: model.library.diagnostics) }
}

@MainActor
final class ReminderWindowController {
    private let model: AppModel
    private let content: ReminderContentState
    private var panels: [RestPanel] = []
    private var current: RestPresentation?
    private var currentStyle: ReminderStyle = .mini
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    static var windowLevel: NSWindow.Level { .screenSaver }

    init(model: AppModel) {
        self.model = model; content = ReminderContentState(model: model)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let current = self.current else { return }
                if self.content.course == nil { self.present(current, style: self.currentStyle) }
                else if self.currentStyle == .fullScreen, let panel = self.panels.first, let screen = panel.screen ?? NSScreen.main { panel.setFrame(screen.frame, display: true) }
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
        if presentation == .due && (current == .resting || current == .preview || content.course != nil) { return }
        let fresh = current == nil
        close()
        current = presentation; currentStyle = style; content.presentation = presentation
        if presentation != .completed { model.prepareRecommendation(preview: presentation == .preview, shuffle: fresh) }
        let screens = style == .fullScreen ? NSScreen.screens : [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        for screen in screens {
            let full = style == .fullScreen
            let panel = RestPanel(contentRect: full ? screen.frame : .zero,
                                  styleMask: full ? [.borderless] : [.titled, .fullSizeContentView, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            panel.title = full ? "息间 · 全屏提醒" : "息间 · 休息"
            panel.appearance = NSAppearance(named: .aqua)
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.level = Self.windowLevel
            panel.onEscape = { [weak self] in self?.close() }
            panel.contentView = NSHostingView(rootView: ReminderPanelContent(model: model, content: content, full: full,
                choose: { [weak self, weak panel] course in if let panel { self?.open(course, in: panel) } },
                back: { [weak self, weak panel] in if let panel { self?.back(in: panel) } }, close: { [weak self] in self?.close() }))
            if full { panel.setFrame(screen.frame, display: true) }
            else {
                panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
                for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
                panel.isMovableByWindowBackground = true
                panel.setContentSize(NSSize(width: 440, height: min(presentation == .completed ? 470 : presentation == .due ? 720 : 660, screen.visibleFrame.height - 40)))
                panel.center()
            }
            panels.append(panel); panel.orderFrontRegardless()
        }
        if style == .fullScreen || presentation == .preview || presentation == .resting {
            NSApplication.shared.activate(ignoringOtherApps: true); panels.first?.makeKeyAndOrderFront(nil)
        }
    }
    private func open(_ course: Course, in panel: RestPanel) {
        for other in panels where other !== panel { other.orderOut(nil); other.contentView = nil; other.close() }
        panels = [panel]
        let preview = content.presentation == .preview
        let player = preview ? content.previewPlayer : model.coursePlayer
        if !preview { model.inReminderTraining = true }
        if player.courseID != course.id || player.error != nil || player.finished { player.load(course, url: model.library.mediaURL(for: course)) }
        content.course = course
        if currentStyle == .mini, let screen = panel.screen ?? NSScreen.main {
            let size = NSSize(width: min(880, screen.visibleFrame.width - 60), height: min(760, screen.visibleFrame.height - 40))
            panel.setContentSize(size); panel.center()
        }
        NSApplication.shared.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    private func back(in panel: RestPanel) {
        let preview = content.presentation == .preview
        let player = preview ? content.previewPlayer : model.coursePlayer
        let wasActive = player.active
        player.stop(); content.course = nil; model.inReminderTraining = false
        if !preview && wasActive { content.presentation = .due; current = .due }
        model.prepareRecommendation(preview: preview, shuffle: true)
        if currentStyle == .mini, let screen = panel.screen ?? NSScreen.main {
            panel.setContentSize(NSSize(width: 440, height: min(content.presentation == .preview ? 660 : 720, screen.visibleFrame.height - 40))); panel.center()
        }
    }
    func dismissIfDue() { if current == .due && content.course == nil { close() } }
    func close() {
        if let course = content.course {
            if content.presentation == .preview { content.previewPlayer.unload() }
            else { model.coursePlayer.pause(); model.library.selectedID = course.id }
        }
        model.inReminderTraining = false; content.course = nil
        for panel in panels { panel.orderOut(nil); panel.contentView = nil; panel.close() }
        panels.removeAll(); current = nil
    }
}

private struct ReminderPanelContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var content: ReminderContentState
    let full: Bool
    let choose: (Course) -> Void
    let back: () -> Void
    let close: () -> Void
    var body: some View {
        Group {
            if let course = content.course {
                ReminderWorkoutView(model: model, course: course,
                    player: content.presentation == .preview ? content.previewPlayer : model.coursePlayer,
                    preview: content.presentation == .preview, back: back, close: close)
            } else if full {
                FullScreenRestView(model: model, presentation: content.presentation, close: close, chooseCourse: choose)
            } else { RestView(model: model, presentation: content.presentation, close: close, chooseCourse: choose) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class RestPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

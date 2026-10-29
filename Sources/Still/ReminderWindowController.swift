import AppKit
import SwiftUI
import StillCore

@MainActor
final class ReminderWindowController {
    private let model: AppModel
    private var panels: [RestPanel] = []
    private var current: RestPresentation?
    private var currentStyle: ReminderStyle = .mini
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let current = self.current, self.currentStyle == .fullScreen else { return }
                self.present(current, style: .fullScreen)
            }
        }
    }

    func present(_ presentation: RestPresentation, style: ReminderStyle) {
        if presentation == .due && (current == .resting || current == .preview) { return }
        close()
        current = presentation; currentStyle = style
        let screens = style == .fullScreen ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let full = style == .fullScreen
            let panel = RestPanel(contentRect: full ? screen.frame : .zero,
                                  styleMask: full ? [.borderless] : [.titled, .fullSizeContentView, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            panel.title = full ? "息间 · 全屏提醒" : "息间 · 休息"
            panel.appearance = NSAppearance(named: .aqua)
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.level = full ? .screenSaver : .floating
            panel.onEscape = { [weak self] in self?.close() }
            if full {
                panel.contentView = NSHostingView(rootView: FullScreenRestView(model: model, presentation: presentation, close: { [weak self] in self?.close() }))
                panel.setFrame(screen.frame, display: true)
            } else {
                panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
                for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
                panel.isMovableByWindowBackground = true
                panel.contentView = NSHostingView(rootView: RestView(model: model, presentation: presentation, close: { [weak self] in self?.close() }))
                panel.setContentSize(NSSize(width: 390, height: presentation == .completed ? 470 : 570))
                panel.center()
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        if style == .fullScreen || presentation == .preview || presentation == .resting {
            NSApplication.shared.activate(ignoringOtherApps: true)
            panels.first?.makeKeyAndOrderFront(nil)
        }
    }

    func dismissIfDue() { if current == .due { close() } }
    func close() {
        for panel in panels { panel.orderOut(nil); panel.contentView = nil; panel.close() }
        panels.removeAll(); current = nil
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

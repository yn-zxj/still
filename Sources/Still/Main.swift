import AppKit
import SwiftUI
import StillCore

@main
struct StillMain {
    @MainActor static func main() {
        if ProcessInfo.processInfo.arguments.contains("--verify-bundle") { exit(BundleVerification.run()) }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        let dockVisible = UserDefaults.standard.data(forKey: "settings.v1")
            .flatMap { try? JSONDecoder().decode(MonitorSettings.self, from: $0) }
            .map(\.dockIconVisible) ?? true
        application.setActivationPolicy(dockVisible ? .regular : .accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class PopoverVisibility: ObservableObject {
    @Published var isShown = false
}

private struct PopoverMenuHost: View {
    @ObservedObject var visibility: PopoverVisibility
    let model: AppModel
    let open: () -> Void
    let insights: () -> Void
    let settings: () -> Void
    let close: () -> Void

    var body: some View {
        if visibility.isShown {
            MenuPanelView(model: model, open: open, insights: insights, settings: settings, close: close)
        } else {
            Color.clear.frame(width: 500, height: 10)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var model: AppModel!
    private var mainWindow: NSWindow!
    private var reminders: ReminderWindowController?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let popoverVisibility = PopoverVisibility()
    private let postureAlerts = PostureAlertController()
    private var visibilityObserver: NSObjectProtocol?
    private var popoverEventMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            running.activate(options: [.activateIgnoringOtherApps])
            if let url = running.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
            NSApplication.shared.terminate(nil)
            return
        }
        setupMenu()
        model = AppModel()
        let root = DashboardView(model: model)
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 790),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        mainWindow.title = "息间 · 用眼与休息"
        mainWindow.titleVisibility = .hidden
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.backgroundColor = Palette.backgroundNSColor
        mainWindow.minSize = NSSize(width: 1020, height: 720)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.contentView = NSHostingView(rootView: root)
        visibilityObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: mainWindow, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAnimationVisibility() }
        }
        mainWindow.center()
        setupStatusItem()
        model.applyAppearance = { [weak self] in self?.applyWindowAppearance() }
        model.applyDockVisibility = { [weak self] in self?.applyDockVisibility() }
        model.showDashboard = { [weak self] in self?.showMainWindow() }
        model.showPreview = { [weak self] in self?.presentRest(.preview) }
        model.showReminder = { [weak self] in self?.presentRest(.due) }
        model.showRest = { [weak self] in self?.presentRest(.resting) }
        model.showCompletion = { [weak self] in self?.presentRest(.completed) }
        model.hideAllReminders = { [weak self] in self?.reminders?.close() }
        model.hideReminder = { [weak self] in self?.reminders?.dismissIfDue() }
        model.refreshMenu = { [weak self] in self?.refreshStatusItem() }
        model.posture.onAlert = { [weak self] issue in self?.presentPostureAlert(issue) }
        model.posture.onPreview = { [weak self] issue in self?.presentPostureAlert(issue, preview: true) }
        applyWindowAppearance()
        installPopoverDismissMonitors()
        showMainWindow()
        refreshStatusItem()
        if ProcessInfo.processInfo.arguments.contains("--preview-rest") { presentRest(.preview) }
        if model.isUITest && ProcessInfo.processInfo.arguments.contains("--test-reminder-due") { presentRest(.due) }
        if model.engine.phase == .due && model.settings.remindersEnabled { presentRest(.due) }
    }

    private func setupMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于息间", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "检查更新…", action: #selector(checkUpdates), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏息间", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "退出息间", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem(); editItem.submenu = editMenu; menu.addItem(editItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "打开主窗口", action: #selector(openMain), keyEquivalent: "0"))
        let quickPanel = NSMenuItem(title: "显示快捷面板", action: #selector(togglePopover), keyEquivalent: "m")
        quickPanel.keyEquivalentModifierMask = [.command, .shift]
        quickPanel.target = self
        windowMenu.addItem(quickPanel)
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: ""); windowItem.submenu = windowMenu; menu.addItem(windowItem)
        NSApplication.shared.mainMenu = menu
    }

    private var effectiveMotionEnabled: Bool {
        model.settings.motionEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func closePopover() {
        popover.animates = effectiveMotionEnabled
        if popover.isShown { popover.performClose(nil) }
        popoverVisibility.isShown = false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = LineIcon.menuImage("leaf")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.setAccessibilityLabel("息间")
        statusItem.button?.setAccessibilityHelp("打开息间快捷面板")
        statusItem.button?.toolTip = nil
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverMenuHost(
            visibility: popoverVisibility,
            model: model,
            open: { [weak self] in self?.closePopover(); self?.showMainWindow() },
            insights: { [weak self] in
                self?.closePopover()
                self?.model.page = .insights
                self?.showMainWindow()
            },
            settings: { [weak self] in self?.closePopover(); self?.openSettings() },
            close: { [weak self] in self?.closePopover() }
        ))
    }

    func popoverDidClose(_ notification: Notification) {
        popoverVisibility.isShown = false
    }

    private func refreshStatusItem() {
        let fatigue = model.engine.fatiguePercent
        let phase = model.engine.phase
        statusItem.button?.title = "  \(fatigue)%"
        let symbol = StatusItemPresentation.symbol(for: phase)
        statusItem.button?.image = LineIcon.menuImage(symbol)
        statusItem.button?.setAccessibilityLabel(
            StatusItemPresentation.accessibilityLabel(
                phase: phase,
                fatiguePercent: fatigue,
                remindersEnabled: model.settings.remindersEnabled
            )
        )
        statusItem.button?.setAccessibilityHelp("打开息间快捷面板")
        statusItem.button?.toolTip = nil
    }

    @objc private func togglePopover() {
        popover.animates = effectiveMotionEnabled
        if popover.isShown {
            popover.performClose(nil)
            popoverVisibility.isShown = false
        } else if let button = statusItem.button {
            popoverVisibility.isShown = true
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func installPopoverDismissMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.closePopover()
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.window === self.statusItem.button?.window { return event }
            if event.window !== self.popover.contentViewController?.view.window {
                self.closePopover()
            }
            return event
        }
        popoverEventMonitors = [global, local].compactMap { $0 }
    }

    private func presentRest(_ presentation: RestPresentation) {
        if model.settings.reminderStyle == .notification && presentation != .resting {
            if presentation != .preview { reminders?.close() }
            model.deliverNotification(presentation)
            return
        }
        // Opening a visual break reminder begins the break immediately. startRest()
        // re-enters this method as .resting and owns the countdown from that point.
        if presentation == .due {
            guard !model.inReminderTraining else { return }
            model.startRest()
            return
        }
        if reminders == nil {
            reminders = ReminderWindowController(model: model)
            reminders?.applyAppearance(model.settings.appearanceTheme.appearance)
        }
        reminders?.present(presentation, style: model.settings.reminderStyle == .notification ? .mini : model.settings.reminderStyle)
    }

    private func applyWindowAppearance() {
        let appearance = model.settings.appearanceTheme.appearance
        mainWindow.appearance = appearance
        popover.appearance = appearance
        reminders?.applyAppearance(appearance)
        postureAlerts.appearance = appearance
    }

    private func applyDockVisibility() {
        let policy: NSApplication.ActivationPolicy = model.settings.dockIconVisible ? .regular : .accessory
        guard NSApplication.shared.activationPolicy() != policy else { return }
        NSApplication.shared.setActivationPolicy(policy)
        if policy == .regular {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func presentPostureAlert(_ issue: PostureIssue, preview: Bool = false) {
        postureAlerts.show(issue: issue, playful: model.settings.posturePlayful,
            displaySeconds: model.settings.postureThresholds.displaySeconds, preview: preview)
    }
    @objc private func checkUpdates() { closePopover(); model.page = .settings; showMainWindow(); model.updatesRequest += 1; model.updater.check() }
    private func showMainWindow() { mainWindow.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true) }
    @objc private func openMain() { closePopover(); showMainWindow() }
    @objc private func openSettings() { closePopover(); model.page = .settings; showMainWindow() }
    @objc private func showAbout() { NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "息间", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版", .credits: NSAttributedString(string: "给每一段专注，留一点余地。\n原生 macOS 用眼与休息提醒工具")]) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMainWindow(); return true }
    private func updateAnimationVisibility() {
        model?.appIsActive = NSApplication.shared.isActive && mainWindow?.occlusionState.contains(.visible) == true
    }
    func applicationDidBecomeActive(_ notification: Notification) { updateAnimationVisibility(); model?.refreshNotificationStatus() }
    func applicationDidResignActive(_ notification: Notification) { model?.appIsActive = false }
    func applicationWillTerminate(_ notification: Notification) {
        popoverEventMonitors.forEach(NSEvent.removeMonitor)
        popoverEventMonitors.removeAll()
        model?.shutdown()
    }
}

enum StatusItemPresentation {
    static func symbol(for phase: EnginePhase) -> String {
        switch phase {
        case .resting: return "timer"
        case .paused, .suspended: return "pause.circle"
        case .due: return "sun.max"
        default: return "leaf"
        }
    }

    static func accessibilityLabel(phase: EnginePhase, fatiguePercent: Int, remindersEnabled: Bool) -> String {
        let reminderNote = remindersEnabled ? "" : "，提醒已暂停"
        return "息间，\(phase.title)，疲劳值 \(fatiguePercent)%\(reminderNote)"
    }
}

private extension AppearanceTheme {
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

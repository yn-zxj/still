import AppKit
import SwiftUI
import StillCore

@main
struct StillMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var mainWindow: NSWindow!
    private var reminders: ReminderWindowController?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let postureAlerts = PostureAlertController()
    private var visibilityObserver: NSObjectProtocol?

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

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = LineIcon.menuImage("eye")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.setAccessibilityLabel("息间快捷面板")
        statusItem.button?.toolTip = "息间 · 查看使用时长与休息进度"
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuPanelView(model: model,
            open: { [weak self] in self?.popover.performClose(nil); self?.showMainWindow() },
            settings: { [weak self] in self?.popover.performClose(nil); self?.openSettings() },
            close: { [weak self] in self?.popover.performClose(nil) }))
    }

    private func refreshStatusItem() {
        statusItem.button?.title = "  \(model.engine.fatiguePercent)%"
        let symbol: String
        switch model.engine.phase {
        case .resting: symbol = "leaf.fill"
        case .paused, .suspended: symbol = "pause.circle"
        case .due: symbol = "sun.max"
        default: symbol = "leaf"
        }
        statusItem.button?.image = LineIcon.menuImage(symbol)
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            popover.animates = model.settings.motionEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func presentRest(_ presentation: RestPresentation) {
        if model.settings.reminderStyle == .notification && presentation != .resting {
            if presentation != .preview { reminders?.close() }
            model.deliverNotification(presentation)
            return
        }
        if reminders == nil {
            reminders = ReminderWindowController(model: model)
            reminders?.applyAppearance(model.settings.appearanceTheme.appearance)
        }
        reminders?.present(presentation, style: model.settings.reminderStyle == .fullScreen ? .fullScreen : .mini)
    }

    private func applyWindowAppearance() {
        let appearance = model.settings.appearanceTheme.appearance
        mainWindow.appearance = appearance
        popover.appearance = appearance
        reminders?.applyAppearance(appearance)
        postureAlerts.appearance = appearance
    }

    private func presentPostureAlert(_ issue: PostureIssue, preview: Bool = false) {
        postureAlerts.show(issue: issue, playful: model.settings.posturePlayful,
            displaySeconds: model.settings.postureThresholds.displaySeconds, preview: preview)
    }
    @objc private func checkUpdates() { model.page = .settings; showMainWindow(); model.updatesRequest += 1; model.updater.check() }
    private func showMainWindow() { mainWindow.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true) }
    @objc private func openMain() { showMainWindow() }
    @objc private func openSettings() { model.page = .settings; showMainWindow() }
    @objc private func showAbout() { NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "息间", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版", .credits: NSAttributedString(string: "给每一段专注，留一点余地。\n原生 macOS 用眼与休息提醒工具")]) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMainWindow(); return true }
    private func updateAnimationVisibility() {
        model?.appIsActive = NSApplication.shared.isActive && mainWindow?.occlusionState.contains(.visible) == true
    }
    func applicationDidBecomeActive(_ notification: Notification) { updateAnimationVisibility(); model?.refreshNotificationStatus() }
    func applicationDidResignActive(_ notification: Notification) { model?.appIsActive = false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
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

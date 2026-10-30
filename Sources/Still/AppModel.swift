import AppKit
import Combine
import ServiceManagement
import UserNotifications
import StillCore

enum Page: String, CaseIterable {
    case courses = "休息课程", today = "今天", insights = "时间去向", history = "使用记录", rules = "休息规则", settings = "偏好设置", posture = "坐姿关照"
    var icon: String {
        switch self {
        case .posture: return "person-standing"
        case .courses: return "book-open"
        case .today: return "sun.max"
        case .insights: return "chart-pie"
        case .history: return "chart.bar.xaxis"
        case .rules: return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var page: Page = .today
    @Published var historyDays = 7
    @Published var updatesRequest = 0
    @Published private(set) var engine: UsageEngine
    @Published var settings: MonitorSettings {
        didSet {
            engine.updateSettings(settings)
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings.v1") }
            if !settings.remindersEnabled && engine.phase != .resting { hideReminder?() }
            if !settings.remindersEnabled || oldValue.reminderStyle != settings.reminderStyle { clearDueNotification() }
            if oldValue.appearanceTheme != settings.appearanceTheme { applyAppearance?() }
            if oldValue.dockIconVisible != settings.dockIconVisible { applyDockVisibility?() }
            if oldValue.postureThresholds != settings.postureThresholds { posture.updateThresholds(settings.postureThresholds) }
            if oldValue.postureEnabled != settings.postureEnabled {
                posture.configure(enabled: settings.postureEnabled, requestPermission: settings.postureEnabled)
                if !settings.postureEnabled && page == .posture { page = .settings }
            }
            if oldValue.agentActivityEnabled != settings.agentActivityEnabled ||
                oldValue.hapiSyncEnabled != settings.hapiSyncEnabled ||
                oldValue.hapiExecutablePath != settings.hapiExecutablePath {
                agentActivity.configure(settings)
            }
            if !oldValue.automaticUpdateChecks && settings.automaticUpdateChecks { updater.checkAutomaticallyIfNeeded() }
            refreshMenu?()
            save()
        }
    }
    @Published var storageError: String?
    @Published var notificationStatus = "尚未启用"
    @Published var notificationAuthorized = false
    @Published var notificationDenied = false
    @Published var reminderError: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var exportMessage: String?
    @Published var appIsActive = true
    @Published private(set) var recommendedCourseID: String?
    @Published private(set) var previewCourseID: String?
    var inReminderTraining = false
    private var courseRotation = DailyCourseRotation()
    private var previewRotation = DailyCourseRotation()
    let posture: PostureMonitor
    let agentActivity: AgentActivityCoordinator
    let hapiInstaller: HAPIInstaller
    let updater = AppUpdater()
    let library: CourseLibrary
    let coursePlayer: CoursePlayer
    private(set) var recordingStartedAt = Date()
    let isUITest: Bool
    private let defaults: UserDefaults
    private let monitor: SystemActivityMonitor
    private let repository: UsageRepository?
    private var timer: Timer?
    private var tickCount = 0
    private var previousReminder = 0
    private var previousCompletion = 0
    var showReminder: (() -> Void)?
    var showCompletion: (() -> Void)?
    var showRest: (() -> Void)?
    var showPreview: (() -> Void)?
    var showDashboard: (() -> Void)?
    var hideAllReminders: (() -> Void)?
    var hideReminder: (() -> Void)?
    var refreshMenu: (() -> Void)?
    var applyAppearance: (() -> Void)?
    var applyDockVisibility: (() -> Void)?

    override init() {
        isUITest = ProcessInfo.processInfo.arguments.contains("--ui-test") || (Bundle.main.bundleIdentifier == "local.still.preview" || Bundle.main.bundleIdentifier?.hasPrefix("local.still.preview.") == true)
        let arguments = ProcessInfo.processInfo.arguments
        let testLibrary = isUITest ? arguments.firstIndex(of: "--ui-test-library").flatMap { index in
            index + 1 < arguments.count ? URL(fileURLWithPath: arguments[index + 1]) : nil
        } : nil
        library = CourseLibrary(isUITest: isUITest, rootOverride: testLibrary)
        coursePlayer = CoursePlayer(cache: library.videoCache, diagnostics: library.diagnostics)
        defaults = isUITest ? UserDefaults(suiteName: "local.still.ui-validation")! : .standard
        posture = PostureMonitor(defaults: defaults)
        agentActivity = AgentActivityCoordinator(
            store: AgentActivityStore(
                fileURL: isUITest
                    ? FileManager.default.temporaryDirectory.appendingPathComponent("still-ui-agent-activity.json")
                    : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Still/AgentActivity.json")
            )
        )
        hapiInstaller = HAPIInstaller()
        // One-time migration from the initial development identity. Existing Still settings win.
        if !isUITest, defaults.data(forKey: "settings.v1") == nil,
           let legacy = UserDefaults(suiteName: "local.xijian.app") {
            for key in ["settings.v1", "checkpoint.v1"] {
                if let value = legacy.data(forKey: key) { defaults.set(value, forKey: key) }
            }
        }
        var initial = MonitorSettings()
        if !isUITest, let data = defaults.data(forKey: "settings.v1"), let value = try? JSONDecoder().decode(MonitorSettings.self, from: data) { initial = value }
        settings = initial
        monitor = SystemActivityMonitor()
        var repo: UsageRepository?
        var diskError: String?
        var savedSegments: [UsageSegment] = [], savedApplications: [ApplicationUsageSegment] = []
        var savedBreaks: [BreakRecord] = []
        do {
            repo = try UsageRepository(inMemory: isUITest)
            let saved = try repo!.load()
            savedSegments = saved.segments; savedApplications = saved.applicationSegments; savedBreaks = saved.breaks
        } catch { diskError = "本地记录暂时无法保存：\(error.localizedDescription)" }
        repository = repo
        let checkpoint: EngineCheckpoint? = !isUITest ? defaults.data(forKey: "checkpoint.v1").flatMap { try? JSONDecoder().decode(EngineCheckpoint.self, from: $0) } : nil
        engine = UsageEngine(settings: initial, segments: savedSegments,
                             applicationSegments: savedApplications, breaks: savedBreaks,
                             checkpoint: checkpoint)
        let earliest = (savedSegments.map(\.startedAt) + savedBreaks.map(\.startedAt)).min()
        let persistedStart = defaults.object(forKey: "usage.recordingStartedAt") as? Date
        recordingStartedAt = min(persistedStart ?? earliest ?? Date(), earliest ?? persistedStart ?? Date())
        if !isUITest { defaults.set(recordingStartedAt, forKey: "usage.recordingStartedAt") }
        storageError = diskError
        super.init()
        if !isUITest, let data = defaults.data(forKey: "reminder.courseRotation.v1"),
           let rotation = try? JSONDecoder().decode(DailyCourseRotation.self, from: data) { courseRotation = rotation }
        coursePlayer.onStart = { [weak self] duration in
            guard let self else { return }
            self.clearDueNotification(); if !self.inReminderTraining { self.hideAllReminders?() }
            self.engine.startGuidedRest(self.currentSample(), duration: duration)
            self.save(); self.refreshMenu?()
        }
        coursePlayer.onProgress = { [weak self] elapsed, completed in
            guard let self else { return }
            self.engine.updateGuidedRest(elapsed: elapsed, completed: completed, sample: self.currentSample())
            if completed { self.previousCompletion = self.engine.completionSerial; self.save() }
        }
        coursePlayer.onStop = { [weak self] in
            guard let self, self.engine.guidedRest else { return }
            self.engine.interruptRest(self.currentSample()); self.save(); self.refreshMenu?()
        }
        if ProcessInfo.processInfo.arguments.contains("--courses") { page = .courses }

        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            let start = UNNotificationAction(identifier: "still.start", title: "开始休息", options: [.foreground])
            let later = UNNotificationAction(identifier: "still.snooze", title: "稍后提醒", options: [])
            UNUserNotificationCenter.current().setNotificationCategories([
                UNNotificationCategory(identifier: "still.break", actions: [start, later], intentIdentifiers: [], options: [])
            ])
            refreshNotificationStatus()
        }
        monitor.onChange = { [weak self] in self?.tick(); self?.save() }
        posture.updateThresholds(initial.postureThresholds)
        posture.configure(enabled: initial.postureEnabled)
        if !isUITest { agentActivity.configure(initial) }
        if initial.automaticUpdateChecks && !isUITest { updater.checkAutomaticallyIfNeeded() }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.2
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var today: DailySummary { UsageStatistics.daily(segments: engine.segments, breaks: engine.breaks, endingAt: engine.now, days: 1)[0] }
    var week: [DailySummary] { UsageStatistics.daily(segments: engine.segments, breaks: engine.breaks, endingAt: engine.now, days: 7) }
    var longestToday: Double { UsageStatistics.longestRound(segments: engine.segments, on: engine.now) }
    var countdown: Double {
        if engine.phase == .resting { return engine.restRemaining }
        if engine.phase == .snoozed, let until = engine.snoozeUntil { return max(0, until.timeIntervalSince(engine.now)) }
        return engine.workRemaining
    }
    var headline: String {
        switch engine.phase {
        case .resting: return "把这一刻，留给自己。"
        case .due: return "停一停，再继续。"
        case .away: return "离开一会儿，也很好。"
        case .paused: return "按你的节奏来。"
        default: return "专注，也别忘了呼吸。"
        }
    }
    var countdownTitle: String {
        switch engine.phase {
        case .resting: return "距离休息结束"
        case .due: return "已经到休息时间"
        case .snoozed: return "下次提醒还有"
        case .away: return "回来后，继续这一轮"
        case .paused: return "恢复后，继续计时"
        default: return "下一次休息"
        }
    }

    func tick() {
        let previousPhase = engine.phase
        let sample = currentSample()
        if !sample.available { coursePlayer.pause() }
        engine.tick(sample)
        posture.setAvailable(sample.available && engine.phase != .resting)
        if engine.reminderSerial != previousReminder {
            previousReminder = engine.reminderSerial
            if engine.phase == .due && settings.remindersEnabled { showReminder?() }
        }
        if engine.completionSerial != previousCompletion {
            previousCompletion = engine.completionSerial
            showCompletion?()
            if settings.soundEnabled && settings.reminderStyle != .notification { NSSound(named: "Glass")?.play() }
            save()
        }
        if [.away, .suspended, .paused].contains(engine.phase) {
            hideReminder?()
            if engine.phase != previousPhase { clearDueNotification() }
        }
        refreshMenu?()
        tickCount += 1
        if tickCount % 3600 == 0 && settings.automaticUpdateChecks && !isUITest { updater.checkAutomaticallyIfNeeded() }
        if tickCount % 20 == 0 { save() }
    }

    func startRest() {
        if coursePlayer.active { page = .courses; showDashboard?(); return }
        clearDueNotification()
        let short = isUITest && ProcessInfo.processInfo.arguments.contains("--short-rest")
        engine.startRest(currentSample(), duration: short ? 5 : nil)
        if engine.phase == .resting { showRest?() } else { showCompletion?() }
        save(); refreshMenu?()
    }

    var reminderCandidates: [Course] {
        library.courses.filter { course in
            guard course.media != nil, course.displayDurationMinutes <= 10,
                  !course.title.contains("按摩") else { return false }
            let preparation = (course.preparation ?? []).joined()
            return !["瑜伽垫", "垫子", "按摩球", "墙", "按摩者", "被按摩"].contains(where: preparation.contains)
        }
    }
    func reminderRecommendation(preview: Bool) -> Course? {
        if !preview, coursePlayer.active { return library.courses.first { $0.id == coursePlayer.courseID } }
        let id = preview ? previewCourseID : recommendedCourseID
        return reminderCandidates.first { $0.id == id }
    }
    func prepareRecommendation(preview: Bool, shuffle: Bool = false) {
        if !shuffle, reminderRecommendation(preview: preview) != nil { return }
        let candidates = reminderCandidates
        let prefer = Set(candidates.filter { $0.displayDurationMinutes <= settings.restMinutes }.map(\.id))
        let choose: ([String]) -> String? = { ids in
            let short = ids.filter { prefer.contains($0) }
            return (short.isEmpty ? ids : short).randomElement()
        }
        if preview {
            previewCourseID = previewRotation.next(candidates: candidates.map(\.id), date: engine.now, choose: choose)
        } else {
            recommendedCourseID = courseRotation.next(candidates: candidates.map(\.id), date: engine.now, choose: choose)
            if !isUITest, let data = try? JSONEncoder().encode(courseRotation) { defaults.set(data, forKey: "reminder.courseRotation.v1") }
        }
    }

    func openCourses() { hideAllReminders?(); page = .courses; showDashboard?() }

    func endRest() { if coursePlayer.active { coursePlayer.stop(); return }; engine.interruptRest(currentSample()); hideReminder?(); save(); refreshMenu?() }
    func snooze(skipped: Bool = false) { if coursePlayer.active { coursePlayer.stop() }; clearDueNotification(); engine.snooze(currentSample(), skipped: skipped); hideReminder?(); save(); refreshMenu?() }
    func toggleTracking() { engine.setTrackingPaused(!engine.trackingPaused, sample: currentSample()); save(); refreshMenu?() }
    func toggleReminders() {
        settings.remindersEnabled.toggle()
        if !settings.remindersEnabled && engine.phase != .resting { hideReminder?() }
        refreshMenu?()
    }

    func save() {
        guard !isUITest else { return }
        do {
            guard let repository else { return }
            try repository.save(segments: engine.segments,
                                applicationSegments: engine.applicationSegments,
                                breaks: engine.breaks)
            if let data = try? JSONEncoder().encode(engine.checkpoint) { defaults.set(data, forKey: "checkpoint.v1") }
            storageError = nil
        } catch { storageError = "记录保存失败：\(error.localizedDescription)" }
    }

    func shutdown() { posture.shutdown(); coursePlayer.shutdown(); timer?.invalidate(); save() }

    private func currentSample() -> ActivitySample {
        monitor.sample(includeForegroundApplication: settings.applicationInsightsEnabled)
    }

    func clearApplicationHistory() {
        engine.clearApplicationSegments()
        save()
    }

    func chooseHAPIPath() {
        let panel = NSOpenPanel()
        panel.title = "选择 hapi 可执行文件"
        panel.message = "请选择 HAPI 0.30 或更高版本提供的 hapi 可执行文件。"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.hapiExecutablePath = url.path
        }
    }

    func installHAPI() {
        hapiInstaller.install { [weak self] url, _ in
            guard let self else { return }
            self.settings.hapiExecutablePath = url.path
            self.settings.agentActivityEnabled = true
            self.settings.hapiSyncEnabled = true
            self.agentActivity.syncNow()
        }
    }

    private func clearDueNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["still.due"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["still.due"])
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许息间。" : nil
        } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.settings.notificationsEnabled = granted
                self?.refreshNotificationStatus()
            }
        }
    }

    func enableNotifications() {
        if notificationDenied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        } else { requestNotifications() }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] result in
            let status = result.authorizationStatus
            Task { @MainActor in
                self?.notificationAuthorized = status == .authorized || status == .provisional
                self?.notificationDenied = status == .denied
                switch status {
                case .authorized, .provisional: self?.notificationStatus = "已允许"
                case .denied: self?.notificationStatus = "已关闭，可前往系统设置开启"
                default: self?.notificationStatus = "尚未启用"
                }
            }
        }
    }

    var reminderText: String {
        let text = settings.reminderMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "喝杯水，起来走走吧" : String(text.prefix(100))
    }

    func deliverNotification(_ presentation: RestPresentation) {
        let preview = presentation == .preview
        let completed = presentation == .completed
        let title = preview ? "休息提醒 · 预览" : completed ? "休息结束" : "该休息了"
        var body = completed ? "可以开始新一轮使用。" : reminderText
        if settings.showDailyTimeInReminder { body += "\n今日使用 \(durationText(today.seconds))" }
        let text = body
        let sound = settings.soundEnabled
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] authorization in
            let allowed = authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard allowed else {
                    self.reminderError = "系统通知尚未允许，请先开启通知权限。"
                    self.refreshNotificationStatus()
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title; content.body = text
                if !preview && !completed { content.categoryIdentifier = "still.break" }
                if sound { content.sound = .default }
                let request = UNNotificationRequest(identifier: preview ? "still.preview" : completed ? "still.completed" : "still.due", content: content, trigger: nil)
                do {
                    try await UNUserNotificationCenter.current().add(request)
                    self.reminderError = nil
                } catch { self.reminderError = "通知发送失败：" + error.localizedDescription }

            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        Task { @MainActor [weak self] in
            if action == "still.start" { self?.startRest() }
            else if action == "still.snooze" { self?.snooze() }
            else if action == UNNotificationDefaultActionIdentifier { self?.showDashboard?() }
            completionHandler()
        }
    }

    func exportCSV() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "息间-使用记录.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let iso = ISO8601DateFormatter()
        var lines = ["类型,开始时间,结束时间,使用秒数,模式或来源,结果,应用,应用标识,分类"]
        for segment in engine.segments where segment.seconds > 0 {
            lines.append("使用,\(iso.string(from: segment.startedAt)),\(iso.string(from: segment.endedAt)),\(Int(segment.seconds)),\(segment.mode.title),,,,")
        }
        for segment in engine.applicationSegments where segment.seconds > 0 {
            lines.append("应用,\(iso.string(from: segment.startedAt)),\(iso.string(from: segment.endedAt)),\(Int(segment.seconds)),,,\(segment.applicationName),\(segment.bundleID),\(segment.category.title)")
        }
        for record in engine.breaks {
            let outcome: String
            switch record.outcome { case .completed: outcome = "完成"; case .interrupted: outcome = "提前结束"; case .skipped: outcome = "跳过"; case .inProgress: outcome = "进行中" }
            lines.append("休息,\(iso.string(from: record.startedAt)),\(record.endedAt.map { iso.string(from: $0) } ?? ""),,\(record.source == .manual ? "手动" : "自然离开"),\(outcome),,,")
        }
        do { try ("\u{FEFF}" + lines.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8); exportMessage = "已导出到 \(url.lastPathComponent)" }
        catch { exportMessage = "导出失败：\(error.localizedDescription)" }
    }
}

func clockText(_ seconds: Double) -> String {
    let total = max(0, Int(ceil(seconds)))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

func durationText(_ seconds: Double) -> String {
    let minutes = max(0, Int(seconds) / 60)
    if seconds > 0 && minutes == 0 { return "不足1分钟" }
    return minutes >= 60 ? "\(minutes / 60)小时\(minutes % 60)分" : "\(minutes)分钟"
}

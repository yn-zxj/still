import Foundation

// Historical segment labels; reading is retained only to decode/export old records.
public enum TrackingMode: String, Codable, CaseIterable {
    case activity, reading
    public var title: String { self == .activity ? "活动估算" : "持续阅读" }
}

public enum ReminderStyle: String, Codable, CaseIterable {
    case fullScreen, mini, simple, notification
    public var title: String {
        switch self { case .fullScreen: return "全屏弹窗"; case .mini: return "迷你弹窗"; case .simple: return "简洁提醒"; case .notification: return "系统通知" }
    }
}

public enum AppearanceTheme: String, Codable, CaseIterable, Identifiable {
    case light, dark, system
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }
}

public struct MonitorSettings: Codable, Equatable {
    public var workMinutes = 45
    public var restMinutes = 5
    public var idleSeconds = 90
    public var snoozeMinutes = 5
    public var repeatMinutes = 5
    public var remindersEnabled = true
    public var soundEnabled = true
    public var notificationsEnabled = false
    public var motionEnabled = true
    public var appearanceTheme: AppearanceTheme = .light
    public var coursesEnabled = false
    public var postureEnabled = false
    public var posturePlayful = true
    public var postureThresholds = PostureThresholds()
    public var applicationInsightsEnabled = true
    public var agentActivityEnabled = true
    public var hapiSyncEnabled = true
    public var hapiExecutablePath = ""
    public var dockIconVisible = true
    public var automaticUpdateChecks = true
    // Kept in the Codable shape so older settings continue to decode.
    // The menu bar now always shows only the icon and fatigue percentage.
    public var showMenuCountdown = true
    public var showMenuFatigue = true
    public var reminderStyle: ReminderStyle = .mini
    public var reminderMessage = "喝杯水，起来走走吧"
    public var showDailyTimeInReminder = true
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case workMinutes, restMinutes, idleSeconds, snoozeMinutes, repeatMinutes
        case remindersEnabled, soundEnabled, notificationsEnabled, motionEnabled, appearanceTheme, showMenuCountdown
        case coursesEnabled, postureEnabled, posturePlayful, postureThresholds, applicationInsightsEnabled
        case agentActivityEnabled, hapiSyncEnabled, hapiExecutablePath, dockIconVisible, automaticUpdateChecks
        case showMenuFatigue, reminderStyle, reminderMessage, showDailyTimeInReminder
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workMinutes = min(180, max(1, try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? workMinutes))
        restMinutes = min(30, max(1, try c.decodeIfPresent(Int.self, forKey: .restMinutes) ?? restMinutes))
        idleSeconds = max(1, try c.decodeIfPresent(Int.self, forKey: .idleSeconds) ?? idleSeconds)
        snoozeMinutes = max(1, try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? snoozeMinutes)
        repeatMinutes = max(1, try c.decodeIfPresent(Int.self, forKey: .repeatMinutes) ?? repeatMinutes)
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? remindersEnabled
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? soundEnabled
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? notificationsEnabled
        motionEnabled = try c.decodeIfPresent(Bool.self, forKey: .motionEnabled) ?? motionEnabled
        appearanceTheme = try c.decodeIfPresent(AppearanceTheme.self, forKey: .appearanceTheme) ?? appearanceTheme
        coursesEnabled = try c.decodeIfPresent(Bool.self, forKey: .coursesEnabled) ?? coursesEnabled
        postureEnabled = try c.decodeIfPresent(Bool.self, forKey: .postureEnabled) ?? postureEnabled
        posturePlayful = try c.decodeIfPresent(Bool.self, forKey: .posturePlayful) ?? posturePlayful
        postureThresholds = try c.decodeIfPresent(PostureThresholds.self, forKey: .postureThresholds) ?? postureThresholds
        applicationInsightsEnabled = try c.decodeIfPresent(Bool.self, forKey: .applicationInsightsEnabled) ?? applicationInsightsEnabled
        agentActivityEnabled = try c.decodeIfPresent(Bool.self, forKey: .agentActivityEnabled) ?? agentActivityEnabled
        hapiSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapiSyncEnabled) ?? hapiSyncEnabled
        hapiExecutablePath = try c.decodeIfPresent(String.self, forKey: .hapiExecutablePath) ?? hapiExecutablePath
        dockIconVisible = try c.decodeIfPresent(Bool.self, forKey: .dockIconVisible) ?? dockIconVisible
        automaticUpdateChecks = try c.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecks) ?? automaticUpdateChecks
        showMenuCountdown = try c.decodeIfPresent(Bool.self, forKey: .showMenuCountdown) ?? showMenuCountdown
        showMenuFatigue = try c.decodeIfPresent(Bool.self, forKey: .showMenuFatigue) ?? showMenuFatigue
        reminderStyle = try c.decodeIfPresent(ReminderStyle.self, forKey: .reminderStyle) ?? reminderStyle
        reminderMessage = try c.decodeIfPresent(String.self, forKey: .reminderMessage) ?? reminderMessage
        showDailyTimeInReminder = try c.decodeIfPresent(Bool.self, forKey: .showDailyTimeInReminder) ?? showDailyTimeInReminder
    }
    public var workSeconds: Double { Double(max(1, workMinutes)) * 60 }
    public var restSeconds: Double { Double(max(1, restMinutes)) * 60 }
}

public struct UsageSegment: Identifiable, Codable, Equatable {
    public var id: UUID
    public var roundID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var seconds: Double
    public var mode: TrackingMode
    public init(id: UUID = UUID(), roundID: UUID, startedAt: Date, endedAt: Date,
                seconds: Double, mode: TrackingMode) {
        self.id = id; self.roundID = roundID; self.startedAt = startedAt
        self.endedAt = endedAt; self.seconds = seconds; self.mode = mode
    }
    public func seconds(in interval: DateInterval) -> Double {
        guard seconds > 0, endedAt > startedAt else { return 0 }
        let start = max(startedAt, interval.start), end = min(endedAt, interval.end)
        guard end > start else { return 0 }
        return seconds * end.timeIntervalSince(start) / endedAt.timeIntervalSince(startedAt)
    }
}

public enum BreakOutcome: String, Codable { case inProgress, completed, interrupted, skipped }
public enum BreakSource: String, Codable { case manual, natural }

public struct BreakRecord: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var startedAt: Date
    public var endedAt: Date?
    public var targetSeconds: Double
    public var outcome: BreakOutcome
    public var source: BreakSource
    public init(startedAt: Date, endedAt: Date? = nil, targetSeconds: Double,
                outcome: BreakOutcome, source: BreakSource) {
        self.startedAt = startedAt; self.endedAt = endedAt
        self.targetSeconds = targetSeconds; self.outcome = outcome; self.source = source
    }
}

public struct EngineCheckpoint: Codable {
    public var roundID: UUID
    public var snoozeUntil: Date?
    public var trackingPaused: Bool
    public var fatigueWorkSeconds: Double?
    public var unavailableSince: Date?
    public init(roundID: UUID, snoozeUntil: Date?, trackingPaused: Bool, fatigueWorkSeconds: Double? = nil, unavailableSince: Date? = nil) {
        self.roundID = roundID; self.snoozeUntil = snoozeUntil; self.trackingPaused = trackingPaused
        self.fatigueWorkSeconds = fatigueWorkSeconds
        self.unavailableSince = unavailableSince
    }
}

public struct ActivitySample {
    public var date: Date
    public var monotonic: Double
    public var idleSeconds: Double
    public var available: Bool
    /// False for a failed status/input query: unknown time is neither work nor rest.
    public var inactivityConfirmed: Bool
    public var foregroundApplication: ForegroundApplication?
    public init(date: Date, monotonic: Double, idleSeconds: Double, available: Bool = true,
                foregroundApplication: ForegroundApplication? = nil, inactivityConfirmed: Bool = true) {
        self.date = date; self.monotonic = monotonic; self.idleSeconds = idleSeconds
        self.available = available; self.foregroundApplication = foregroundApplication
        self.inactivityConfirmed = inactivityConfirmed
    }
}

public enum EnginePhase: Equatable {
    case working, away, due, resting, snoozed, suspended, paused
    public var title: String {
        switch self {
        case .working: return "正在记录"
        case .away: return "离开屏幕"
        case .due: return "该休息了"
        case .resting: return "休息时间"
        case .snoozed: return "提醒已延后"
        case .suspended: return "系统已暂停"
        case .paused: return "统计已暂停"
        }
    }
}

public struct DailySummary: Identifiable {
    public var date: Date
    public var seconds: Double
    public var completedBreaks: Int
    public var id: Date { date }
}

public struct UsageActivityPoint: Equatable, Sendable {
    public var fraction: Double
    public var activity: Double
}

public enum UsageStatistics {
    /// Include zero-use days after collection began, never dates before installation.
    public static func coveredDays(startedAt: Date, endingAt: Date, days: Int,
                                   calendar: Calendar = .current) -> Int {
        guard startedAt <= endingAt else { return 0 }
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: startedAt),
                                               to: calendar.startOfDay(for: endingAt)).day ?? 0
        return min(max(1, days), max(1, elapsed + 1))
    }

    /// Five-minute occupancy samples, positioned on a fixed full-day axis.
    /// Future time is absent; the unfinished bucket uses only elapsed time.
    public static func activity(segments: [UsageSegment], date: Date,
                                calendar: Calendar = .current) -> [UsageActivityPoint] {
        let window = DayTimelineWindow(date: date, now: date, calendar: calendar)
        let relevant = segments.filter { $0.seconds(in: window.visible) > 0 }
        guard let first = relevant.map(\.startedAt).min() else { return [] }
        let offset = max(0, first.timeIntervalSince(window.day.start))
        var start = window.day.start.addingTimeInterval(floor(offset / 300) * 300)
        var result = [UsageActivityPoint(fraction: window.fraction(for: start), activity: 0)]
        while start < window.visible.end {
            let end = min(start.addingTimeInterval(300), window.visible.end)
            let interval = DateInterval(start: start, end: end)
            let value = min(1, max(0, relevant.reduce(0) { $0 + $1.seconds(in: interval) } / interval.duration))
            result.append(UsageActivityPoint(fraction: window.fraction(for: end), activity: value))
            start = end
        }
        return result
    }

    public static func daily(segments: [UsageSegment], breaks: [BreakRecord], endingAt date: Date,
                             days: Int, calendar: Calendar = .current) -> [DailySummary] {
        let today = calendar.startOfDay(for: date)
        return (0..<days).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let interval = DateInterval(start: start, end: end)
            let total = segments.reduce(0) { $0 + $1.seconds(in: interval) }
            let count = breaks.filter { $0.outcome == .completed && ($0.endedAt ?? $0.startedAt) >= start && ($0.endedAt ?? $0.startedAt) < end }.count
            return DailySummary(date: start, seconds: total, completedBreaks: count)
        }
    }

    public static func longestRound(segments: [UsageSegment], on date: Date, calendar: Calendar = .current) -> Double {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return 0 }
        return Dictionary(grouping: segments, by: \.roundID).values.map {
            $0.reduce(0) { $0 + $1.seconds(in: interval) }
        }.max() ?? 0
    }
}

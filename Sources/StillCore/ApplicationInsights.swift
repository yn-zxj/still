import Foundation

public enum ApplicationCategory: String, Codable, CaseIterable, Identifiable {
    case development, communication, productivity, browsing, design, media, learning, utilities, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .development: return "开发与终端"
        case .communication: return "沟通与会议"
        case .productivity: return "文档与效率"
        case .browsing: return "浏览与网页"
        case .design: return "设计与创作"
        case .media: return "影音娱乐"
        case .learning: return "阅读与学习"
        case .utilities: return "系统与工具"
        case .other: return "其他应用"
        }
    }

    public static func classify(bundleID: String, name: String) -> ApplicationCategory {
        let text = (bundleID + " " + name).lowercased()
        let rules: [(ApplicationCategory, [String])] = [
            (.development, [
                "xcode", "terminal", "iterm", "visual studio code", "vscode", "cursor",
                "jetbrains", "intellij", "pycharm", "webstorm", "android studio", "ghostty",
                "warp", "alacritty", "github", "sourcetree", "tower", "postman", "docker",
                "qoder", "codex", "chatgpt", "claude"
            ]),
            (.communication, [
                "wechat", "微信", "qq", "feishu", "lark", "飞书", "dingtalk", "钉钉",
                "teams", "slack", "zoom", "tencent meeting", "腾讯会议", "discord",
                "messages", "信息", "mail", "邮件"
            ]),
            (.browsing, [
                "safari", "chrome", "firefox", "edge", "arc", "brave", "opera", "browser"
            ]),
            (.design, [
                "figma", "sketch", "photoshop", "illustrator", "affinity", "blender",
                "pixelmator", "canva", "keynote", "pages"
            ]),
            (.media, [
                "spotify", "music", "音乐", "podcast", "播客", "vlc", "iina", "quicktime",
                "tv", "netflix", "哔哩哔哩", "bilibili", "爱奇艺", "腾讯视频"
            ]),
            (.learning, [
                "books", "图书", "kindle", "readwise", "marginnote", "anki", "zotero",
                "coursera", "udemy", "得到", "微信读书"
            ]),
            (.productivity, [
                "notion", "obsidian", "notes", "备忘录", "word", "excel", "powerpoint",
                "numbers", "calendar", "日历", "reminders", "提醒事项", "todoist",
                "things", "craft", "typora", "ulysses", "preview"
            ]),
            (.utilities, [
                "finder", "访达", "system settings", "系统设置", "activity monitor",
                "活动监视器", "1password", "raycast", "alfred", "cleanmymac", "still"
            ])
        ]
        for (category, needles) in rules where needles.contains(where: text.contains) {
            return category
        }
        return .other
    }
}

public struct ForegroundApplication: Codable, Equatable {
    public var bundleID: String
    public var name: String
    public var category: ApplicationCategory

    public init(bundleID: String, name: String) {
        let trimmedID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleID = trimmedID
        self.name = trimmedName.isEmpty ? (trimmedID.isEmpty ? "未知应用" : trimmedID) : trimmedName
        category = ApplicationCategory.classify(bundleID: trimmedID, name: self.name)
    }

    public var key: String { bundleID.isEmpty ? name.lowercased() : bundleID }
}

public struct ApplicationUsageSegment: Identifiable, Codable, Equatable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var seconds: Double
    public var bundleID: String
    public var applicationName: String
    public var category: ApplicationCategory

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, seconds: Double,
                application: ForegroundApplication) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
        bundleID = application.bundleID
        applicationName = application.name
        category = application.category
    }

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, seconds: Double,
                bundleID: String, applicationName: String, category: ApplicationCategory) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
        self.bundleID = bundleID
        self.applicationName = applicationName
        self.category = category
    }

    public var application: ForegroundApplication {
        var value = ForegroundApplication(bundleID: bundleID, name: applicationName)
        value.category = category
        return value
    }

    public func seconds(in interval: DateInterval) -> Double {
        guard seconds > 0, endedAt > startedAt else { return 0 }
        let start = max(startedAt, interval.start)
        let end = min(endedAt, interval.end)
        guard end > start else { return 0 }
        return seconds * end.timeIntervalSince(start) / endedAt.timeIntervalSince(startedAt)
    }
}

public struct ApplicationTime: Identifiable, Equatable {
    public var bundleID: String
    public var name: String
    public var category: ApplicationCategory
    public var seconds: Double
    public var id: String { bundleID.isEmpty ? name.lowercased() : bundleID }
}

public struct CategoryTime: Identifiable, Equatable {
    public var category: ApplicationCategory
    public var seconds: Double
    public var id: String { category.rawValue }
}

public struct DailyCategoryTime: Identifiable, Equatable {
    public var date: Date
    public var category: ApplicationCategory
    public var seconds: Double
    public var id: String { "\(date.timeIntervalSinceReferenceDate)-\(category.rawValue)" }
}

public struct ApplicationInsights: Equatable {
    public var interval: DateInterval
    public var totalSeconds: Double
    public var byApplication: [ApplicationTime]
    public var byCategory: [CategoryTime]
    public var switches: Int
    public var longestApplicationStretch: Double
    public var applicationCount: Int

    public var switchesPerHour: Double {
        guard totalSeconds >= 60 else { return 0 }
        return Double(switches) / (totalSeconds / 3600)
    }

    public static func make(segments: [ApplicationUsageSegment], interval: DateInterval) -> ApplicationInsights {
        var clipped: [ApplicationUsageSegment] = []
        var alreadySorted = true
        var lastStartedAt: Date?
        for segment in segments where segment.seconds > 0 && segment.endedAt > interval.start && segment.startedAt < interval.end {
            let seconds = segment.seconds(in: interval)
            guard seconds > 0 else { continue }
            let clippedStart = max(segment.startedAt, interval.start)
            if let lastStartedAt, clippedStart < lastStartedAt { alreadySorted = false }
            lastStartedAt = clippedStart
            clipped.append(
                ApplicationUsageSegment(
                    id: segment.id,
                    startedAt: clippedStart,
                    endedAt: min(segment.endedAt, interval.end),
                    seconds: seconds,
                    bundleID: segment.bundleID,
                    applicationName: segment.applicationName,
                    category: segment.category
                )
            )
        }
        if !alreadySorted {
            clipped.sort { $0.startedAt < $1.startedAt }
        }

        var applications: [String: ApplicationTime] = [:]
        var categories: [ApplicationCategory: Double] = [:]
        for segment in clipped {
            let key = segment.application.key
            var app = applications[key] ?? ApplicationTime(
                bundleID: segment.bundleID,
                name: segment.applicationName,
                category: segment.category,
                seconds: 0
            )
            app.seconds += segment.seconds
            applications[key] = app
            categories[segment.category, default: 0] += segment.seconds
        }

        var switches = 0
        var previousKey: String?
        var previousEnd: Date?
        var currentStretch = 0.0
        var longestStretch = 0.0
        for segment in clipped {
            let key = segment.application.key
            if let previousKey {
                if key != previousKey && (previousEnd.map { segment.startedAt.timeIntervalSince($0) <= 90 } ?? true) {
                    switches += 1
                }
                if key == previousKey && (previousEnd.map { segment.startedAt.timeIntervalSince($0) <= 5 } ?? true) {
                    currentStretch += segment.seconds
                } else {
                    currentStretch = segment.seconds
                }
            } else {
                currentStretch = segment.seconds
            }
            longestStretch = max(longestStretch, currentStretch)
            previousKey = key
            previousEnd = segment.endedAt
        }

        return ApplicationInsights(
            interval: interval,
            totalSeconds: clipped.reduce(0) { $0 + $1.seconds },
            byApplication: applications.values.sorted { $0.seconds > $1.seconds },
            byCategory: categories.map { CategoryTime(category: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds },
            switches: switches,
            longestApplicationStretch: longestStretch,
            applicationCount: applications.count
        )
    }

    public static func daily(segments: [ApplicationUsageSegment], endingAt date: Date,
                             days: Int, calendar: Calendar = .current) -> [DailyCategoryTime] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: date)
        var dayIntervals: [DateInterval] = []
        dayIntervals.reserveCapacity(days)
        for offset in (0..<days).reversed() {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            dayIntervals.append(DateInterval(start: start, end: end))
        }
        guard let windowStart = dayIntervals.first?.start,
              let windowEnd = dayIntervals.last?.end else { return [] }

        var buckets: [[ApplicationCategory: Double]] = Array(repeating: [:], count: dayIntervals.count)

        func bucketIndex(for timestamp: Date) -> Int {
            let approx = Int(timestamp.timeIntervalSince(windowStart) / 86_400)
            var index = min(max(0, approx), dayIntervals.count - 1)
            while index > 0 && timestamp < dayIntervals[index].start { index -= 1 }
            while index + 1 < dayIntervals.count && timestamp >= dayIntervals[index].end { index += 1 }
            return index
        }

        for segment in segments where segment.seconds > 0 && segment.endedAt > segment.startedAt {
            guard segment.endedAt > windowStart && segment.startedAt < windowEnd else { continue }
            var index = bucketIndex(for: max(segment.startedAt, windowStart))
            while index < dayIntervals.count {
                let interval = dayIntervals[index]
                if segment.endedAt <= interval.start { break }
                let span = segment.seconds(in: interval)
                if span > 0 {
                    buckets[index][segment.category, default: 0] += span
                }
                if segment.endedAt <= interval.end { break }
                index += 1
            }
        }

        var result: [DailyCategoryTime] = []
        for index in dayIntervals.indices {
            let start = dayIntervals[index].start
            for (category, seconds) in buckets[index] {
                result.append(DailyCategoryTime(date: start, category: category, seconds: seconds))
            }
        }
        return result
    }
}

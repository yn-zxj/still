import Foundation

public struct AgentWorkSpan: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var seconds: Double {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    public func seconds(in interval: DateInterval) -> Double {
        guard endedAt > startedAt else { return 0 }
        let start = max(startedAt, interval.start)
        let end = min(endedAt, interval.end)
        return max(0, end.timeIntervalSince(start))
    }
}

public struct AgentActivitySession: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var hapiID: String?
    public var flavor: String
    public var title: String?
    public var projectPath: String?
    public var host: String?
    public var spans: [AgentWorkSpan]
    public var updatedAt: Date

    public init(id: String, hapiID: String?, flavor: String, title: String?, projectPath: String?,
                host: String?, spans: [AgentWorkSpan], updatedAt: Date) {
        self.id = id
        self.hapiID = hapiID
        self.flavor = flavor
        self.title = title
        self.projectPath = projectPath
        self.host = host
        self.spans = Self.merged(spans)
        self.updatedAt = updatedAt
    }

    public var isWorking: Bool {
        guard let last = spans.last else { return false }
        return Date().timeIntervalSince(last.endedAt) < 90
    }

    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let projectPath = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !projectPath.isEmpty {
            return URL(fileURLWithPath: projectPath).lastPathComponent
        }
        return flavorLabel
    }

    public var flavorLabel: String {
        switch flavor.lowercased() {
        case "codex": return "Codex"
        case "claude": return "Claude Code"
        case "pi": return "pi"
        case "cursor": return "Cursor"
        case "qoder": return "Qoder"
        default:
            let trimmed = flavor.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Agent" : trimmed.capitalized
        }
    }

    public var locationLabel: String {
        if let host = host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return host
        }
        return "这台 Mac"
    }

    public func seconds(in interval: DateInterval) -> Double {
        Self.union(spans.flatMap { span -> [DateInterval] in
            let start = max(span.startedAt, interval.start)
            let end = min(span.endedAt, interval.end)
            return end > start ? [DateInterval(start: start, end: end)] : []
        }).reduce(0) { $0 + $1.duration }
    }

    public func clipped(to interval: DateInterval) -> AgentActivitySession? {
        let clipped = spans.compactMap { span -> AgentWorkSpan? in
            let start = max(span.startedAt, interval.start)
            let end = min(span.endedAt, interval.end)
            guard end > start else { return nil }
            return AgentWorkSpan(id: span.id, startedAt: start, endedAt: end)
        }
        guard !clipped.isEmpty else { return nil }
        var value = self
        value.spans = Self.merged(clipped)
        return value
    }

    public static func merged(_ spans: [AgentWorkSpan]) -> [AgentWorkSpan] {
        let sorted = spans.filter { $0.endedAt > $0.startedAt }.sorted { $0.startedAt < $1.startedAt }
        guard var current = sorted.first else { return [] }
        var result: [AgentWorkSpan] = []
        for span in sorted.dropFirst() {
            if span.startedAt <= current.endedAt {
                current.endedAt = max(current.endedAt, span.endedAt)
            } else {
                result.append(current)
                current = span
            }
        }
        result.append(current)
        return result
    }

    public static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }
}

public struct AgentActivitySummary: Equatable {
    public var interval: DateInterval
    public var sessions: [AgentActivitySession]
    public var wallSeconds: Double
    public var sessionSeconds: Double
    public var longestStretch: Double
    public var hostCount: Int
    public var workingCount: Int

    public static func make(sessions: [AgentActivitySession], interval: DateInterval) -> AgentActivitySummary {
        let clipped = sessions.compactMap { $0.clipped(to: interval) }.sorted {
            ($0.spans.last?.endedAt ?? .distantPast) > ($1.spans.last?.endedAt ?? .distantPast)
        }
        let all = clipped.flatMap { $0.spans.map { DateInterval(start: $0.startedAt, end: $0.endedAt) } }
        let union = AgentActivitySession.union(all)
        let hosts = Set(clipped.compactMap { session -> String? in
            guard let host = session.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else { return nil }
            return host
        })
        return AgentActivitySummary(
            interval: interval,
            sessions: clipped,
            wallSeconds: union.reduce(0) { $0 + $1.duration },
            sessionSeconds: clipped.flatMap(\.spans).reduce(0) { $0 + $1.seconds },
            longestStretch: union.map(\.duration).max() ?? 0,
            hostCount: hosts.count,
            workingCount: clipped.filter(\.isWorking).count
        )
    }
}

public struct HAPIActivityReport: Decodable, Sendable, Equatable {
    public static let supportedSchema = "hapi.activity.v1"

    public struct Session: Decodable, Sendable, Equatable {
        public struct Turn: Decodable, Sendable, Equatable {
            public var start: Double
            public var end: Double?
            public var startedBy: String?
        }

        public struct Wait: Decodable, Sendable, Equatable {
            public var start: Double
            public var end: Double?
        }

        public var id: String
        public var flavor: String?
        public var agentSessionId: String?
        public var machineId: String?
        public var host: String?
        public var machineName: String?
        public var path: String?
        public var title: String?
        public var turns: [Turn]
        public var waits: [Wait]
    }

    public var schema: String
    public var generatedAt: Double
    public var hubUrl: String
    public var localMachineId: String?
    public var since: Double
    public var until: Double
    public var sessions: [Session]
}

public enum HAPIReportError: Error, Equatable {
    case unsupportedSchema(String)
    case unreadable
}

public extension HAPIActivityReport {
    static func decode(_ data: Data) throws -> HAPIActivityReport {
        struct Header: Decodable { var schema: String }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw HAPIReportError.unreadable
        }
        guard header.schema == supportedSchema else {
            throw HAPIReportError.unsupportedSchema(header.schema)
        }
        do {
            return try JSONDecoder().decode(HAPIActivityReport.self, from: data)
        } catch {
            throw HAPIReportError.unreadable
        }
    }
}

public enum HAPIActivityPlanner {
    public static func plan(_ report: HAPIActivityReport, localHosts: Set<String>,
                            now: Date) -> [AgentActivitySession] {
        let hostNames = Set(localHosts.map { $0.lowercased() })
        var planned: [String: AgentActivitySession] = [:]
        for item in report.sessions where !item.turns.isEmpty {
            let flavor = normalizedFlavor(item.flavor)
            let local = isLocal(item, report: report, localHosts: hostNames)
            let waits = item.waits.compactMap { wait -> DateInterval? in
                guard let start = date(wait.start) else { return nil }
                let end = wait.end.flatMap(date) ?? now
                return DateInterval(start: start, end: max(start, end))
            }.filter { $0.duration >= 5 }
            var spans: [AgentWorkSpan] = []
            for turn in item.turns {
                guard let start = date(turn.start) else { continue }
                let end = turn.end.flatMap(date) ?? now
                guard end >= start else { continue }
                spans += subtract(waits, from: DateInterval(start: start, end: end))
            }
            let session = AgentActivitySession(
                id: "hapi:\(item.id)",
                hapiID: item.id,
                flavor: flavor,
                title: item.title?.nilIfBlank,
                projectPath: item.path?.nilIfBlank,
                host: local ? nil : (item.machineName?.nilIfBlank ?? item.host?.nilIfBlank),
                spans: spans,
                updatedAt: now
            )
            // A repeated HAPI session is the same session and must never be counted twice.
            if let existing = planned[session.id] {
                var merged = session
                merged.spans = AgentActivitySession.merged(existing.spans + session.spans)
                planned[session.id] = merged
            } else {
                planned[session.id] = session
            }
        }
        return planned.values.sorted {
            ($0.spans.last?.endedAt ?? .distantPast) > ($1.spans.last?.endedAt ?? .distantPast)
        }
    }

    private static func normalizedFlavor(_ flavor: String?) -> String {
        let value = flavor?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.isEmpty ? "agent" : value
    }

    private static func isLocal(_ session: HAPIActivityReport.Session,
                                report: HAPIActivityReport,
                                localHosts: Set<String>) -> Bool {
        if let localMachine = report.localMachineId?.nilIfBlank,
           let machine = session.machineId?.nilIfBlank {
            return localMachine == machine
        }
        guard let host = session.host?.nilIfBlank?.lowercased() else { return false }
        return localHosts.contains(host)
    }

    private static func date(_ milliseconds: Double) -> Date? {
        guard milliseconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func subtract(_ waits: [DateInterval], from turn: DateInterval) -> [AgentWorkSpan] {
        var cursor = turn.start
        var pieces: [DateInterval] = []
        for wait in AgentActivitySession.union(waits) {
            guard wait.end > turn.start, wait.start < turn.end else { continue }
            if wait.start > cursor {
                pieces.append(DateInterval(start: cursor, end: min(wait.start, turn.end)))
            }
            cursor = max(cursor, wait.end)
            if cursor >= turn.end { break }
        }
        if cursor < turn.end {
            pieces.append(DateInterval(start: cursor, end: turn.end))
        }
        return pieces.filter { $0.duration >= 1 }.map {
            AgentWorkSpan(startedAt: $0.start, endedAt: $0.end)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

import Foundation
import Testing
@testable import StillCore

@Suite("Agent activity and timeline")
struct AgentActivityTests {
    let origin = Date(timeIntervalSince1970: 1_790_000_000)

    private func milliseconds(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1_000
    }

    private func report(_ sessions: [[String: Any]], localMachineId: String? = "local") throws -> HAPIActivityReport {
        var object: [String: Any] = [
            "schema": HAPIActivityReport.supportedSchema,
            "generatedAt": milliseconds(origin.addingTimeInterval(600)),
            "hubUrl": "https://hub.example.test",
            "since": milliseconds(origin),
            "until": milliseconds(origin.addingTimeInterval(600)),
            "sessions": sessions
        ]
        if let localMachineId { object["localMachineId"] = localMachineId }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try HAPIActivityReport.decode(data)
    }

    @Test func repeatedHAPISessionsAreMergedWithoutDoubleCounting() throws {
        let first: [String: Any] = [
            "id": "session-1",
            "flavor": "codex",
            "machineId": "local",
            "path": "/tmp/still",
            "title": "Ship 0.5.0",
            "turns": [["start": milliseconds(origin), "end": milliseconds(origin.addingTimeInterval(100))]],
            "waits": []
        ]
        let repeated: [String: Any] = [
            "id": "session-1",
            "flavor": "codex",
            "machineId": "local",
            "path": "/tmp/still",
            "title": "Ship 0.5.0",
            "turns": [["start": milliseconds(origin.addingTimeInterval(50)), "end": milliseconds(origin.addingTimeInterval(150))]],
            "waits": []
        ]
        let plan = HAPIActivityPlanner.plan(
            try report([first, repeated]),
            localHosts: [],
            now: origin.addingTimeInterval(600)
        )
        #expect(plan.count == 1)
        #expect(plan[0].id == "hapi:session-1")
        #expect(plan[0].spans.count == 1)
        #expect(abs(plan[0].seconds(in: DateInterval(start: origin, end: origin.addingTimeInterval(600))) - 150) < 0.001)
    }

    @Test func waitsAreRemovedAndRemoteMachineNameBecomesTheSource() throws {
        let local: [String: Any] = [
            "id": "local-session",
            "flavor": "claude",
            "machineId": "local",
            "host": "studio.local",
            "path": "/tmp/local",
            "turns": [["start": milliseconds(origin), "end": milliseconds(origin.addingTimeInterval(600))]],
            "waits": [["start": milliseconds(origin.addingTimeInterval(120)),
                       "end": milliseconds(origin.addingTimeInterval(180))]]
        ]
        let remote: [String: Any] = [
            "id": "remote-session",
            "flavor": "codex",
            "machineId": "remote",
            "host": "builder.local",
            "machineName": "构建机",
            "path": "/tmp/remote",
            "turns": [["start": milliseconds(origin.addingTimeInterval(300)), "end": milliseconds(origin.addingTimeInterval(420))]],
            "waits": []
        ]
        let plan = HAPIActivityPlanner.plan(
            try report([local, remote]),
            localHosts: ["studio.local"],
            now: origin.addingTimeInterval(600)
        )
        let localSession = try #require(plan.first { $0.hapiID == "local-session" })
        let remoteSession = try #require(plan.first { $0.hapiID == "remote-session" })
        #expect(abs(localSession.spans.reduce(0) { $0 + $1.seconds } - 540) < 0.001)
        #expect(localSession.locationLabel == "这台 Mac")
        #expect(remoteSession.locationLabel == "构建机")
    }

    @Test func overlappingAgentsUseWallClockUnionAndKeepPerSessionTotals() {
        let first = AgentActivitySession(
            id: "hapi:a", hapiID: "a", flavor: "codex", title: "A", projectPath: nil,
            host: nil, spans: [AgentWorkSpan(startedAt: origin, endedAt: origin.addingTimeInterval(100))],
            updatedAt: origin
        )
        let second = AgentActivitySession(
            id: "hapi:b", hapiID: "b", flavor: "claude", title: "B", projectPath: nil,
            host: "构建机", spans: [AgentWorkSpan(startedAt: origin.addingTimeInterval(40), endedAt: origin.addingTimeInterval(150))],
            updatedAt: origin
        )
        let summary = AgentActivitySummary.make(
            sessions: [first, second],
            interval: DateInterval(start: origin, end: origin.addingTimeInterval(300))
        )
        #expect(abs(summary.wallSeconds - 150) < 0.001)
        #expect(abs(summary.sessionSeconds - 210) < 0.001)
        #expect(summary.hostCount == 1)
    }

    @Test func storePersistsRetainsThirtyOneDaysAndCanBeCleared() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("still-agent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent("AgentActivity.json")
        let store = AgentActivityStore(fileURL: fileURL)
        let recent = AgentActivitySession(
            id: "hapi:recent", hapiID: "recent", flavor: "codex", title: "Recent", projectPath: nil,
            host: nil, spans: [AgentWorkSpan(startedAt: origin, endedAt: origin.addingTimeInterval(60))],
            updatedAt: origin
        )
        let old = AgentActivitySession(
            id: "hapi:old", hapiID: "old", flavor: "codex", title: "Old", projectPath: nil,
            host: nil, spans: [AgentWorkSpan(startedAt: origin.addingTimeInterval(-90 * 86_400),
                                             endedAt: origin.addingTimeInterval(-90 * 86_400 + 60))],
            updatedAt: origin
        )
        try store.save([recent, old], retainingSince: origin.addingTimeInterval(-31 * 86_400))
        let loaded = store.load(retainingSince: origin.addingTimeInterval(-31 * 86_400))
        #expect(loaded.map(\.id) == ["hapi:recent"])

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        try store.save([], retainingSince: origin.addingTimeInterval(-31 * 86_400))
        #expect(store.load(retainingSince: origin.addingTimeInterval(-31 * 86_400)).isEmpty)
    }

    @Test func unsupportedSchemaCannotBeMistakenForActivity() {
        let data = Data(#"{"schema":"hapi.activity.v2","generatedAt":0,"hubUrl":"","since":0,"until":0,"sessions":[]}"#.utf8)
        #expect(throws: HAPIReportError.unsupportedSchema("hapi.activity.v2")) {
            try HAPIActivityReport.decode(data)
        }
    }

    @Test func dayTimelineStopsAtTheCurrentMomentAndKeepsLabelsBounded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30)))
        let now = try #require(calendar.date(byAdding: .minute, value: 14 * 60 + 25, to: day))
        let window = DayTimelineWindow(date: now, now: now, calendar: calendar)
        #expect(abs(window.elapsedFraction - (14.0 * 60 + 25) / (24 * 60)) < 0.0001)
        #expect(window.visible.end == now)
        #expect(window.marks(everyHours: 6, calendar: calendar).allSatisfy { $0 <= now })
        #expect(window.reducedSampleCount(varCount: 24) == 15)
    }
}

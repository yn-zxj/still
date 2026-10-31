import Foundation
import Testing
@testable import StillCore

struct FatigueHistoryTests {
    @Test func shortVisitAfterRestDoesNotBecomeFullActivity() {
        let now = Date()
        let history = FatigueHistory()
        history.record(date: now.addingTimeInterval(-120), percent: 0)
        history.record(date: now.addingTimeInterval(-60), percent: 1)
        history.record(date: now, percent: 3)
        let points = history.points(at: now)
        #expect(points.map(\.activity) == [0, 0.01, 0.03])
        #expect(points.last?.activity == 0.03)
        #expect(points.last!.fraction < 1)
    }
    @Test func unknownGapsAndFutureHaveNoInventedValues() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(3600)
        let history = FatigueHistory()
        history.record(date: start, percent: 20)
        history.record(date: start.addingTimeInterval(60), percent: 10)
        history.record(date: start.addingTimeInterval(7200), percent: 0)
        history.record(date: start.addingTimeInterval(7260), percent: 2)
        let points = history.points(at: start.addingTimeInterval(7200))
        #expect(points.count == 3)
        #expect(points.map(\.startsSegment) == [true, false, true])
        #expect(points.map(\.activity) == [0.2, 0.1, 0])
    }
    @Test func survivesRestartAndOnlyImportsRecordedFatigue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("FatigueHistory.json")
        let log = Data("{\"time\":\"2026-10-31T06:00:00Z\",\"fatiguePercent\":12}\n{\"time\":\"2026-10-31T06:01:00Z\",\"idleSeconds\":0}\ninvalid".utf8)
        let history = FatigueHistory(fileURL: file, diagnostics: log)
        #expect(history.observations.count == 1)
        #expect(history.observations.first?.percent == 12)
        try history.save()
        let restored = FatigueHistory(fileURL: file, diagnostics: log)
        #expect(restored.observations == history.observations)
    }
}

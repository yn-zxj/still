import Foundation
import Testing
@testable import StillCore

@Suite(.serialized)
struct UsageEngineTests {
    let origin = Date(timeIntervalSince1970: 1_790_000_000)
    func sample(_ second: Double, idle: Double = 0, available: Bool = true, wallOffset: Double = 0,
                application: ForegroundApplication? = nil) -> ActivitySample {
        ActivitySample(date: origin.addingTimeInterval(second + wallOffset), monotonic: second,
                       idleSeconds: idle, available: available, foregroundApplication: application)
    }
    func advance(_ engine: inout UsageEngine, from: Int, to: Int, idleSince: Int? = nil) {
        for second in from...to { engine.tick(sample(Double(second), idle: idleSince.map { Double(max(0, second - $0)) } ?? 0)) }
    }

    @Test func readingCannotAccumulateWhileDisplayUnavailableOrAcrossWakeGap() {
        var settings = MonitorSettings(); settings.mode = .reading
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 60)
        for second in 61...180 { engine.tick(sample(Double(second), idle: 500, available: false)) }
        #expect(engine.segments.reduce(0) { $0 + $1.seconds } == 60)
        #expect(engine.fatigueWorkSeconds == 0)
        engine.tick(sample(3600, available: true))
        #expect(engine.roundSeconds == 0)
        engine.tick(sample(3601, available: true))
        #expect(engine.roundSeconds == 1)
    }

    @Test func averageOnlyIncludesCalendarDaysSinceRecordingBegan() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 28800))
        let today = calendar.startOfDay(for: origin)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        #expect(UsageStatistics.coveredDays(startedAt: yesterday, endingAt: origin, days: 7, calendar: calendar) == 2)
        #expect(UsageStatistics.coveredDays(startedAt: yesterday, endingAt: origin, days: 28, calendar: calendar) == 2)
        let thirtyDaysAgo = try #require(calendar.date(byAdding: .day, value: -30, to: today))
        #expect(UsageStatistics.coveredDays(startedAt: thirtyDaysAgo, endingAt: origin, days: 7, calendar: calendar) == 7)
        #expect(UsageStatistics.coveredDays(startedAt: thirtyDaysAgo, endingAt: origin, days: 28, calendar: calendar) == 28)
        #expect(UsageStatistics.coveredDays(startedAt: origin, endingAt: origin, days: 7, calendar: calendar) == 1)
    }

    @Test func fineActivityCurveKeepsGapsAndFutureTimeBlank() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = calendar.startOfDay(for: origin)
        let start = day.addingTimeInterval(9 * 3600)
        let segment = UsageSegment(roundID: UUID(), startedAt: start, endedAt: start.addingTimeInterval(300), seconds: 300, mode: .activity)
        let now = start.addingTimeInterval(750)
        let points = UsageStatistics.activity(segments: [segment], date: now, calendar: calendar)
        #expect(points.map(\.activity) == [0, 1, 0, 0])
        let expectedFraction = 33150.0 / 86400.0
        let lastFraction = points.last?.fraction ?? 0
        #expect(abs(lastFraction - expectedFraction) < 0.0001)
        #expect(points.allSatisfy { $0.fraction < 1 })
        #expect(UsageStatistics.activity(segments: [], date: now).isEmpty)
    }

    @Test func testElapsedTimeAndSingleDueReminder() {
        var settings = MonitorSettings(); settings.workMinutes = 1
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 65)
        #expect(abs((engine.roundSeconds) - (65)) <= 0.01)
        #expect((engine.reminderSerial) == (1))
        #expect((engine.phase) == (.due))
    }

    @Test func testIdleThresholdRetractsCandidateFromLastInput() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 20)
        advance(&engine, from: 21, to: 110, idleSince: 20)
        #expect(abs((engine.roundSeconds) - (20)) <= 0.01)
        #expect((engine.phase) == (.away))
        #expect(engine.breaks.isEmpty)
        engine.tick(sample(111, idle: 0))
        engine.tick(sample(112, idle: 0))
        #expect(abs((engine.roundSeconds) - (21)) <= 0.01)
    }

    @Test func testShortPauseDoesNotResetRound() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 20)
        advance(&engine, from: 21, to: 60, idleSince: 20)
        engine.tick(sample(61))
        #expect(abs((engine.roundSeconds) - (61)) <= 0.01)
        #expect(engine.breaks.isEmpty)
    }

    @Test func testNaturalRestResetsRoundOnlyOnce() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 20)
        advance(&engine, from: 21, to: 350, idleSince: 20)
        #expect((engine.roundSeconds) == (0))
        #expect(abs((engine.segments.reduce(0) { $0 + $1.seconds }) - (20)) <= 0.01)
        #expect((engine.breaks.count) == (1))
        #expect((engine.breaks.first?.source) == (.natural))
        #expect((engine.breaks.first?.outcome) == (.completed))
    }

    @Test func testReadingModeCountsWithoutInput() {
        var settings = MonitorSettings(); settings.mode = .reading
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 400, idleSince: 0)
        #expect(abs((engine.roundSeconds) - (400)) <= 0.01)
        #expect((engine.phase) == (.working))
        #expect(engine.breaks.isEmpty)
    }

    @Test func testSleepAndUnobservedGapNeverCountAsWork() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 10)
        engine.tick(sample(11, available: false))
        engine.tick(sample(3600, available: false))
        engine.tick(sample(3601))
        engine.tick(sample(3602))
        #expect(engine.roundSeconds == 1)
        engine.tick(sample(7200))
        #expect(engine.roundSeconds == 1)
        #expect(engine.breaks.isEmpty)
    }

    @Test func testWallClockChangeDoesNotCreateNegativeOrLongUsage() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 10)
        engine.tick(sample(11, wallOffset: -3600))
        engine.tick(sample(12, wallOffset: -3600))
        #expect(abs((engine.roundSeconds) - (11)) <= 0.01)
        #expect(engine.segments.allSatisfy { $0.seconds >= 0 && $0.endedAt >= $0.startedAt })
    }

    @Test func testSnoozeKeepsProgressAndEventuallyRemindsAgain() {
        var settings = MonitorSettings(); settings.workMinutes = 1
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 61)
        engine.snooze(sample(61))
        advance(&engine, from: 62, to: 360)
        #expect((engine.reminderSerial) == (1))
        #expect((engine.phase) == (.snoozed))
        engine.tick(sample(361))
        #expect((engine.reminderSerial) == (2))
        #expect(abs((engine.roundSeconds) - (361)) <= 0.01)
        #expect(engine.breaks.isEmpty)
    }

    @Test func testMutingRemindersStillRecordsWork() {
        var settings = MonitorSettings(); settings.workMinutes = 1; settings.remindersEnabled = false
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 70)
        #expect((engine.roundSeconds) == (70))
        #expect((engine.reminderSerial) == (0))
        settings.remindersEnabled = true; engine.updateSettings(settings)
        engine.tick(sample(71))
        #expect((engine.reminderSerial) == (1))
    }

    @Test func testCompletedManualRestStopsUsageAndStartsNewRound() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 30)
        engine.startRest(sample(30), duration: 5)
        engine.tick(sample(35))
        #expect((engine.phase) == (.working))
        #expect((engine.roundSeconds) == (0))
        #expect((engine.completionSerial) == (1))
        #expect((engine.breaks.first?.outcome) == (.completed))
        engine.tick(sample(36))
        #expect((engine.roundSeconds) == (1))
        #expect((engine.segments.reduce(0) { $0 + $1.seconds }) == (31))
    }

    @Test func testInterruptedOrSkippedRestNeverResetsRound() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 30)
        engine.startRest(sample(30), duration: 60)
        engine.tick(sample(35))
        engine.interruptRest(sample(35))
        #expect((engine.roundSeconds) == (30))
        #expect((engine.breaks.first?.outcome) == (.interrupted))
        engine.snooze(sample(35), skipped: true)
        #expect((engine.breaks.last?.outcome) == (.skipped))
        #expect((engine.roundSeconds) == (30))
    }

    @Test func testTrackingPausePreservesRoundAndExcludesPausedInterval() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 30)
        engine.setTrackingPaused(true, sample: sample(30))
        advance(&engine, from: 31, to: 50)
        engine.setTrackingPaused(false, sample: sample(50))
        engine.tick(sample(51))
        #expect((engine.roundSeconds) == (31))
    }

    @Test func testRelaunchDoesNotTurnUnobservedIdleIntoCompletedRest() {
        var engine = UsageEngine()
        advance(&engine, from: 0, to: 30)
        var restored = UsageEngine(segments: engine.segments, checkpoint: engine.checkpoint)
        restored.tick(sample(10_000, idle: 9_000))
        #expect((restored.roundSeconds) == (30))
        #expect(restored.breaks.isEmpty)
    }

    @Test func testCrossMidnightSplitUsesCalendarBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 50)))
        let end = start.addingTimeInterval(1200)
        let segment = UsageSegment(roundID: UUID(), startedAt: start, endedAt: end, seconds: 1200, mode: .reading)
        let days = UsageStatistics.daily(segments: [segment], breaks: [], endingAt: end, days: 2, calendar: calendar)
        #expect(abs((days[0].seconds) - (600)) <= 0.01)
        #expect(abs((days[1].seconds) - (600)) <= 0.01)
    }

    @Test func testRepositoryUpdatesWithoutDuplicatingSegments() throws {
        let repository = try UsageRepository(inMemory: true)
        _ = try repository.load()
        var segment = UsageSegment(roundID: UUID(), startedAt: origin, endedAt: origin.addingTimeInterval(10), seconds: 10, mode: .activity)
        try repository.save(segments: [segment], applicationSegments: [], breaks: [])
        segment.seconds = 5; segment.endedAt = origin.addingTimeInterval(5)
        let rest = BreakRecord(startedAt: origin, endedAt: origin.addingTimeInterval(5), targetSeconds: 5, outcome: .completed, source: .manual)
        try repository.save(segments: [segment], applicationSegments: [], breaks: [rest])
        let loaded = try repository.load()
        #expect((loaded.segments.count) == (1))
        #expect((loaded.segments[0].seconds) == (5))
        #expect((loaded.breaks.count) == (1))
        #expect((loaded.breaks[0].outcome) == (.completed))
    }

    @Test func testDiskStoreSurvivesNewRepositoryInstance() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("still-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let segment = UsageSegment(roundID: UUID(), startedAt: origin, endedAt: origin.addingTimeInterval(90), seconds: 90, mode: .reading)
        do {
            let first = try UsageRepository(directory: folder)
            _ = try first.load()
            try first.save(segments: [segment], applicationSegments: [], breaks: [])
        }
        let second = try UsageRepository(directory: folder)
        let loaded = try second.load()
        #expect(loaded.segments == [segment])
    }

    @Test func testReopeningRestAtDeadlineDoesNotStartAnotherRest() {
        var engine = UsageEngine()
        engine.tick(sample(0))
        engine.startRest(sample(1), duration: 5)
        engine.startRest(sample(6), duration: 5)
        #expect(engine.breaks.count == 1)
        #expect(engine.breaks[0].outcome == .completed)
        #expect(engine.phase == .working)
    }

    @Test func testOverlappingDevelopmentCopiesDoNotDoubleCountOnRestore() {
        let round = UUID()
        let first = UsageSegment(roundID: round, startedAt: origin, endedAt: origin.addingTimeInterval(100), seconds: 100, mode: .activity)
        let second = UsageSegment(roundID: round, startedAt: origin.addingTimeInterval(50), endedAt: origin.addingTimeInterval(150), seconds: 100, mode: .activity)
        let checkpoint = EngineCheckpoint(roundID: round, snoozeUntil: nil, trackingPaused: false)
        let engine = UsageEngine(segments: [first, second], checkpoint: checkpoint)
        #expect(abs(engine.roundSeconds - 150) < 0.001)
        #expect(engine.segments.count == 2)
        #expect(engine.segments[1].seconds == 0)
    }

    @Test func testOldSettingsDecodeWithoutResettingUserRules() throws {
        let data = Data(#"{"workMinutes":25,"restMinutes":7,"idleSeconds":180,"mode":"reading","remindersEnabled":false,"showMenuCountdown":false}"#.utf8)
        let settings = try JSONDecoder().decode(MonitorSettings.self, from: data)
        #expect(settings.workMinutes == 25)
        #expect(settings.restMinutes == 7)
        #expect(settings.mode == .reading)
        #expect(settings.remindersEnabled == false)
        #expect(settings.showMenuCountdown == false)
        #expect(settings.reminderStyle == .mini)
        #expect(settings.appearanceTheme == .light)
        #expect(settings.showMenuFatigue)
        #expect(settings.applicationInsightsEnabled)
    }

    @Test func testAppearanceThemePersists() throws {
        for theme in AppearanceTheme.allCases {
            var settings = MonitorSettings()
            settings.appearanceTheme = theme
            let saved = try JSONDecoder().decode(MonitorSettings.self, from: JSONEncoder().encode(settings))
            #expect(saved.appearanceTheme == theme)
        }
    }

    @Test func testReminderModesAndMessagePersist() throws {
        for mode in ReminderStyle.allCases {
            var settings = MonitorSettings()
            settings.reminderStyle = mode; settings.reminderMessage = "站起来活动一下"
            settings.showDailyTimeInReminder = false
            let saved = try JSONDecoder().decode(MonitorSettings.self, from: JSONEncoder().encode(settings))
            #expect(saved == settings)
        }
    }

    @Test func testApplicationInsightsTrackOnlyCountedForegroundTimeAndSplitSwitches() {
        let browser = ForegroundApplication(bundleID: "com.apple.Safari", name: "Safari")
        let editor = ForegroundApplication(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        var engine = UsageEngine()
        for second in 0...10 {
            engine.tick(sample(Double(second), application: browser))
        }
        for second in 11...20 {
            engine.tick(sample(Double(second), application: editor))
        }
        #expect(engine.applicationSegments.count == 2)
        #expect(engine.applicationSegments[0].bundleID == browser.bundleID)
        #expect(engine.applicationSegments[1].bundleID == editor.bundleID)
        #expect(abs(engine.applicationSegments.reduce(0) { $0 + $1.seconds } - engine.roundSeconds) < 0.001)

        engine.tick(sample(21, available: false, application: browser))
        engine.tick(sample(22, application: browser))
        engine.setTrackingPaused(true, sample: sample(23, application: browser))
        let countBeforePause = engine.applicationSegments.count
        let secondsBeforePause = engine.applicationSegments.reduce(0) { $0 + $1.seconds }
        engine.tick(sample(30, application: browser))
        #expect(engine.applicationSegments.count == countBeforePause)
        #expect(abs(engine.applicationSegments.reduce(0) { $0 + $1.seconds } - secondsBeforePause) < 0.001)
    }

    @Test func testApplicationInsightsSummariesSwitchCountsAndCategoryClassification() {
        let start = origin
        let browser = ForegroundApplication(bundleID: "com.apple.Safari", name: "Safari")
        let editor = ForegroundApplication(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        let chat = ForegroundApplication(bundleID: "com.tencent.xinWeChat", name: "微信")
        let codingAgent = ForegroundApplication(bundleID: "com.qoder.ide", name: "Qoder")
        #expect(browser.category == .browsing)
        #expect(editor.category == .development)
        #expect(chat.category == .communication)
        #expect(codingAgent.category == .development)

        let segments = [
            ApplicationUsageSegment(startedAt: start, endedAt: start.addingTimeInterval(600), seconds: 600, application: browser),
            ApplicationUsageSegment(startedAt: start.addingTimeInterval(600), endedAt: start.addingTimeInterval(900), seconds: 300, application: editor),
            ApplicationUsageSegment(startedAt: start.addingTimeInterval(900), endedAt: start.addingTimeInterval(1200), seconds: 300, application: browser)
        ]
        let summary = ApplicationInsights.make(
            segments: segments,
            interval: DateInterval(start: start, end: start.addingTimeInterval(1200))
        )
        #expect(summary.totalSeconds == 1200)
        #expect(summary.byApplication.first?.bundleID == browser.bundleID)
        #expect(summary.byApplication.first?.seconds == 900)
        #expect(summary.switches == 2)
        #expect(summary.longestApplicationStretch == 600)
    }

    @Test func testApplicationSegmentsPersistAndOverlapsAreClippedOnRestore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("still-app-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = ForegroundApplication(bundleID: "com.apple.Safari", name: "Safari")
        let first = ApplicationUsageSegment(startedAt: origin, endedAt: origin.addingTimeInterval(100), seconds: 100, application: app)
        let second = ApplicationUsageSegment(startedAt: origin.addingTimeInterval(50), endedAt: origin.addingTimeInterval(150), seconds: 100, application: app)
        do {
            let repository = try UsageRepository(directory: folder)
            _ = try repository.load()
            try repository.save(segments: [], applicationSegments: [first, second], breaks: [])
        }
        let loaded = try UsageRepository(directory: folder).load()
        #expect(loaded.applicationSegments.count == 2)
        let engine = UsageEngine(applicationSegments: loaded.applicationSegments)
        #expect(engine.applicationSegments.count == 1)
        #expect(abs(engine.applicationSegments[0].seconds - 150) < 0.001)
    }

    @Test func testClearedApplicationHistoryStaysClearedAfterRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("still-clear-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = ForegroundApplication(bundleID: "com.apple.Safari", name: "Safari")
        let segment = ApplicationUsageSegment(
            startedAt: origin,
            endedAt: origin.addingTimeInterval(100),
            seconds: 100,
            application: app
        )
        do {
            let repository = try UsageRepository(directory: folder)
            _ = try repository.load()
            try repository.save(segments: [], applicationSegments: [segment], breaks: [])
            try repository.save(segments: [], applicationSegments: [], breaks: [])
        }
        let loaded = try UsageRepository(directory: folder).load()
        #expect(loaded.applicationSegments.isEmpty)
    }

    @Test func testFatigueIncreasesAndCapsDisplayAt100Percent() {
        var settings = MonitorSettings(); settings.workMinutes = 1
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 30)
        #expect(engine.fatiguePercent == 50)
        advance(&engine, from: 31, to: 100)
        #expect(engine.fatiguePercent == 100)
        #expect(engine.phase == .due)
        #expect(engine.roundSeconds == 100)
    }

    @Test func testPartialRestRecoverySurvivesEarlyEndAndRelaunch() throws {
        var settings = MonitorSettings(); settings.workMinutes = 1
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 60)
        engine.startRest(sample(60), duration: 60)
        engine.tick(sample(90))
        #expect(engine.fatiguePercent == 50)
        engine.interruptRest(sample(90))
        #expect(engine.fatiguePercent == 50)
        #expect(engine.roundSeconds == 60)
        let checkpoint = try JSONDecoder().decode(EngineCheckpoint.self, from: JSONEncoder().encode(engine.checkpoint))
        let restored = UsageEngine(settings: settings, segments: engine.segments, breaks: engine.breaks, checkpoint: checkpoint)
        #expect(restored.fatiguePercent == 50)
        #expect(restored.workRemaining == 30)
    }

    @Test func testNaturalIdleRecoveryIsNotAppliedTwice() {
        var settings = MonitorSettings(); settings.workMinutes = 1; settings.restMinutes = 1; settings.idleSeconds = 10
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 60)
        advance(&engine, from: 61, to: 90, idleSince: 60)
        #expect(engine.fatiguePercent == 50)
        engine.tick(sample(90, idle: 30))
        #expect(engine.fatiguePercent == 50)
        #expect(engine.roundSeconds == 60)
        advance(&engine, from: 91, to: 120, idleSince: 60)
        #expect(engine.fatiguePercent == 0)
        #expect(engine.roundSeconds == 0)
    }

    @Test func testUnobservedGapDoesNotRecoverFatigue() {
        var settings = MonitorSettings(); settings.workMinutes = 1
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 30)
        engine.tick(sample(3600, idle: 3000))
        #expect(engine.fatiguePercent == 50)
        #expect(engine.breaks.isEmpty)
    }
    @Test func screenOffRecoveryPersistsAcrossRelaunchWithoutInventingUsageOrBreaks() throws {
        var settings = MonitorSettings(); settings.workMinutes = 1; settings.restMinutes = 1; settings.mode = .reading
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 60)
        engine.tick(sample(61, available: false))
        engine.tick(sample(91, available: false))
        #expect(engine.fatiguePercent == 50)
        let checkpoint = try JSONDecoder().decode(EngineCheckpoint.self, from: JSONEncoder().encode(engine.checkpoint))
        var restored = UsageEngine(settings: settings, segments: engine.segments, checkpoint: checkpoint)
        restored.tick(ActivitySample(date: origin.addingTimeInterval(36000), monotonic: 0, idleSeconds: 0))
        #expect(restored.fatiguePercent == 0)
        #expect(restored.roundSeconds == 0)
        #expect(restored.segments.reduce(0) { $0 + $1.seconds } == 60)
        #expect(restored.breaks.isEmpty)
        restored.tick(ActivitySample(date: origin.addingTimeInterval(36001), monotonic: 1, idleSeconds: 0))
        #expect(restored.roundSeconds == 1)
    }

    @Test func suspensionClockChangesAndPausedTrackingDoNotInventRecovery() {
        var settings = MonitorSettings(); settings.workMinutes = 1; settings.restMinutes = 1
        var engine = UsageEngine(settings: settings)
        advance(&engine, from: 0, to: 30)
        engine.setTrackingPaused(true, sample: sample(30))
        engine.tick(sample(40))
        #expect(engine.fatiguePercent == 50)
        engine.tick(sample(41, available: false))
        engine.tick(sample(42, available: false, wallOffset: 3600))
        #expect(engine.fatiguePercent == 50)
        engine.tick(sample(43, wallOffset: 3600))
        #expect(engine.fatiguePercent == 48)
        #expect(engine.breaks.isEmpty)
    }

}

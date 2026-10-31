import Foundation
import Testing
@testable import StillCore

struct ScreenActivityTests {
    func frame(_ value: UInt8) -> [UInt8] {
        Array(repeating: value, count: ScreenActivityEvidence.width * ScreenActivityEvidence.height)
    }
    @Test func recurringVideoChangesProduceActivityButStaticFramesDoNotRefreshIt() {
        var evidence = ScreenActivityEvidence()
        evidence.observe(frame(0), at: 0)
        evidence.observe(frame(80), at: 1)
        #expect(evidence.lastActivity == nil)
        evidence.observe(frame(160), at: 2)
        #expect(evidence.lastActivity == 2)
        for t in 3...100 { evidence.observe(frame(160), at: Double(t)) }
        #expect(evidence.lastActivity == 2)
    }
    @Test func cursorClockAndSingleNotificationDoNotSustainUsage() {
        var evidence = ScreenActivityEvidence()
        evidence.observe(frame(0), at: 0)
        var small = frame(0)
        for i in 0..<40 { small[10 * 64 + i] = 200 }
        evidence.observe(small, at: 1)
        evidence.observe(frame(0), at: 2)
        #expect(evidence.lastActivity == nil)
        evidence.observe(frame(120), at: 3)
        evidence.observe(frame(120), at: 4)
        evidence.observe(frame(240), at: 5)
        #expect(evidence.lastActivity == nil)
    }
    @Test func localizedAnimationAndTitleBarAreIgnored() {
        var evidence = ScreenActivityEvidence()
        evidence.observe(frame(0), at: 0)
        var top = frame(0)
        for i in 0..<(64 * 4) { top[i] = 255 }
        evidence.observe(top, at: 1)
        evidence.observe(frame(0), at: 2)
        var oneRegion = frame(0)
        for y in 5..<10 { for x in 4..<14 { oneRegion[y*64+x] = 255 } }
        evidence.observe(oneRegion, at: 3)
        evidence.observe(frame(0), at: 4)
        #expect(evidence.lastActivity == nil)
    }
    @Test func droppedFramesTargetChangesAndInvalidInputResetEvidence() {
        var evidence = ScreenActivityEvidence()
        evidence.observe(frame(0), at: 0)
        evidence.observe(frame(100), at: 1)
        evidence.observe(frame(200), at: 100)
        #expect(evidence.lastActivity == nil)
        evidence.reset()
        evidence.observe(frame(0), at: 101)
        evidence.observe(frame(100), at: 102)
        #expect(evidence.lastActivity == nil)
        evidence.observe([], at: 103)
        evidence.observe(frame(200), at: 104)
        #expect(evidence.lastActivity == nil)
        evidence.observe(frame(0), at: .nan)
        #expect(evidence.lastActivity == nil)
    }
    @Test func visualActivityCountsVideoThenStopsAfterItBecomesStatic() {
        var settings = MonitorSettings(); settings.idleSeconds = 10
        var engine = UsageEngine(settings: settings)
        var evidence = ScreenActivityEvidence()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        for t in 0...30 {
            evidence.observe(frame(t.isMultiple(of: 2) ? 0 : 200), at: Double(t))
            let idle = min(1000 + Double(t), evidence.lastActivity.map { Double(t) - $0 } ?? 1000)
            engine.tick(ActivitySample(date: date.addingTimeInterval(Double(t)), monotonic: Double(t), idleSeconds: idle))
        }
        #expect(engine.fatigueWorkSeconds > 20)
        for t in 31...60 {
            evidence.observe(frame(0), at: Double(t))
            let idle = Double(t) - (evidence.lastActivity ?? 0)
            engine.tick(ActivitySample(date: date.addingTimeInterval(Double(t)), monotonic: Double(t), idleSeconds: idle))
        }
        #expect(engine.phase == .away)
        #expect(engine.segments.reduce(0) { $0 + $1.seconds } <= 30)
    }
    @Test func lockOverridesEvenFreshVisualActivity() {
        var engine = UsageEngine()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        for t in 0...30 { engine.tick(ActivitySample(date: date.addingTimeInterval(Double(t)), monotonic: Double(t), idleSeconds: 0)) }
        engine.tick(ActivitySample(date: date.addingTimeInterval(31), monotonic: 31, idleSeconds: 0, available: false))
        engine.tick(ActivitySample(date: date.addingTimeInterval(400), monotonic: 400, idleSeconds: 0, available: false))
        #expect(engine.fatiguePercent == 0)
        #expect(engine.segments.reduce(0) { $0 + $1.seconds } == 30)
    }
}

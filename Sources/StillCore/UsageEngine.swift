import Foundation

/// Pure state machine. All elapsed time comes from samples, never timer tick counts.
public struct UsageEngine {
    public private(set) var settings: MonitorSettings
    public private(set) var segments: [UsageSegment]
    public private(set) var breaks: [BreakRecord]
    public private(set) var phase: EnginePhase = .working
    public private(set) var now: Date
    public private(set) var roundID: UUID
    public private(set) var trackingPaused: Bool
    public private(set) var reminderSerial = 0
    public private(set) var completionSerial = 0
    public private(set) var restRemaining: Double = 0
    public private(set) var snoozeUntil: Date?
    public private(set) var fatigueWorkSeconds: Double = 0
    private var previous: ActivitySample?
    private var activeSegmentID: UUID?
    private var restingID: UUID?
    private var restStartedMonotonic: Double?
    private var snoozeDeadline: Double?
    private var lastReminderMonotonic: Double?
    private var observedSince: Double?
    private var recoveredIdleSeconds: Double = 0
    private var restStartFatigue: Double = 0
    public private(set) var guidedRest = false

    public init(settings: MonitorSettings = MonitorSettings(), segments: [UsageSegment] = [],
                breaks: [BreakRecord] = [], checkpoint: EngineCheckpoint? = nil, now: Date = Date()) {
        self.settings = settings; self.segments = Self.coalesceOverlaps(segments); self.breaks = breaks
        self.roundID = checkpoint?.roundID ?? UUID(); self.now = now
        self.trackingPaused = checkpoint?.trackingPaused ?? false
        self.snoozeUntil = checkpoint?.snoozeUntil
        fatigueWorkSeconds = max(0, checkpoint?.fatigueWorkSeconds ?? self.segments.filter { $0.roundID == self.roundID }.reduce(0) { $0 + $1.seconds })
        // An unobserved process gap never counts as completed rest or computer usage.
        for index in self.breaks.indices where self.breaks[index].outcome == .inProgress {
            self.breaks[index].outcome = .interrupted
            self.breaks[index].endedAt = self.breaks[index].startedAt
        }
    }

    public var roundSeconds: Double { segments.filter { $0.roundID == roundID }.reduce(0) { $0 + $1.seconds } }
    public var progress: Double { min(1, max(0, fatigueWorkSeconds / settings.workSeconds)) }
    public var fatiguePercent: Int { min(100, max(0, Int((progress * 100 + 0.0000001).rounded(.down)))) }
    public var workRemaining: Double { max(0, settings.workSeconds - fatigueWorkSeconds) }
    public var checkpoint: EngineCheckpoint { .init(roundID: roundID, snoozeUntil: snoozeUntil, trackingPaused: trackingPaused, fatigueWorkSeconds: fatigueWorkSeconds) }

    /// Recover overlapping observations from development copies without counting a second twice.
    /// Retain obsolete IDs as zero-duration records so the repository can update them in place.
    private static func coalesceOverlaps(_ input: [UsageSegment]) -> [UsageSegment] {
        var result = input.sorted { $0.startedAt < $1.startedAt }
        var lastByRoundAndMode: [String: Int] = [:]
        for index in result.indices where result[index].seconds > 0 {
            let key = result[index].roundID.uuidString + result[index].mode.rawValue
            if let prior = lastByRoundAndMode[key], result[prior].endedAt > result[index].startedAt {
                let current = result[index]
                let wall = current.endedAt.timeIntervalSince(current.startedAt)
                let tail = max(0, current.endedAt.timeIntervalSince(max(current.startedAt, result[prior].endedAt)))
                result[prior].seconds += wall > 0 ? current.seconds * tail / wall : 0
                result[prior].endedAt = max(result[prior].endedAt, current.endedAt)
                result[index].seconds = 0; result[index].endedAt = result[index].startedAt
            } else { lastByRoundAndMode[key] = index }
        }
        return result
    }

    public mutating func updateSettings(_ newSettings: MonitorSettings) {
        if settings.mode != newSettings.mode { activeSegmentID = nil; previous = nil; observedSince = nil }
        settings = newSettings
    }

    public mutating func tick(_ sample: ActivitySample) {
        now = sample.date
        defer { previous = sample }
        if snoozeDeadline == nil, let until = snoozeUntil {
            snoozeDeadline = sample.monotonic + max(0, until.timeIntervalSince(sample.date))
        }
        if phase == .resting, guidedRest { return }
        if phase == .resting, let began = restStartedMonotonic {
            let target = breaks.first(where: { $0.id == restingID })?.targetSeconds ?? settings.restSeconds
            restRemaining = max(0, target - max(0, sample.monotonic - began))
            fatigueWorkSeconds = restStartFatigue * restRemaining / target
            if restRemaining == 0 { finishRest(at: sample.date) }
            return
        }
        guard sample.available, !trackingPaused else {
            activeSegmentID = nil
            observedSince = nil
            recoveredIdleSeconds = 0
            phase = trackingPaused ? .paused : .suspended
            return
        }
        let elapsed = previous.map { sample.monotonic - $0.monotonic } ?? 0
        let wallElapsed = previous.map { sample.date.timeIntervalSince($0.date) } ?? 0
        let usableInterval = previous?.available == true && elapsed >= 0 && elapsed <= 15 && abs(wallElapsed - elapsed) < 5
        if !usableInterval { activeSegmentID = nil; observedSince = sample.monotonic; recoveredIdleSeconds = 0 }

        if settings.mode == .activity && sample.idleSeconds >= Double(settings.idleSeconds) {
            let idleStart = sample.date.addingTimeInterval(-max(0, sample.idleSeconds))
            trimActiveSegment(at: idleStart)
            activeSegmentID = nil
            phase = .away
            let observedIdle = min(sample.idleSeconds, max(0, sample.monotonic - (observedSince ?? sample.monotonic)))
            let recovered = max(0, observedIdle - recoveredIdleSeconds)
            fatigueWorkSeconds = max(0, min(settings.workSeconds, fatigueWorkSeconds) - recovered * settings.workSeconds / settings.restSeconds)
            recoveredIdleSeconds = observedIdle
            if observedIdle >= settings.restSeconds, roundSeconds > 0 {
                breaks.append(BreakRecord(startedAt: sample.date.addingTimeInterval(-observedIdle),
                                          endedAt: sample.date, targetSeconds: settings.restSeconds,
                                          outcome: .completed, source: .natural))
                resetRound()
            }
            return
        }

        recoveredIdleSeconds = 0

        if usableInterval, let previous, phase != .paused && phase != .suspended {
            // When returning, count only time after the new input, not the whole polling interval.
            let delta = phase == .away ? min(elapsed, max(0, sample.idleSeconds)) : elapsed
            if delta > 0 { addUsage(from: max(previous.date, sample.date.addingTimeInterval(-delta)), to: sample.date, seconds: delta) }
        }
        if let deadline = snoozeDeadline, sample.monotonic < deadline {
            phase = .snoozed
            return
        }
        snoozeDeadline = nil; snoozeUntil = nil
        phase = fatigueWorkSeconds >= settings.workSeconds ? .due : .working
        if phase == .due && settings.remindersEnabled &&
            (lastReminderMonotonic == nil || sample.monotonic - lastReminderMonotonic! >= Double(max(1, settings.repeatMinutes)) * 60) {
            reminderSerial += 1
            lastReminderMonotonic = sample.monotonic
        }
    }

    public mutating func startRest(_ sample: ActivitySample, duration: Double? = nil) {
        let wasResting = phase == .resting
        tick(sample)
        guard !wasResting, phase != .resting else { return }
        activeSegmentID = nil
        let target = max(1, duration ?? settings.restSeconds)
        let record = BreakRecord(startedAt: sample.date, targetSeconds: target, outcome: .inProgress, source: .manual)
        breaks.append(record); restingID = record.id; restStartedMonotonic = sample.monotonic
        restStartFatigue = min(settings.workSeconds, fatigueWorkSeconds)
        restRemaining = target; phase = .resting
        snoozeDeadline = nil; snoozeUntil = nil
    }

    public mutating func startGuidedRest(_ sample: ActivitySample, duration: Double) {
        if phase == .resting { interruptRest(sample) }
        startRest(sample, duration: duration)
        guidedRest = true
    }

    public mutating func updateGuidedRest(elapsed: Double, completed: Bool, sample: ActivitySample) {
        guard guidedRest, phase == .resting, elapsed.isFinite,
              let target = breaks.first(where: { $0.id == restingID })?.targetSeconds else { return }
        tick(sample)
        restRemaining = max(0, target - min(target, max(0, elapsed)))
        fatigueWorkSeconds = restStartFatigue * restRemaining / target
        if completed && elapsed >= target - min(1, target * 0.01) { finishRest(at: sample.date) }
    }

    public mutating func interruptRest(_ sample: ActivitySample) {
        tick(sample)
        guard phase == .resting else { return }
        guard let id = restingID, let index = breaks.firstIndex(where: { $0.id == id }) else { return }
        breaks[index].outcome = .interrupted; breaks[index].endedAt = sample.date
        restingID = nil; restStartedMonotonic = nil; restRemaining = 0; guidedRest = false
        phase = .working; activeSegmentID = nil; previous = sample
        snooze(sample)
    }

    public mutating func snooze(_ sample: ActivitySample, skipped: Bool = false) {
        if phase == .resting { interruptRest(sample); return }
        let duration = Double(max(1, settings.snoozeMinutes)) * 60
        snoozeDeadline = sample.monotonic + duration
        snoozeUntil = sample.date.addingTimeInterval(duration)
        lastReminderMonotonic = sample.monotonic
        phase = .snoozed
        if skipped {
            breaks.append(BreakRecord(startedAt: sample.date, endedAt: sample.date,
                                      targetSeconds: settings.restSeconds, outcome: .skipped, source: .manual))
        }
    }

    public mutating func setTrackingPaused(_ paused: Bool, sample: ActivitySample) {
        tick(sample)
        trackingPaused = paused; activeSegmentID = nil; previous = sample
        if phase != .resting { phase = paused ? .paused : .working }
    }

    private mutating func addUsage(from start: Date, to end: Date, seconds: Double) {
        fatigueWorkSeconds += seconds
        if let id = activeSegmentID, let index = segments.firstIndex(where: { $0.id == id }),
           abs(segments[index].endedAt.timeIntervalSince(start)) < 0.1 {
            segments[index].endedAt = end; segments[index].seconds += seconds
        } else {
            let segment = UsageSegment(roundID: roundID, startedAt: start, endedAt: end, seconds: seconds, mode: settings.mode)
            segments.append(segment); activeSegmentID = segment.id
        }
    }

    private mutating func trimActiveSegment(at cutoff: Date) {
        guard let id = activeSegmentID, let index = segments.firstIndex(where: { $0.id == id }),
              segments[index].endedAt > cutoff else { return }
        let segment = segments[index]
        let end = max(segment.startedAt, cutoff)
        let fraction = segment.endedAt > segment.startedAt ? end.timeIntervalSince(segment.startedAt) / segment.endedAt.timeIntervalSince(segment.startedAt) : 0
        segments[index].endedAt = end
        segments[index].seconds = max(0, segment.seconds * fraction)
        fatigueWorkSeconds = max(0, fatigueWorkSeconds - (segment.seconds - segments[index].seconds))
    }

    private mutating func finishRest(at date: Date) {
        if let index = breaks.firstIndex(where: { $0.id == restingID }) {
            breaks[index].endedAt = date; breaks[index].outcome = .completed
        }
        restingID = nil; restStartedMonotonic = nil; restRemaining = 0; guidedRest = false
        resetRound(); phase = .working; completionSerial += 1
    }

    private mutating func resetRound() {
        roundID = UUID(); activeSegmentID = nil
        fatigueWorkSeconds = 0
        snoozeDeadline = nil; snoozeUntil = nil; lastReminderMonotonic = nil
    }
}

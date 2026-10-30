import Foundation

/// A full-day axis with observations clipped at the current moment.
public struct DayTimelineWindow: Equatable {
    public let day: DateInterval
    public let visible: DateInterval
    public let now: Date

    public init(date: Date, now: Date = Date(), calendar: Calendar = .current) {
        let fullDay = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        day = fullDay
        self.now = now

        let clamped = min(max(now, fullDay.start), fullDay.end)
        // Keep the scale non-degenerate while preserving a visible end at 00:00.
        let end = max(fullDay.start.addingTimeInterval(1), clamped)
        visible = DateInterval(start: fullDay.start, end: min(end, fullDay.end))
    }

    public var elapsedFraction: Double {
        visible.duration / max(day.duration, 1)
    }

    public func fraction(for date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(visible.start) / max(day.duration, 1)))
    }

    public func visibleEnd(for start: Date, end: Date) -> Date? {
        let clippedStart = max(start, visible.start)
        let clippedEnd = min(end, visible.end)
        return clippedEnd > clippedStart ? clippedEnd : nil
    }

    /// Fixed 00–24 hour anchors. Future data is still clipped by visibleEnd.
    public func marks(everyHours step: Int = 6, calendar: Calendar = .current) -> [Date] {
        var result = Swift.stride(from: 0, to: 24, by: max(1, step)).compactMap {
            calendar.date(byAdding: .hour, value: $0, to: day.start)
        }
        result.append(day.end)
        return result
    }

    public func reducedSampleCount(varCount: Int, minimum: Int = 1) -> Int {
        guard varCount > 0 else { return 0 }
        let count = Int(ceil(elapsedFraction * Double(varCount)))
        return min(varCount, max(minimum, count))
    }
}

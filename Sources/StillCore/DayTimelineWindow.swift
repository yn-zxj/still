import Foundation

/// A bounded day timeline that ends at the current moment instead of drawing hours
/// which have not happened yet.
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
        min(1, max(0, date.timeIntervalSince(visible.start) / max(visible.duration, 1)))
    }

    public func visibleEnd(for start: Date, end: Date) -> Date? {
        let clippedStart = max(start, visible.start)
        let clippedEnd = min(end, visible.end)
        return clippedEnd > clippedStart ? clippedEnd : nil
    }

    /// Whole-hour anchors up to the current time. The current minute is appended
    /// when it does not coincide with a whole-hour mark.
    public func marks(everyHours step: Int = 6, calendar: Calendar = .current) -> [Date] {
        let stride = max(1, step)
        var result: [Date] = []
        for hour in Swift.stride(from: 0, to: 24, by: stride) {
            guard let mark = calendar.date(byAdding: .hour, value: hour, to: day.start),
                  mark <= visible.end else { continue }
            result.append(mark)
        }
        if let last = result.last,
           visible.end.timeIntervalSince(last) < 2 * 3_600 {
            return result
        }
        result.append(visible.end)
        return result
    }

    public func reducedSampleCount(varCount: Int, minimum: Int = 1) -> Int {
        guard varCount > 0 else { return 0 }
        let count = Int(ceil(elapsedFraction * Double(varCount)))
        return min(varCount, max(minimum, count))
    }
}

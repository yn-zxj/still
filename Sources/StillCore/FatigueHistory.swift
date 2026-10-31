import Foundation

public struct FatigueObservation: Codable, Equatable {
    public var date: Date
    public var percent: Int
    public init(date: Date, percent: Int) { self.date = date; self.percent = min(100, max(0, percent)) }
}

public struct FatiguePlotPoint: Equatable {
    public var fraction: Double
    public var activity: Double
    public var startsSegment: Bool
}

/// Stores measured engine values, never estimates fatigue from activity density.
public final class FatigueHistory {
    public private(set) var observations: [FatigueObservation] = []
    private let fileURL: URL?
    public init(fileURL: URL? = nil, diagnostics: Data? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([FatigueObservation].self, from: data) {
            observations = saved.filter { (0...100).contains($0.percent) }.sorted { $0.date < $1.date }
        }
        // Only bootstrap from actual diagnostic samples, never usage segments.
        if observations.isEmpty, let diagnostics,
           let text = String(data: diagnostics, encoding: .utf8) {
            let formatter = ISO8601DateFormatter()
            observations = text.split(separator: "\n").compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let time = event["time"] as? String, let date = formatter.date(from: time),
                      let percent = event["fatiguePercent"] as? Int, (0...100).contains(percent) else { return nil }
                return FatigueObservation(date: date, percent: percent)
            }.sorted { $0.date < $1.date }
        }
    }
    public func record(date: Date, percent: Int) {
        let point = FatigueObservation(date: date, percent: percent)
        if let last = observations.last {
            guard date >= last.date else { return }
            if date == last.date { observations[observations.count - 1] = point; return }
            guard point.percent != last.percent || date.timeIntervalSince(last.date) >= 15 else { return }
        }
        observations.append(point)
        let cutoff = date.addingTimeInterval(-31 * 86_400)
        if observations.first?.date ?? date < cutoff { observations.removeAll { $0.date < cutoff } }
    }
    public func save() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(observations).write(to: fileURL, options: .atomic)
    }
    public func points(at date: Date, calendar: Calendar = .current) -> [FatiguePlotPoint] {
        let window = DayTimelineWindow(date: date, now: date, calendar: calendar)
        let day = observations.filter { $0.date >= window.day.start && $0.date <= date }
        return day.enumerated().map { index, value in
            FatiguePlotPoint(fraction: window.fraction(for: value.date), activity: Double(value.percent) / 100,
                             startsSegment: index == 0 || value.date.timeIntervalSince(day[index - 1].date) > 90)
        }
    }
}

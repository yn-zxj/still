import Foundation

/// Remembers recommendations shown today, including explicit "换一个" choices.
public struct DailyCourseRotation: Codable, Equatable {
    public private(set) var day: String?
    public private(set) var seen: [String] = []
    public private(set) var lastID: String?
    public init() {}
    public mutating func next(candidates: [String], date: Date, calendar: Calendar = .current,
                              choose: ([String]) -> String? = { $0.randomElement() }) -> String? {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let today = "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        if day != today { day = today; seen = [] }
        var unique: [String] = []
        for id in candidates where !id.isEmpty && !unique.contains(id) { unique.append(id) }
        guard !unique.isEmpty else { return nil }
        var pool = unique.filter { !seen.contains($0) }
        if pool.isEmpty { seen = []; pool = unique }
        if pool.count > 1, let lastID { pool.removeAll { $0 == lastID } }
        guard let selected = choose(pool), pool.contains(selected) else { return nil }
        seen.append(selected); lastID = selected
        return selected
    }
}

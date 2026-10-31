import Foundation

/// Conservative frame evidence, independent of capture APIs. No images are persisted.
public struct ScreenActivityEvidence {
    public static let width = 64, height = 36
    private var previous: [UInt8]?
    private var previousTime: Double?
    private var candidateTime: Double?
    public private(set) var lastActivity: Double?
    public init() {}
    public mutating func reset() { self = Self() }

    public mutating func observe(_ pixels: [UInt8], at time: Double) {
        guard pixels.count == Self.width * Self.height, time.isFinite else { reset(); return }
        defer { previous = pixels; previousTime = time }
        guard let before = previous, let last = previousTime,
              time > last, time - last <= 5 else { candidateTime = nil; return }
        // Ignore window edges, title bars and blinking cursors. Changes must cover
        // multiple regions and recur; one notification or window transition is insufficient.
        var changed = 0
        var regions = Set<Int>()
        for y in 4..<Self.height-3 {
            for x in 3..<Self.width-3 {
                let index = y * Self.width + x
                if abs(Int(pixels[index]) - Int(before[index])) >= 18 {
                    changed += 1
                    regions.insert((y * 3 / Self.height) * 4 + x * 4 / Self.width)
                }
            }
        }
        guard changed >= 45, regions.count >= 3 else { candidateTime = nil; return }
        if let candidate = candidateTime, time - candidate <= 5 { lastActivity = time }
        candidateTime = time
    }
}

import Foundation

public enum InputActivityTiming {
    /// A failed query is not an infinitely long absence or a fresh input event.
    public static func latest(_ elapsedTimes: [Double]) -> Double? {
        elapsedTimes.filter { $0.isFinite && $0 >= 0 }.min()
    }
}

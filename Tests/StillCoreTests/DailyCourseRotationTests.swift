import Foundation
import Testing
@testable import StillCore
struct DailyCourseRotationTests {
    private let date = Date(timeIntervalSince1970: 1793232000)
    @Test func unseenCoursesBeforeRepeatsIncludingRandomChanges() {
        var rotation = DailyCourseRotation()
        let candidates = ["neck", "eyes", "hands"]
        let selected = (0..<3).compactMap { _ in rotation.next(candidates: candidates, date: date, choose: { $0.first }) }
        #expect(Set(selected).count == 3)
        #expect(rotation.next(candidates: candidates, date: date, choose: { $0.first }) != selected.last)
    }
    @Test func restartPreservesDayHistoryAndMidnightResetsIt() throws {
        var rotation = DailyCourseRotation()
        #expect(rotation.next(candidates: ["a", "b", "c"], date: date, choose: { $0.first }) == "a")
        var restored = try JSONDecoder().decode(DailyCourseRotation.self, from: JSONEncoder().encode(rotation))
        #expect(restored.next(candidates: ["a", "b", "c"], date: date, choose: { $0.first }) == "b")
        #expect(restored.next(candidates: ["a", "b", "c"], date: date.addingTimeInterval(86400), choose: { $0.first }) == "a")
        #expect(restored.seen == ["a"])
    }
    @Test func singleEmptyAndChangedLibrariesRemainValid() {
        var rotation = DailyCourseRotation()
        #expect(rotation.next(candidates: [], date: date) == nil)
        #expect(rotation.next(candidates: ["a", "a", ""], date: date) == "a")
        #expect(rotation.next(candidates: ["a"], date: date) == "a")
        #expect(rotation.next(candidates: ["b", "c"], date: date, choose: { $0.first }) == "b")
        #expect(rotation.next(candidates: ["c"], date: date) == "c")
    }
    @Test func previewCopyAndInvalidChoiceDoNotConsumeRealHistory() {
        var live = DailyCourseRotation(), preview = live
        _ = preview.next(candidates: ["a", "b"], date: date, choose: { $0.first })
        #expect(live.seen.isEmpty)
        #expect(live.next(candidates: ["a", "b"], date: date, choose: { _ in "missing" }) == nil)
        #expect(live.seen.isEmpty)
    }
}

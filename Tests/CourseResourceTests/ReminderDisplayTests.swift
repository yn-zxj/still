import AppKit
import Testing
import StillCore
@testable import Still

struct ReminderDisplayTests {
    private let main = ReminderDisplay(id: 1, frame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: NSRect(x: 0, y: 70, width: 1728, height: 1015))
    private let left = ReminderDisplay(id: 2, frame: NSRect(x: -1920, y: -120, width: 1920, height: 1080),
        visibleFrame: NSRect(x: -1920, y: -120, width: 1920, height: 1055))
    private let above = ReminderDisplay(id: 3, frame: NSRect(x: 120, y: 1117, width: 1280, height: 800),
        visibleFrame: NSRect(x: 120, y: 1117, width: 1280, height: 775))

    @Test func allScreensRemindButOnlyClickedScreenOwnsTraining() {
        let screens = [main, left, above]
        #expect(ReminderDisplayLayout.targets(screens, trainingDisplayID: nil) == screens)
        #expect(ReminderDisplayLayout.targets(screens, trainingDisplayID: left.id) == [left])
        #expect(ReminderDisplayLayout.targets(screens, trainingDisplayID: above.id) == [above])
        // Back to reminder: releasing the training screen restores all displays.
        #expect(ReminderDisplayLayout.targets(screens, trainingDisplayID: nil).count == 3)
    }
    @Test func disconnectTransfersOneTrainingSessionAndNoScreensIsSafe() {
        #expect(ReminderDisplayLayout.targets([main, above], trainingDisplayID: left.id) == [main])
        #expect(ReminderDisplayLayout.targets([], trainingDisplayID: left.id).isEmpty)
        #expect(ReminderDisplayLayout.targets([left, main], trainingDisplayID: left.id) == [left])
    }
    @Test func miniatureCentersInsideItsOwnMonitorIncludingNegativeOrigins() {
        for screen in [main, left, above] {
            let frame = ReminderDisplayLayout.frame(on: screen, style: .mini, preferredSize: NSSize(width: 440, height: 660))
            #expect(frame.midX == screen.visibleFrame.midX)
            #expect(frame.midY == screen.visibleFrame.midY)
            #expect(screen.visibleFrame.contains(frame))
        }
    }
    @Test func simpleBannerUsesEachVisibleTopAndClampsLongTextToSmallDisplay() {
        for screen in [main, left, above] {
            let frame = ReminderDisplayLayout.frame(on: screen, style: .simple, preferredSize: NSSize(width: 4000, height: 50))
            #expect(frame.maxY == screen.visibleFrame.maxY - 20)
            #expect(frame.midX == screen.visibleFrame.midX)
            #expect(frame.height == 50)
            #expect(screen.visibleFrame.contains(frame))
        }
    }
    @Test func fullscreenCoversFrameWhileWorkoutRespectsVisibleArea() {
        let screen = ReminderDisplay(id: 4, frame: NSRect(x: -800, y: 200, width: 800, height: 600),
            visibleFrame: NSRect(x: -800, y: 240, width: 800, height: 535))
        #expect(ReminderDisplayLayout.frame(on: screen, style: .fullScreen, preferredSize: .zero) == screen.frame)
        let workout = ReminderDisplayLayout.frame(on: screen, style: .mini, preferredSize: NSSize(width: 880, height: 760))
        #expect(workout.width == 760)
        #expect(workout.height == 495)
        #expect(screen.visibleFrame.contains(workout))
    }
    @Test func manualReminderCloseSnoozesOnlyUnfinishedStates() {
        #expect(ReminderManualClosePolicy.shouldSnooze(.due))
        #expect(ReminderManualClosePolicy.shouldSnooze(.resting))
        #expect(!ReminderManualClosePolicy.shouldSnooze(.preview))
        #expect(!ReminderManualClosePolicy.shouldSnooze(.completed))
        #expect(!ReminderManualClosePolicy.shouldSnooze(nil))
    }
    @Test func quickPanelChartUsesFineTwoHourAndTwentyPercentAxes() {
        #expect(MenuUsageChartAxis.activityPercents == [100, 80, 60, 40, 20, 0])
        #expect(MenuUsageChartAxis.hours == [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24])
    }
}

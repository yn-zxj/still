import AppKit
import AVFoundation
import CoreGraphics
import Testing
@testable import Still
@MainActor struct VideoSurfaceTests {
    private final class ScrollReceiver: NSResponder {
        var received = 0
        override func scrollWheel(with event: NSEvent) { received += 1 }
    }
    @MainActor
    private final class SliderReceiver: NSObject {
        var values: [Double] = []
        @objc func changed(_ sender: NSSlider) { values.append(sender.doubleValue) }
    }
    @Test func videoFocusUsesArrowKeysWhileWheelStillGoesToPage() throws {
        let view = CoursePlayerLayerView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let receiver = ScrollReceiver(); view.nextResponder = receiver
        let player = AVPlayer(); view.videoLayer.player = player
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 80, wheel2: 0, wheel3: 0).flatMap(NSEvent.init(cgEvent:)))
        let before = player.currentTime()
        view.scrollWheel(with: event)
        #expect(receiver.received == 1)
        #expect(player.currentTime() == before)
        #expect(view.acceptsFirstResponder)
        var seeks: [Double] = [], toggles = 0
        view.seek = { seeks.append($0) }; view.toggle = { toggles += 1 }
        let left = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 123, keyDown: true).flatMap(NSEvent.init(cgEvent:)))
        let right = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true).flatMap(NSEvent.init(cgEvent:)))
        view.keyDown(with: left); view.keyDown(with: right)
        #expect(seeks == [-5, 5])
        let space = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true).flatMap(NSEvent.init(cgEvent:)))
        view.keyDown(with: space); #expect(toggles == 1)
        view.layout()
        #expect(view.videoLayer.frame == view.bounds)
    }
    @Test func seekSliderSupportsKeyboardAndLeavesWheelToThePage() throws {
        let receiver = SliderReceiver()
        let scrollReceiver = ScrollReceiver()
        let slider = CourseSeekSlider(
            value: 10, minValue: 0, maxValue: 100,
            target: receiver, action: #selector(SliderReceiver.changed(_:))
        )
        slider.nextResponder = scrollReceiver
        var toggles = 0
        slider.toggle = { toggles += 1 }
        slider.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        #expect(slider.value(at: NSPoint(x: 75, y: 10)) == 37.5)

        let right = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true).flatMap(NSEvent.init(cgEvent:)))
        let left = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 123, keyDown: true).flatMap(NSEvent.init(cgEvent:)))
        let space = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true).flatMap(NSEvent.init(cgEvent:)))
        slider.keyDown(with: right)
        slider.keyDown(with: left)
        slider.keyDown(with: space)

        #expect(receiver.values == [15, 10])
        #expect(toggles == 1)
        let wheel = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: 80, wheel2: 0, wheel3: 0
        ).flatMap(NSEvent.init(cgEvent:)))
        slider.scrollWheel(with: wheel)
        #expect(scrollReceiver.received == 1)
        #expect(slider.doubleValue == 10)
    }
}

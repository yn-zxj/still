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
    @Test func wheelGoesToPageInsteadOfScrubbingVideo() throws {
        let view = CoursePlayerLayerView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let receiver = ScrollReceiver(); view.nextResponder = receiver
        let player = AVPlayer(); view.videoLayer.player = player
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 80, wheel2: 0, wheel3: 0).flatMap(NSEvent.init(cgEvent:)))
        let before = player.currentTime()
        view.scrollWheel(with: event)
        #expect(receiver.received == 1)
        #expect(player.currentTime() == before)
        #expect(!view.acceptsFirstResponder)
        view.layout()
        #expect(view.videoLayer.frame == view.bounds)
    }
}

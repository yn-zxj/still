import AppKit
import SwiftUI

/// Native click/drag/keyboard slider. A wheel event belongs to the enclosing page.
struct CourseSeekBar: NSViewRepresentable {
    @ObservedObject var controller: CoursePlayer
    @MainActor
    final class Coordinator: NSObject {
        var controller: CoursePlayer
        var wasPlaying = false
        init(_ controller: CoursePlayer) { self.controller = controller }
        @objc func changed(_ slider: CourseSeekSlider) { controller.seek(to: slider.doubleValue) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    func makeNSView(context: Context) -> CourseSeekSlider {
        let slider = CourseSeekSlider(value: 0, minValue: 0, maxValue: 1, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = false
        slider.setAccessibilityLabel("播放进度")
        slider.toolTip = "点击或拖动跳转 · ← / → 前后 5 秒 · 空格播放或暂停"
        slider.toggle = { controller.toggle() }
        return slider
    }
    func updateNSView(_ slider: CourseSeekSlider, context: Context) {
        context.coordinator.controller = controller
        slider.maxValue = max(1, controller.duration)
        slider.isEnabled = controller.duration > 0 && !controller.loading && controller.error == nil
        if !slider.tracking { slider.doubleValue = controller.position }
        if controller.playing && !context.coordinator.wasPlaying { slider.window?.makeFirstResponder(slider) }
        context.coordinator.wasPlaying = controller.playing
    }
}

@MainActor
final class CourseSeekSlider: NSSlider {
    var tracking = false
    var toggle: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        tracking = true
        doubleValue = value(at: convert(event.locationInWindow, from: nil))
        sendAction(action, to: target)
        // Move the native knob under the pointer before AppKit starts its tracking
        // loop, so a track click jumps here and a drag continues from this value.
        super.mouseDown(with: event)
        tracking = false
    }
    func value(at point: NSPoint) -> Double {
        let fraction = min(1, max(0, point.x / max(1, bounds.width)))
        return minValue + fraction * (maxValue - minValue)
    }
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123, 124:
            doubleValue = min(maxValue, max(minValue, doubleValue + (event.keyCode == 123 ? -5 : 5)))
            sendAction(action, to: target)
        case 49: toggle?()
        default: super.keyDown(with: event)
        }
    }
}

import AppKit
import StillCore

struct ReminderDisplay: Equatable {
    let id: UInt32
    let frame: NSRect
    let visibleFrame: NSRect

    @MainActor static func current() -> [Self] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return Self(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }
}

enum ReminderDisplayLayout {
    /// During training a single display owns the player. If unplugged, move that
    /// same session to the first remaining display rather than starting a new one.
    static func targets(_ displays: [ReminderDisplay], trainingDisplayID: UInt32?) -> [ReminderDisplay] {
        guard let id = trainingDisplayID else { return displays }
        return [displays.first { $0.id == id } ?? displays.first].compactMap { $0 }
    }

    static func frame(on display: ReminderDisplay, style: ReminderStyle, preferredSize: NSSize) -> NSRect {
        if style == .fullScreen { return display.frame }
        let area = display.visibleFrame
        let margin: CGFloat = min(20, max(0, min(area.width, area.height) / 4))
        let width = min(preferredSize.width, max(1, area.width - margin * 2))
        let height = min(preferredSize.height, max(1, area.height - margin * 2))
        let y = style == .simple ? area.maxY - margin - height : area.midY - height / 2
        return NSRect(x: area.midX - width / 2, y: y, width: width, height: height)
    }
}

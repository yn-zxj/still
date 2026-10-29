import SwiftUI
import AppKit

/// Native vector rendering of Lucide, with legacy names mapped at the view boundary.
struct LineIcon: View {
    let systemName: String
    var size: CGFloat = 18
    var body: some View {
        LucideGlyph(name: Self.aliases[systemName] ?? systemName)
            .stroke(style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
    static let aliases: [String: String] = [
        "sun.max":"sun", "chart.bar.xaxis":"chart-no-axes-column", "slider.horizontal.3":"sliders-horizontal",
        "gearshape":"settings-2", "desktopcomputer":"monitor", "hourglass":"timer", "book.closed":"book-open",
        "bell.slash":"bell-off", "circle.dotted":"circle-dashed", "exclamationmark.triangle":"triangle-alert",
        "square.and.arrow.up":"upload", "checkmark.circle.fill":"circle-check", "circle.dashed":"circle-dashed",
        "leaf.circle":"leaf", "sparkle":"sparkles", "speaker.wave.2":"volume-2", "menubar.rectangle":"panel-top",
        "app.badge":"bell", "pause.circle":"pause", "play.circle":"play", "xmark":"x", "leaf.fill":"leaf",
        "arrow.up.right.square":"external-link", "lock.shield":"eye"
    ]
    static func menuImage(_ name: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 17), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState(); defer { context.restoreGState() }
            context.translateBy(x: 0, y: 17); context.scaleBy(x: 17/24, y: -17/24)
            context.addPath(LucidePaths.path(aliases[name] ?? name).cgPath)
            context.setStrokeColor(NSColor.black.cgColor); context.setLineWidth(1.9)
            context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct LucideGlyph: Shape {
    let name: String
    func path(in rect: CGRect) -> Path {
        LucidePaths.path(name).applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

struct LineLabel: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View { HStack(spacing: 7) { LineIcon(systemName: systemImage, size: 15); Text(title) } }
}

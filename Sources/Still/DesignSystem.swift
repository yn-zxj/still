import AppKit
import SwiftUI

enum Palette {
    static let backgroundNSColor = adaptiveNS("background", light: 0xF7F8FC, dark: 0x17171F)
    static let background = Color(nsColor: backgroundNSColor)
    static let sidebar = adaptive("sidebar", light: 0xF0F0F8, dark: 0x111117)
    static let surface = adaptive("surface", light: 0xFFFFFF, dark: 0x24242E)
    static let ink = adaptive("ink", light: 0x29283E, dark: 0xF4F2FA)
    static let secondary = adaptive("secondary", light: 0x616075, dark: 0xADAAC0)
    static let accent = adaptive("accent", light: 0x6C57CE, dark: 0xA492F6)
    static let accentDark = adaptive("accentDark", light: 0x523DB2, dark: 0xC6BCFF)
    static let accentFill = adaptive("accentFill", light: 0x634EC5, dark: 0x6954CD)
    static let accentFillEnd = adaptive("accentFillEnd", light: 0x523DB2, dark: 0x543FB3)
    static let accentOnFill = Color.white
    static let lavender = adaptive("lavender", light: 0xEEEBFA, dark: 0x312C46)
    static let mint = adaptive("mint", light: 0xCEE8DE, dark: 0x1E382F)
    static let green = adaptive("green", light: 0x397B67, dark: 0x82C9AD)
    static let greenText = adaptive("greenText", light: 0x2B6855, dark: 0x8CD5B8)
    static let warning = adaptive("warning", light: 0xAD5300, dark: 0xFFB35C)
    static let line = adaptive("line", light: 0xE2E2EE, dark: 0x3E3D4D)
    static let selectionBorder = adaptive("selectionBorder", light: 0x6C57CE, dark: 0xA492F6)
    static let heroStart = adaptive("heroStart", light: 0xF0EDFB, dark: 0x2A2441)
    static let heroMiddle = adaptive("heroMiddle", light: 0xF2F2FA, dark: 0x232330)
    static let heroEnd = adaptive("heroEnd", light: 0xE9F1F0, dark: 0x1D302C)
    static let restStart = adaptive("restStart", light: 0xF6F4FC, dark: 0x242138)
    static let restEnd = adaptive("restEnd", light: 0xEFF5F2, dark: 0x1B2A28)
    static let panelEnd = adaptive("panelEnd", light: 0xF3F4FA, dark: 0x1B1C25)

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: adaptiveNS(name, light: light, dark: dark))
    }

    private static func adaptiveNS(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("local.still.palette.\(name)"), dynamicProvider: { appearance in
            NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }
}

private struct StillMotionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var stillMotionEnabled: Bool {
        get { self[StillMotionEnabledKey.self] }
        set { self[StillMotionEnabledKey.self] = newValue }
    }
}

private let stillTimelineFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter
}()

func timelineTimeText(_ date: Date) -> String {
    stillTimelineFormatter.string(from: date)
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: 1
        )
    }
}

extension View {
    func card(padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.line.opacity(0.7), lineWidth: 1))
    }
}

struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotionEnabled) private var motionEnabled
    private var allowsMotion: Bool { !reduceMotion && motionEnabled }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .foregroundStyle(prominent ? Palette.accentOnFill : Palette.ink)
            .background(prominent ? Palette.accentFill : Palette.surface.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(prominent ? Palette.accentDark.opacity(0.28) : Palette.line, lineWidth: 1))
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed && allowsMotion ? 0.975 : 1)
            .animation(allowsMotion ? .easeOut(duration: 0.16) : nil, value: configuration.isPressed)
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotionEnabled) private var motionEnabled
    private var allowsMotion: Bool { !reduceMotion && motionEnabled }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .foregroundStyle(prominent ? Palette.accentOnFill : Palette.ink)
            .background(prominent ? Palette.accentFill : Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(prominent ? Palette.accentDark.opacity(0.28) : Palette.line, lineWidth: 1)
            )
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed && allowsMotion ? 0.985 : 1)
            .animation(allowsMotion ? .easeOut(duration: 0.14) : nil, value: configuration.isPressed)
    }
}

struct SelectableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotionEnabled) private var motionEnabled
    private var allowsMotion: Bool { !reduceMotion && motionEnabled }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && allowsMotion ? 0.985 : 1)
            .animation(allowsMotion ? .easeOut(duration: 0.14) : nil, value: configuration.isPressed)
    }
}

struct SegmentedPillControl<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotionEnabled) private var motionEnabled
    private var allowsMotion: Bool { !reduceMotion && motionEnabled }

    init(
        selection: Binding<Value>,
        values: [Value],
        @ViewBuilder label: @escaping (Value) -> Label
    ) {
        _selection = selection
        self.values = values
        self.label = label
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    label(value)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == value ? Palette.accentOnFill : Palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            selection == value ? Palette.accentFill : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 36)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.line.opacity(0.95), lineWidth: 1)
        )
        .animation(allowsMotion ? .easeOut(duration: 0.16) : nil, value: selection)
    }
}

struct CompactMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let title: (Value) -> String
    var width: CGFloat = 144
    var isEnabled = true
    let accessibilityTitle: String

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                Text(title(selection))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                LineIcon(systemName: "chevron-down", size: 13)
                    .foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 13)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Menu {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        if selection == value {
                            Label(title(value), systemImage: "checkmark")
                        } else {
                            Text(title(value))
                        }
                    }
                }
            } label: {
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(title(selection))
        }
        .frame(width: width, height: 36)
        .background(
            Palette.background.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }
}

struct FlowerView: View {
    var isAnimating = true
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotionEnabled) private var motionEnabled
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let shouldAnimate = isAnimating && !reduceMotion && motionEnabled
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !shouldAnimate)) { context in
            let time = shouldAnimate ? context.date.timeIntervalSinceReferenceDate : 0
            let breath = sin(time * .pi / 4)
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    if !compact {
                        Circle().stroke(Palette.accent.opacity(0.09), lineWidth: 1).padding(side * 0.025)
                        Circle().stroke(Palette.accent.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [2, 8])).padding(side * 0.115)
                    }
                    ForEach(0..<8, id: \.self) { index in
                        Ellipse()
                            .fill(LinearGradient(colors: [
                                index % 2 == 0 ? Palette.accent.opacity(colorScheme == .dark ? 0.72 : 0.40) : Palette.mint.opacity(0.9),
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18)
                            ], startPoint: .top, endPoint: .bottom))
                            .overlay(Ellipse().stroke(Color.white.opacity(0.7), lineWidth: 0.7))
                            .frame(width: side * 0.265, height: side * 0.53)
                            .offset(y: -side * (0.14 + breath * 0.008))
                            .rotationEffect(.degrees(Double(index) * 45 + breath * 3))
                            .blendMode(colorScheme == .dark ? .screen : .multiply)
                    }
                    Circle().fill(Color.white.opacity(0.82)).frame(width: side * 0.12, height: side * 0.12)
                    Circle().fill(Palette.accent.opacity(0.5)).frame(width: side * 0.027, height: side * 0.027)
                    if !compact {
                        Circle().fill(Palette.accent.opacity(0.65)).frame(width: 5, height: 5)
                            .offset(y: -side * 0.475).rotationEffect(.degrees(breath * 14 + 34))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(0.94 + breath * 0.035)
            }
        }
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let title: String
    var active = true
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(active ? Palette.greenText : Palette.secondary).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(active ? Palette.greenText : Palette.secondary)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(active ? Palette.mint.opacity(0.42) : Palette.line.opacity(0.5), in: Capsule())
        .overlay(
            Capsule()
                .stroke(active ? Palette.greenText.opacity(0.24) : Palette.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct FatigueGauge: View {
    let progress: Double
    let percent: Int
    var animate = true
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Palette.accent.opacity(0.09), lineWidth: 4)
                Circle().trim(from: 0, to: max(0.005, progress))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                FlowerView(isAnimating: animate).padding(18).opacity(0.38)
                VStack(spacing: 3) {
                    Text("\(percent)%").font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("疲劳值").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
            .frame(width: 174, height: 174)
        }
        .help("根据使用和休息时长估算，休息时逐渐降低。")
        .accessibilityElement(children: .ignore).accessibilityLabel("疲劳值 \(percent)%")
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.secondary) }
        }
    }
}

struct SettingsGroupHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

enum ScrollEdgeFadeStyle {
    case color(Color)
    case alphaMask
}

/// Reusable vertical ScrollView with dynamic top/bottom edge fade driven by real
/// NSScrollView scroll offset and content overflow. Never blocks hits or wheel events,
/// and isolates fade state so scrolling does not invalidate scroll content.
struct EdgeFadeScrollView<Content: View>: View {
    var showsIndicators: Bool = true
    var fadeLength: CGFloat = 28
    var fadeThreshold: CGFloat = 22
    var fadeStyle: ScrollEdgeFadeStyle = .color(Palette.background)
    let content: () -> Content
    @StateObject private var holder = ScrollEdgeHolder()

    init(
        showsIndicators: Bool = true,
        fadeLength: CGFloat = 28,
        fadeThreshold: CGFloat = 22,
        fadeStyle: ScrollEdgeFadeStyle = .color(Palette.background),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.fadeLength = fadeLength
        self.fadeThreshold = fadeThreshold
        self.fadeStyle = fadeStyle
        self.content = content
    }

    var body: some View {
        let base = ScrollView(.vertical, showsIndicators: showsIndicators) {
            content()
                .background(
                    ScrollEdgeProbe(state: holder.state, fadeThreshold: fadeThreshold)
                        .allowsHitTesting(false)
                )
        }
        switch fadeStyle {
        case .color(let color):
            base.overlay {
                EdgeFadeOverlayView(state: holder.state, color: color, fadeLength: fadeLength)
            }
        case .alphaMask:
            base.mask {
                EdgeFadeMaskView(state: holder.state, fadeLength: fadeLength)
            }
        }
    }
}

@MainActor
private final class ScrollEdgeHolder: ObservableObject {
    let state = ScrollEdgeState()
}

@MainActor
private final class ScrollEdgeState: ObservableObject {
    @Published var topProgress: CGFloat = 0
    @Published var bottomProgress: CGFloat = 0

    func update(top: CGFloat, bottom: CGFloat) {
        let clampedTop = min(1, max(0, top))
        let clampedBottom = min(1, max(0, bottom))
        let quantizedTop: CGFloat = clampedTop < 0.02 ? 0 : clampedTop > 0.98 ? 1 : (clampedTop * 50).rounded() / 50
        let quantizedBottom: CGFloat = clampedBottom < 0.02 ? 0 : clampedBottom > 0.98 ? 1 : (clampedBottom * 50).rounded() / 50
        if abs(topProgress - quantizedTop) >= 0.015 { topProgress = quantizedTop }
        if abs(bottomProgress - quantizedBottom) >= 0.015 { bottomProgress = quantizedBottom }
    }
}

private struct EdgeFadeOverlayView: View {
    @ObservedObject var state: ScrollEdgeState
    let color: Color
    let fadeLength: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if state.topProgress > 0 {
                LinearGradient(
                    stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0.76), location: 0.32),
                        .init(color: color.opacity(0.28), location: 0.68),
                        .init(color: color.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeLength)
                .opacity(state.topProgress)
            }
            Spacer(minLength: 0)
            if state.bottomProgress > 0 {
                LinearGradient(
                    stops: [
                        .init(color: color.opacity(0), location: 0),
                        .init(color: color.opacity(0.28), location: 0.32),
                        .init(color: color.opacity(0.76), location: 0.68),
                        .init(color: color, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeLength)
                .opacity(state.bottomProgress)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EdgeFadeMaskView: View {
    @ObservedObject var state: ScrollEdgeState
    let fadeLength: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if state.topProgress > 0 {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(1 - state.topProgress), location: 0),
                        .init(color: .black.opacity(1 - state.topProgress * 0.68), location: 0.35),
                        .init(color: .black.opacity(1 - state.topProgress * 0.24), location: 0.72),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeLength)
            }
            Color.black
            if state.bottomProgress > 0 {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(1 - state.bottomProgress * 0.24), location: 0.28),
                        .init(color: .black.opacity(1 - state.bottomProgress * 0.68), location: 0.65),
                        .init(color: .black.opacity(1 - state.bottomProgress), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeLength)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ScrollEdgeProbe: NSViewRepresentable {
    let state: ScrollEdgeState
    let fadeThreshold: CGFloat

    func makeNSView(context: Context) -> ScrollEdgeProbeNSView {
        let view = ScrollEdgeProbeNSView()
        view.state = state
        view.fadeThreshold = fadeThreshold
        return view
    }

    func updateNSView(_ nsView: ScrollEdgeProbeNSView, context: Context) {
        nsView.state = state
        nsView.fadeThreshold = fadeThreshold
        nsView.attachAndMeasure()
    }
}

private final class ScrollEdgeProbeNSView: NSView {
    weak var state: ScrollEdgeState?
    var fadeThreshold: CGFloat = 22
    private weak var observedScrollView: NSScrollView?
    private weak var observedDocumentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachAndMeasure()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachAndMeasure()
    }

    override func layout() {
        super.layout()
        attachAndMeasure()
    }

    func attachAndMeasure() {
        guard let scrollView = findEnclosingScrollView() else { return }
        let docView = scrollView.documentView
        if observedScrollView !== scrollView || observedDocumentView !== docView {
            detach()
            observedScrollView = scrollView
            observedDocumentView = docView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true
            docView?.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
            })
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
            })
            if let docView {
                observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: docView, queue: .main) { [weak self] _ in
                    self?.scheduleUpdate()
                })
            }
        }
        scheduleUpdate()
    }

    private func findEnclosingScrollView() -> NSScrollView? {
        if let direct = enclosingScrollView { return direct }
        var cursor = superview
        while let view = cursor {
            if let scrollView = view as? NSScrollView { return scrollView }
            cursor = view.superview
        }
        return nil
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.measureNow()
        }
    }

    private func measureNow() {
        guard let state, let scrollView = observedScrollView, let docView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let visible = clipView.documentVisibleRect
        let docBounds = docView.bounds
        let insets = clipView.contentInsets
        let totalHeight = docBounds.height + insets.top + insets.bottom
        guard totalHeight > visible.height + 1.5, visible.height > 0 else {
            state.update(top: 0, bottom: 0)
            return
        }
        let topDistance: CGFloat
        let bottomDistance: CGFloat
        if docView.isFlipped {
            topDistance = max(0, visible.minY - (docBounds.minY - insets.top))
            bottomDistance = max(0, (docBounds.maxY + insets.bottom) - visible.maxY)
        } else {
            topDistance = max(0, (docBounds.maxY + insets.top) - visible.maxY)
            bottomDistance = max(0, visible.minY - (docBounds.minY - insets.bottom))
        }
        let deadzone: CGFloat = 1.5
        let threshold = max(1, fadeThreshold)
        let topProgress = topDistance <= deadzone ? 0 : min(1, (topDistance - deadzone) / threshold)
        let bottomProgress = bottomDistance <= deadzone ? 0 : min(1, (bottomDistance - deadzone) / threshold)
        state.update(top: topProgress, bottom: bottomProgress)
    }

    private func detach() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
        observedScrollView = nil
        observedDocumentView = nil
    }

    deinit {
        detach()
    }
}

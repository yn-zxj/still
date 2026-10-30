import AppKit
import SwiftUI

enum Palette {
    static let backgroundNSColor = adaptiveNS("background", light: 0xF7F8FC, dark: 0x17171F)
    static let background = Color(nsColor: backgroundNSColor)
    static let sidebar = adaptive("sidebar", light: 0xF0F0F8, dark: 0x111117)
    static let surface = adaptive("surface", light: 0xFFFFFF, dark: 0x24242E)
    static let ink = adaptive("ink", light: 0x29283E, dark: 0xF4F2FA)
    static let secondary = adaptive("secondary", light: 0x7D7C91, dark: 0xA5A2B5)
    static let accent = adaptive("accent", light: 0x7864D9, dark: 0x9D8AF4)
    static let accentDark = adaptive("accentDark", light: 0x5C47BD, dark: 0xC2B7FF)
    static let lavender = adaptive("lavender", light: 0xEEEBFA, dark: 0x312C46)
    static let mint = adaptive("mint", light: 0xCEE8DE, dark: 0x1E382F)
    static let green = adaptive("green", light: 0x4C8C78, dark: 0x82C9AD)
    static let line = adaptive("line", light: 0xE8E8F1, dark: 0x383744)
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

/// Rounds only the two corners facing the navigation sidebar (macOS 13 compatible).
struct ContentPaneShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(max(0, radius), min(rect.width, rect.height) / 2), k = 0.5522847498
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                      control1: CGPoint(x: rect.minX + r * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.maxY - r * (1 - k)))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + r * (1 - k)),
                      control2: CGPoint(x: rect.minX + r * (1 - k), y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct ContentPaneLeadingEdge: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(max(0, radius), min(rect.width, rect.height) / 2), k = 0.5522847498
        let x = rect.minX + 0.5, top = rect.minY + 0.5, bottom = rect.maxY - 0.5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: top))
        path.addCurve(to: CGPoint(x: x, y: rect.minY + r),
                      control1: CGPoint(x: rect.minX + r * (1 - k), y: top),
                      control2: CGPoint(x: x, y: rect.minY + r * (1 - k)))
        path.addLine(to: CGPoint(x: x, y: rect.maxY - r))
        path.addCurve(to: CGPoint(x: rect.minX + r, y: bottom),
                      control1: CGPoint(x: x, y: rect.maxY - r * (1 - k)),
                      control2: CGPoint(x: rect.minX + r * (1 - k), y: bottom))
        return path
    }
}

struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .background(prominent ? Palette.accent : Palette.surface.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(prominent ? Color.clear : Palette.line, lineWidth: 1))
            .brightness(configuration.isPressed ? -0.04 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .background(prominent ? Palette.accent : Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(prominent ? Color.clear : Palette.line, lineWidth: 1)
            )
            .brightness(configuration.isPressed ? -0.04 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct SegmentedPillControl<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .foregroundStyle(selection == value ? Color.white : Palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            selection == value ? Palette.accent : Color.clear,
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
                .stroke(Palette.line.opacity(0.9), lineWidth: 1)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
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
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isAnimating || reduceMotion)) { context in
            let time = isAnimating && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0
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
            Circle().fill(active ? Palette.green : Palette.secondary).frame(width: 6, height: 6)
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(active ? Palette.green : Palette.secondary)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(active ? Palette.mint.opacity(0.36) : Palette.line.opacity(0.5), in: Capsule())
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
            Text(title).font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-0.6).foregroundStyle(Palette.ink)
            if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.secondary) }
        }
    }
}

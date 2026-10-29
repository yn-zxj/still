import SwiftUI

enum Palette {
    static let background = Color(hex: 0xF7F8FC)
    static let sidebar = Color(hex: 0xF0F0F8)
    static let surface = Color.white
    static let ink = Color(hex: 0x29283E)
    static let secondary = Color(hex: 0x7D7C91)
    static let accent = Color(hex: 0x7864D9)
    static let accentDark = Color(hex: 0x5C47BD)
    static let lavender = Color(hex: 0xEEEBFA)
    static let mint = Color(hex: 0xCEE8DE)
    static let green = Color(hex: 0x4C8C78)
    static let line = Color(hex: 0xE8E8F1)
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
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

struct FlowerView: View {
    var isAnimating = true
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                            .fill(LinearGradient(colors: [index % 2 == 0 ? Palette.accent.opacity(0.40) : Palette.mint.opacity(0.9), Color.white.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                            .overlay(Ellipse().stroke(Color.white.opacity(0.7), lineWidth: 0.7))
                            .frame(width: side * 0.265, height: side * 0.53)
                            .offset(y: -side * (0.14 + breath * 0.008))
                            .rotationEffect(.degrees(Double(index) * 45 + breath * 3))
                            .blendMode(.multiply)
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

import SwiftUI
import StillCore

struct SimpleRestView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var liveClock: LiveEngineClock
    let previewDeadline: Date?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @MainActor
    init(model: AppModel, previewDeadline: Date?, close: @escaping () -> Void) {
        self.model = model
        _liveClock = ObservedObject(wrappedValue: model.liveClock)
        self.previewDeadline = previewDeadline
        self.close = close
    }

    private var isPreview: Bool { previewDeadline != nil }
    private var reduceMotion: Bool { systemReduceMotion || !model.settings.motionEnabled }

    static func message(model: AppModel) -> String {
        model.settings.showDailyTimeInReminder
            ? "\(model.reminderText) · 今日 \(durationText(model.today.seconds))" : model.reminderText
    }

    static func spokenDuration(_ seconds: Double) -> String {
        let total = max(0, Int(ceil(seconds)))
        let minutes = total / 60
        let remainder = total % 60
        if minutes > 0 && remainder > 0 { return "\(minutes) 分 \(remainder) 秒" }
        if minutes > 0 { return "\(minutes) 分钟" }
        return "\(remainder) 秒"
    }

    var body: some View {
        let _ = liveClock.tick
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = previewDeadline.map { max(0, $0.timeIntervalSince(context.date)) } ?? model.engine.restRemaining
            HStack(spacing: 10) {
                if isPreview {
                    Text("预览")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accentDark)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.lavender, in: Capsule())
                        .fixedSize()
                        .accessibilityLabel("提醒预览")
                }
                Text(model.reminderText)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.92)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(Self.message(model: model))
                if model.settings.showDailyTimeInReminder {
                    Text("今日 \(durationText(model.today.seconds))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(clockText(remaining))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityLabel(isPreview ? "预览剩余时间" : "剩余休息时间")
                    .accessibilityValue(Self.spokenDuration(remaining))
                Button(action: close) {
                    LineIcon(systemName: "x", size: 15)
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 32, height: 32)
                        .background(Palette.surface.opacity(0.45), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(SimpleRestCloseButtonStyle(reduceMotion: reduceMotion))
                .help(isPreview ? "关闭预览" : "关闭并在稍后提醒")
                .accessibilityLabel(isPreview ? "关闭预览" : "关闭并稍后提醒")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Palette.ink)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Palette.ink.opacity(0.12), lineWidth: 1))
        }
        .onExitCommand(perform: close)
    }
}

private struct SimpleRestCloseButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

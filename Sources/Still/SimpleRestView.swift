import SwiftUI
import StillCore

struct SimpleRestView: View {
    @ObservedObject var model: AppModel
    let previewDeadline: Date?
    let close: () -> Void

    static func message(model: AppModel) -> String {
        model.settings.showDailyTimeInReminder
            ? "\(durationText(model.today.seconds)) · \(model.reminderText)" : model.reminderText
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 14) {
                Text(Self.message(model: model))
                    .font(.system(size: 15, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(clockText(previewDeadline.map { max(0, $0.timeIntervalSince(context.date)) } ?? model.engine.restRemaining))
                    .font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                    .fixedSize().accessibilityLabel("剩余休息时间")
                Button(action: close) {
                    LineIcon(systemName: "x", size: 16).frame(width: 26, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).help("收起提醒").accessibilityLabel("收起休息提醒")
            }
            .padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Palette.ink)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Palette.ink.opacity(0.12), lineWidth: 1))
        }
        .onExitCommand(perform: close)
    }
}

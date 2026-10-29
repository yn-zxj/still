import SwiftUI
import StillCore

struct ReminderSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("提醒方式").font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle("开启提醒", isOn: $model.settings.remindersEnabled).toggleStyle(.switch).font(.system(size: 13))
            }
            HStack(spacing: 12) {
                ForEach(ReminderStyle.allCases, id: \.self) { style in
                    Button { model.settings.reminderStyle = style; model.reminderError = nil } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                LineIcon(systemName: icon(style), size: 21)
                                Spacer()
                                if model.settings.reminderStyle == style {
                                    LineIcon(systemName: "circle-check", size: 16)
                                }
                            }
                            Text(style.title).font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(model.settings.reminderStyle == style ? Palette.accentDark : Palette.secondary)
                        .padding(18).frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
                        .background(model.settings.reminderStyle == style ? Palette.lavender : Palette.background, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(model.settings.reminderStyle == style ? Palette.accent.opacity(0.35) : Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel(style.title).accessibilityAddTraits(model.settings.reminderStyle == style ? .isSelected : [])
                }
            }
            HStack(spacing: 25) {
                Text("提醒内容").font(.system(size: 14, weight: .medium)).frame(width: 75, alignment: .leading)
                TextField("喝杯水，起来走走吧", text: Binding(get: { model.settings.reminderMessage }, set: { model.settings.reminderMessage = String($0.prefix(100)) }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 14)).controlSize(.large)
            }
            HStack {
                Text("显示今日使用时长").font(.system(size: 14))
                Spacer()
                Toggle("显示今日使用时长", isOn: $model.settings.showDailyTimeInReminder).labelsHidden().toggleStyle(.switch)
            }
            if model.settings.reminderStyle == .notification && !model.notificationAuthorized {
                HStack(spacing: 12) {
                    LineIcon(systemName: "bell", size: 16)
                    Text(model.notificationDenied ? "系统通知已关闭" : "需要允许系统通知").font(.system(size: 13))
                    Spacer()
                    Button(model.notificationDenied ? "打开系统设置" : "允许通知") { model.enableNotifications() }.buttonStyle(.bordered)
                }.foregroundStyle(Palette.secondary)
            }
            if let error = model.reminderError {
                Text(error).font(.system(size: 13)).foregroundStyle(Color.orange)
            }
            HStack {
                Text(model.settings.reminderStyle == .fullScreen ? "按 Esc 退出全屏" : model.settings.reminderStyle == .notification ? "通知中可开始休息或延后" : "支持延后和跳过")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer()
                Button { model.showPreview?() } label: { LineLabel("预览提醒", systemImage: "play") }.buttonStyle(SoftButtonStyle())
            }
        }.card(padding: 24).onAppear { model.refreshNotificationStatus() }
    }
    private func icon(_ style: ReminderStyle) -> String {
        switch style { case .fullScreen: return "maximize"; case .mini: return "rectangle-vertical"; case .notification: return "bell" }
    }
}

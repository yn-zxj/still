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
            HStack(alignment: .top, spacing: 12) {
                ForEach(ReminderStyle.allCases, id: \.self) { style in
                    let isSelected = model.settings.reminderStyle == style
                    Button { model.settings.reminderStyle = style; model.reminderError = nil } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                LineIcon(systemName: icon(style), size: 20)
                                    .foregroundStyle(isSelected ? Palette.accentDark : Palette.secondary)
                                Spacer()
                                LineIcon(systemName: isSelected ? "circle-check" : "circle", size: 16)
                                    .foregroundStyle(isSelected ? Palette.accentDark : Palette.line)
                            }
                            .accessibilityHidden(true)
                            Text(style.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected ? Palette.accentDark : Palette.ink)
                            Text(shortDescription(style))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
                        .background(isSelected ? Palette.lavender : Palette.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(isSelected ? Palette.selectionBorder : Palette.line, lineWidth: isSelected ? 1.5 : 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(SelectableCardButtonStyle())
                    .accessibilityLabel("\(style.title)，\(shortDescription(style))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .fixedSize(horizontal: false, vertical: true)
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
                    Button(model.notificationDenied ? "打开系统设置" : "允许通知") { model.enableNotifications() }
                        .buttonStyle(SettingsButtonStyle())
                }.foregroundStyle(Palette.secondary)
            }
            if let error = model.reminderError {
                Text(error).font(.system(size: 13)).foregroundStyle(Palette.warning)
            }
            HStack(alignment: .center, spacing: 16) {
                Text(styleHint)
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { model.showPreview?() } label: { LineLabel("预览提醒", systemImage: "play") }.buttonStyle(SoftButtonStyle())
            }
        }.card(padding: 24).onAppear { model.refreshNotificationStatus() }
    }
    private func shortDescription(_ style: ReminderStyle) -> String {
        switch style {
        case .fullScreen: return "全屏覆盖，强提醒休息"
        case .mini: return "角落浮窗，轻柔打断"
        case .simple: return "顶部横幅，不遮挡操作"
        case .notification: return "系统通知，极轻打扰"
        }
    }
    private var styleHint: String {
        switch model.settings.reminderStyle {
        case .fullScreen: return "所有屏幕同时显示全屏休息界面；课程只在点击的屏幕播放。"
        case .mini: return "所有屏幕角落显示迷你浮窗；课程只在点击的屏幕播放。"
        case .simple: return "所有屏幕顶部显示提示与倒计时，休息结束后自动收起。"
        case .notification: return "真实到期通知支持开始休息或稍后提醒；预览通知仅展示外观，不含操作按钮。"
        }
    }
    private func icon(_ style: ReminderStyle) -> String {
        switch style { case .fullScreen: return "maximize"; case .mini: return "rectangle-vertical"; case .simple: return "minus"; case .notification: return "bell" }
    }
}

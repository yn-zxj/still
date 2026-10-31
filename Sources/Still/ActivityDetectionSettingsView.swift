import SwiftUI

struct ActivityDetectionSettingsView: View {
    @ObservedObject var monitor: SystemActivityMonitor
    @ObservedObject private var screen: ScreenActivityMonitor
    init(monitor: SystemActivityMonitor) {
        self.monitor = monitor
        _screen = ObservedObject(wrappedValue: monitor.screenActivity)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LineIcon(systemName: "eye", size: 21).frame(width: 25).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("自动检测").font(.system(size: 15, weight: .semibold))
                    Text("结合输入和前台画面判断使用，无需切换模式。")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
            Divider().overlay(Palette.line)
            row("键鼠活动", detail: "自动检测点击、移动、拖动、滚轮及键盘活动时距。", status: "已启用") { EmptyView() }
            row("键盘辅助", detail: "授权后补充全局键盘活动；只记发生时间，不读取按键内容。",
                status: monitor.keyboardStatus) {
                Button(monitor.keyboardAuthorized ? "管理权限" : "授权键盘辅助") {
                    if monitor.keyboardAuthorized { monitor.openKeyboardPrivacy() } else { monitor.requestKeyboardAuthorization() }
                }.buttonStyle(SettingsButtonStyle())
            }
            row("画面变化", detail: "辅助识别视频等无输入场景。仅分析前台窗口的低分辨率画面，不录音、不保存或上传画面。", status: screenStatus) {
                Button(screen.authorized ? "管理权限" : "授权画面检测") {
                    if screen.authorized { screen.openPrivacySettings() } else { screen.requestAuthorization() }
                }.buttonStyle(SettingsButtonStyle())
            }
            Text("锁屏、息屏和休眠优先停止累计。静态阅读或无人播放的视频仍可能有误差；画面变化不代表检测到人在观看。")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3)
        }.card(padding: 25)
    }
    private var screenStatus: String {
        guard let date = screen.lastActivityDate else { return screen.status }
        return screen.status + " · 最近画面活动 " + date.formatted(date: .omitted, time: .standard)
    }
    private func row<Content: View>(_ title: String, detail: String, status: String, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
            }
            Spacer(minLength: 8)
            action()
        }
    }
}

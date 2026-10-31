import SwiftUI

struct ActivityDetectionSettingsView: View {
    @ObservedObject var monitor: SystemActivityMonitor
    @ObservedObject private var playback: PlaybackActivityMonitor
    @ObservedObject private var foregroundProcess: ForegroundProcessActivityMonitor
    let revealActivityLog: () -> Void
    init(monitor: SystemActivityMonitor, revealActivityLog: @escaping () -> Void) {
        self.monitor = monitor
        self.revealActivityLog = revealActivityLog
        _playback = ObservedObject(wrappedValue: monitor.playbackActivity)
        _foregroundProcess = ObservedObject(wrappedValue: monitor.foregroundProcessActivity)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LineIcon(systemName: "eye", size: 21).frame(width: 25).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("自动检测").font(.system(size: 15, weight: .semibold))
                    Text("结合键鼠、键盘辅助、媒体播放与前台界面活动判断使用，无需切换模式。")
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
            row("媒体播放", detail: "无需额外权限。检测系统是否有音频播放，辅助覆盖视频、音乐等无输入场景。",
                status: playback.status) { EmptyView() }
            row("前台界面活动", detail: "根据前台应用的短时处理活动辅助判断阅读、流式输出和静音播放；不读取窗口标题、文字、画面或输入内容。",
                status: foregroundProcess.status) { EmptyView() }
            HStack(alignment: .top, spacing: 16) {
                Text("锁屏、息屏和休眠优先停止累计。日志只保存活动时距、状态和 Bundle ID，每分钟或状态变化时记录。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3)
                Spacer(minLength: 8)
                Button("查看活动日志", action: revealActivityLog)
                    .buttonStyle(SettingsButtonStyle())
            }
        }.card(padding: 25)
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

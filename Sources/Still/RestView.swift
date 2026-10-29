import SwiftUI

// A preview never starts a break or changes fatigue.
enum RestPresentation { case due, resting, preview, completed }

struct RestActions: View {
    @ObservedObject var model: AppModel
    let presentation: RestPresentation
    var close: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            switch presentation {
            case .preview:
                Button("关闭预览", action: close).buttonStyle(SoftButtonStyle())
            case .resting:
                Button("提前结束休息") { model.endRest(); close() }.buttonStyle(SoftButtonStyle())
            case .completed:
                Button("继续使用", action: close).buttonStyle(SoftButtonStyle(prominent: true))
            case .due:
                Button { model.startRest() } label: { Text("开始 \(model.settings.restMinutes) 分钟休息").frame(minWidth: 174) }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                HStack(spacing: 25) {
                    Button("\(model.settings.snoozeMinutes) 分钟后提醒") { model.snooze(); close() }
                    Button("跳过这次") { model.snooze(skipped: true); close() }
                }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct RestView: View {
    @ObservedObject var model: AppModel
    var presentation: RestPresentation
    var close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 7) { LineIcon(systemName: "leaf", size: 15); Text(presentation == .preview ? "提醒预览" : "息间") }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accentDark)
                Spacer()
                Button(action: close) { LineIcon(systemName: "x", size: 13).foregroundStyle(Palette.secondary).frame(width: 28, height: 28).background(Color.white.opacity(0.7), in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel(presentation == .resting ? "收起休息窗口" : "关闭休息窗口")
            }.padding(.horizontal, 25).padding(.top, 20)
            FlowerView(isAnimating: model.settings.motionEnabled).frame(width: 195, height: 195).padding(.top, 18)
            Text(presentation == .completed ? "休息结束" : model.reminderText)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: 330, minHeight: 62).padding(.top, 10)
            if presentation == .resting || presentation == .preview {
                Text(clockText(presentation == .preview ? model.settings.restSeconds : model.engine.restRemaining))
                    .font(.system(size: 43, weight: .light, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.accentDark).padding(.top, 10)
            }
            HStack(spacing: 12) {
                Text("疲劳值 \(model.engine.fatiguePercent)%")
                if model.settings.showDailyTimeInReminder { Text("今日 \(durationText(model.today.seconds))") }
            }.font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 10)
            if presentation == .preview {
                Text("预览不会开始休息").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 8)
            }
            RestActions(model: model, presentation: presentation, close: close).padding(.top, 25)
            Spacer(minLength: 20)
        }
        .frame(width: 390, height: presentation == .completed ? 470 : 570)
        .background(LinearGradient(colors: [Color(hex: 0xF6F4FC), Color(hex: 0xEFF5F2)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Palette.ink).environment(\.colorScheme, .light)
        .onExitCommand(perform: close)
    }
}

struct FullScreenRestView: View {
    @ObservedObject var model: AppModel
    let presentation: RestPresentation
    var close: () -> Void
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xEDE9F9), Color(hex: 0xF6F7FB), Color(hex: 0xE3F0EC)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 10) {
                        FlowerView(isAnimating: false, compact: true).frame(width: 30, height: 30)
                        Text(presentation == .preview ? "全屏提醒 · 预览" : "息间").font(.system(size: 15, weight: .medium))
                    }
                    Spacer()
                    Button { close() } label: { LineLabel("退出全屏", systemImage: "x") }.buttonStyle(SoftButtonStyle())
                }.padding(30)
                Spacer(minLength: 10)
                FlowerView(isAnimating: model.settings.motionEnabled).frame(width: 230, height: 230)
                Text(presentation == .completed ? "休息结束" : model.reminderText)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.75)
                    .frame(maxWidth: 650).padding(.horizontal, 30).padding(.top, 20)
                if presentation == .resting || presentation == .preview {
                    Text(clockText(presentation == .preview ? model.settings.restSeconds : model.engine.restRemaining))
                        .font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Palette.accentDark).padding(.top, 16)
                }
                HStack(spacing: 20) {
                    Text("疲劳值 \(model.engine.fatiguePercent)%")
                    if model.settings.showDailyTimeInReminder { Text("今日使用 \(durationText(model.today.seconds))") }
                }.font(.system(size: 14)).foregroundStyle(Palette.secondary).padding(.top, 14)
                RestActions(model: model, presentation: presentation, close: close).padding(.top, 30)
                Spacer(minLength: 20)
                Text("Esc 退出全屏").font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.bottom, 25)
            }
        }
        .foregroundStyle(Palette.ink).tint(Palette.accent).environment(\.colorScheme, .light).ignoresSafeArea()
        .onExitCommand(perform: close)
    }
}

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    var open: () -> Void
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 8) {
                    FlowerView(isAnimating: false, compact: true).frame(width: 26, height: 26)
                    Text("息间").font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                Spacer()
                StatusBadge(title: model.engine.phase.title, active: ![.away, .suspended, .paused].contains(model.engine.phase))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("疲劳值").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        Text("\(model.engine.fatiguePercent)%").font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(model.countdownTitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Text(clockText(model.countdown)).font(.system(size: 22, weight: .regular, design: .rounded)).monospacedDigit()
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.accent.opacity(0.1))
                        Capsule().fill(Palette.accent).frame(width: max(0, geo.size.width * model.engine.progress))
                    }
                }.frame(height: 4)
                Text("今日使用 \(durationText(model.today.seconds))").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }.padding(18).background(Palette.lavender.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
            HStack {
                Button { model.startRest(); close() } label: { LineLabel(model.engine.phase == .resting ? "查看休息" : "现在休息", systemImage: "leaf") }.buttonStyle(SoftButtonStyle(prominent: true))
                Spacer()
                Button { model.toggleReminders() } label: { LineIcon(systemName: model.settings.remindersEnabled ? "bell.slash" : "bell") }
                    .buttonStyle(SoftButtonStyle()).help(model.settings.remindersEnabled ? "暂停提醒，继续统计" : "恢复提醒")
            }
            Toggle("持续阅读", isOn: Binding(get: { model.settings.mode == .reading }, set: { model.settings.mode = $0 ? .reading : .activity })).toggleStyle(.switch).font(.system(size: 14))
            if let error = model.reminderError { Text(error).font(.system(size: 12)).foregroundStyle(Color.orange) }
            Divider().overlay(Palette.line)
            HStack {
                Button { open() } label: { LineLabel("打开主窗口", systemImage: "external-link") }.buttonStyle(.plain)
                Spacer()
                Button("退出息间") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
            }.font(.system(size: 13))
        }.padding(22).frame(width: 350).background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent).environment(\.colorScheme, .light)
    }
}

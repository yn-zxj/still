import SwiftUI
import StillCore

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
                Button("查看全部课程") { model.openCourses(); close() }.buttonStyle(SoftButtonStyle())
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
    var chooseCourse: (Course) -> Void = { _ in }
    var body: some View {
        ScrollView(showsIndicators: false) {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 7) { LineIcon(systemName: "leaf", size: 15); Text(presentation == .preview ? "提醒预览" : "息间") }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accentDark)
                Spacer()
                Button(action: close) { LineIcon(systemName: "x", size: 13).foregroundStyle(Palette.secondary).frame(width: 28, height: 28).background(Color.white.opacity(0.7), in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel(presentation == .resting ? "收起休息窗口" : "关闭休息窗口")
            }.padding(.horizontal, 25).padding(.top, 20)
            FlowerView(isAnimating: model.settings.motionEnabled).frame(width: 130, height: 130).padding(.top, 12)
            Text(presentation == .completed ? "休息结束" : model.reminderText)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: 370, minHeight: 48).padding(.top, 10)
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
            if presentation != .completed {
                ReminderRecommendationCard(model: model, preview: presentation == .preview, choose: chooseCourse)
                    .padding(.horizontal, 24).padding(.top, 18)
            }
            RestActions(model: model, presentation: presentation, close: close).padding(.top, 18)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(hex: 0xF6F4FC), Color(hex: 0xEFF5F2)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Palette.ink).environment(\.colorScheme, .light)
        .onExitCommand(perform: close)
    }
}

struct FullScreenRestView: View {
    @ObservedObject var model: AppModel
    let presentation: RestPresentation
    var close: () -> Void
    var chooseCourse: (Course) -> Void = { _ in }
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
                ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                Spacer(minLength: 10)
                FlowerView(isAnimating: model.settings.motionEnabled).frame(width: 145, height: 145)
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
                if presentation != .completed {
                    ReminderRecommendationCard(model: model, preview: presentation == .preview, choose: chooseCourse)
                        .frame(width: 380).padding(.top, 22)
                }
                RestActions(model: model, presentation: presentation, close: close).padding(.top, 22)
                Spacer(minLength: 20)
                }.frame(maxWidth: .infinity).padding(.bottom, 12)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
    var settings: () -> Void
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    FlowerView(isAnimating: false, compact: true).frame(width: 26, height: 26)
                    Text("息间").font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                Spacer()
                StatusBadge(title: model.engine.phase.title, active: ![.away, .suspended, .paused].contains(model.engine.phase))
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 10) {
                    MenuMetricCard(
                        title: "疲劳值",
                        value: "\(model.engine.fatiguePercent)%",
                        detail: "\(model.countdownTitle) · \(clockText(model.countdown))",
                        progress: model.engine.progress,
                        tint: Palette.accent
                    )
                    MenuMetricCard(
                        title: "今日时长",
                        value: durationText(model.today.seconds),
                        detail: "完成休息 \(model.today.completedBreaks) 次 · \(model.settings.mode.title)",
                        progress: nil,
                        tint: Palette.green
                    )
                }
                .frame(width: 218)

                VStack(spacing: 3) {
                    MenuActionRow(
                        title: model.engine.phase == .resting ? "查看休息" : "现在休息",
                        icon: "leaf"
                    ) {
                        model.startRest()
                        close()
                    }
                    MenuActionRow(
                        title: model.settings.remindersEnabled ? "暂停提醒" : "恢复提醒",
                        icon: model.settings.remindersEnabled ? "bell.slash" : "bell"
                    ) {
                        model.toggleReminders()
                    }
                    MenuActionRow(title: "打开主窗口", icon: "app-window", action: open)
                    MenuActionRow(title: "设置与偏好", icon: "settings-2", action: settings)
                    MenuActionRow(title: "退出息间", icon: "power", tint: Palette.secondary) {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Divider().overlay(Palette.line)
            MenuUsageChart(segments: model.engine.segments, date: model.engine.now)
            if let error = model.reminderError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 468)
        .background(
            LinearGradient(
                colors: [Palette.background, Color(hex: 0xF3F4FA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .environment(\.colorScheme, .light)
    }
}

private struct MenuMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Text(value)
                .font(.system(size: title == "疲劳值" ? 40 : 28, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.1))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(2, geo.size.width * progress))
                    }
                }
                .frame(height: 3)
                .animation(.easeOut(duration: 0.35), value: progress)
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Palette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Palette.line.opacity(0.9), lineWidth: 1)
        )
    }
}

private struct MenuActionRow: View {
    let title: String
    let icon: String
    var tint = Palette.ink
    let action: () -> Void
    @StateObject private var state = MenuActionRowState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                LineIcon(systemName: icon, size: 19)
                    .foregroundStyle(state.hovering ? Palette.accentDark : tint)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 39, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(state.hovering ? Palette.lavender.opacity(0.75) : Color.clear)
            )
        }
        .buttonStyle(MenuActionPressStyle(reduceMotion: reduceMotion))
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                state.hovering = inside
            }
        }
        .accessibilityLabel(title)
    }
}

private final class MenuActionRowState: ObservableObject {
    @Published var hovering = false
}

private struct MenuActionPressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MenuUsageChart: View {
    let segments: [UsageSegment]
    let date: Date
    @StateObject private var revealState = MenuUsageChartRevealState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var values: [Double] {
        let calendar = Calendar.current
        guard let day = calendar.dateInterval(of: .day, for: date) else { return Array(repeating: 0, count: 24) }
        return (0..<24).map { hour in
            guard let start = calendar.date(byAdding: .hour, value: hour, to: day.start),
                  let end = calendar.date(byAdding: .hour, value: 1, to: start) else { return 0 }
            let interval = DateInterval(start: start, end: min(end, day.end))
            return min(1, segments.reduce(0) { $0 + $1.seconds(in: interval) } / interval.duration)
        }
    }

    private var latestIndex: Int? {
        values.lastIndex(where: { $0 > 0.001 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("今日使用")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("每小时活跃度")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    ForEach(Array([100, 75, 50, 25, 0].enumerated()), id: \.offset) { index, value in
                        Text("\(value)%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.secondary.opacity(0.72))
                            .offset(y: CGFloat(index) * 27 - 5)
                    }
                }
                .frame(width: 34, height: 116, alignment: .topTrailing)

                GeometryReader { geo in
                    let size = geo.size
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<5, id: \.self) { index in
                            Rectangle()
                                .fill(Palette.line.opacity(index == 4 ? 0.9 : 0.62))
                                .frame(height: 1)
                                .offset(y: size.height * CGFloat(index) / 4)
                        }
                        MenuUsageArea(values: values)
                            .fill(
                                LinearGradient(
                                    colors: [Palette.accent.opacity(0.2), Palette.accent.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(revealState.revealed ? 1 : 0)
                        MenuUsageLine(values: values)
                            .trim(from: 0, to: revealState.revealed ? 1 : 0)
                            .stroke(
                                LinearGradient(
                                    colors: [Palette.accent.opacity(0.7), Palette.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                            )
                        if let latestIndex, revealState.revealed {
                            Circle()
                                .fill(Palette.accent)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .frame(width: 7, height: 7)
                                .shadow(color: Palette.accent.opacity(0.28), radius: 3)
                                .offset(
                                    x: size.width * (CGFloat(latestIndex) + 0.5) / 24 - 3.5,
                                    y: size.height * (1 - CGFloat(values[latestIndex])) - 3.5
                                )
                        }
                    }
                    .clipped()
                }
                .frame(height: 116)
            }

            HStack(spacing: 0) {
                ForEach(Array(["0", "6", "12", "18", "24"].enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.secondary.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : index == 4 ? .trailing : .center)
                }
            }
            .padding(.leading, 44)
        }
        .onAppear {
            revealState.revealed = false
            DispatchQueue.main.async {
                revealState.revealed = true
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.75), value: revealState.revealed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日每小时活跃度图")
    }
}

private final class MenuUsageChartRevealState: ObservableObject {
    @Published var revealed = false
}

private struct MenuUsageLine: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        guard !values.isEmpty else { return Path() }
        var path = Path()
        for (index, value) in values.enumerated() {
            let point = CGPoint(
                x: rect.width * (CGFloat(index) + 0.5) / CGFloat(values.count),
                y: rect.height * (1 - CGFloat(value))
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

private struct MenuUsageArea: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        guard !values.isEmpty else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.5 / CGFloat(values.count), y: rect.height))
        for (index, value) in values.enumerated() {
            path.addLine(to: CGPoint(
                x: rect.width * (CGFloat(index) + 0.5) / CGFloat(values.count),
                y: rect.height * (1 - CGFloat(value))
            ))
        }
        path.addLine(to: CGPoint(x: rect.width * (CGFloat(values.count) - 0.5) / CGFloat(values.count), y: rect.height))
        path.closeSubpath()
        return path
    }
}

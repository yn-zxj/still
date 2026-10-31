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
                Button(action: close) { LineIcon(systemName: "x", size: 13).foregroundStyle(Palette.secondary).frame(width: 28, height: 28).background(Palette.surface.opacity(0.78), in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel(presentation == .resting || presentation == .due ? "关闭并稍后提醒" : "关闭窗口")
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
            if presentation != .completed && model.settings.coursesEnabled {
                ReminderRecommendationCard(model: model, preview: presentation == .preview, choose: chooseCourse)
                    .padding(.horizontal, 24).padding(.top, 18)
            }
            RestActions(model: model, presentation: presentation, close: close).padding(.top, 18)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Palette.restStart, Palette.restEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Palette.ink)
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
            LinearGradient(colors: [Palette.restStart, Palette.heroMiddle, Palette.restEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 10) {
                        FlowerView(isAnimating: false, compact: true).frame(width: 30, height: 30)
                        Text(presentation == .preview ? "全屏提醒 · 预览" : "息间").font(.system(size: 15, weight: .medium))
                    }
                    Spacer()
                    Button { close() } label: { LineLabel(presentation == .resting || presentation == .due ? "稍后提醒" : "关闭窗口", systemImage: "x") }.buttonStyle(SoftButtonStyle())
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
                if presentation != .completed && model.settings.coursesEnabled {
                    ReminderRecommendationCard(model: model, preview: presentation == .preview, choose: chooseCourse)
                        .frame(width: 380).padding(.top, 22)
                }
                RestActions(model: model, presentation: presentation, close: close).padding(.top, 22)
                Spacer(minLength: 20)
                }.frame(maxWidth: .infinity).padding(.bottom, 12)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(presentation == .resting || presentation == .due ? "Esc 稍后提醒" : "Esc 关闭窗口").font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.bottom, 25)
            }
        }
        .foregroundStyle(Palette.ink).tint(Palette.accent).ignoresSafeArea()
        .onExitCommand(perform: close)
    }
}

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    var open: () -> Void
    var insights: () -> Void
    var settings: () -> Void
    var close: () -> Void

    private var applicationSummary: ApplicationInsights {
        let day = Calendar.current.dateInterval(of: .day, for: model.engine.now)
            ?? DateInterval(start: model.engine.now, duration: 86_400)
        return ApplicationInsights.make(
            segments: model.engine.applicationSegments,
            interval: DateInterval(start: day.start, end: max(day.start.addingTimeInterval(1), model.engine.now))
        )
    }

    private var agentSummary: AgentActivitySummary {
        let day = Calendar.current.dateInterval(of: .day, for: model.engine.now)
            ?? DateInterval(start: model.engine.now, duration: 86_400)
        return AgentActivitySummary.make(
            sessions: model.settings.agentActivityEnabled ? model.agentActivity.sessions : [],
            interval: DateInterval(start: day.start, end: max(day.start.addingTimeInterval(1), model.engine.now))
        )
    }

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
                        detail: "完成休息 \(model.today.completedBreaks) 次",
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
            MenuInsightsCard(
                insights: applicationSummary,
                agents: agentSummary,
                enabled: model.settings.applicationInsightsEnabled,
                action: insights
            )
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
                colors: [Palette.background, Palette.panelEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
    }
}

private struct MenuInsightsCard: View {
    let insights: ApplicationInsights
    let agents: AgentActivitySummary
    let enabled: Bool
    let action: () -> Void
    @StateObject private var state = MenuInsightsCardState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    LineIcon(systemName: "chart-pie", size: 17)
                        .foregroundStyle(Palette.accent)
                    Text("时间去向")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("查看详情")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    LineIcon(systemName: "chevron-right", size: 12)
                        .foregroundStyle(Palette.secondary)
                }

                if insights.totalSeconds > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(durationText(insights.totalSeconds))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("前台应用 · \(insights.applicationCount) 个")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                        Spacer()
                    }
                    MenuCategoryStrip(entries: insights.byCategory, total: insights.totalSeconds)
                    Text(topApplications)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                } else {
                    Text(enabled ? "使用一会儿后，这里会出现今天的应用时间流。" : "应用明细已关闭；总计时仍会正常工作。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                }

                if !agents.sessions.isEmpty {
                    Divider().overlay(Palette.line.opacity(0.8))
                    HStack(spacing: 8) {
                        LineIcon(systemName: "terminal", size: 14)
                            .foregroundStyle(Palette.green)
                        Text("Agent \(durationText(agents.wallSeconds))")
                            .font(.system(size: 11, weight: .semibold))
                        Text("· \(agents.sessions.count) 个会话")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                        if agents.hostCount > 0 {
                            Text("· \(agents.hostCount) 台远程机器")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                state.hovering ? Palette.lavender.opacity(0.72) : Palette.surface.opacity(0.74),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.line.opacity(0.9), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                state.hovering = inside
            }
        }
        .accessibilityLabel("打开时间去向")
    }

    private var topApplications: String {
        insights.byApplication.prefix(3).map {
            "\($0.name) \(durationText($0.seconds))"
        }.joined(separator: "  ·  ")
    }
}

private struct MenuCategoryStrip: View {
    let entries: [CategoryTime]
    let total: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.background)
                ForEach(slices) { slice in
                    Capsule()
                        .fill(slice.entry.category.color)
                        .frame(width: max(2, proxy.size.width * slice.width - 1.5))
                        .offset(x: proxy.size.width * slice.start)
                }
            }
        }
        .frame(height: 7)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private struct Slice: Identifiable {
        let entry: CategoryTime
        let start: Double
        let width: Double
        var id: String { entry.id }
    }

    private var slices: [Slice] {
        var cursor = 0.0
        return entries.map { entry in
            let width = entry.seconds / max(total, 1)
            defer { cursor += width }
            return Slice(entry: entry, start: cursor, width: width)
        }
    }
}

private final class MenuInsightsCardState: ObservableObject {
    @Published var hovering = false
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

    private var window: DayTimelineWindow {
        DayTimelineWindow(date: date, now: date)
    }

    private var points: [UsageActivityPoint] {
        UsageStatistics.activity(segments: segments, date: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("今日使用")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("每 5 分钟活跃度")
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
                        MenuUsageArea(points: points)
                            .fill(
                                LinearGradient(
                                    colors: [Palette.accent.opacity(0.2), Palette.accent.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(revealState.revealed ? 1 : 0)
                        MenuUsageLine(points: points)
                            .trim(from: 0, to: revealState.revealed ? 1 : 0)
                            .stroke(
                                LinearGradient(
                                    colors: [Palette.accent.opacity(0.7), Palette.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                            )
                        if let latest = points.last, revealState.revealed {
                            Circle()
                                .fill(Palette.accent)
                                .overlay(Circle().stroke(Palette.surface, lineWidth: 1.5))
                                .frame(width: 7, height: 7)
                                .shadow(color: Palette.accent.opacity(0.28), radius: 3)
                                .offset(
                                    x: size.width * latest.fraction - 3.5,
                                    y: size.height * (1 - CGFloat(latest.activity)) - 3.5
                                )
                        }
                    }
                    .clipped()
                }
                .frame(height: 116)
            }

            GeometryReader { proxy in
                ForEach(window.marks(everyHours: 6), id: \.self) { mark in
                    Text(mark == window.day.end ? "24:00" : timelineTimeText(mark))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.secondary.opacity(0.78))
                        .frame(width: 40)
                        .position(
                            x: min(proxy.size.width - 20, max(64, 44 + (proxy.size.width - 44) * window.fraction(for: mark))),
                            y: 6
                        )
                }
            }
            .frame(height: 12)
        }
        .onAppear {
            revealState.revealed = false
            DispatchQueue.main.async {
                revealState.revealed = true
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.75), value: revealState.revealed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日每五分钟活跃度图")
    }
}

private final class MenuUsageChartRevealState: ObservableObject {
    @Published var revealed = false
}

private struct MenuUsageLine: Shape {
    let points: [UsageActivityPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: rect.width * point.fraction, y: rect.height * (1 - point.activity))
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        return path
    }
}

private struct MenuUsageArea: Shape {
    let points: [UsageActivityPoint]
    func path(in rect: CGRect) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: rect.width * first.fraction, y: rect.height))
        for point in points {
            path.addLine(to: CGPoint(x: rect.width * point.fraction, y: rect.height * (1 - point.activity)))
        }
        path.addLine(to: CGPoint(x: rect.width * last.fraction, y: rect.height))
        path.closeSubpath()
        return path
    }
}

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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                FlowerView(isAnimating: false, compact: true).frame(width: 27, height: 27)
                VStack(alignment: .leading, spacing: 1) {
                    Text("息间").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(model.engine.now.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                StatusBadge(title: model.engine.phase.title, active: ![.away, .suspended, .paused].contains(model.engine.phase))
                Button(action: close) {
                    LineIcon(systemName: "x", size: 13)
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 28, height: 28)
                        .background(Palette.surface.opacity(0.58), in: Circle())
                }
                .buttonStyle(.plain)
                .help("收起快捷面板")
                .accessibilityLabel("收起快捷面板")
            }

            MenuVitalsPanel(
                fatigue: model.engine.fatiguePercent,
                progress: model.engine.progress,
                countdownTitle: model.countdownTitle,
                countdown: clockText(model.countdown),
                today: durationText(model.today.seconds),
                breaks: model.today.completedBreaks,
                applications: applicationSummary.applicationCount
            )

            MenuCommandDock(
                resting: model.engine.phase == .resting,
                remindersEnabled: model.settings.remindersEnabled,
                rest: {
                    model.startRest()
                    close()
                },
                toggleReminders: model.toggleReminders,
                open: open,
                settings: settings
            )

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
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 500)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Palette.background, Palette.panelEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Palette.accent.opacity(0.035))
                    .frame(width: 280, height: 280)
                    .offset(x: 210, y: -190)
                Circle()
                    .fill(Palette.mint.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .offset(x: -220, y: 260)
            }
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
                    LineIcon(systemName: "chart-line", size: 17)
                        .foregroundStyle(Palette.accent)
                    Text("时间去向")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if insights.totalSeconds > 0 {
                        Text("前台应用 \(insights.applicationCount) 个")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                    }
                    Text("查看详情")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    LineIcon(systemName: "chevron-right", size: 12)
                        .foregroundStyle(Palette.secondary)
                }

                if insights.totalSeconds > 0 {
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

private struct MenuVitalsPanel: View {
    let fatigue: Int
    let progress: Double
    let countdownTitle: String
    let countdown: String
    let today: String
    let breaks: Int
    let applications: Int

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    LineIcon(systemName: "eye", size: 13)
                        .foregroundStyle(Palette.accent)
                    Text("此刻状态")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(fatigue)")
                        .font(.system(size: 50, weight: .medium, design: .rounded))
                        .tracking(-2)
                    Text("%")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.accentDark)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.accent.opacity(0.09))
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.green, Palette.accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(2, proxy.size.width * min(1, max(0, progress))))
                    }
                }
                .frame(height: 3)
                Text("\(countdownTitle) · \(countdown)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Palette.line.opacity(0.75))
                .frame(width: 1, height: 102)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("今日使用")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.secondary)
                Text(today)
                    .font(.system(size: 25, weight: .medium, design: .rounded))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                MenuFactRow(icon: "leaf", text: "完成休息 \(breaks) 次")
                MenuFactRow(icon: "monitor", text: "前台应用 \(applications) 个")
            }
            .frame(width: 158, alignment: .leading)
        }
        .padding(19)
        .background(
            LinearGradient(
                colors: [Palette.surface.opacity(0.92), Palette.lavender.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.line.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct MenuFactRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            LineIcon(systemName: icon, size: 12)
                .foregroundStyle(Palette.secondary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
    }
}

private struct MenuCommandDock: View {
    let resting: Bool
    let remindersEnabled: Bool
    let rest: () -> Void
    let toggleReminders: () -> Void
    let open: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            MenuCommandButton(title: resting ? "休息中" : "现在休息", icon: "leaf", prominent: true, action: rest)
            MenuCommandButton(title: remindersEnabled ? "暂停提醒" : "恢复提醒",
                              icon: remindersEnabled ? "bell-off" : "bell",
                              action: toggleReminders)
            MenuCommandButton(title: "主窗口", icon: "app-window", action: open)
            MenuCommandButton(title: "偏好设置", icon: "settings-2", action: settings)
            MenuCommandButton(title: "退出", icon: "power", action: { NSApplication.shared.terminate(nil) })
        }
    }
}

private struct MenuCommandButton: View {
    let title: String
    let icon: String
    var prominent = false
    let action: () -> Void
    @StateObject private var state = MenuCommandButtonState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                LineIcon(systemName: icon, size: 17)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 57)
            .background(
                prominent
                    ? AnyShapeStyle(LinearGradient(colors: [Palette.accent, Palette.accentDark],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(state.hovering ? Palette.lavender.opacity(0.82) : Palette.surface.opacity(0.62)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(prominent ? Color.clear : Palette.line.opacity(0.82), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private final class MenuCommandButtonState: ObservableObject {
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

enum MenuUsageChartAxis {
    static let activityPercents = Array(stride(from: 100, through: 0, by: -20))
    static let hours = Array(stride(from: 0, through: 24, by: 2))
}

private struct MenuUsageChart: View {
    let segments: [UsageSegment]
    let date: Date
    @StateObject private var revealState = MenuUsageChartRevealState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var points: [UsageActivityPoint] {
        UsageStatistics.activity(segments: segments, date: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuUsageChartHeader()
            HStack(alignment: .top, spacing: 8) {
                MenuUsageYAxis()
                    .frame(width: 30, height: 132)
                MenuUsagePlot(
                    points: points,
                    revealed: revealState.revealed
                )
                .frame(height: 132)
            }
            MenuUsageXAxis()
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

private struct MenuUsageChartHeader: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日节奏")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("每 5 分钟活跃度 · 未来时段留白")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(Palette.green)
                    .frame(width: 5, height: 5)
                Text("现在")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

private struct MenuUsageYAxis: View {
    var body: some View {
        GeometryReader { proxy in
            ForEach(MenuUsageChartAxis.activityPercents, id: \.self) { value in
                Text("\(value)%")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.secondary.opacity(0.64))
                    .frame(width: 30, alignment: .trailing)
                    .position(
                        x: 15,
                        y: MenuUsageChartAxis.yPosition(
                            for: value,
                            height: proxy.size.height
                        )
                    )
            }
        }
    }
}

private struct MenuUsagePlot: View {
    let points: [UsageActivityPoint]
    let revealed: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            plotBackground
            MenuUsageGrid()
            area
            line
            MenuUsageEndpoint(point: revealed ? points.last : nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var plotBackground: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Palette.surface.opacity(0.62),
                        Palette.lavender.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var area: some View {
        MenuUsageArea(points: points)
            .fill(
                LinearGradient(
                    colors: [
                        Palette.accent.opacity(0.11),
                        Palette.accent.opacity(0.005)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(revealed ? 1 : 0)
    }

    private var line: some View {
        MenuUsageLine(points: points)
            .trim(from: 0, to: revealed ? 1 : 0)
            .stroke(
                LinearGradient(
                    colors: [Palette.green.opacity(0.9), Palette.accent],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            )
    }
}

private struct MenuUsageGrid: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                horizontalLines(size: proxy.size)
                verticalLines(size: proxy.size)
            }
        }
    }

    private func horizontalLines(size: CGSize) -> some View {
        ForEach(MenuUsageChartAxis.activityPercents, id: \.self) { value in
            Rectangle()
                .fill(Palette.line.opacity(value == 0 ? 0.7 : 0.42))
                .frame(height: value == 0 ? 0.75 : 0.5)
                .offset(y: size.height * (1 - CGFloat(value) / 100))
        }
    }

    private func verticalLines(size: CGSize) -> some View {
        ForEach(MenuUsageChartAxis.hours, id: \.self) { hour in
            Rectangle()
                .fill(Palette.line.opacity(hour % 6 == 0 ? 0.56 : 0.3))
                .frame(width: hour % 6 == 0 ? 0.7 : 0.45, height: size.height)
                .offset(x: size.width * CGFloat(hour) / 24)
        }
    }
}

private struct MenuUsageEndpoint: View {
    let point: UsageActivityPoint?

    var body: some View {
        GeometryReader { proxy in
            if let point {
                endpoint(point: point, size: proxy.size)
            }
        }
    }

    private func endpoint(point: UsageActivityPoint, size: CGSize) -> some View {
        let inset: CGFloat = 6
        let activity = CGFloat(point.activity)
        let plotHeight = max(1, size.height - inset * 2)
        let center = CGPoint(
            x: size.width * point.fraction,
            y: inset + plotHeight * (1 - activity)
        )
        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(Palette.accent.opacity(0.14))
                .frame(width: 12, height: 12)
                .offset(x: center.x - 6, y: center.y - 6)
            Circle()
                .fill(Palette.accent)
                .overlay(Circle().stroke(Palette.surface, lineWidth: 1))
                .frame(width: 5, height: 5)
                .offset(x: center.x - 2.5, y: center.y - 2.5)
        }
    }
}

private struct MenuUsageXAxis: View {
    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: 30, height: 10)
            GeometryReader { proxy in
                ForEach(MenuUsageChartAxis.hours, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.secondary.opacity(0.64))
                        .frame(width: 18)
                        .position(
                            x: MenuUsageChartAxis.xPosition(
                                for: hour,
                                width: proxy.size.width
                            ),
                            y: 5
                        )
                }
            }
        }
        .frame(height: 11)
    }
}

private extension MenuUsageChartAxis {
    static func yPosition(for value: Int, height: CGFloat) -> CGFloat {
        let inset: CGFloat = 6
        let raw = height * (1 - CGFloat(value) / 100)
        return max(inset, min(height - inset, raw))
    }

    static func xPosition(for hour: Int, width: CGFloat) -> CGFloat {
        let halfLabel: CGFloat = 9
        let raw = width * CGFloat(hour) / 24
        return min(width - halfLabel, max(halfLabel, raw))
    }
}

private final class MenuUsageChartRevealState: ObservableObject {
    @Published var revealed = false
}

private struct MenuUsageLine: Shape {
    let points: [UsageActivityPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let plot = rect.insetBy(dx: 0, dy: 6)
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: plot.width * point.fraction,
                                   y: plot.minY + plot.height * (1 - point.activity))
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
        let plot = rect.insetBy(dx: 0, dy: 6)
        path.move(to: CGPoint(x: plot.width * first.fraction, y: plot.maxY))
        for point in points {
            path.addLine(to: CGPoint(x: plot.width * point.fraction,
                                     y: plot.minY + plot.height * (1 - point.activity)))
        }
        path.addLine(to: CGPoint(x: plot.width * last.fraction, y: plot.maxY))
        path.closeSubpath()
        return path
    }
}

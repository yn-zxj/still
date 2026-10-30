import AppKit
import Charts
import SwiftUI
import StillCore

private enum InsightsRange: Int, CaseIterable, Identifiable {
    case today = 1, week = 7, month = 28

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .today: return "今天"
        case .week: return "近 7 天"
        case .month: return "近 28 天"
        }
    }

    func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 1 - rawValue, to: today) ?? today
        return DateInterval(start: start, end: max(start.addingTimeInterval(1), now))
    }
}

@MainActor
private final class InsightsViewState: ObservableObject {
    @Published var range = InsightsRange.today
    @Published var appeared = false
}

struct InsightsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var agentActivity: AgentActivityCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state = InsightsViewState()

    @MainActor
    init(model: AppModel) {
        self.model = model
        _agentActivity = ObservedObject(wrappedValue: model.agentActivity)
    }

    private var insights: ApplicationInsights {
        ApplicationInsights.make(
            segments: model.engine.applicationSegments,
            interval: state.range.interval(now: model.engine.now)
        )
    }

    private var usageTotal: Double {
        UsageStatistics.daily(
            segments: model.engine.segments,
            breaks: model.engine.breaks,
            endingAt: model.engine.now,
            days: state.range.rawValue
        ).reduce(0) { $0 + $1.seconds }
    }

    private var dailyCategories: [DailyCategoryTime] {
        ApplicationInsights.daily(
            segments: model.engine.applicationSegments,
            endingAt: model.engine.now,
            days: state.range.rawValue
        )
    }

    private var displayedTotal: Double {
        insights.totalSeconds > 0 ? insights.totalSeconds : usageTotal
    }

    private var agentSummary: AgentActivitySummary {
        AgentActivitySummary.make(
            sessions: model.settings.agentActivityEnabled ? agentActivity.sessions : [],
            interval: state.range.interval(now: model.engine.now)
        )
    }

    private var animated: Bool { model.settings.motionEnabled && !reduceMotion }

    var body: some View {
        let data = insights
        VStack(alignment: .leading, spacing: 22) {
            header
            hero(data)
                .opacity(state.appeared ? 1 : 0)
                .offset(y: state.appeared ? 0 : 8)
            facts(data)
                .opacity(state.appeared ? 1 : 0)
                .offset(y: state.appeared ? 0 : 10)
            agentWork(agentSummary)
            timeline(data)
            HStack(alignment: .top, spacing: 16) {
                applicationBreakdown(data)
                    .frame(maxWidth: .infinity)
                categoryBreakdown(data)
                    .frame(width: 300)
            }
            privacyNote
        }
        .onAppear {
            guard !state.appeared else { return }
            withAnimation(animated ? .easeOut(duration: 0.38) : nil) { state.appeared = true }
        }
        .onChange(of: state.range) { _ in
            guard animated else { return }
            withAnimation(.easeInOut(duration: 0.22)) { state.appeared = true }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("时间去向")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.7)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            SegmentedPillControl(selection: $state.range, values: InsightsRange.allCases) { item in
                Text(item.title)
            }
            .frame(width: 260)
        }
    }

    private var subtitle: String {
        if state.range == .today {
            return model.engine.now.formatted(.dateTime.month(.wide).day().weekday(.wide))
        }
        return "\(state.range.title)的前台应用停留分布"
    }

    private func hero(_ data: ApplicationInsights) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(data.totalSeconds > 0 ? "屏幕时间去了哪里" : "从这一版开始，看见时间流向")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accentDark)
                    Text(durationText(displayedTotal))
                        .font(.system(size: 46, weight: .medium, design: .rounded))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text(headline(data))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 20)
                coverageBadge(data)
            }
            if data.totalSeconds > 0 {
                CategoryBar(entries: data.byCategory, total: data.totalSeconds)
                    .frame(height: 13)
                categoryLegend(data.byCategory, total: data.totalSeconds)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.surface.opacity(0.7))
                    .frame(height: 13)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.accent.opacity(0.18))
                            .frame(maxWidth: usageTotal > 0 ? .infinity : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(27)
        .background(
            LinearGradient(
                colors: [Palette.heroStart, Palette.heroMiddle, Palette.heroEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.line.opacity(0.85), lineWidth: 1)
        )
    }

    private func headline(_ data: ApplicationInsights) -> String {
        guard let top = data.byApplication.first else {
            return usageTotal > 0
                ? "已有总使用时长；应用明细会从新版本开始本地积累。"
                : "开始使用 Mac 后，这里会逐渐长出一条属于你的时间流。"
        }
        return "\(top.name) 占了最多时间，共 \(durationText(top.seconds))。"
    }

    private func coverageBadge(_ data: ApplicationInsights) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(data.totalSeconds > 0 ? "应用明细覆盖" : "总使用时长")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Text(data.totalSeconds > 0 ? coverageText(data) : durationText(usageTotal))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(data.totalSeconds > 0 ? "与息间总计时相比" : "尚无应用明细")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Palette.line.opacity(0.8), lineWidth: 1)
        )
    }

    private func coverageText(_ data: ApplicationInsights) -> String {
        guard usageTotal > 0 else { return "0%" }
        return insightPercent(data.totalSeconds, of: usageTotal)
    }

    private func categoryLegend(_ entries: [CategoryTime], total: Double) -> some View {
        let visible = entries.prefix(5)
        return HStack(spacing: 18) {
            ForEach(Array(visible)) { entry in
                HStack(spacing: 7) {
                    Circle().fill(entry.category.color).frame(width: 7, height: 7)
                    Text(entry.category.title)
                    Text(insightPercent(entry.seconds, of: total))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func facts(_ data: ApplicationInsights) -> some View {
        HStack(spacing: 16) {
            factCard(
                icon: "app-window",
                title: "停留最久",
                value: data.byApplication.first?.name ?? "等待记录",
                detail: data.byApplication.first.map { durationText($0.seconds) } ?? "应用名称只保存在本机"
            )
            factCard(
                icon: "arrow-left-right",
                title: "应用切换",
                value: data.switches == 0 ? "平稳" : "\(data.switches) 次",
                detail: data.totalSeconds >= 600
                    ? String(format: "每小时约 %.0f 次", data.switchesPerHour)
                    : "积累十分钟后显示频率"
            )
            factCard(
                icon: "timer",
                title: "最长停留",
                value: durationText(data.longestApplicationStretch),
                detail: data.applicationCount == 0 ? "还没有应用明细" : "连续使用同一应用"
            )
        }
    }

    private func factCard(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            LineIcon(systemName: icon, size: 19)
                .foregroundStyle(Palette.accent)
                .frame(width: 38, height: 38)
                .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Palette.line.opacity(0.8), lineWidth: 1)
        )
    }

    private func agentWork(_ summary: AgentActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent 工作时间")
                        .font(.system(size: 15, weight: .semibold))
                    Text("来自 HAPI Hub；同一会话重复同步只计算一次，等待你回复的时间不计入。")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                if model.settings.agentActivityEnabled && model.settings.hapiSyncEnabled {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(agentActivity.status.isError ? Color.orange : agentActivity.status.isHealthy ? Palette.green : Palette.secondary)
                            .frame(width: 6, height: 6)
                        Text(agentActivity.status.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(agentActivity.status.isError ? Color.orange : Palette.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Palette.background, in: Capsule())
                }
            }

            if !model.settings.agentActivityEnabled {
                agentEmpty("Agent 时间已在偏好设置中关闭。")
            } else if summary.sessions.isEmpty {
                agentEmpty(
                    model.settings.hapiSyncEnabled
                        ? "还没有可展示的 HAPI 会话；安装并登录 HAPI 后会在这里汇总本机与其它机器。"
                        : "HAPI 同步已关闭；已有 Agent 历史仍会保留。"
                )
            } else {
                HStack(spacing: 12) {
                    agentMetric(
                        title: "Agent 墙钟时间",
                        value: durationText(summary.wallSeconds),
                        note: "按时间并集计算"
                    )
                    agentMetric(
                        title: "会话工作时长",
                        value: durationText(summary.sessionSeconds),
                        note: "\(summary.sessions.count) 个会话"
                    )
                    agentMetric(
                        title: "另一台机器",
                        value: "\(summary.hostCount) 台",
                        note: summary.hostCount == 0 ? "本次都是本机会话" : "远程 Agent 已接入"
                    )
                }

                VStack(spacing: 10) {
                    ForEach(Array(summary.sessions.prefix(6))) { session in
                        agentSessionRow(session)
                    }
                }

                if summary.sessions.count > 6 {
                    Text("另有 \(summary.sessions.count - 6) 个 Agent 会话")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .card(padding: 24)
    }

    private func agentMetric(title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(Palette.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func agentSessionRow(_ session: AgentActivitySession) -> some View {
        HStack(spacing: 12) {
            LineIcon(systemName: "terminal", size: 17)
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(session.flavorLabel)
                    Text("·")
                    Text(session.locationLabel)
                    if let project = session.projectPath {
                        Text("·")
                        Text(URL(fileURLWithPath: project).lastPathComponent)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 10)
            Text(durationText(session.seconds(in: agentSummary.interval)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func agentEmpty(_ text: String) -> some View {
        HStack(spacing: 12) {
            LineIcon(systemName: "terminal", size: 20)
                .foregroundStyle(Palette.accent.opacity(0.7))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(3)
            Spacer()
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func timeline(_ data: ApplicationInsights) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.range == .today ? "今天的时间流" : "每天去了哪里")
                        .font(.system(size: 15, weight: .semibold))
                    Text(state.range == .today ? "每一段颜色对应一个应用类别" : "按天叠加，比较不同类别的时间占比")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                if data.totalSeconds > 0 {
                    Text("\(data.applicationCount) 个应用")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Palette.background, in: Capsule())
                }
            }
            if state.range == .today {
                TimelineRibbon(
                    segments: model.engine.applicationSegments,
                    agentSessions: agentSummary.sessions,
                    date: model.engine.now,
                    animate: animated
                )
            } else if dailyCategories.isEmpty {
                emptyTimeline
            } else {
                CategoryDailyChart(points: dailyCategories, days: state.range.rawValue)
                    .frame(height: 220)
            }
        }
        .card(padding: 24)
    }

    private var emptyTimeline: some View {
        HStack(spacing: 14) {
            LineIcon(systemName: "chart-pie", size: 28)
                .foregroundStyle(Palette.accent.opacity(0.7))
            VStack(alignment: .leading, spacing: 4) {
                Text("暂时没有应用时间流").font(.system(size: 14, weight: .medium))
                Text("开启“时间去向”并使用一会儿应用后，这里会自动出现。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 22)
    }

    private func applicationBreakdown(_ data: ApplicationInsights) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("应用去向").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("累计 \(durationText(data.totalSeconds))")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).monospacedDigit()
            }
            if data.byApplication.isEmpty {
                emptyTimeline
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(data.byApplication.prefix(8))) { app in
                        ApplicationBreakdownRow(
                            app: app,
                            total: data.totalSeconds,
                            animate: animated
                        )
                    }
                }
                if data.byApplication.count > 8 {
                    Text("另有 \(data.byApplication.count - 8) 个应用未展开")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
        }
        .card(padding: 24)
    }

    private func categoryBreakdown(_ data: ApplicationInsights) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("类别构成").font(.system(size: 15, weight: .semibold))
            if data.byCategory.isEmpty {
                emptyTimeline
            } else {
                HStack {
                    Spacer()
                    CategoryDonut(entries: data.byCategory, total: data.totalSeconds, animate: animated)
                        .frame(width: 150, height: 150)
                    Spacer()
                }
                VStack(spacing: 11) {
                    ForEach(data.byCategory) { entry in
                        HStack(spacing: 9) {
                            Circle().fill(entry.category.color).frame(width: 8, height: 8)
                            Text(entry.category.title).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Text(durationText(entry.seconds))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .card(padding: 24)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            LineIcon(systemName: "eye", size: 17)
                .foregroundStyle(Palette.accent)
            Text("应用去向只记录前台应用名称、粗略类别与停留时段，全部留在本机。HAPI 只读取 Agent 会话标题、项目路径、机器和时段，不保存 prompt、回复或代码内容；它连接到你自己的 HAPI Hub，不经过息间的服务器。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
    }
}

private struct CategoryBar: View {
    let entries: [CategoryTime]
    let total: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface.opacity(0.7))
                ForEach(slices) { slice in
                    Capsule()
                        .fill(slice.entry.category.color)
                        .frame(width: max(2, proxy.size.width * slice.width - 2))
                        .offset(x: proxy.size.width * slice.start)
                }
            }
        }
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间类别分布")
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

private struct TimelineRibbon: View {
    let segments: [ApplicationUsageSegment]
    let agentSessions: [AgentActivitySession]
    let date: Date
    let animate: Bool
    @StateObject private var state = RevealState()

    var body: some View {
        let window = DayTimelineWindow(date: date, now: date)
        let visible = segments.filter { $0.seconds(in: window.visible) > 0 }
        let hasAgentLane = !agentSessions.isEmpty
        let laneHeight: CGFloat = 26
        let laneGap: CGFloat = 8
        VStack(spacing: 9) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.background)
                    ForEach(0..<24, id: \.self) { hour in
                        if let mark = Calendar.current.date(byAdding: .hour, value: hour, to: window.day.start),
                           mark <= window.visible.end {
                            Rectangle()
                                .fill(Palette.surface.opacity(0.9))
                                .frame(width: 1, height: hasAgentLane ? laneHeight * 2 + laneGap : laneHeight)
                                .offset(x: proxy.size.width * window.fraction(for: mark))
                        }
                    }
                    ForEach(visible) { segment in
                        if let end = window.visibleEnd(for: segment.startedAt, end: segment.endedAt) {
                            let start = max(segment.startedAt, window.visible.start)
                            let x = proxy.size.width * start.timeIntervalSince(window.visible.start) / window.visible.duration
                            let width = max(2, proxy.size.width * end.timeIntervalSince(start) / window.visible.duration)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(segment.category.color.opacity(0.86))
                                .frame(width: width * (state.revealed ? 1 : 0.1), height: laneHeight)
                                .offset(x: x)
                        }
                    }
                    if hasAgentLane {
                        ForEach(agentSessions) { session in
                            ForEach(session.spans) { span in
                                if let end = window.visibleEnd(for: span.startedAt, end: span.endedAt) {
                                    let start = max(span.startedAt, window.visible.start)
                                    let x = proxy.size.width * start.timeIntervalSince(window.visible.start) / window.visible.duration
                                    let width = max(2, proxy.size.width * end.timeIntervalSince(start) / window.visible.duration)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Palette.green.opacity(0.82))
                                        .frame(width: width * (state.revealed ? 1 : 0.1), height: laneHeight)
                                        .offset(x: x, y: laneHeight + laneGap)
                                }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: hasAgentLane ? laneHeight * 2 + laneGap : laneHeight)
            if hasAgentLane {
                HStack(spacing: 18) {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6)
                        Text("前台应用")
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Palette.green).frame(width: 6, height: 6)
                        Text("Agent")
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.secondary)
            }
            GeometryReader { proxy in
                ForEach(window.marks(), id: \.self) { mark in
                    Text(timelineTimeText(mark))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.secondary.opacity(0.8))
                        .frame(width: 44)
                        .position(
                            x: min(max(22, proxy.size.width * window.fraction(for: mark)), proxy.size.width - 22),
                            y: 6
                        )
                }
            }
            .frame(height: 12)
        }
        .onAppear {
            withAnimation(animate ? .easeOut(duration: 0.55) : nil) { state.revealed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日应用时间流")
    }
}

private struct CategoryDailyChart: View {
    let points: [DailyCategoryTime]
    let days: Int

    var body: some View {
        let categories = ApplicationCategory.allCases.filter { category in
            points.contains { $0.category == category && $0.seconds > 0 }
        }
        Chart(points) { point in
            BarMark(
                x: .value("日期", point.date, unit: .day),
                y: .value("分钟", point.seconds / 60)
            )
            .foregroundStyle(by: .value("类别", point.category.title))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(
            domain: categories.map(\.title),
            range: categories.map(\.color)
        )
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days == 28 ? 7 : 1)) { value in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

private struct ApplicationBreakdownRow: View {
    let app: ApplicationTime
    let total: Double
    let animate: Bool
    @StateObject private var state = RevealState()

    var body: some View {
        HStack(spacing: 12) {
            ApplicationIcon(bundleID: app.bundleID, name: app.name)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(app.category.title).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Spacer(minLength: 8)
                    Text(durationText(app.seconds))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.background)
                        Capsule()
                            .fill(app.category.color.opacity(0.8))
                            .frame(width: max(2, proxy.size.width * app.seconds / max(total, 1)) * (state.revealed ? 1 : 0.02))
                    }
                }
                .frame(height: 6)
            }
            Text(insightPercent(app.seconds, of: total))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .onAppear {
            withAnimation(animate ? .easeOut(duration: 0.48) : nil) { state.revealed = true }
        }
    }
}

private struct CategoryDonut: View {
    let entries: [CategoryTime]
    let total: Double
    let animate: Bool
    @StateObject private var state = RevealState()

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.background, lineWidth: 18)
            ForEach(slices) { slice in
                Circle()
                    .trim(from: slice.start, to: slice.end)
                    .stroke(slice.entry.category.color, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 4) {
                Text(durationText(total))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("应用时间").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }
        .scaleEffect(state.revealed ? 1 : 0)
        .opacity(state.revealed ? 1 : 0)
        .onAppear {
            withAnimation(animate ? .spring(response: 0.55, dampingFraction: 0.78) : nil) { state.revealed = true }
        }
    }

    private struct Slice: Identifiable {
        let entry: CategoryTime
        let start: CGFloat
        let end: CGFloat
        var id: String { entry.id }
    }

    private var slices: [Slice] {
        var cursor = 0.0
        return entries.map { entry in
            let start = cursor
            cursor += entry.seconds / max(total, 1)
            return Slice(entry: entry, start: start, end: min(1, cursor))
        }
    }
}

private struct ApplicationIcon: View {
    let bundleID: String
    let name: String
    @StateObject private var state = ApplicationIconState()

    var body: some View {
        Group {
            if let image = state.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                LineIcon(systemName: "app-window", size: 18)
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .onAppear { state.image = ApplicationIconCache.shared.icon(for: bundleID) }
        .accessibilityLabel(name)
    }
}

@MainActor
private final class RevealState: ObservableObject {
    @Published var revealed = false
}

@MainActor
private final class ApplicationIconState: ObservableObject {
    @Published var image: NSImage?
}

@MainActor
private final class ApplicationIconCache {
    static let shared = ApplicationIconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

private func insightPercent(_ seconds: Double, of total: Double) -> String {
    let percent = seconds / max(total, 1) * 100
    if seconds > 0 && percent < 1 { return "<1%" }
    return "\(min(100, max(0, Int(percent.rounded()))))%"
}

extension ApplicationCategory {
    var color: Color {
        switch self {
        case .development: return Color(hex: 0x7465D4)
        case .communication: return Color(hex: 0x4D91A8)
        case .productivity: return Color(hex: 0x6E9670)
        case .browsing: return Color(hex: 0x5E86C6)
        case .design: return Color(hex: 0xC4789E)
        case .media: return Color(hex: 0xC99355)
        case .learning: return Color(hex: 0x4F9B8B)
        case .utilities: return Color(hex: 0x8A8798)
        case .other: return Color(hex: 0xB4ACB9)
        }
    }
}

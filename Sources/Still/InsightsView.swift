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

    func dateSpanText(now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        if self == .today {
            return now.formatted(.dateTime.month(.wide).day().weekday(.wide))
        }
        let start = calendar.date(byAdding: .day, value: 1 - rawValue, to: today) ?? today
        let startText = start.formatted(.dateTime.month(.defaultDigits).day())
        let endText = today.formatted(.dateTime.month(.defaultDigits).day())
        return "\(startText)–\(endText)"
    }
}

private enum InsightsDisplayState {
    case hasDetails(recordingEnabled: Bool)
    case onlyAgent(recordingEnabled: Bool)
    case disabledNoDetails
    case waitingForDetails
}

@MainActor
private final class InsightsViewState: ObservableObject {
    @Published var range = InsightsRange.today
    @Published var agentExpandedOverride: Bool? = nil
}

struct InsightsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var statsClock: StatsClock
    @ObservedObject private var agentActivity: AgentActivityCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state = InsightsViewState()

    @MainActor
    init(model: AppModel) {
        self.model = model
        _statsClock = ObservedObject(wrappedValue: model.statsClock)
        _agentActivity = ObservedObject(wrappedValue: model.agentActivity)
    }

    private var hasAnyAppHistory: Bool {
        !model.engine.applicationSegments.isEmpty
    }

    private var animated: Bool { model.settings.motionEnabled && !reduceMotion }

    private func displayState(data: ApplicationInsights, agent: AgentActivitySummary) -> InsightsDisplayState {
        let enabled = model.settings.applicationInsightsEnabled
        if data.totalSeconds > 0 {
            return .hasDetails(recordingEnabled: enabled)
        }
        if model.settings.agentActivityEnabled && !agent.sessions.isEmpty {
            return .onlyAgent(recordingEnabled: enabled)
        }
        return enabled ? .waitingForDetails : .disabledNoDetails
    }

    var body: some View {
        let _ = statsClock.revision
        let now = model.engine.now
        let interval = state.range.interval(now: now)
        let data = ApplicationInsights.make(
            segments: model.engine.applicationSegments,
            interval: interval
        )
        let usageTotal = UsageStatistics.daily(
            segments: model.engine.segments,
            breaks: model.engine.breaks,
            endingAt: now,
            days: state.range.rawValue
        ).reduce(0) { $0 + $1.seconds }
        let agent = AgentActivitySummary.make(
            sessions: model.settings.agentActivityEnabled ? agentActivity.sessions : [],
            interval: interval
        )
        let mode = displayState(data: data, agent: agent)

        VStack(alignment: .leading, spacing: 22) {
            header(now: now)
            hero(data: data, agent: agent, usageTotal: usageTotal, mode: mode)

            switch mode {
            case .hasDetails:
                facts(data)
                if model.settings.agentActivityEnabled {
                    agentWork(agent)
                }
                timeline(data: data, agent: agent, now: now)
                BreakdownCardsLayout(spacing: 16, trailingWidth: 300) {
                    applicationBreakdown(data)
                    categoryBreakdown(data)
                }
            case .onlyAgent(let recordingEnabled):
                if model.settings.agentActivityEnabled {
                    agentWork(agent)
                }
                if state.range == .today {
                    timeline(data: data, agent: agent, now: now)
                }
                singleAppEmptyCard(
                    recordingEnabled: recordingEnabled,
                    hasAgentInRange: true
                )
            case .disabledNoDetails:
                singleAppEmptyCard(
                    recordingEnabled: false,
                    hasAgentInRange: false
                )
                if model.settings.agentActivityEnabled {
                    agentWork(agent)
                }
            case .waitingForDetails:
                singleAppEmptyCard(
                    recordingEnabled: true,
                    hasAgentInRange: false
                )
                if model.settings.agentActivityEnabled {
                    agentWork(agent)
                }
            }

            privacyNote
        }
        .onChange(of: state.range) { _ in
            state.agentExpandedOverride = nil
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("时间去向")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.7)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle(now: now))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            SegmentedPillControl(selection: $state.range, values: InsightsRange.allCases) { item in
                Text(item.title)
            }
            .frame(width: 260)
            .accessibilityLabel("统计时段")
        }
    }

    private func subtitle(now: Date) -> String {
        let span = state.range.dateSpanText(now: now)
        if state.range == .today {
            return span
        }
        return "\(span) · 前台应用停留分布"
    }

    private func hero(data: ApplicationInsights, agent: AgentActivitySummary, usageTotal: Double, mode: InsightsDisplayState) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(heroEyebrow(mode))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accentDark)
                    Text(heroPrimaryMetric(data: data, agent: agent, usageTotal: usageTotal, mode: mode))
                        .font(.system(size: 46, weight: .medium, design: .rounded))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text(heroHeadline(data: data, agent: agent, usageTotal: usageTotal, mode: mode))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 20)
                heroBadge(data: data, agent: agent, usageTotal: usageTotal, mode: mode)
            }

            if data.totalSeconds > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    CategoryBar(entries: data.byCategory, total: data.totalSeconds)
                        .frame(height: 13)
                    categoryLegend(data.byCategory, total: data.totalSeconds)
                }
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

    private func heroEyebrow(_ mode: InsightsDisplayState) -> String {
        switch mode {
        case .hasDetails(let recordingEnabled):
            return recordingEnabled ? "\(state.range.title)屏幕时间去向" : "\(state.range.title)历史应用明细 · 已停止新记录"
        case .onlyAgent(let recordingEnabled):
            return recordingEnabled ? "\(state.range.title)仅有 Agent 工作记录" : "前台应用记录已关闭 · 仅显示 Agent"
        case .disabledNoDetails:
            return "前台应用记录已关闭"
        case .waitingForDetails:
            return "\(state.range.title)尚未积累应用明细"
        }
    }

    private func heroPrimaryMetric(data: ApplicationInsights, agent: AgentActivitySummary, usageTotal: Double, mode: InsightsDisplayState) -> String {
        switch mode {
        case .hasDetails:
            return durationText(data.totalSeconds)
        case .onlyAgent:
            return durationText(agent.wallSeconds)
        case .disabledNoDetails, .waitingForDetails:
            return durationText(usageTotal)
        }
    }

    private func heroHeadline(data: ApplicationInsights, agent: AgentActivitySummary, usageTotal: Double, mode: InsightsDisplayState) -> String {
        switch mode {
        case .hasDetails(let recordingEnabled):
            let topLine: String
            if let top = data.byApplication.first {
                topLine = "\(top.name) 占了最多时间，共 \(durationText(top.seconds))（\(insightPercent(top.seconds, of: data.totalSeconds))）。"
            } else {
                topLine = "已记录 \(data.applicationCount) 个前台应用的停留时长。"
            }
            return recordingEnabled ? topLine : "\(topLine)当前已关闭记录，仅展示已保留的历史明细。"
        case .onlyAgent(let recordingEnabled):
            let base = "\(agent.sessions.count) 个 Agent 会话，合计会话工作 \(durationText(agent.sessionSeconds))。"
            return recordingEnabled
                ? "\(base)\(state.range.title)暂无前台应用明细。"
                : "\(base)前台应用记录已在偏好设置中关闭。"
        case .disabledNoDetails:
            if hasAnyAppHistory {
                return "\(state.range.title)没有已保存的前台应用明细；其他时段的历史仍已保留，可切换时段查看或在偏好设置中重新开启。"
            }
            if usageTotal > 0 {
                return "息间仍正常累计总使用时长，但已停止记录前台应用明细。"
            }
            return "前台应用记录已在偏好设置中关闭；开启后会在本机记录应用与类别分布。"
        case .waitingForDetails:
            if usageTotal > 0 {
                return "息间总计时已有记录，但\(state.range.title)尚未采到前台应用明细；继续使用应用后会自动汇总到这里。"
            }
            return "开始使用 Mac 后，这里会自动汇总前台应用的停留时段与类别分布。"
        }
    }

    private func heroBadge(data: ApplicationInsights, agent: AgentActivitySummary, usageTotal: Double, mode: InsightsDisplayState) -> some View {
        let title: String
        let value: String
        let caption: String

        switch mode {
        case .hasDetails(let recordingEnabled):
            title = "应用明细覆盖"
            value = coverageText(data, usageTotal: usageTotal)
            caption = recordingEnabled ? "与息间总计时相比" : "历史记录 · 新记录已停"
        case .onlyAgent:
            if usageTotal > 0 {
                title = "息间总计时"
                value = durationText(usageTotal)
                caption = "不含前台应用拆分"
            } else {
                title = "Agent 会话"
                value = "\(agent.sessions.count) 个"
                caption = agent.hostCount > 0 ? "含 \(agent.hostCount) 台远程机器" : "均为本机会话"
            }
        case .disabledNoDetails:
            title = "记录状态"
            value = "已关闭"
            caption = hasAnyAppHistory ? "已有历史已保留" : "仅统计总时长"
        case .waitingForDetails:
            title = "记录状态"
            value = "等待积累"
            caption = hasAnyAppHistory ? "其他时段已有历史" : "已开启本机记录"
        }

        return VStack(alignment: .trailing, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(caption)
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
        .accessibilityElement(children: .combine)
    }

    private func coverageText(_ data: ApplicationInsights, usageTotal: Double) -> String {
        guard usageTotal > 0 else { return "0%" }
        return insightPercent(data.totalSeconds, of: usageTotal)
    }

    private func categoryLegend(_ entries: [CategoryTime], total: Double) -> some View {
        InsightsWrapLayout(spacing: 14, lineSpacing: 8) {
            ForEach(entries) { entry in
                HStack(spacing: 7) {
                    Circle().fill(entry.category.color).frame(width: 7, height: 7)
                    Text(entry.category.title)
                    Text(insightPercent(entry.seconds, of: total))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func singleAppEmptyCard(recordingEnabled: Bool, hasAgentInRange: Bool) -> some View {
        let heading: String
        let detail: String
        let icon: String

        if !recordingEnabled {
            icon = "eye"
            heading = hasAnyAppHistory ? "\(state.range.title)暂无已保存的应用明细" : "已关闭前台应用记录"
            detail = hasAnyAppHistory
                ? "当前已停止记录新的应用与类别分布，此前积累的历史仍保存在本机。可切换至近 7 天或近 28 天查看，或前往偏好设置重新开启。"
                : "关闭开关后不会采集前台应用名称与类别构成，总使用时长与休息记录仍正常保留。"
        } else if hasAgentInRange {
            icon = "chart-line"
            heading = "\(state.range.title)暂无前台应用明细"
            detail = hasAnyAppHistory && state.range == .today
                ? "今日尚未记录到前台应用停留，上方已展示 Agent 工作时段。你也可以切换至近 7 天查看历史应用分布。"
                : "已开启本机前台应用记录；继续切换或使用桌面应用后，应用排行与类别构成会自动显示在这里。"
        } else {
            icon = "chart-line"
            heading = "\(state.range.title)还没有应用与类别明细"
            detail = hasAnyAppHistory && state.range == .today
                ? "今天还没有记录到前台应用停留，近 7 天或近 28 天已有历史数据。继续使用 Mac 后，今天的时间流会自动出现。"
                : "时间去向已开启，正常使用桌面应用一段时间后，这里会自动生成时间流、应用排行与类别构成。"
        }

        return HStack(alignment: .center, spacing: 16) {
            LineIcon(systemName: icon, size: 22)
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(heading)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                if hasAnyAppHistory && state.range == .today {
                    Button("查看近 7 天") {
                        withAnimation(animated ? .easeInOut(duration: 0.2) : nil) {
                            state.range = .week
                        }
                    }
                    .buttonStyle(SettingsButtonStyle())
                }
                if !recordingEnabled {
                    Button("前往偏好设置") {
                        model.page = .settings
                    }
                    .buttonStyle(SettingsButtonStyle(prominent: true))
                }
            }
        }
        .card(padding: 22)
    }

    private func facts(_ data: ApplicationInsights) -> some View {
        let switchValue = "\(data.switches) 次"
        let switchDetail: String
        if data.switches == 0 && data.applicationCount <= 1 {
            switchDetail = "当前仅停留在一个应用"
        } else if data.totalSeconds >= 600 {
            switchDetail = String(format: "每小时约 %.0f 次", data.switchesPerHour)
        } else {
            switchDetail = "积累十分钟后显示频率"
        }

        return HStack(spacing: 16) {
            factCard(
                icon: "app-window",
                title: "停留最久",
                value: data.byApplication.first?.name ?? "—",
                detail: data.byApplication.first.map { durationText($0.seconds) } ?? "应用名称只保存在本机"
            )
            factCard(
                icon: "arrow-left-right",
                title: "应用切换",
                value: switchValue,
                detail: switchDetail
            )
            factCard(
                icon: "timer",
                title: "最长停留",
                value: durationText(data.longestApplicationStretch),
                detail: "连续使用同一应用"
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
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
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
        .accessibilityElement(children: .combine)
    }

    private func agentWork(_ summary: AgentActivitySummary) -> some View {
        let hasSessions = !summary.sessions.isEmpty
        let isExpanded = state.agentExpandedOverride ?? hasSessions
        let statusDotColor: Color = {
            if !model.settings.hapiSyncEnabled { return Palette.secondary }
            if agentActivity.status.isError { return insightsWarningColor }
            if agentActivity.status.isHealthy { return Palette.green }
            return Palette.secondary
        }()
        let statusTitle = model.settings.hapiSyncEnabled ? agentActivity.status.title : "同步已关闭"
        let statusTextColor = (model.settings.hapiSyncEnabled && agentActivity.status.isError) ? insightsWarningColor : Palette.secondary

        return VStack(alignment: .leading, spacing: isExpanded ? 16 : 0) {
            Button {
                withAnimation(animated ? .easeInOut(duration: 0.18) : nil) {
                    state.agentExpandedOverride = !isExpanded
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    LineIcon(systemName: "terminal", size: 16)
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text("Agent 工作时间")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !isExpanded && hasSessions {
                        Text("\(durationText(summary.wallSeconds)) · \(summary.sessions.count) 个会话")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    } else if !isExpanded && !hasSessions {
                        Text("\(state.range.title)暂无会话")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6, height: 6)
                        Text(statusTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(statusTextColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.background, in: Capsule())
                    LineIcon(systemName: "chevron-down", size: 13)
                        .foregroundStyle(Palette.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Agent 工作时间，\(statusTitle)")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            .accessibilityHint(isExpanded ? "点击收起 Agent 工作时间卡片" : "点击展开查看说明与配置引导")

            if isExpanded {
                Divider().overlay(Palette.line)

                Text("来自 HAPI Hub；同一会话重复同步只计算一次，等待你回复的时间不计入。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if summary.sessions.isEmpty {
                    agentEmptyGuidance
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
                            agentSessionRow(session, interval: summary.interval)
                        }
                    }

                    if summary.sessions.count > 6 {
                        Text("另有 \(summary.sessions.count - 6) 个 Agent 会话")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, isExpanded ? 24 : 20)
        .padding(.vertical, isExpanded ? 20 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: isExpanded ? 22 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 22 : 18, style: .continuous)
                .stroke(Palette.line.opacity(0.7), lineWidth: 1)
        )
    }

    private var agentEmptyGuidance: some View {
        let message: String
        let primaryActionTitle: String?
        let showsSyncButton: Bool

        if !model.settings.hapiSyncEnabled {
            message = "HAPI 同步已关闭；已有 Agent 历史仍会保留。可在偏好设置中重新开启同步或关闭本模块。"
            primaryActionTitle = "前往偏好设置"
            showsSyncButton = false
        } else {
            switch agentActivity.status {
            case .notInstalled, .cliTooOld:
                message = "\(state.range.title)还没有可展示的 HAPI 会话；前往偏好设置安装或更新 hapi 并登录后，会自动汇总本机与其它机器。"
                primaryActionTitle = "前往安装与配置"
                showsSyncButton = false
            case .notSignedIn:
                message = "HAPI 尚未登录。在终端完成 hapi 登录后点击立即同步，即可汇总本机与其它机器的 Agent 会话；若暂不使用，可在偏好设置关闭此模块。"
                primaryActionTitle = "前往偏好设置"
                showsSyncButton = true
            default:
                message = "\(state.range.title)还没有可展示的 HAPI 会话；使用接入 HAPI 的 Agent 后会自动汇总到这里。"
                primaryActionTitle = "偏好设置"
                showsSyncButton = true
            }
        }

        return HStack(alignment: .center, spacing: 14) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if showsSyncButton {
                    Button("立即同步") { agentActivity.syncNow() }
                        .buttonStyle(SettingsButtonStyle())
                        .disabled(agentActivity.status == .checking || agentActivity.status == .syncing)
                }
                if let primaryActionTitle {
                    Button(primaryActionTitle) { model.page = .settings }
                        .buttonStyle(SettingsButtonStyle(prominent: !showsSyncButton))
                }
            }
        }
        .padding(.top, 2)
    }

    private func agentMetric(title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(Palette.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func agentSessionRow(_ session: AgentActivitySession, interval: DateInterval) -> some View {
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
            Text(durationText(session.seconds(in: interval)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func timeline(data: ApplicationInsights, agent: AgentActivitySummary, now: Date) -> some View {
        let isToday = state.range == .today
        let onlyAgentToday = isToday && data.totalSeconds == 0 && !agent.sessions.isEmpty
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isToday ? "今天的时间流" : "每天去了哪里")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        onlyAgentToday
                            ? "按 00:00–24:00 展示今日 Agent 工作时段"
                            : isToday
                                ? "按 00:00–24:00 展示实际记录时段，颜色对应应用类别"
                                : "\(state.range.dateSpanText(now: now)) · 按天叠加比较各类别时长"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                }
                Spacer()
                if data.totalSeconds > 0 {
                    Text("\(data.applicationCount) 个应用 · \(data.byCategory.count) 个类别")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Palette.background, in: Capsule())
                } else if onlyAgentToday {
                    Text("\(agent.sessions.count) 个 Agent 会话")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Palette.background, in: Capsule())
                }
            }
            if isToday {
                TimelineRibbon(
                    segments: model.engine.applicationSegments,
                    categories: data.byCategory,
                    appTotalSeconds: data.totalSeconds,
                    agentSessions: agent.sessions,
                    agentWallSeconds: agent.wallSeconds,
                    date: now
                )
            } else {
                let dailyPoints = ApplicationInsights.daily(
                    segments: model.engine.applicationSegments,
                    endingAt: now,
                    days: state.range.rawValue
                )
                CategoryDailyChart(
                    points: dailyPoints,
                    categories: data.byCategory,
                    totalSeconds: data.totalSeconds,
                    dateRangeText: state.range.dateSpanText(now: now),
                    days: state.range.rawValue
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 24)
    }

    private func applicationBreakdown(_ data: ApplicationInsights) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("应用去向")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("累计 \(durationText(data.totalSeconds))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .monospacedDigit()
            }
            VStack(spacing: 14) {
                ForEach(Array(data.byApplication.prefix(8))) { app in
                    ApplicationBreakdownRow(
                        app: app,
                        total: data.totalSeconds
                    )
                }
            }
            if data.byApplication.count > 8 {
                Text("另有 \(data.byApplication.count - 8) 个应用未展开")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 24)
    }

    private func categoryBreakdown(_ data: ApplicationInsights) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("类别构成")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(data.byCategory.count) 类")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .monospacedDigit()
            }
            HStack {
                Spacer()
                CategoryDonut(entries: data.byCategory, total: data.totalSeconds)
                    .frame(width: 150, height: 150)
                Spacer()
            }
            VStack(spacing: 11) {
                ForEach(data.byCategory) { entry in
                    HStack(spacing: 9) {
                        Circle().fill(entry.category.color).frame(width: 8, height: 8)
                        Text(entry.category.title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(insightPercent(entry.seconds, of: data.totalSeconds))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                        Text(durationText(entry.seconds))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .monospacedDigit()
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 24)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            LineIcon(systemName: "eye", size: 17)
                .foregroundStyle(Palette.accent)
            Text(
                model.settings.agentActivityEnabled
                    ? "应用去向只记录前台应用名称、粗略类别与停留时段，全部留在本机。HAPI 只读取 Agent 会话标题、项目路径、机器和时段，不保存 prompt、回复或代码内容；它连接到你自己的 HAPI Hub，不经过息间的服务器。"
                    : "应用去向只记录前台应用名称、粗略类别与停留时段，全部留在本机。"
            )
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
    }
}

private let insightsWarningColor = Color(nsColor: NSColor(
    name: NSColor.Name("local.still.insights.warning"),
    dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 245 / 255, green: 185 / 255, blue: 89 / 255, alpha: 1)
            : NSColor(srgbRed: 154 / 255, green: 91 / 255, blue: 0 / 255, alpha: 1)
    }
))

private struct InsightsWrapLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + layout.origins[index].x, y: bounds.minY + layout.origins[index].y),
                anchor: .topLeading,
                proposal: ProposedViewSize(layout.sizes[index])
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (origins: [CGPoint], sizes: [CGSize], size: CGSize) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let limit = width ?? sizes.reduce(0) { $0 + $1.width + spacing }
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > limit {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            maxWidth = max(maxWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, sizes, CGSize(width: width ?? maxWidth, height: y + rowHeight))
    }
}

private struct BreakdownCardsLayout: Layout {
    let spacing: CGFloat
    let trailingWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let widths = columnWidths(totalWidth: proposal.width ?? idealWidth(subviews))
        let sizes = measuredSizes(
            subviews,
            primaryWidth: widths.primary,
            trailingWidth: widths.trailing
        )
        return CGSize(
            width: widths.total,
            height: max(sizes.primary.height, sizes.trailing.height)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let widths = columnWidths(totalWidth: bounds.width)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: widths.primary,
                height: bounds.height
            )
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + widths.primary + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: widths.trailing,
                height: bounds.height
            )
        )
    }

    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        subviews[0].sizeThatFits(.unspecified).width + spacing + trailingWidth
    }

    private func columnWidths(totalWidth: CGFloat) -> (total: CGFloat, primary: CGFloat, trailing: CGFloat) {
        let safeWidth = max(0, totalWidth)
        let trailing = min(trailingWidth, safeWidth)
        let primary = max(0, safeWidth - trailing - spacing)
        return (safeWidth, primary, trailing)
    }

    private func measuredSizes(
        _ subviews: Subviews,
        primaryWidth: CGFloat,
        trailingWidth: CGFloat
    ) -> (primary: CGSize, trailing: CGSize) {
        (
            subviews[0].sizeThatFits(
                ProposedViewSize(width: primaryWidth, height: nil)
            ),
            subviews[1].sizeThatFits(
                ProposedViewSize(width: trailingWidth, height: nil)
            )
        )
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
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        entries.map { entry in
            "\(entry.category.title) \(insightPercent(entry.seconds, of: total))（\(durationText(entry.seconds))）"
        }.joined(separator: "，")
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
    let categories: [CategoryTime]
    let appTotalSeconds: Double
    let agentSessions: [AgentActivitySession]
    let agentWallSeconds: Double
    let date: Date

    var body: some View {
        let window = DayTimelineWindow(date: date, now: date)
        let visibleApps = segments.compactMap { segment -> (segment: ApplicationUsageSegment, start: Date, end: Date)? in
            guard let end = window.visibleEnd(for: segment.startedAt, end: segment.endedAt) else { return nil }
            let start = max(segment.startedAt, window.visible.start)
            return (segment, start, end)
        }
        let visibleAgentSpans = agentSessions.flatMap { session in
            session.spans.compactMap { span -> (id: String, start: Date, end: Date)? in
                guard let end = window.visibleEnd(for: span.startedAt, end: span.endedAt) else { return nil }
                let start = max(span.startedAt, window.visible.start)
                return ("\(session.id)-\(span.id.uuidString)", start, end)
            }
        }

        let hasAppLane = !visibleApps.isEmpty
        let hasAgentLane = !visibleAgentSpans.isEmpty
        let laneCount = (hasAppLane ? 1 : 0) + (hasAgentLane ? 1 : 0)
        let laneHeight: CGFloat = 26
        let laneGap: CGFloat = 8
        let trackHeight: CGFloat = laneCount == 2 ? laneHeight * 2 + laneGap : laneHeight
        let agentYOffset: CGFloat = hasAppLane ? laneHeight + laneGap : 0

        let appSpanText = timeRangeText(
            starts: visibleApps.map(\.start),
            ends: visibleApps.map(\.end)
        )
        let agentSpanText = timeRangeText(
            starts: visibleAgentSpans.map(\.start),
            ends: visibleAgentSpans.map(\.end)
        )
        let gridColor = Palette.surface.opacity(0.9)
        let agentColor = Palette.green.opacity(0.82)

        VStack(alignment: .leading, spacing: 11) {
            if let summaryText = visibleSummaryText(appSpan: appSpanText, agentSpan: agentSpanText) {
                HStack(spacing: 8) {
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 9) {
                Canvas { context, size in
                    context.fill(
                        Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8),
                        with: .color(Palette.background)
                    )
                    for hour in 0..<24 {
                        if let mark = Calendar.current.date(byAdding: .hour, value: hour, to: window.day.start),
                           mark <= window.visible.end {
                            let x = size.width * window.fraction(for: mark)
                            context.fill(Path(CGRect(x: x, y: 0, width: 1, height: trackHeight)), with: .color(gridColor))
                        }
                    }
                    if hasAppLane {
                        for item in visibleApps {
                            let x = size.width * item.start.timeIntervalSince(window.visible.start) / window.day.duration
                            let width = max(2, size.width * item.end.timeIntervalSince(item.start) / window.day.duration)
                            let rect = CGRect(x: x, y: 0, width: width, height: laneHeight)
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 4),
                                with: .color(item.segment.category.color.opacity(0.86))
                            )
                        }
                    }
                    if hasAgentLane {
                        for item in visibleAgentSpans {
                            let x = size.width * item.start.timeIntervalSince(window.visible.start) / window.day.duration
                            let width = max(2, size.width * item.end.timeIntervalSince(item.start) / window.day.duration)
                            let rect = CGRect(x: x, y: agentYOffset, width: width, height: laneHeight)
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 4),
                                with: .color(agentColor)
                            )
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(height: trackHeight)

                GeometryReader { proxy in
                    ForEach(window.marks(), id: \.self) { mark in
                        Text(mark == window.day.end ? "24:00" : timelineTimeText(mark))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 46)
                            .position(
                                x: min(max(23, proxy.size.width * window.fraction(for: mark)), proxy.size.width - 23),
                                y: 7
                            )
                    }
                }
                .frame(height: 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle(hasAppLane: hasAppLane, hasAgentLane: hasAgentLane))
            .accessibilityValue(accessibilitySummary(appSpan: appSpanText, agentSpan: agentSpanText))

            if hasAppLane || hasAgentLane {
                InsightsWrapLayout(spacing: 14, lineSpacing: 8) {
                    if hasAppLane && hasAgentLane {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 10, height: 6)
                            Text("上轨：前台应用")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if hasAppLane {
                        ForEach(categories) { entry in
                            HStack(spacing: 6) {
                                Circle().fill(entry.category.color).frame(width: 7, height: 7)
                                Text(entry.category.title)
                                Text(durationText(entry.seconds))
                                    .foregroundStyle(Palette.secondary)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 11))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if hasAgentLane {
                        HStack(spacing: 6) {
                            Circle().fill(Palette.green).frame(width: 7, height: 7)
                            Text(hasAppLane ? "下轨：Agent" : "Agent 工作时段")
                                .fontWeight(.medium)
                                .foregroundStyle(Palette.ink)
                            Text(durationText(agentWallSeconds))
                                .foregroundStyle(Palette.secondary)
                                .monospacedDigit()
                        }
                        .font(.system(size: 11))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func timeRangeText(starts: [Date], ends: [Date]) -> String? {
        guard let first = starts.min(), let last = ends.max() else { return nil }
        return "\(timelineTimeText(first))–\(timelineTimeText(last))"
    }

    private func visibleSummaryText(appSpan: String?, agentSpan: String?) -> String? {
        var parts: [String] = []
        if let appSpan {
            parts.append("前台应用实际时段 \(appSpan)（共 \(durationText(appTotalSeconds))）")
        }
        if let agentSpan {
            parts.append("Agent 时段 \(agentSpan)（墙钟 \(durationText(agentWallSeconds))）")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func accessibilityTitle(hasAppLane: Bool, hasAgentLane: Bool) -> String {
        if hasAppLane && hasAgentLane { return "今日应用与 Agent 时间流" }
        if hasAgentLane { return "今日 Agent 时间流" }
        return "今日应用时间流"
    }

    private func accessibilitySummary(appSpan: String?, agentSpan: String?) -> String {
        var parts: [String] = []
        if let appSpan {
            let categoryText = categories.map { "\($0.category.title) \(durationText($0.seconds))" }.joined(separator: "，")
            parts.append("前台应用时段 \(appSpan)，累计 \(durationText(appTotalSeconds))，包含\(categoryText)")
        }
        if let agentSpan {
            parts.append("Agent 时段 \(agentSpan)，\(agentSessions.count) 个会话，墙钟 \(durationText(agentWallSeconds))")
        }
        return parts.isEmpty ? "暂无记录" : parts.joined(separator: "；")
    }
}

private struct CategoryDailyChart: View {
    private struct LegendEntry: Identifiable {
        let category: ApplicationCategory
        let seconds: Double
        var id: String { category.rawValue }
    }

    let points: [DailyCategoryTime]
    let categories: [CategoryTime]
    let totalSeconds: Double
    let dateRangeText: String
    let days: Int

    var body: some View {
        let orderedCategories: [LegendEntry] = categories.isEmpty
            ? ApplicationCategory.allCases.compactMap { category -> LegendEntry? in
                let total = points.filter { $0.category == category }.reduce(0) { $0 + $1.seconds }
                return total > 0 ? LegendEntry(category: category, seconds: total) : nil
            }.sorted { $0.seconds > $1.seconds }
            : categories.map { LegendEntry(category: $0.category, seconds: $0.seconds) }

        let dailyTotals = Dictionary(grouping: points, by: \.date).map { (date: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }
        let activeDays = dailyTotals.filter { $0.seconds > 0 }.count
        let peakDay = dailyTotals.max { $0.seconds < $1.seconds }

        VStack(alignment: .leading, spacing: 12) {
            Text(summaryLine(activeDays: activeDays, peakDay: peakDay))
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .monospacedDigit()

            Chart(points) { point in
                BarMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("分钟", point.seconds / 60)
                )
                .foregroundStyle(by: .value("类别", point.category.title))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(
                domain: orderedCategories.map(\.category.title),
                range: orderedCategories.map(\.category.color)
            )
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: days == 28 ? 7 : 1)) { _ in
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
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("每日类别时间分布图")
            .accessibilityValue(chartAccessibilityValue(activeDays: activeDays, peakDay: peakDay, categories: orderedCategories))

            InsightsWrapLayout(spacing: 14, lineSpacing: 8) {
                ForEach(orderedCategories) { entry in
                    HStack(spacing: 6) {
                        Circle().fill(entry.category.color).frame(width: 7, height: 7)
                        Text(entry.category.title)
                        Text(insightPercent(entry.seconds, of: totalSeconds))
                            .foregroundStyle(Palette.secondary)
                            .monospacedDigit()
                        Text(durationText(entry.seconds))
                            .foregroundStyle(Palette.secondary)
                            .monospacedDigit()
                    }
                    .font(.system(size: 11))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func summaryLine(activeDays: Int, peakDay: (date: Date, seconds: Double)?) -> String {
        var parts = ["范围 \(dateRangeText)", "有记录 \(activeDays)/\(days) 天"]
        if let peakDay, peakDay.seconds > 0 {
            let dayText = peakDay.date.formatted(.dateTime.month(.defaultDigits).day())
            parts.append("峰值 \(dayText) \(durationText(peakDay.seconds))")
        }
        return parts.joined(separator: " · ")
    }

    private func chartAccessibilityValue(
        activeDays: Int,
        peakDay: (date: Date, seconds: Double)?,
        categories: [LegendEntry]
    ) -> String {
        var parts = ["统计范围 \(dateRangeText)，共 \(activeDays) 天有记录，累计 \(durationText(totalSeconds))"]
        if let peakDay, peakDay.seconds > 0 {
            let dayText = peakDay.date.formatted(.dateTime.month(.defaultDigits).day())
            parts.append("最高为 \(dayText) \(durationText(peakDay.seconds))")
        }
        if !categories.isEmpty {
            let breakdown = categories.map { "\($0.category.title) \(durationText($0.seconds))" }.joined(separator: "，")
            parts.append("分类合计：\(breakdown)")
        }
        return parts.joined(separator: "；")
    }
}

private struct ApplicationBreakdownRow: View {
    let app: ApplicationTime
    let total: Double

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
                            .frame(width: max(2, proxy.size.width * app.seconds / max(total, 1)))
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
        .accessibilityElement(children: .combine)
    }
}

private struct CategoryDonut: View {
    let entries: [CategoryTime]
    let total: Double

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
                Text("应用时间").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("类别构成环形图")
        .accessibilityValue("应用总时长 \(durationText(total))，共 \(entries.count) 个类别")
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
        let displayed = state.image ?? ApplicationIconCache.shared.cachedIcon(for: bundleID)
        Group {
            if let image = displayed {
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
        .task(id: bundleID) {
            if let cached = ApplicationIconCache.shared.cachedIcon(for: bundleID) {
                state.image = cached
                return
            }
            let icon = await ApplicationIconCache.shared.loadIcon(for: bundleID)
            guard !Task.isCancelled else { return }
            state.image = icon
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private final class ApplicationIconState: ObservableObject {
    @Published var image: NSImage?
}

@MainActor
private final class ApplicationIconCache {
    static let shared = ApplicationIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private var missing = Set<String>()
    private var pending: [String: Task<CGImage?, Never>] = [:]

    func cachedIcon(for bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        return cache.object(forKey: bundleID as NSString)
    }

    func loadIcon(for bundleID: String) async -> NSImage? {
        guard !bundleID.isEmpty, !missing.contains(bundleID) else { return nil }
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let task = pending[bundleID] ?? Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
            return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        pending[bundleID] = task
        let cgImage = await task.value
        pending[bundleID] = nil
        if let cached = cache.object(forKey: key) { return cached }
        if let cgImage {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: 64, height: 64))
            cache.setObject(image, forKey: key)
            return image
        } else {
            missing.insert(bundleID)
            return nil
        }
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

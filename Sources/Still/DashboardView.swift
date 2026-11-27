import SwiftUI
import StillCore

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var allowsMotion: Bool { !reduceMotion && model.settings.motionEnabled }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 185)
                .animation(allowsMotion ? .easeOut(duration: 0.14) : nil, value: model.page)
            Group {
                if model.page == .courses {
                    VStack(spacing: 0) {
                        CoursesView(model: model, library: model.library, player: model.coursePlayer)
                        if let error = model.storageError {
                            Text(error).font(.system(size: 13)).foregroundStyle(Palette.warning).padding(12)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        EdgeFadeScrollView(fadeLength: 36, fadeThreshold: 24) {
                            VStack(alignment: .leading, spacing: 25) {
                                switch model.page {
                                case .posture: PostureView(model: model, monitor: model.posture)
                                case .courses: EmptyView()
                                case .today: TodayView(model: model)
                                case .insights: InsightsView(model: model)
                                case .history: HistoryView(model: model)
                                case .rules: RulesView(model: model)
                                case .settings: PreferencesView(model: model)
                                }
                                if let error = model.storageError {
                                    LineLabel(error + "。当前会话可继续计时，请先导出记录并检查磁盘。", systemImage: "exclamationmark.triangle")
                                        .font(.system(size: 13)).foregroundStyle(Palette.warning).padding(12)
                                        .background(Palette.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                }
                                if let error = model.reminderError, model.page != .rules {
                                    LineLabel(error, systemImage: "triangle-alert").font(.system(size: 13)).foregroundStyle(Palette.warning)
                                }
                            }
                            .padding(.horizontal, 32).padding(.top, 38).padding(.bottom, 24)
                            .frame(maxWidth: 1040, alignment: .leading)
                            .frame(maxWidth: .infinity)
                        }
                        .id(model.page)
                        .onChange(of: model.updatesRequest) { request in
                            guard request > 0 else { return }
                            DispatchQueue.main.async { proxy.scrollTo("app-updates", anchor: .bottom); model.updatesRequest = 0 }
                        }
                        .onAppear {
                            if model.page == .settings && model.updatesRequest > 0 {
                                DispatchQueue.main.async { proxy.scrollTo("app-updates", anchor: .bottom); model.updatesRequest = 0 }
                            }
                        }
                    }
                }
            }
            .background(Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Palette.line.opacity(0.9), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .padding(.vertical, 10)
        }
        .foregroundStyle(Palette.ink).tint(Palette.accent)
        .frame(minWidth: 1020, minHeight: 720)
        .background(Palette.sidebar)
        .environment(\.stillMotionEnabled, model.settings.motionEnabled)
        .transaction { if !model.settings.motionEnabled { $0.disablesAnimations = true } }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                FlowerView(isAnimating: false, compact: true).frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("息间").font(.system(size: 22, weight: .semibold, design: .rounded)).tracking(2)
                }
            }.padding(.leading, 18).padding(.top, 55).padding(.bottom, 40)
            ForEach([Page.today, .insights, .courses, .history, .rules].filter { $0 != .courses || model.settings.coursesEnabled }, id: \.self) { page in
                navItem(page)
            }
            if model.settings.postureEnabled { navItem(.posture) }
            Spacer(minLength: 35)
            navItem(.settings)
                .padding(.bottom, 24)
            if model.isUITest { Text("体验模式").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.horizontal, 28).padding(.bottom, 14) }
        }
        .background(Palette.sidebar)
    }

    private func navItem(_ page: Page) -> some View {
        let isSelected = model.page == page
        return Button {
            if page == .courses {
                model.coursePlayer.pause()
                model.library.selectedID = nil
            }
            if model.page != page {
                model.page = page
            }
        } label: {
            HStack(spacing: 12) {
                LineIcon(systemName: page.icon, size: 19).frame(width: 20)
                    .accessibilityHidden(true)
                Text(page.rawValue).font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer()
                if isSelected {
                    Capsule().fill(Palette.accent).frame(width: 4, height: 14)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? Palette.accentDark : Palette.secondary)
            .padding(.horizontal, 15).padding(.vertical, 14)
            .background(isSelected ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Palette.selectionBorder.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SelectableCardButtonStyle())
        .accessibilityLabel(page.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .padding(.horizontal, 14).padding(.bottom, 5)
    }
}

struct TodayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var liveClock: LiveEngineClock

    @MainActor
    init(model: AppModel) {
        self.model = model
        _liveClock = ObservedObject(wrappedValue: model.liveClock)
    }

    var body: some View {
        let _ = liveClock.tick
        let now = model.engine.now
        let todaySummary = model.today
        let longest = model.longestToday
        let window = DayTimelineWindow(date: now, now: now)
        let visibleSegments = model.engine.segments.filter { $0.seconds(in: window.visible) > 0 }
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("今日概览")
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    StatusBadge(title: model.engine.phase.title, active: ![.paused, .suspended, .away].contains(model.engine.phase))
                }
            }
            hero
            HStack(spacing: 16) {
                stat(icon: "desktopcomputer", title: "今日使用", seconds: todaySummary.seconds, tint: Palette.accent)
                stat(icon: "leaf", title: "完成休息", count: todaySummary.completedBreaks, tint: Palette.green)
                    .help("包括完成的休息倒计时与自然离开")
                stat(icon: "hourglass", title: "最长一轮", seconds: longest, tint: Color(hex: 0xB38B60))
                    .help("同一轮累计使用时长，充分休息后开始新一轮")
            }
            timeline(todaySeconds: todaySummary.seconds, visibleSegments: visibleSegments, now: now)
        }
    }

    private var hero: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    LineIcon(systemName: model.engine.phase == .resting ? "leaf" : "circle.dotted").font(.system(size: 14))
                        .accessibilityHidden(true)
                    Text(model.countdownTitle).font(.system(size: 14, weight: .medium))
                }.foregroundStyle(Palette.accentDark).padding(.bottom, 9)
                Text(clockText(model.countdown))
                    .font(.system(size: 65, weight: .light, design: .rounded)).monospacedDigit().tracking(-2)
                    .accessibilityLabel("\(model.countdownTitle)，\(clockText(model.countdown))")
                HStack(spacing: 7) {
                    Text("本轮 \(durationText(model.engine.roundSeconds))")
                    Text("·").foregroundStyle(Palette.secondary.opacity(0.6))
                    Text("每轮 \(model.settings.workMinutes) 分钟")
                    if model.engine.trackingPaused {
                        Text("·").foregroundStyle(Palette.secondary.opacity(0.6))
                        Text("统计已暂停")
                    } else if !model.settings.remindersEnabled {
                        Text("·").foregroundStyle(Palette.secondary.opacity(0.6))
                        Text("提醒已暂停，仍记录使用")
                    }
                }.font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 7)
                HStack(spacing: 12) {
                    Button { model.startRest() } label: { LineLabel(model.engine.phase == .resting ? "查看休息" : "现在休息", systemImage: "leaf") }.buttonStyle(SoftButtonStyle(prominent: true))
                    Button { model.toggleReminders() } label: {
                        LineLabel(model.settings.remindersEnabled ? "暂停提醒" : "恢复提醒", systemImage: model.settings.remindersEnabled ? "bell.slash" : "bell")
                    }
                    .buttonStyle(SoftButtonStyle(prominent: false))
                    .help(model.settings.remindersEnabled ? "仅暂停休息提醒，使用统计仍会继续；如需暂停统计请前往偏好设置" : "恢复休息提醒")
                    .accessibilityHint("仅影响休息提醒，不影响使用统计")
                }.padding(.top, 23)
            }.padding(.leading, 24).padding(.vertical, 24)
            Spacer(minLength: 8)
            FatigueGauge(progress: model.engine.progress, percent: model.engine.fatiguePercent,
                         animate: model.settings.motionEnabled && model.appIsActive)
                .frame(width: 190, height: 214).padding(.trailing, 30).padding(.vertical, 15)
        }
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Palette.heroStart, Palette.heroMiddle, Palette.heroEnd], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(Palette.line.opacity(0.8), lineWidth: 1))
    }

    private func stat(icon: String, title: String, seconds: Double? = nil, count: Int? = nil, tint: Color) -> some View {
        let totalSeconds = max(0, seconds ?? 0)
        let accessibleValue = count.map { "\($0) 次" } ?? durationText(totalSeconds)
        return HStack(alignment: .center, spacing: 14) {
            LineIcon(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let count {
                        Text("\(count)").font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("次").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    } else {
                        let minutes = Int(totalSeconds) / 60
                        if totalSeconds > 0 && minutes == 0 {
                            Text("不足 1").font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("分钟").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        } else if minutes >= 60 {
                            Text("\(minutes / 60)").font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("时").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                            Text(String(format: "%02d", minutes % 60)).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("分").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        } else {
                            Text("\(minutes)").font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("分钟").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.vertical, 21)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Palette.line.opacity(0.8), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibleValue)
    }

    private func timeline(todaySeconds: Double, visibleSegments: [UsageSegment], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("使用时段").font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Circle().fill(Palette.accent.opacity(0.82)).frame(width: 6, height: 6)
                        Text("活动估算")
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Palette.green.opacity(0.82)).frame(width: 6, height: 6)
                        Text("持续阅读")
                    }
                }
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .accessibilityHidden(true)
            }
            DayTimeline(segments: visibleSegments, date: now)
            if todaySeconds <= 0 && visibleSegments.isEmpty {
                Text("暂无使用记录")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            } else if todaySeconds > 0 && todaySeconds < 60 {
                Text("今日已记录 \(durationText(todaySeconds))，继续使用后将逐步展开时段")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }.card(padding: 24)
    }
}

struct DayTimeline: View {
    let segments: [UsageSegment]
    let date: Date
    var body: some View {
        let window = DayTimelineWindow(date: date, now: date)
        let visibleSegments = segments.filter { $0.seconds(in: window.visible) > 0 }
        let activityColor = Palette.accent.opacity(0.82)
        let readingColor = Palette.green.opacity(0.8)
        let gridColor = Palette.surface.opacity(0.9)
        VStack(spacing: 9) {
            Canvas { context, size in
                let trackRect = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: trackRect, cornerRadius: 6), with: .color(Palette.background))
                for hour in 0..<24 {
                    if let mark = Calendar.current.date(byAdding: .hour, value: hour, to: window.day.start),
                       mark <= window.visible.end {
                        let x = size.width * window.fraction(for: mark)
                        context.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(gridColor))
                    }
                }
                for segment in visibleSegments {
                    guard let end = window.visibleEnd(for: segment.startedAt, end: segment.endedAt) else { continue }
                    let start = max(segment.startedAt, window.visible.start)
                    let x = size.width * start.timeIntervalSince(window.visible.start) / window.day.duration
                    let width = max(2, size.width * end.timeIntervalSince(start) / window.day.duration)
                    let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(segment.mode == .reading ? readingColor : activityColor)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(height: 18)
            GeometryReader { geo in
                ForEach(window.marks(), id: \.self) { mark in
                    Text(mark == window.day.end ? "24:00" : timelineTimeText(mark))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 48)
                        .position(
                            x: min(max(24, geo.size.width * window.fraction(for: mark)), geo.size.width - 24),
                            y: 7
                        )
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日使用时间分布")
        .accessibilityValue(accessibilitySummary(visibleSegments: visibleSegments, window: window))
    }

    private func accessibilitySummary(visibleSegments: [UsageSegment], window: DayTimelineWindow) -> String {
        guard !visibleSegments.isEmpty else { return "暂无使用记录" }
        var totalSeconds = 0.0
        var activitySeconds = 0.0
        var readingSeconds = 0.0
        var earliest: Date?
        var latest: Date?
        for segment in visibleSegments {
            guard let end = window.visibleEnd(for: segment.startedAt, end: segment.endedAt) else { continue }
            let start = max(segment.startedAt, window.visible.start)
            let span = max(0, end.timeIntervalSince(start))
            guard span > 0 else { continue }
            totalSeconds += span
            if segment.mode == .reading { readingSeconds += span } else { activitySeconds += span }
            earliest = earliest.map { min($0, start) } ?? start
            latest = latest.map { max($0, end) } ?? end
        }
        guard totalSeconds > 0, let earliest, let latest else { return "暂无使用记录" }
        let range = "\(timelineTimeText(earliest)) 至 \(timelineTimeText(latest))"
        var parts = ["共 \(visibleSegments.count) 段", range, "合计 \(durationText(totalSeconds))"]
        if readingSeconds > 0 && activitySeconds > 0 {
            parts.append("活动估算 \(durationText(activitySeconds))，持续阅读 \(durationText(readingSeconds))")
        } else if readingSeconds > 0 {
            parts.append("模式为持续阅读")
        } else {
            parts.append("模式为活动估算")
        }
        return parts.joined(separator: "，")
    }
}

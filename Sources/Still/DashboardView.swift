import SwiftUI
import StillCore

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 185)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    switch model.page {
                    case .today: TodayView(model: model)
                    case .history: HistoryView(model: model)
                    case .rules: RulesView(model: model)
                    case .settings: PreferencesView(model: model)
                    }
                    if let error = model.storageError {
                        LineLabel(error + "。当前会话可继续计时，请先导出记录并检查磁盘。", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13)).foregroundStyle(Color.orange).padding(12)
                            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let error = model.reminderError, model.page != .rules {
                        LineLabel(error, systemImage: "triangle-alert").font(.system(size: 13)).foregroundStyle(Color.orange)
                    }
                }
                .padding(.horizontal, 32).padding(.top, 38).padding(.bottom, 24)
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
        }
        .foregroundStyle(Palette.ink).tint(Palette.accent)
        .frame(minWidth: 1020, minHeight: 720)
        .background(Palette.background)
        .environment(\.colorScheme, .light)
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
            ForEach([Page.today, .history, .rules], id: \.self) { page in
                navItem(page)
            }
            Spacer(minLength: 35)
            navItem(.settings)
                .padding(.bottom, 24)
            if model.isUITest { Text("体验模式").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.horizontal, 28).padding(.bottom, 14) }
        }
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.line.opacity(0.8)).frame(width: 1) }
    }

    private func navItem(_ page: Page) -> some View {
        Button {
            withAnimation(reduceMotion || !model.settings.motionEnabled ? nil : .easeInOut(duration: 0.22)) { model.page = page }
        } label: {
            HStack(spacing: 12) {
                LineIcon(systemName: page.icon, size: 19).frame(width: 20)
                Text(page.rawValue).font(.system(size: 14, weight: model.page == page ? .semibold : .regular))
                Spacer()
                if model.page == page { Circle().fill(Palette.accent).frame(width: 4, height: 4) }
            }
            .foregroundStyle(model.page == page ? Palette.accentDark : Palette.secondary)
            .padding(.horizontal, 15).padding(.vertical, 14)
            .background(model.page == page ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 5)
    }
}

struct TodayView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.engine.now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
                    Text("今日概览").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.6)
                }
                Spacer()
                StatusBadge(title: model.engine.phase.title, active: ![.paused, .suspended, .away].contains(model.engine.phase)).padding(.top, 23)
            }
            hero
            HStack(spacing: 16) {
                stat(icon: "desktopcomputer", title: "今日使用", seconds: model.today.seconds, tint: Palette.accent)
                stat(icon: "leaf", title: "完成休息", count: model.today.completedBreaks, tint: Palette.green)
                    .help("包括完成的休息倒计时与自然离开")
                stat(icon: "hourglass", title: "最长一轮", seconds: model.longestToday, tint: Color(hex: 0xB38B60))
                    .help("同一轮累计使用时长，充分休息后开始新一轮")
            }
            timeline
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.lavender).frame(width: 42, height: 42)
                    LineIcon(systemName: "book.closed").font(.system(size: 18, weight: .light)).foregroundStyle(Palette.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("持续阅读").font(.system(size: 14, weight: .medium))
                    Text("没有键鼠操作时继续计时。").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Toggle("持续阅读", isOn: Binding(get: { model.settings.mode == .reading }, set: { model.settings.mode = $0 ? .reading : .activity }))
                    .labelsHidden().toggleStyle(.switch).font(.system(size: 13)).fixedSize()
            }.card(padding: 20)
        }
    }

    private var hero: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    LineIcon(systemName: model.engine.phase == .resting ? "leaf" : "circle.dotted").font(.system(size: 14))
                    Text(model.countdownTitle).font(.system(size: 14, weight: .medium))
                }.foregroundStyle(Palette.accentDark).padding(.bottom, 9)
                Text(clockText(model.countdown))
                    .font(.system(size: 65, weight: .light, design: .rounded)).monospacedDigit().tracking(-2)
                    .accessibilityLabel("\(model.countdownTitle)，\(clockText(model.countdown))")
                HStack(spacing: 7) {
                    Text("本轮 \(durationText(model.engine.roundSeconds))")
                    Text("·").foregroundStyle(Palette.secondary.opacity(0.5))
                    Text("每轮 \(model.settings.workMinutes) 分钟")
                }.font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 7)
                HStack(spacing: 12) {
                    Button { model.startRest() } label: { LineLabel(model.engine.phase == .resting ? "查看休息" : "现在休息", systemImage: "leaf") }.buttonStyle(SoftButtonStyle(prominent: true))
                    Button { model.toggleReminders() } label: {
                        HStack(spacing: 7) {
                            LineIcon(systemName: model.settings.remindersEnabled ? "bell.slash" : "bell").frame(width: 14)
                            Text(model.settings.remindersEnabled ? "暂停提醒" : "恢复提醒")
                        }.padding(.horizontal, 8).padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                }.padding(.top, 23)
            }.padding(.leading, 24).padding(.vertical, 24)
            Spacer(minLength: 8)
            FatigueGauge(progress: model.engine.progress, percent: model.engine.fatiguePercent,
                         animate: model.settings.motionEnabled && model.appIsActive)
                .frame(width: 190, height: 214).padding(.trailing, 30).padding(.vertical, 15)
        }
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0xF0EDFB), Color(hex: 0xF2F2FA), Color(hex: 0xE9F1F0)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.white.opacity(0.8), lineWidth: 1))
    }

    private func stat(icon: String, title: String, seconds: Double? = nil, count: Int? = nil, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            LineIcon(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let count {
                        Text("\(count)").font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("次").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    } else {
                        let minutes = max(0, Int(seconds ?? 0) / 60)
                        if minutes >= 60 {
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
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("使用时段").font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) { Circle().fill(Palette.accent.opacity(0.75)).frame(width: 5, height: 5); Text(model.settings.mode.title) }
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            DayTimeline(segments: model.engine.segments, date: model.engine.now)
            if model.today.seconds < 60 {
                Text("暂无使用记录")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }.card(padding: 24)
    }
}

struct DayTimeline: View {
    let segments: [UsageSegment]
    let date: Date
    var body: some View {
        let interval = Calendar.current.dateInterval(of: .day, for: date)!
        VStack(spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Palette.background)
                    ForEach(0..<24, id: \.self) { hour in
                        Rectangle().fill(Color.white).frame(width: 2).offset(x: geo.size.width * Double(hour) / 24)
                    }
                    ForEach(segments.filter { $0.seconds(in: interval) > 0 }) { segment in
                        let start = max(segment.startedAt, interval.start)
                        let end = min(segment.endedAt, interval.end)
                        let length = interval.duration
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segment.mode == .reading ? Palette.green.opacity(0.65) : Palette.accent.opacity(0.7))
                            .frame(width: max(2, geo.size.width * end.timeIntervalSince(start) / length), height: 18)
                            .offset(x: geo.size.width * start.timeIntervalSince(interval.start) / length)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 6))
            }.frame(height: 18)
            HStack { ForEach(["00:00", "06:00", "12:00", "18:00", "24:00"], id: \.self) { label in
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary.opacity(0.8))
                if label != "24:00" { Spacer() }
            } }
        }.accessibilityElement(children: .ignore).accessibilityLabel("今日使用时间分布")
    }
}

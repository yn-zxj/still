import SwiftUI
import Charts
import StillCore

struct HistoryView: View {
    @ObservedObject var model: AppModel
    private var days: Int { model.historyDays }
    private var summaries: [DailySummary] { UsageStatistics.daily(segments: model.engine.segments, breaks: model.engine.breaks, endingAt: model.engine.now, days: days) }
    private var chartInHours: Bool { (summaries.map(\.seconds).max() ?? 0) >= 3600 }
    private var chartUnit: Double { chartInHours ? 3600 : 60 }
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                SectionHeading(title: "使用记录")
                Spacer()
                Button { model.exportCSV() } label: { LineLabel("导出记录", systemImage: "square.and.arrow.up") }.buttonStyle(SoftButtonStyle())
            }
            HStack(spacing: 16) {
                metric("累计使用", durationText(summaries.reduce(0) { $0 + $1.seconds }), "过去 \(days) 天")
                metric("日均使用", durationText(summaries.reduce(0) { $0 + $1.seconds } / Double(days)), "包含未使用的日期")
                metric("完成休息", "\(summaries.reduce(0) { $0 + $1.completedBreaks }) 次", "完成次数")
            }
            VStack(alignment: .leading, spacing: 27) {
                HStack {
                    Text("使用时长 · \(chartInHours ? "小时" : "分钟")").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Picker("时间范围", selection: $model.historyDays) { Text("近 7 天").tag(7); Text("近 28 天").tag(28) }
                        .labelsHidden().pickerStyle(.segmented).controlSize(.large).frame(width: 190)
                }
                Chart(summaries) { summary in
                    BarMark(x: .value("日期", summary.date, unit: .day), y: .value(chartInHours ? "小时" : "分钟", summary.seconds / chartUnit))
                        .foregroundStyle(Calendar.current.isDateInToday(summary.date) ? Palette.accent : Palette.accent.opacity(0.25))
                        .cornerRadius(5)
                }
                .chartYScale(domain: 0...max(chartInHours ? 1 : 5, ceil((summaries.map(\.seconds).max() ?? 0) / chartUnit)))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 4)) { value in
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Palette.line); AxisValueLabel().font(.system(size: 12)).foregroundStyle(Palette.secondary) } }
                .frame(height: 225)
                if summaries.allSatisfy({ $0.seconds < 1 }) {
                    LineLabel("暂无使用记录", systemImage: "sparkle").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                }
            }.card(padding: 26)
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("最近的休息").font(.system(size: 15, weight: .semibold)); Spacer()
                }
                let recent = Array(model.engine.breaks.suffix(6).reversed())
                if recent.isEmpty {
                    HStack(spacing: 15) {
                        LineIcon(systemName: "leaf.circle").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Palette.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("还没有休息记录").font(.system(size: 14, weight: .medium))
                            Text("完成一次倒计时，或自然离开足够久，就会记录在这里。")
                                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                    }.padding(.vertical, 18)
                } else {
                    ForEach(recent) { record in
                        HStack(spacing: 12) {
                            LineIcon(systemName: record.outcome == .completed ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(record.outcome == .completed ? Palette.green : Palette.secondary)
                            Text(record.source == .natural ? "自然离开" : "休息倒计时").font(.system(size: 14))
                            Text(record.startedAt.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                            Spacer()
                            Text(outcomeLabel(record.outcome)).font(.system(size: 13)).foregroundStyle(record.outcome == .completed ? Palette.green : Palette.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }.card(padding: 24)
            if let message = model.exportMessage { Text(message).font(.system(size: 13)).foregroundStyle(Palette.secondary) }
        }
    }
    private func metric(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 22)
    }
    private func outcomeLabel(_ outcome: BreakOutcome) -> String {
        switch outcome { case .completed: return "已完成"; case .interrupted: return "提前结束"; case .skipped: return "已跳过"; case .inProgress: return "进行中" }
    }
}

struct RulesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            SectionHeading(title: "休息规则")
            ReminderSettingsView(model: model)
            HStack(spacing: 12) {
                ForEach([(25, 5, "轻专注"), (45, 5, "日常节奏"), (60, 10, "深度工作")], id: \.0) { preset in
                    Button {
                        model.settings.workMinutes = preset.0; model.settings.restMinutes = preset.1
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(preset.2).font(.system(size: 14, weight: .medium))
                                Spacer()
                                LineIcon(systemName: selected(preset.0, preset.1) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected(preset.0, preset.1) ? Palette.accent : Palette.line)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(preset.0)").font(.system(size: 30, weight: .light, design: .rounded))
                                Text("/ \(preset.1) 分钟").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                            }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected(preset.0, preset.1) ? Palette.lavender : Palette.surface, in: RoundedRectangle(cornerRadius: 19))
                            .overlay(RoundedRectangle(cornerRadius: 19).stroke(selected(preset.0, preset.1) ? Palette.accent.opacity(0.3) : Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected(preset.0, preset.1) ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                numericRow("每轮使用", subtitle: "累计到这个时长，提醒你休息", value: $model.settings.workMinutes, range: 5...180, step: 5, icon: "hourglass")
                Divider().overlay(Palette.line).padding(.vertical, 20)
                numericRow("每次休息", subtitle: "完成休息后，开始新的一轮", value: $model.settings.restMinutes, range: 1...30, step: 1, icon: "leaf")
            }.card(padding: 25)
            VStack(spacing: 22) {
                ruleRow("如何记录", "阅读模式会持续计时，直到休息或系统睡眠。") {
                    Picker("计时方式", selection: $model.settings.mode) { ForEach(TrackingMode.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 145)
                }
                Divider().overlay(Palette.line)
                ruleRow("多久没有操作视为离开", "活动估算会回溯空闲边界；短暂停顿不会清空本轮。") {
                    Picker("空闲阈值", selection: $model.settings.idleSeconds) {
                        Text("30 秒").tag(30); Text("1 分钟").tag(60); Text("90 秒").tag(90); Text("3 分钟").tag(180)
                    }.labelsHidden().frame(width: 110).disabled(model.settings.mode == .reading)
                }
                Divider().overlay(Palette.line)
                ruleRow("稍后提醒与重复提醒", "延后不会清空使用时长，跳过也不会算作完成休息。") {
                    Picker("提醒间隔", selection: Binding(get: { model.settings.snoozeMinutes }, set: { model.settings.snoozeMinutes = $0; model.settings.repeatMinutes = $0 })) {
                        Text("3 分钟").tag(3); Text("5 分钟").tag(5); Text("10 分钟").tag(10); Text("15 分钟").tag(15)
                    }.labelsHidden().frame(width: 110)
                }
            }.card(padding: 25)

        }
    }
    private func selected(_ work: Int, _ rest: Int) -> Bool { model.settings.workMinutes == work && model.settings.restMinutes == rest }
    private func numericRow(_ title: String, subtitle: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, icon: String) -> some View {
        HStack(spacing: 15) {
            LineIcon(systemName: icon).font(.system(size: 21, weight: .light)).foregroundStyle(Palette.accent).frame(width: 35)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: { LineIcon(systemName: "minus").frame(width: 28, height: 28) }
                .buttonStyle(.borderless).disabled(value.wrappedValue <= range.lowerBound).accessibilityLabel("减少\(title)")
            Text("\(value.wrappedValue)").font(.system(size: 25, weight: .light, design: .rounded)).monospacedDigit().frame(width: 47)
            Text("分钟").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: { LineIcon(systemName: "plus").frame(width: 28, height: 28) }
                .buttonStyle(.borderless).disabled(value.wrappedValue >= range.upperBound).accessibilityLabel("增加\(title)")
        }
    }
    private func ruleRow<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20); control().font(.system(size: 14)).controlSize(.large).fixedSize()
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            SectionHeading(title: "偏好设置")
            VStack(spacing: 22) {
                toggleRow("休息提醒", "暂停提醒后，仍然记录使用时间。", isOn: $model.settings.remindersEnabled, icon: "bell")
                Divider().overlay(Palette.line)
                toggleRow("休息结束声音", "倒计时结束时播放声音。", isOn: $model.settings.soundEnabled, icon: "speaker.wave.2")
                Divider().overlay(Palette.line)
                toggleRow("呼吸动效", "呼吸花与轻微过渡；同时尊重系统的减少动态效果设置。", isOn: $model.settings.motionEnabled, icon: "sparkles")
            }.card(padding: 25)
            VStack(spacing: 22) {
                HStack(spacing: 15) {
                    LineIcon(systemName: "power").frame(width: 25).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登录后自动启动").font(.system(size: 14, weight: .medium))
                        Text("登录后自动开始记录。").font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    }
                    Spacer()
                    Toggle("登录后自动启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) })).labelsHidden().toggleStyle(.switch)
                }
                if let error = model.loginError { Text(error).font(.system(size: 12)).foregroundStyle(Color.orange) }
                Divider().overlay(Palette.line)
                HStack(spacing: 15) {
                    LineIcon(systemName: "app.badge").frame(width: 25).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("系统通知").font(.system(size: 14, weight: .medium))
                        Text(model.notificationStatus).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    if model.notificationAuthorized {
                        Text("已允许").font(.system(size: 13)).foregroundStyle(Palette.green)
                    } else {
                        Button(model.notificationDenied ? "打开系统设置" : "允许通知") { model.enableNotifications() }.buttonStyle(.bordered)
                    }

                }
            }.card(padding: 25)
            HStack(spacing: 15) {
                LineIcon(systemName: "pause.circle").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.engine.trackingPaused ? "使用统计已暂停" : "暂时不想记录？").font(.system(size: 14, weight: .medium))
                    Text("暂停统计会保留历史与本轮进度，恢复后继续。").font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(model.engine.trackingPaused ? "恢复统计" : "暂停统计") { model.toggleTracking() }.buttonStyle(SoftButtonStyle())
            }.card(padding: 22)
            Text("息间 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.1")")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.horizontal, 5)

        }.onAppear { model.refreshNotificationStatus() }
    }
    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>, icon: String) -> some View {
        HStack(spacing: 15) {
            LineIcon(systemName: icon).frame(width: 25).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

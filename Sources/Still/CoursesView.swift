import SwiftUI
import AVKit
import StillCore

struct CoursesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: CourseLibrary
    @ObservedObject var player: CoursePlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: Course? { library.courses.first { $0.id == library.selectedID } ?? library.courses.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                SectionHeading(title: "休息课程", subtitle: "从肩颈到指尖，跟着做一小段。")
                Spacer()
                Button { library.chooseFolder() } label: { LineLabel(library.importing ? "正在导入…" : "导入课程", systemImage: "upload") }
                    .buttonStyle(SoftButtonStyle()).disabled(library.importing || player.active)
            }
            if let error = library.error { Text(error).font(.system(size: 14)).foregroundStyle(.orange) }
            if library.courses.isEmpty {
                VStack(spacing: 18) {
                    FlowerView(isAnimating: false).frame(width: 140, height: 140)
                    Text("放进你的第一门课程").font(.system(size: 22, weight: .medium))
                    Text("选择课程文件夹，即可浏览动作说明和播放视频。")
                        .font(.system(size: 15)).foregroundStyle(Palette.secondary)
                    Button("选择文件夹") { library.chooseFolder() }.buttonStyle(SoftButtonStyle(prominent: true))
                }.frame(maxWidth: .infinity).padding(.vertical, 55).card()
            } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("我的课程 · \(library.courses.count)").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary).padding(.bottom, 6)
                        ForEach(library.courses) { course in courseRow(course) }
                    }.frame(width: 186)
                    if let course = selected {
                        VStack(alignment: .leading, spacing: 22) {
                            video(course)
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(course.title).font(.system(size: 23, weight: .semibold, design: .rounded))
                                    HStack(spacing: 10) {
                                        Text(course.difficulty)
                                        Text("·")
                                        Text("\(course.displayDurationMinutes) 分钟")
                                        if let kcal = course.estimatedKcal { Text("·"); Text("参考 \(kcal) 千卡") }
                                    }.font(.system(size: 13)).foregroundStyle(Palette.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            Text(course.description).font(.system(size: 15)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                            info("练习准备", items: course.preparation, fallback: "原课程暂未提供准备说明")
                            info("身体反应", items: course.bodyResponses, fallback: "原课程暂未提供身体反应说明")
                            info("课程建议", items: course.recommendations)
                            DisclosureGroup(isExpanded: $library.showDetails) {
                                VStack(alignment: .leading, spacing: 20) {
                                    info("课程类型", items: course.courseTypes)
                                    info("适用人群", items: course.suitableFor)
                                    info("不适宜人群", items: course.contraindications, fallback: "原课程未列出这一栏")
                                    Text("来源：\(course.source.application)\(course.source.provider.flatMap { $0 == "unverified" ? nil : " · " + $0 } ?? "")")
                                        .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                                }.padding(.top, 16)
                            } label: { Text("适用说明与来源").font(.system(size: 15, weight: .medium)) }
                            Divider().overlay(Palette.line)
                            HStack {
                                Text("动作安排").font(.system(size: 18, weight: .semibold))
                                Spacer()
                                Text(course.actionsComplete ? "\(course.actions.count) 个动作" : "动作信息待补齐").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                            }
                            ForEach(course.actions) { action in
                                HStack(alignment: .top, spacing: 15) {
                                    Text(String(format: "%02d", action.order)).font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Palette.accent).frame(width: 28).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(action.name).font(.system(size: 15, weight: .medium))
                                        Text(action.phase).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                                    }
                                    Spacer()
                                    Text(action.quantityText ?? "待补齐").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                                }.padding(.vertical, 6)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear { loadSelection() }
        .onChange(of: library.selectedID) { _ in loadSelection() }
        .onChange(of: library.revision) { _ in
            if let selected { player.load(selected, url: library.mediaURL(for: selected)) }
        }
    }
    private func loadSelection() {
        guard let selected, player.courseID != selected.id else { return }
        player.load(selected, url: library.mediaURL(for: selected))
    }
    private func courseRow(_ course: Course) -> some View {
        let current = selected?.id == course.id
        return Button {
            withAnimation(reduceMotion || !model.settings.motionEnabled ? nil : .easeOut(duration: 0.18)) { library.selectedID = course.id }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LineIcon(systemName: course.title.contains("眼") ? "eye" : "leaf", size: 20)
                    Spacer()
                    Text("\(course.displayDurationMinutes)′").font(.system(size: 18, weight: .regular, design: .rounded))
                }.foregroundStyle(current ? Palette.accent : Palette.secondary)
                Text(course.title).font(.system(size: 15, weight: current ? .semibold : .medium)).lineSpacing(4).multilineTextAlignment(.leading)
                Text(library.mediaURL(for: course) == nil ? "视频待导入" : "可跟练")
                    .font(.system(size: 12)).foregroundStyle(current ? Palette.accentDark : Palette.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
                .background(current ? Color.white : Palette.sidebar.opacity(0.5), in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(current ? Palette.accent.opacity(0.28) : .clear, lineWidth: 1))
        }.buttonStyle(.plain).disabled(player.active && !current)
    }
    private func video(_ course: Course) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.white
                if library.mediaURL(for: course) != nil {
                    CourseVideoSurface(player: player.player).aspectRatio(16/9, contentMode: .fit)
                    if player.loading { ProgressView().padding(18).background(.regularMaterial, in: Circle()) }
                } else {
                    VStack(spacing: 12) {
                        LineIcon(systemName: "book-open", size: 35).foregroundStyle(Palette.accent.opacity(0.7))
                        Text("先看看动作与准备事项").font(.system(size: 17, weight: .medium))
                        Text("这门课程的视频尚未导入").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    }.frame(maxWidth: .infinity).aspectRatio(16/9, contentMode: .fit)
                }
            }.clipped()
            if library.mediaURL(for: course) != nil {
                VStack(spacing: 15) {
                    ProgressView(value: player.duration > 0 ? player.position / player.duration : 0).tint(Palette.accent)
                    HStack(spacing: 12) {
                        Button { player.toggle() } label: {
                            LineLabel(player.playing ? "暂停" : player.finished ? "再练一次" : player.active ? "继续跟练" : "开始跟练", systemImage: player.playing ? "pause" : "play")
                        }.buttonStyle(SoftButtonStyle(prominent: true)).disabled(player.loading || player.error != nil)
                        if player.active { Button("结束") { player.stop() }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.secondary) }
                        Spacer(minLength: 0)
                        Text(player.finished ? "本次跟练已完成" : "\(clockText(player.position)) / \(clockText(player.duration))")
                            .font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.secondary)
                    }
                    if let error = player.error {
                        HStack { Text(error).font(.system(size: 13)); Button("重试") { player.load(course, url: library.mediaURL(for: course)) } }.foregroundStyle(.orange)
                    }
                }.padding(18).background(Palette.lavender.opacity(0.45))
            }
            CourseWatchStrip(watch: model.watch) { model.page = .watch }
        }.clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line, lineWidth: 1))
    }
    @ViewBuilder private func info(_ title: String, items: [String]?, fallback: String? = nil) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 16, weight: .semibold))
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in Text(text).font(.system(size: 15)).foregroundStyle(Palette.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true) }
            }
        } else if let fallback { Text(fallback).font(.system(size: 14)).foregroundStyle(Palette.secondary) }
    }
}

struct CourseVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .none; view.videoGravity = .resizeAspect
        view.allowsVideoFrameAnalysis = false; view.showsFullScreenToggleButton = false; return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
}

struct CourseWatchStrip: View {
    @ObservedObject var watch: WatchConnection
    var open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                LineIcon(systemName: "watch", size: 17)
                Text(watch.connected ? watch.deviceName ?? "手表" : "连接手表").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(watch.heartRate.map { "\($0) 次/分" } ?? (watch.connected ? "等待心率" : "查看心率与课程进度"))
                    .font(.system(size: 13)).monospacedDigit()
            }.foregroundStyle(watch.connected ? Palette.green : Palette.secondary).padding(16).background(Color.white)
        }.buttonStyle(.plain)
    }
}

struct WatchView: View {
    @ObservedObject var watch: WatchConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SectionHeading(title: "我的手表", subtitle: "跟练时，抬腕看进度。")
            HStack(spacing: 38) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30).fill(Palette.mint.opacity(0.5)).frame(width: 80, height: 238)
                    RoundedRectangle(cornerRadius: 39).fill(Palette.ink).frame(width: 156, height: 180)
                    RoundedRectangle(cornerRadius: 33).fill(Color(hex: 0xF0F5F2)).frame(width: 140, height: 164)
                    VStack(spacing: 10) {
                        Text("实时心率").font(.system(size: 13)).foregroundStyle(Palette.green)
                        Text(watch.heartRate.map(String.init) ?? "—").font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                        Text(watch.heartRate == nil ? "等待读数" : "次 / 分钟").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }.frame(width: 184, height: 248)
                VStack(alignment: .leading, spacing: 18) {
                    Text(watch.deviceName ?? "OPPO Watch X").font(.system(size: 25, weight: .semibold, design: .rounded))
                    StatusBadge(title: watch.status, active: watch.connected)
                    Text(watch.supportsCourses ? "可同步课程进度，并在手表暂停、继续或结束跟练。" : "在手表打开 Still Link，开始广播后搜索连接。也支持提供标准心率服务的设备。")
                        .font(.system(size: 15)).foregroundStyle(Palette.secondary).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if watch.connected { Button("断开连接") { watch.disconnect() }.buttonStyle(SoftButtonStyle()) }
                        else { Button(watch.scanning ? "停止搜索" : "搜索手表") { watch.scanning ? watch.stopScan() : watch.scan() }.buttonStyle(SoftButtonStyle(prominent: true)) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(28).background(LinearGradient(colors: [Palette.lavender, Color(hex: 0xECF4F0)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            if !watch.connected {
                ForEach(watch.devices) { device in
                    HStack(spacing: 14) {
                        LineIcon(systemName: "watch", size: 24).foregroundStyle(Palette.accent).frame(width: 38)
                        Text(device.name).font(.system(size: 16, weight: .medium))
                        Spacer()
                        Button("连接") { watch.connect(device) }.buttonStyle(SoftButtonStyle())
                    }.card(padding: 18)
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                Text("第一次连接").font(.system(size: 18, weight: .semibold))
                instruction("1", "在 Watch X 安装 Still Link", "通过手表的无线调试安装伴侣应用；保留原有 OPPO 健康配对。")
                instruction("2", "打开伴侣，允许传感器和蓝牙权限", "戴好手表，点击开始连接。首次连接可能需要确认系统蓝牙配对。")
                instruction("3", "回到息间搜索手表", "收到真实心率后会显示读数；暂停或结束可在两端操作。")
            }.card(padding: 26)
            Text("此连接不会写入 OPPO 健康运动记录。Watch X 真机兼容性正在验证。")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
        }
    }
    private func instruction(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(n).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 28, height: 28).background(Palette.lavender, in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(detail).font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(4)
            }
        }
    }
}

import SwiftUI
import AVKit
import StillCore

struct CoursesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: CourseLibrary
    @ObservedObject var player: CoursePlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: Course? { library.courses.first { $0.id == library.selectedID } }
    private var transition: Animation? { reduceMotion || !model.settings.motionEnabled ? nil : .easeOut(duration: 0.2) }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let course = selected {
                    training(course).padding(.top, 38)
                } else {
                    ScrollView(showsIndicators: false) {
                        catalog.padding(.top, 38).padding(.bottom, 24)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = library.error { Text(error).font(.system(size: 14)).foregroundStyle(.orange).padding(.vertical, 12) }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 1040, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadSelection() }
        .onChange(of: library.selectedID) { _ in loadSelection() }
        .onChange(of: library.revision) { _ in loadSelection(force: true) }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                SectionHeading(title: "休息课程", subtitle: "选一段练习，让身体松下来。")
                Spacer()
                CourseCacheControls(cache: library.videoCache, player: player)
            }
            if player.active, let current = library.courses.first(where: { $0.id == player.courseID }) {
                Button { open(current) } label: {
                    HStack(spacing: 12) {
                        LineIcon(systemName: "play", size: 18)
                        Text("返回跟练 · " + current.title).font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text(clockText(player.position)).font(.system(size: 14, design: .monospaced))
                    }.foregroundStyle(Palette.accentDark).padding(18).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
            if library.courses.isEmpty {
                VStack(spacing: 18) {
                    FlowerView(isAnimating: false).frame(width: 140, height: 140)
                    Text("暂无课程").font(.system(size: 22, weight: .medium))
                    Text("课程目录准备好后，会显示在这里。")
                        .font(.system(size: 15)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 55).card()
            } else {
                Text("全部课程 · \(library.courses.count)").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(library.courses) { course in
                        CourseCoverCard(course: course, remoteImages: library.remoteThumbnails, reduceMotion: reduceMotion || !model.settings.motionEnabled) { open(course) }
                            .disabled(player.active && player.courseID != course.id)
                    }
                }
            }
        }
    }

    private func training(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 20) {
                Button {
                    player.pause()
                    withAnimation(transition) { library.selectedID = nil }
                } label: { HStack(spacing: 6) { Text("‹").font(.system(size: 25, weight: .light)); Text("全部课程").font(.system(size: 14, weight: .medium)) } }
                    .buttonStyle(.plain).foregroundStyle(Palette.accentDark)
                Rectangle().fill(Palette.line).frame(width: 1, height: 26)
                VStack(alignment: .leading, spacing: 7) {
                    Text(course.title).font(.system(size: 25, weight: .semibold, design: .rounded))
                    metadata(course).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 24) {
                if !course.actions.isEmpty { actionRail(course).frame(width: 222).padding(.bottom, 24) }
                ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    video(course)
                    VStack(alignment: .leading, spacing: 22) {
                        Text("关于这节课").font(.system(size: 19, weight: .semibold))
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
                    }.card(padding: 24)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 24)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).id(course.id)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func actionRail(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("动作安排").font(.system(size: 18, weight: .semibold))
                Spacer()
                if !course.actions.isEmpty { Text("\(course.actions.count) 个").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
            }.padding(.horizontal, 4)
            if course.actions.isEmpty {
                Text("来源未提供动作拆分，可直接播放课程").font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(5).padding(16)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(course.actions.enumerated()), id: \.element.id) { index, action in
                            if index == 0 || course.actions[index - 1].phase != action.phase {
                                Text(action.phase).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                                    .padding(.horizontal, 4).padding(.top, index == 0 ? 0 : 8)
                            }
                            HStack(alignment: .center, spacing: 12) {
                                CourseActionThumbnail(action: action, localImage: library.thumbnail(for: action), remoteImages: library.remoteThumbnails)
                                    .frame(width: 66, height: 58).background(Color.white, in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(action.name).font(.system(size: 14, weight: .medium)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                                    Text(action.quantityText ?? "时长待补齐").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accentDark)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("第 \(action.order) 个动作，\(action.name)，\(action.quantityText ?? "时长待补齐")，\(action.phase)")
                        }
                    }.padding(.trailing, 4)
                }.frame(maxHeight: .infinity)
                if !course.actionsComplete { Text("动作信息待补齐").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
            }
        }
    }

    private func metadata(_ course: Course) -> some View {
        HStack(spacing: 9) {
            Text(course.difficulty)
            Text("·")
            Text("\(course.displayDurationMinutes) 分钟")
            if let kcal = course.estimatedKcal { Text("·"); Text("参考 \(kcal) 千卡") }
        }
    }
    private func open(_ course: Course) {
        withAnimation(transition) { library.selectedID = course.id }
        loadSelection()
    }
    private func loadSelection(force: Bool = false) {
        guard let selected, force || player.courseID != selected.id else { return }
        player.load(selected, url: library.mediaURL(for: selected))
    }
    private func video(_ course: Course) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Color.white
                    if library.mediaURL(for: course) != nil {
                        if player.loading {
                            CourseVideoPoster(resource: course.coverURL, remoteImages: library.remoteThumbnails)
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        } else {
                            CourseVideoSurface(player: player.player, aspectRatio: player.videoAspectRatio)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                        if player.loading || player.buffering {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text(player.buffering ? "正在缓冲…" : "正在加载视频…").font(.system(size: 13))
                            }.foregroundStyle(Palette.ink).padding(18).background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        VStack(spacing: 12) {
                            LineIcon(systemName: "book-open", size: 35).foregroundStyle(Palette.accent.opacity(0.7))
                            Text("先看看动作与准备事项").font(.system(size: 17, weight: .medium))
                            Text("这门课程的视频尚未导入").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }.aspectRatio(player.videoAspectRatio, contentMode: .fit).clipped()
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
                    HStack(spacing: 10) {
                        if player.videoAvailableOffline {
                            Text(player.usingCachedVideo ? "本地缓存 · 离线播放" : "已缓存 · 下次可离线播放").foregroundStyle(Palette.green)
                        } else if player.caching {
                            if let progress = player.downloadProgress { ProgressView(value: progress).tint(Palette.accent).frame(width: 70) }
                            Text(player.downloadProgress.map { "正在缓存 \(Int($0 * 100))%" } ?? (player.error == nil ? "在线播放 · 后台缓存中" : "正在缓存视频…"))
                                .foregroundStyle(Palette.secondary)
                        } else if let error = player.cacheError {
                            Text(error).foregroundStyle(Palette.secondary)
                            Button("重试缓存") { player.retryCaching(course) }.buttonStyle(.plain).foregroundStyle(Palette.accentDark)
                        }
                        Spacer(minLength: 0)
                    }.font(.system(size: 12))
                    if let error = player.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.system(size: 13)).foregroundStyle(.orange)
                            HStack {
                                Button("重新加载") { player.load(course, url: library.mediaURL(for: course)) }
                                if course.media?.url != nil, !player.videoAvailableOffline {
                                    Button("缓存后再播放") { player.playFromCache(course) }.disabled(player.caching)
                                }
                            }.font(.system(size: 13))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(18).background(Palette.lavender.opacity(0.45))
            }
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

struct CourseVideoPoster: View {
    let resource: HTTPSResourceURL?
    let remoteImages: RemoteCourseImages
    @StateObject private var state = CourseImageState()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.lavender
                if let image = state.image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                Color.white.opacity(0.2)
            }
        }.task(id: resource) {
            state.image = nil
            guard let resource else { return }
            let image = await remoteImages.image(for: resource)
            guard !Task.isCancelled else { return }
            state.image = image
        }
    }
}

private struct CourseCacheControls: View {
    @ObservedObject var cache: CourseVideoCache
    @ObservedObject var player: CoursePlayer
    @StateObject private var state = CourseCacheControlState()
    var body: some View {
        Menu {
            Text("首次缓存，后续离线播放")
            Button("清理视频缓存") {
                do { player.unload(); try cache.clear(); state.error = nil }
                catch { state.error = "缓存清理失败：" + error.localizedDescription }
            }.disabled(cache.byteCount == 0 || player.active || player.loading)
            if let error = state.error { Text(error) }
        } label: {
            Text("视频缓存 · " + (cache.byteCount == 0 ? "0 MB" : ByteCountFormatter.string(fromByteCount: cache.byteCount, countStyle: .file)))
                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }
}
private final class CourseCacheControlState: ObservableObject { @Published var error: String? }

private final class CourseImageState: ObservableObject {
    @Published var image: NSImage?
    @Published var hovering = false
    @Published var failed = false
    @Published var retry = 0
    @Published var failure: String?
}

private struct CourseCoverCard: View {
    let course: Course
    let remoteImages: RemoteCourseImages
    let reduceMotion: Bool
    let open: () -> Void
    @StateObject private var state = CourseImageState()
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        Palette.lavender
                        if let image = state.image {
                            Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        } else {
                            LineIcon(systemName: course.title.contains("眼") ? "eye" : "leaf", size: 42).foregroundStyle(Palette.accent.opacity(0.45)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .center, endPoint: .bottom)
                        Text("\(course.displayDurationMinutes) 分钟").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 11).padding(.vertical, 6).background(.black.opacity(0.18), in: Capsule()).padding(14)
                        if state.failed { Text("封面未载入").font(.system(size: 11)).foregroundStyle(.white).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
                    }
                }.aspectRatio(4 / 3, contentMode: .fit).clipped()
                VStack(alignment: .leading, spacing: 12) {
                    Text(course.title).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(2).multilineTextAlignment(.leading).frame(height: 48, alignment: .topLeading)
                    HStack {
                        Text(course.difficulty).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        Spacer()
                        HStack(spacing: 5) { Text("查看课程"); LineIcon(systemName: "play", size: 12) }.font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accentDark)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.white)
            }.clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(state.hovering ? Palette.accent.opacity(0.4) : Palette.line, lineWidth: 1))
                .shadow(color: Palette.accent.opacity(state.hovering ? 0.12 : 0.025), radius: state.hovering ? 14 : 5, y: state.hovering ? 5 : 2)
                .offset(y: state.hovering && !reduceMotion ? -3 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
            .onHover { state.hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.hovering)
            .accessibilityLabel("\(course.title)，\(course.displayDurationMinutes)分钟，\(course.difficulty)，查看课程")
            .task(id: course.coverURL) {
                state.image = nil; state.failed = false
                guard let url = course.coverURL else { return }
                let result = await remoteImages.image(for: url)
                guard !Task.isCancelled else { return }
                state.image = result; state.failed = result == nil
            }
    }
}

struct CourseActionThumbnail: View {
    let action: Course.Action
    let localImage: NSImage?
    let remoteImages: RemoteCourseImages
    @StateObject private var state = CourseImageState()
    var body: some View {
        Group {
            if let image = localImage ?? state.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if action.thumbnailURL != nil && !state.failed {
                ProgressView().controlSize(.small)
            } else {
                VStack(spacing: 4) {
                    Text(String(format: "%02d", action.order)).font(.system(size: 20, weight: .light, design: .rounded))
                    if state.failed {
                        Button("重试") { state.retry += 1 }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accentDark)
                            .help(state.failure ?? "图片载入失败").accessibilityLabel("重新加载动作图片")
                    }
                }.foregroundStyle(Palette.secondary)
            }
        }.task(id: "\(action.thumbnailURL?.url.absoluteString ?? "")|\(state.retry)") {
            state.image = nil; state.failed = false
            guard localImage == nil, let url = action.thumbnailURL else { return }
            let result = await remoteImages.image(for: url)
            guard !Task.isCancelled else { return }
            state.image = result; state.failed = result == nil; state.failure = remoteImages.failure(for: url)
        }
    }
}

/// Display only: AVPlayerLayer has no AVKit wheel/trackpad scrubbing gestures.
final class CoursePlayerLayerView: NSView {
    let videoLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    override var acceptsFirstResponder: Bool { false }
}

struct CourseVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    var aspectRatio: CGFloat = 16 / 9
    func makeNSView(context: Context) -> CoursePlayerLayerView {
        let view = CoursePlayerLayerView(frame: .zero); view.videoLayer.player = player; return view
    }
    func updateNSView(_ view: CoursePlayerLayerView, context: Context) {
        if view.videoLayer.player !== player { view.videoLayer.player = player }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CoursePlayerLayerView, context: Context) -> CGSize? {
        let width = proposal.width ?? 640
        return CGSize(width: width, height: width / aspectRatio)
    }
}

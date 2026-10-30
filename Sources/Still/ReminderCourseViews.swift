import SwiftUI
import StillCore

struct ReminderRecommendationCard: View {
    @ObservedObject var model: AppModel
    let preview: Bool
    var choose: (Course) -> Void
    var body: some View {
        if let course = model.reminderRecommendation(preview: preview) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("这一刻，动一动").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("换一个") { model.prepareRecommendation(preview: preview, shuffle: true) }
                        .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accentDark)
                        .disabled(!preview && model.coursePlayer.active)
                }
                Button { choose(course) } label: {
                    HStack(spacing: 14) {
                        CourseVideoPoster(resource: course.coverURL, remoteImages: model.library.remoteThumbnails)
                            .frame(width: 92, height: 72).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(course.title).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.leading)
                            Text("\(course.displayDurationMinutes) 分钟 · \(course.difficulty)").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                            Text(!preview && model.coursePlayer.active ? "继续跟练" : "在这里跟练").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accentDark)
                        }
                        Spacer(minLength: 0)
                        LineIcon(systemName: "play", size: 18).foregroundStyle(Palette.accent)
                    }
                }.buttonStyle(.plain).accessibilityLabel("跟练推荐课程：\(course.title)，\(course.displayDurationMinutes)分钟")
            }.padding(16).background(Palette.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line, lineWidth: 1))
        }
    }
}

struct ReminderWorkoutView: View {
    @ObservedObject var model: AppModel
    let course: Course
    @ObservedObject var player: CoursePlayer
    let preview: Bool
    var back: () -> Void
    var close: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("‹ 返回提醒", action: back).buttonStyle(.plain).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.accentDark)
                Spacer()
                Text(preview ? "课程预览 · 不计入休息" : "休息跟练").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Button(action: close) { LineIcon(systemName: "x", size: 16).frame(width: 30, height: 30) }
                    .buttonStyle(.plain).accessibilityLabel("收起跟练并暂停")
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(course.title).font(.system(size: 22, weight: .semibold, design: .rounded))
                        Spacer()
                        Text(course.difficulty).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    }
                    if let webpage = course.media?.webpage {
                        WebCourseView(url: webpage.url, playbackURL: course.media?.webPlaybackURL).id(course.id)
                    } else {
                    GeometryReader { geometry in
                        ZStack {
                            if player.loading {
                                CourseVideoPoster(resource: course.coverURL, remoteImages: model.library.remoteThumbnails)
                                ProgressView().padding(18).background(Palette.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                            } else { CourseVideoSurface(controller: player, aspectRatio: player.videoAspectRatio) }
                        }.frame(width: geometry.size.width, height: geometry.size.height)
                    }.aspectRatio(player.videoAspectRatio, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    if let preparation = course.preparation, !preparation.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("练习准备").font(.system(size: 15, weight: .semibold))
                            ForEach(preparation, id: \.self) { Text($0).font(.system(size: 14)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    if !course.actions.isEmpty || !course.description.isEmpty || !(course.bodyResponses ?? []).isEmpty {
                    DisclosureGroup("动作与课程说明") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(course.description).font(.system(size: 14)).lineSpacing(5)
                            ForEach(course.actions) { action in
                                HStack(spacing: 12) {
                                    CourseActionThumbnail(action: action, localImage: model.library.thumbnail(for: action), remoteImages: model.library.remoteThumbnails)
                                        .frame(width: 64, height: 46).clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text("\(action.order). \(action.name)  \(action.quantityText ?? "")").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                                }
                            }
                            ForEach(course.bodyResponses ?? [], id: \.self) { Text($0).font(.system(size: 14)).foregroundStyle(Palette.secondary) }
                        }.padding(.top, 12)
                    }.font(.system(size: 14, weight: .medium))
                    }
                }.frame(maxWidth: 1000).frame(maxWidth: .infinity).padding(.bottom, 12)
            }
            if course.media?.webpage == nil {
            VStack(alignment: .leading, spacing: 12) {
                    CourseSeekBar(controller: player).frame(height: 22)
                    HStack(spacing: 14) {
                        Button { player.toggle() } label: { LineLabel(player.playing ? "暂停" : player.finished ? "再练一次" : player.active ? "继续跟练" : "开始跟练", systemImage: player.playing ? "pause" : "play") }
                            .buttonStyle(SoftButtonStyle(prominent: true)).disabled(player.loading || player.error != nil)
                        if player.finished { Button("完成并关闭", action: close).buttonStyle(SoftButtonStyle()) }
                        else if player.active { Button("结束跟练") { player.stop(); close() }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.secondary) }
                        Spacer()
                        Text(player.finished ? "本次跟练已完成" : "\(clockText(player.position)) / \(clockText(player.duration))")
                            .font(.system(size: 14, design: .monospaced)).foregroundStyle(Palette.secondary)
                    }
                    if player.caching { Text(player.error == nil ? "在线播放 · 后台缓存中" : "正在缓存视频…").font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }
                    else if player.videoAvailableOffline { Text("已缓存 · 可离线跟练").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).foregroundStyle(Palette.green) }
                    if let error = player.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).foregroundStyle(.orange)
                            HStack {
                                Button("重新加载") { player.load(course, url: model.library.mediaURL(for: course)) }
                                if !player.videoAvailableOffline, course.media?.url != nil, course.media?.originalPage == nil {
                                    Button("缓存后再播放") { player.playFromCache(course) }.disabled(player.caching)
                                }
                            }
                        }.font(.system(size: 14))
                    }
            }.fixedSize(horizontal: false, vertical: true).padding(.top, 4).padding(.bottom, 8)
            }
        }.padding(24).background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
            .task(id: course.id) {
                guard course.media?.webpage == nil else { return }
                for _ in 0..<350 {
                    guard !Task.isCancelled else { return }
                    if !player.loading {
                        if player.error == nil, !player.playing, !player.finished { player.toggle() }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
    }
}

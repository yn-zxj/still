import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import StillCore

extension CourseLibrary {
    func chooseCatalog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "选择 JSON 文件或课程文件夹。导入会合并课程，相同 ID 更新原条目。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mergeCatalog(url)
    }

    func mergeCatalog(_ url: URL) {
        guard !importing else { return }
        let root = root
        importing = true; error = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                    let file = isDirectory ? url.appendingPathComponent("courses.json") : url
                    try Self.merge(data: Data(contentsOf: file), source: file.deletingLastPathComponent(), root: root)
                }.value
                reload()
            } catch { self.error = error.localizedDescription }
            importing = false
        }
    }

    /// Stage a complete merged library, then commit once. Never replace unrelated courses.
    nonisolated static func merge(data: Data, source: URL, root: URL) throws {
        let incoming = try Course.decodeCatalog(data)
        let fm = FileManager.default
        let parent = root.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".course-merge-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        if fm.fileExists(atPath: root.path) { try fm.copyItem(at: root, to: stage) }
        else { try fm.createDirectory(at: stage, withIntermediateDirectories: true) }
        let oldURL = stage.appendingPathComponent("courses.json")
        var merged = fm.fileExists(atPath: oldURL.path) ? try Course.decodeCatalog(Data(contentsOf: oldURL)) : []
        for course in incoming {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(course)) as! [String: Any]
            // Renaming imported resources prevents collisions with another course's media.
            var names: [String: String] = [:]
            let existing = merged.first { $0.id == course.id }
            let retainedNames = Set([existing?.media?.filename].compactMap { $0 } + (existing?.actions.compactMap(\.thumbnail) ?? []))
            let resources = [course.media?.filename].compactMap { $0 } + course.actions.compactMap(\.thumbnail)
            for name in Set(resources) {
                let file = source.appendingPathComponent(name).resolvingSymlinksInPath()
                guard file.deletingLastPathComponent() == source.resolvingSymlinksInPath() else { throw CourseError.unsafeFilename }
                if source.resolvingSymlinksInPath() == root.resolvingSymlinksInPath(), fm.fileExists(atPath: stage.appendingPathComponent(name).path) { continue }
                if !fm.fileExists(atPath: file.path) {
                    if retainedNames.contains(name), fm.fileExists(atPath: stage.appendingPathComponent(name).path) { continue }
                    let localRequired = (course.media?.filename == name && course.media?.url == nil && course.media?.webpage == nil)
                        || course.actions.contains { $0.thumbnail == name && $0.thumbnailURL == nil }
                    if localRequired { throw CourseError.missingMedia }
                    continue
                }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { throw CourseError.unsafeFilename }
                if course.media?.filename == name, let hash = course.media?.sha256 {
                    guard try HAPIReleaseClient.sha256(of: file) == hash.lowercased() else { throw CourseError.invalidMedia }
                }
                let newName = UUID().uuidString + "-" + name
                try fm.copyItem(at: file, to: stage.appendingPathComponent(newName))
                names[name] = newName
            }
            if var media = object["media"] as? [String: Any], let name = media["filename"] as? String, let replacement = names[name] {
                media["filename"] = replacement; object["media"] = media
            }
            if var actions = object["actions"] as? [[String: Any]] {
                for index in actions.indices {
                    if let name = actions[index]["thumbnail"] as? String, let replacement = names[name] { actions[index]["thumbnail"] = replacement }
                }
                object["actions"] = actions
            }
            let installed = try Course.decodeCatalog(JSONSerialization.data(withJSONObject: object))[0]
            if let index = merged.firstIndex(where: { $0.id == installed.id }) { merged[index] = installed }
            else { merged.append(installed) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(merged).write(to: oldURL, options: .atomic)
        if fm.fileExists(atPath: root.path) { _ = try fm.replaceItemAt(root, withItemAt: stage) }
        else { try fm.moveItem(at: stage, to: root) }
    }

    func save(_ course: Course, video: URL?) async throws {
        guard !importing else { throw CourseError.invalidCatalog }
        importing = true
        defer { importing = false }
        let data = try JSONEncoder().encode([course]), root = root
        let source = video?.deletingLastPathComponent() ?? root
        try await Task.detached(priority: .userInitiated) { try Self.merge(data: data, source: source, root: root) }.value
        reload()
    }

    func remove(_ course: Course) throws {
        guard !importing else { return }
        let remaining = courses.filter { $0.id != course.id }
        let data = try JSONEncoder().encode(remaining)
        // Media is kept on disk so removal never destroys the user's imported video.
        try data.write(to: root.appendingPathComponent("courses.json"), options: .atomic)
        selectedID = nil
        reload()
    }

    func exportCatalog() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "导出到此处"; panel.message = "新建课程备份文件夹，包含 JSON 和导入的本地媒体。在线资源仅保存链接。"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let destination = folder.appendingPathComponent("Still-Courses-" + String(UUID().uuidString.prefix(8)))
        let root = root, courses = courses
        importing = true
        Task {
            defer { importing = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let fm = FileManager.default
                    try fm.createDirectory(at: destination, withIntermediateDirectories: false)
                    do {
                        let resources = Set(courses.flatMap { [ $0.media?.filename ].compactMap { $0 } + $0.actions.compactMap(\.thumbnail) })
                        for name in resources {
                            let file = root.appendingPathComponent(name)
                            if fm.fileExists(atPath: file.path) { try fm.copyItem(at: file, to: destination.appendingPathComponent(name)) }
                        }
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                        try encoder.encode(courses).write(to: destination.appendingPathComponent("courses.json"), options: .atomic)
                    } catch { try? fm.removeItem(at: destination); throw error }
                }.value
                NSWorkspace.shared.activateFileViewerSelecting([destination.appendingPathComponent("courses.json")])
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct CourseEditor: View {
    @ObservedObject var library: CourseLibrary
    let course: Course?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = CourseEditorState()
    @StateObject private var parserInstaller = VideoParserInstaller()
    private var title: String { get { form.title } nonmutating set { form.title = newValue } }
    private var sourceKind: Int { get { form.sourceKind } nonmutating set { form.sourceKind = newValue } }
    private var address: String { get { form.address } nonmutating set { form.address = newValue } }
    private var video: URL? { get { form.video } nonmutating set { form.video = newValue } }
    private var minutes: Int { get { form.minutes } nonmutating set { form.minutes = newValue } }
    private var description: String { get { form.description } nonmutating set { form.description = newValue } }
    private var preparation: String { get { form.preparation } nonmutating set { form.preparation = newValue } }
    private var response: String { get { form.response } nonmutating set { form.response = newValue } }
    private var advice: String { get { form.advice } nonmutating set { form.advice = newValue } }
    private var actions: String { get { form.actions } nonmutating set { form.actions = newValue } }
    private var cover: String { get { form.cover } nonmutating set { form.cover = newValue } }
    private var error: String? { get { form.error } nonmutating set { form.error = newValue } }
    private var resolving: Bool { get { form.resolving } nonmutating set { form.resolving = newValue } }
    private var saving: Bool { get { form.saving } nonmutating set { form.saving = newValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(course == nil ? "添加课程" : "编辑课程").font(.system(size: 23, weight: .semibold, design: .rounded))
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(SettingsButtonStyle()).disabled(saving)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("课程名称", text: $form.title)
                    SegmentedPillControl(selection: $form.sourceKind, values: [0, 1, 2]) { value in
                        Text(["本地视频", "视频直链", "网页课程"][value])
                    }
                    if sourceKind == 0 {
                        HStack {
                            Text(video?.lastPathComponent ?? course?.media?.filename ?? "选择一个视频文件")
                                .font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("选择视频…", action: chooseVideo).buttonStyle(SettingsButtonStyle())
                        }.padding(14).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        field(sourceKind == 1 ? "HTTPS 视频地址（如 MP4）" : "HTTPS 网页地址（如 B 站视频页）", text: $form.address)
                        HStack(spacing: 12) {
                            Button("识别链接", action: resolveLink).buttonStyle(SettingsButtonStyle())
                                .disabled(resolving || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if resolving { ProgressView().controlSize(.small) }
                            if let result = form.resolutionMessage {
                                Text(result).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack(spacing: 10) {
                            Button(parserInstaller.installed ? "更新解析组件" : "安装通用解析组件") { parserInstaller.install() }.buttonStyle(SettingsButtonStyle())
                                .disabled(parserInstaller.busy || resolving)
                            if parserInstaller.busy { ProgressView().controlSize(.small) }
                            Text(parserInstaller.message ?? (parserInstaller.installed ? "通用链接解析已就绪" : "B 站可直接识别；安装组件后支持更多网站。"))
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if let result = form.resolution, result.title != nil || result.cover != nil {
                            HStack(alignment: .top, spacing: 14) {
                                if let cover = result.cover {
                                    AsyncImage(url: cover) { image in image.resizable().scaledToFill() } placeholder: { Palette.lavender }
                                        .frame(width: 112, height: 70).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    if let name = result.title { Text(name).font(.system(size: 14, weight: .medium)).lineLimit(3) }
                                    Button("使用识别信息") { applyMetadata(result, replacing: true) }.buttonStyle(SettingsButtonStyle())
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if sourceKind == 2 {
                            Text("使用网页播放器；登录、广告和播放限制由来源网站决定。网页播放不自动记录课程完成，也不缓存网页视频。")
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Stepper("展示时长：\(minutes) 分钟", value: $form.minutes, in: 1...180).font(.system(size: 14))
                    field("封面图片地址（可选）", text: $form.cover)
                    Divider()
                    Text("课程内容 · 均可留空").font(.system(size: 14, weight: .semibold))
                    field("简介", text: $form.description, lines: 3)
                    field("练习准备 · 每行一项", text: $form.preparation, lines: 2)
                    field("身体反应 · 每行一项", text: $form.response, lines: 2)
                    field("课程建议 · 每行一项", text: $form.advice, lines: 2)
                    field("动作安排 · 每行：动作名称 | 次数或时长", text: $form.actions, lines: 4)
                    Text("例如：肩部放松 | 30 秒。没有动作时，只显示视频区域。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }.padding(.trailing, 8)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                if saving { ProgressView().controlSize(.small); Text("正在保存视频和课程…").font(.system(size: 12)) }
                Spacer()
                Button("保存课程", action: save).buttonStyle(SettingsButtonStyle(prominent: true))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving || resolving || parserInstaller.busy)
            }
        }
        .padding(26).frame(width: 590, height: 740)
        .background(Palette.background).foregroundStyle(Palette.ink)
        .onAppear(perform: populate)
        .onChange(of: address) { value in
            if value != form.resolvedAddress { form.originalPage = nil }
        }
    }

    private func field(_ label: String, text: Binding<String>, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
            TextField("", text: text, axis: .vertical).lineLimit(lines...max(lines, 5))
                .textFieldStyle(.plain).font(.system(size: 14)).padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
                .accessibilityLabel(label)
        }
    }
    private func resolveLink() {
        let snapshot = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = form.originalPage?.absoluteString ?? snapshot
        resolving = true; form.resolutionMessage = nil
        Task {
            defer { resolving = false }
            do {
                let result = try await VideoLinkResolver().resolve(input)
                guard address.trimmingCharacters(in: .whitespacesAndNewlines) == snapshot else { return }
                form.resolution = result
                if let video = result.video {
                    form.originalPage = video == result.original ? nil : result.original
                    form.resolvedAddress = video.absoluteString
                    sourceKind = 1; address = video.absoluteString
                }
                else { sourceKind = 2; address = result.original.absoluteString }
                applyMetadata(result, replacing: false)
                form.resolutionMessage = result.message
            } catch { form.resolutionMessage = "未能识别，仍可作为网页保存：" + error.localizedDescription }
        }
    }
    private func applyMetadata(_ result: VideoLinkResolution, replacing: Bool) {
        if (replacing || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), let found = result.title { title = found }
        if replacing || cover.isEmpty, let found = result.cover { cover = found.absoluteString }
        if replacing || description.isEmpty, let found = result.description { description = found }
        if let duration = result.duration, duration.isFinite, duration > 0 { minutes = min(180, max(1, Int(ceil(duration / 60)))) }
    }
    private func chooseVideo() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK else { return }
        video = panel.url
        if title.isEmpty { title = video?.deletingPathExtension().lastPathComponent ?? "" }
    }
    private func populate() {
        guard let c = course else { return }
        title = c.title; minutes = c.displayDurationMinutes; description = c.description
        preparation = (c.preparation ?? []).joined(separator: "\n")
        response = (c.bodyResponses ?? []).joined(separator: "\n")
        advice = (c.recommendations ?? []).joined(separator: "\n")
        actions = actionText(c); cover = c.coverURL?.url.absoluteString ?? ""
        form.resolvedAddress = c.media?.url?.url.absoluteString
        form.originalPage = c.media?.originalPage?.url
        if let page = c.media?.webpage { sourceKind = 2; address = page.url.absoluteString }
        else if c.media?.filename == nil, let url = c.media?.url { sourceKind = 1; address = url.url.absoluteString }
    }
    private func actionText(_ c: Course) -> String {
        c.actions.map { $0.name + ($0.quantityText.map { " | " + $0 } ?? "") }.joined(separator: "\n")
    }
    private func lines(_ value: String) -> [String] {
        value.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func save() {
        do {
            var object = course.flatMap { try? JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as? [String: Any] } ?? [:]
            object["schemaVersion"] = 1; object["id"] = course?.id ?? UUID().uuidString
            object["title"] = title.trimmingCharacters(in: .whitespacesAndNewlines)
            object["displayDurationMinutes"] = minutes; object["description"] = description
            object["preparation"] = lines(preparation); object["bodyResponses"] = lines(response); object["recommendations"] = lines(advice)
            if cover.isEmpty { object.removeValue(forKey: "coverURL") } else { object["coverURL"] = try HTTPSResourceURL(cover).url.absoluteString }
            if course == nil || actions != course.map(actionText) {
                object["actions"] = lines(actions).enumerated().map { index, line -> [String: Any] in
                    let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    var action: [String: Any] = ["order": index + 1, "phase": "练习", "name": parts[0]]
                    if parts.count == 2 { action["quantityText"] = parts[1] }
                    return action
                }
                object["actionsComplete"] = true
            }
            if sourceKind == 0 {
                if let video { object["media"] = ["filename": video.lastPathComponent] }
                else if course?.media?.filename == nil { throw CourseError.missingMedia }
            } else {
                let url = try HTTPSResourceURL(address.trimmingCharacters(in: .whitespacesAndNewlines))
                var media = [sourceKind == 1 ? "url" : "webpage": url.url.absoluteString]
                if sourceKind == 1, let page = form.originalPage { media["originalPage"] = page.absoluteString }
                object["media"] = media
            }
            let updated = try Course.decodeCatalog(JSONSerialization.data(withJSONObject: object))[0]
            saving = true; error = nil
            Task {
                do { try await library.save(updated, video: video); dismiss() }
                catch { self.error = error.localizedDescription; saving = false }
            }
        } catch { self.error = error.localizedDescription }
    }
}

/// Isolated web view; no injected scripts, credentials, downloads or native bridge.
struct CourseWebPlayer: NSViewRepresentable {
    let url: URL
    final class Coordinator: NSObject, WKNavigationDelegate {
        var requestedURL: URL?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, ["https", "about"].contains(url.scheme?.lowercased() ?? "") else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.requestedURL = url
        view.load(URLRequest(url: url))
        return view
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.requestedURL != url {
            context.coordinator.requestedURL = url
            view.load(URLRequest(url: url))
        }
    }
}

struct WebCourseView: View {
    let url: URL
    var playbackURL: URL? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CourseWebPlayer(url: playbackURL ?? url).frame(height: 460).clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                Text("网页播放 · 不缓存，不自动记录完成").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer()
                Button("在浏览器打开") { NSWorkspace.shared.open(url) }.buttonStyle(SettingsButtonStyle())
            }
        }
    }
}

@MainActor
private final class CourseEditorState: ObservableObject {
    @Published var title: String = ""
    @Published var sourceKind: Int = 0
    @Published var address: String = ""
    @Published var video: URL? = nil
    @Published var minutes: Int = 5
    @Published var description: String = ""
    @Published var preparation: String = ""
    @Published var response: String = ""
    @Published var advice: String = ""
    @Published var actions: String = ""
    @Published var cover: String = ""
    @Published var error: String? = nil
    @Published var resolving = false
    @Published var resolvedAddress: String?
    @Published var originalPage: URL?
    @Published var resolutionMessage: String?
    @Published var resolution: VideoLinkResolution?
    @Published var saving: Bool = false
}

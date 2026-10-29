import AppKit
import AVFoundation
import Combine
import CryptoKit
import StillCore

@MainActor
final class CourseLibrary: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var importing = false
    @Published private(set) var revision = 0
    @Published var error: String?
    @Published var selectedID: String?
    @Published var showDetails = false
    let root: URL
    init(isUITest: Bool) {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(isUITest ? "Still-UIValidation/Courses" : "Still/Courses")
        reload()
    }
    func reload() {
        do {
            let url = root.appendingPathComponent("courses.json")
            courses = FileManager.default.fileExists(atPath: url.path) ? try Course.decodeCatalog(Data(contentsOf: url)) : []
            revision += 1; error = nil
        } catch { self.error = Self.message(error) }
    }
    private static func message(_ error: Error) -> String {
        if error is DecodingError { return "课程档案格式不完整，请检查 courses.json。" }
        return error.localizedDescription
    }
    func mediaURL(for course: Course) -> URL? {
        guard let media = course.media else { return nil }
        let url = root.appendingPathComponent(media.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "导入课程"; panel.message = "选择包含 courses.json 和视频的文件夹。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFolder(url)
    }
    func importFolder(_ folder: URL) {
        guard !importing else { return }; importing = true; error = nil
        let root = root
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try Self.install(folder: folder, root: root) }.value
                reload()
            } catch { self.error = Self.message(error) }
            importing = false
        }
    }
    nonisolated private static func install(folder: URL, root: URL) throws {
        let fm = FileManager.default
        let source = folder.resolvingSymlinksInPath()
        let data = try Data(contentsOf: source.appendingPathComponent("courses.json"))
        let courses = try Course.decodeCatalog(data)
        guard !courses.isEmpty else { throw CourseError.invalidCatalog }
        let parent = root.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".courses-import-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        for course in courses {
            guard let media = course.media else { continue }
            let file = source.appendingPathComponent(media.filename).resolvingSymlinksInPath()
            guard file.deletingLastPathComponent() == source else { throw CourseError.unsafeFilename }
            guard fm.fileExists(atPath: file.path) else { throw CourseError.missingMedia }
            if let expected = media.sha256 {
                let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else { throw CourseError.invalidMedia }
            }
            let target = stage.appendingPathComponent(media.filename)
            if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: file, to: target) }
        }
        try data.write(to: stage.appendingPathComponent("courses.json"), options: .atomic)
        if fm.fileExists(atPath: root.path) { _ = try fm.replaceItemAt(root, withItemAt: stage) }
        else { try fm.moveItem(at: stage, to: root) }
    }
}

@MainActor
final class CoursePlayer: ObservableObject {
    @Published private(set) var courseID: String?
    @Published private(set) var title = ""
    @Published private(set) var playing = false
    @Published private(set) var active = false
    @Published private(set) var loading = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var finished = false
    @Published var error: String?
    let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var loadID = UUID()
    private var progress = CourseProgress(duration: 1)
    var sessionID: UUID?
    var onStart: ((Double) -> Void)?
    var onProgress: ((Double, Bool) -> Void)?
    var onStop: (() -> Void)?
    var onState: (() -> Void)?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.observe(time.seconds) }
        }
    }
    func load(_ course: Course, url: URL?) {
        stop(); removeItemObservers(); loadID = UUID(); let request = loadID
        courseID = course.id; title = course.title; position = 0; duration = 0; error = nil; finished = false
        player.replaceCurrentItem(with: nil)
        guard let url else { loading = false; return }
        loading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let seconds = try await asset.load(.duration).seconds
                guard request == loadID else { return }
                guard playable, seconds.isFinite, seconds > 0 else { throw CourseError.invalidMedia }
                duration = seconds; progress = CourseProgress(duration: seconds)
                let item = AVPlayerItem(asset: asset); player.replaceCurrentItem(with: item)
                endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.ended() }
                }
                failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.fail() }
                }
                statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    if item.status == .failed { Task { @MainActor in self?.fail() } }
                }
                loading = false
            } catch {
                guard request == loadID else { return }; loading = false; self.error = error.localizedDescription
            }
        }
    }
    func toggle() {
        guard !loading, error == nil, duration > 0 else { return }
        if playing { pause(); return }
        if !active {
            progress = CourseProgress(duration: duration); position = 0; finished = false
            player.seek(to: .zero); sessionID = UUID(); active = true; onStart?(duration)
        }
        playing = true; player.play(); onState?()
    }
    func pause() {
        guard playing else { return }; observe(player.currentTime().seconds)
        player.pause(); playing = false; onState?()
    }
    func stop() {
        pause()
        if active { active = false; onStop?() }
        sessionID = nil; onState?()
    }
    private func observe(_ time: Double) {
        guard time.isFinite else { return }
        position = max(0, min(duration, time))
        guard active else { return }
        progress.observe(position: position, playing: playing)
        onProgress?(progress.elapsed, false); onState?()
    }
    private func ended() {
        guard active else { return }
        observe(duration); playing = false; active = false; finished = progress.completed
        onProgress?(progress.elapsed, finished)
        if !finished { onStop?(); error = "播放出现中断，本次未计为完整跟练。" }
        sessionID = nil; onState?()
    }
    private func fail() { stop(); error = "视频播放中断，请检查文件后重试。" }
    private func removeItemObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil; failureObserver = nil; statusObserver = nil
    }
    func shutdown() { stop(); removeItemObservers(); if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil } }
}

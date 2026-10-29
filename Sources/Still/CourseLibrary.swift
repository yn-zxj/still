import AppKit
import AVFoundation
import Combine
import CryptoKit
import ImageIO
import StillCore

@MainActor
final class CourseLibrary: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var importing = false
    @Published private(set) var revision = 0
    @Published var error: String?
    @Published var selectedID: String?
    @Published var showDetails = false
    private var thumbnails: [String: NSImage] = [:]
    let remoteThumbnails: RemoteCourseImages
    let videoCache: CourseVideoCache
    let root: URL
    init(isUITest: Bool, rootOverride: URL? = nil) {
        root = rootOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(isUITest ? "Still-UIValidation/Courses" : "Still/Courses")
        remoteThumbnails = RemoteCourseImages(diskRoot: root.deletingLastPathComponent().appendingPathComponent("MediaCache/Images"))
        videoCache = CourseVideoCache(root: root.deletingLastPathComponent().appendingPathComponent("MediaCache/Videos"))
        reload()
    }
    func reload() {
        do {
            let url = root.appendingPathComponent("courses.json")
            courses = FileManager.default.fileExists(atPath: url.path) ? try Course.decodeCatalog(Data(contentsOf: url)) : []
            thumbnails = [:]
            for filename in Set(courses.flatMap { $0.actions.compactMap(\.thumbnail) }) {
                if let image = Self.decodeThumbnail(root.appendingPathComponent(filename)) {
                    thumbnails[filename] = NSImage(cgImage: image, size: .zero)
                }
            }
            revision += 1; error = nil
        } catch { self.error = Self.message(error) }
    }
    private static func message(_ error: Error) -> String {
        if error is DecodingError { return "课程档案格式不完整，请检查 courses.json。" }
        return error.localizedDescription
    }
    func mediaURL(for course: Course) -> URL? {
        guard let media = course.media else { return nil }
        let candidate = media.playbackURL(in: root) { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
        }
        if let candidate, !candidate.isFileURL, let cached = videoCache.cachedURL(for: candidate, expectedSHA256: media.sha256) { return cached }
        return candidate
    }
    func thumbnail(for action: Course.Action) -> NSImage? { action.thumbnail.flatMap { thumbnails[$0] } }
    nonisolated private static func decodeThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 392,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "导入课程"; panel.message = "选择包含 courses.json 的文件夹；本地视频和动作图片请放在同一文件夹。"
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
        let actions = courses.flatMap(\.actions)
        for filename in Set(actions.compactMap(\.thumbnail)) {
            let file = source.appendingPathComponent(filename).resolvingSymlinksInPath()
            guard file.deletingLastPathComponent() == source else { throw CourseError.unsafeFilename }
            guard fm.fileExists(atPath: file.path) else {
                if actions.filter({ $0.thumbnail == filename }).allSatisfy({ $0.thumbnailURL != nil }) { continue }
                throw CourseError.missingThumbnail
            }
            guard Self.decodeThumbnail(file) != nil else { throw CourseError.invalidThumbnail }
            try fm.copyItem(at: file, to: stage.appendingPathComponent(filename))
        }
        for course in courses {
            guard let media = course.media, let filename = media.filename else { continue }
            let file = source.appendingPathComponent(filename).resolvingSymlinksInPath()
            guard file.deletingLastPathComponent() == source else { throw CourseError.unsafeFilename }
            guard fm.fileExists(atPath: file.path) else {
                if media.url != nil { continue }
                throw CourseError.missingMedia
            }
            if let expected = media.sha256 {
                let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else { throw CourseError.invalidMedia }
            }
            let target = stage.appendingPathComponent(filename)
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
    @Published private(set) var buffering = false
    @Published private(set) var caching = false
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var usingCachedVideo = false
    @Published private(set) var videoAvailableOffline = false
    @Published private(set) var cacheError: String?
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var videoAspectRatio: CGFloat = 16 / 9
    @Published private(set) var finished = false
    @Published var error: String?
    let player = AVPlayer()
    let cache: CourseVideoCache?
    private let assetFactory: (URL) -> AVURLAsset
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var loadID = UUID()
    private var loadTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?
    private var asset: AVURLAsset?
    private var watchdog: Timer?
    private var loadStarted: TimeInterval = 0
    private var bufferStarted: TimeInterval?
    private var remote = false
    private var progress = CourseProgress(duration: 1)
    var sessionID: UUID?
    var onStart: ((Double) -> Void)?
    var onProgress: ((Double, Bool) -> Void)?
    var onStop: (() -> Void)?

    init(cache: CourseVideoCache? = nil, assetFactory: @escaping (URL) -> AVURLAsset = { AVURLAsset(url: $0) }) {
        self.cache = cache; self.assetFactory = assetFactory
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.observe(time.seconds) }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLoading() }
        }
    }
    func load(_ course: Course, url: URL?) {
        stop(); removeItemObservers(); loadTask?.cancel(); cacheTask?.cancel(); asset?.cancelLoading(); asset = nil
        loadID = UUID(); let request = loadID
        courseID = course.id; title = course.title; position = 0; duration = 0; videoAspectRatio = 16 / 9; error = nil; finished = false
        caching = false; downloadProgress = nil; usingCachedVideo = false; videoAvailableOffline = false; cacheError = nil
        player.replaceCurrentItem(with: nil)
        guard let url else { loading = false; return }
        guard url.isFileURL || (try? HTTPSResourceURL(url.absoluteString)) != nil else {
            loading = false; error = CourseError.unsafeRemoteURL.localizedDescription; return
        }
        var playbackURL = url
        if !url.isFileURL, let ready = cache?.cachedURL(for: url, expectedSHA256: course.media?.sha256) { playbackURL = ready }
        usingCachedVideo = cache.map { playbackURL.deletingLastPathComponent().standardizedFileURL.path == $0.root.standardizedFileURL.path } ?? false
        videoAvailableOffline = usingCachedVideo
        remote = !playbackURL.isFileURL; loading = true; loadStarted = ProcessInfo.processInfo.systemUptime
        if remote, cache != nil { startCaching(course, url: url, request: request) }
        let loadURL = playbackURL
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let asset = assetFactory(loadURL)
                self.asset = asset
                let playable = try await asset.load(.isPlayable)
                let seconds = try await asset.load(.duration).seconds
                var aspect: CGFloat = 16 / 9
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let displayed = size.applying(transform)
                    let width = abs(displayed.width), height = abs(displayed.height)
                    if width.isFinite, height.isFinite, width > 0, height > 0 { aspect = width / height }
                }
                guard request == loadID else { return }
                videoAspectRatio = aspect
                guard playable, seconds.isFinite, seconds > 0 else { throw CourseError.invalidMedia }
                duration = seconds; progress = CourseProgress(duration: seconds)
                let item = AVPlayerItem(asset: asset); player.replaceCurrentItem(with: item)
                endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if self?.loadID == request { self?.ended() } }
                }
                failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if self?.loadID == request { self?.fail() } }
                }
                statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    if item.status == .failed { Task { @MainActor in if self?.loadID == request { self?.fail() } } }
                }
                loading = false
            } catch {
                guard request == loadID else { return }; loading = false
                self.error = remote ? "视频未能载入，请检查网络或资源地址后重试。" : error.localizedDescription
            }
        }
    }
    private func startCaching(_ course: Course, url: URL, request: UUID) {
        guard let cache else { return }
        caching = true; downloadProgress = nil; cacheError = nil
        cacheTask = Task { [weak self] in
            do {
                _ = try await cache.file(for: url, expectedSHA256: course.media?.sha256) { [weak self] value in
                    guard let self, self.loadID == request else { return }
                    self.downloadProgress = value
                }
                guard let self, self.loadID == request, !Task.isCancelled else { return }
                self.caching = false; self.videoAvailableOffline = true
            } catch {
                guard let self, self.loadID == request, !Task.isCancelled else { return }
                self.caching = false; self.cacheError = "缓存未完成，可继续在线播放。"
            }
        }
    }
    func retryCaching(_ course: Course) {
        guard !caching, !videoAvailableOffline, let url = course.media?.url?.url else { return }
        startCaching(course, url: url, request: loadID)
    }
    func unload() {
        stop(); loadID = UUID(); loadTask?.cancel(); cacheTask?.cancel(); asset?.cancelLoading(); asset = nil
        removeItemObservers(); player.replaceCurrentItem(with: nil)
        courseID = nil; loading = false; caching = false; buffering = false; usingCachedVideo = false
        downloadProgress = nil; position = 0; duration = 0; error = nil; cacheError = nil; videoAvailableOffline = false
    }
    func toggle() {
        guard !loading, error == nil, duration > 0 else { return }
        if playing { pause(); return }
        if !active {
            progress = CourseProgress(duration: duration); position = 0; finished = false
            player.seek(to: .zero); sessionID = UUID(); active = true; onStart?(duration)
        }
        playing = true; player.play()
    }
    func pause() {
        guard playing else { return }; observe(player.currentTime().seconds)
        player.pause(); playing = false; buffering = false; bufferStarted = nil
    }
    func stop() {
        pause()
        if active { active = false; onStop?() }
        sessionID = nil
    }
    private func observe(_ time: Double) {
        guard time.isFinite else { return }
        position = max(0, min(duration, time))
        guard active else { return }
        progress.observe(position: position, playing: playing)
        onProgress?(progress.elapsed, false)
    }
    private func ended() {
        guard active else { return }
        observe(duration); playing = false; active = false; finished = progress.completed
        onProgress?(progress.elapsed, finished)
        if !finished { onStop?(); error = "播放出现中断，本次未计为完整跟练。" }
        sessionID = nil
    }
    private func fail() { stop(); error = remote ? "视频播放中断，请检查网络或资源地址后重试。" : "视频播放中断，请检查文件后重试。" }
    private func checkLoading() {
        let now = ProcessInfo.processInfo.systemUptime
        if loading && now - loadStarted > 30 {
            loadID = UUID(); loadTask?.cancel(); asset?.cancelLoading(); loading = false
            error = remote ? "视频加载超时，请检查网络后重试。" : "视频加载超时，请检查文件后重试。"
        }
        buffering = playing && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if buffering {
            if bufferStarted == nil { bufferStarted = now }
            if now - (bufferStarted ?? now) > 30 { fail() }
        } else { bufferStarted = nil }
    }
    private func removeItemObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil; failureObserver = nil; statusObserver = nil
    }
    func shutdown() {
        stop(); loadID = UUID(); loadTask?.cancel(); cacheTask?.cancel(); cache?.cancelAll(); asset?.cancelLoading(); watchdog?.invalidate(); watchdog = nil
        removeItemObservers(); if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
    }
}

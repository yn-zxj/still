import AppKit
import Combine
import Darwin
import Foundation
import StillCore

struct HAPIProcessOutput: Sendable, Equatable {
    var status: Int32
    var stdout: Data
    var stderr: Data
}

enum HAPIProcessError: LocalizedError {
    case launchFailed(String)
    case timedOut
    case outputTooLarge

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return "无法运行 hapi：\(reason)"
        case .timedOut: return "hapi 一分钟内没有响应"
        case .outputTooLarge: return "hapi 返回的数据过大"
        }
    }
}

enum HAPIProcessRunner {
    typealias Runner = @Sendable (URL, [String], TimeInterval) async throws -> HAPIProcessOutput

    static let run: Runner = { executable, arguments, timeout in
        let executablePath = executable.path
        return try await Task.detached(priority: .utility) {
            try runProcess(executablePath: executablePath, arguments: arguments, timeout: timeout)
        }.value
    }

    private static func runProcess(executablePath: String, arguments: [String],
                                   timeout: TimeInterval) throws -> HAPIProcessOutput {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "still-hapi-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stdoutURL = folder.appendingPathComponent("stdout")
        let stderrURL = folder.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw HAPIProcessError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.4)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw HAPIProcessError.timedOut
        }
        process.waitUntilExit()
        try stdout.close()
        try stderr.close()
        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)
        guard stdoutData.count + stderrData.count <= 32 * 1024 * 1024 else {
            throw HAPIProcessError.outputTooLarge
        }
        return HAPIProcessOutput(status: process.terminationStatus, stdout: stdoutData, stderr: stderrData)
    }
}

struct HAPIBinaryLocator {
    var home: URL
    var override: String?

    var candidates: [URL] {
        var result: [URL] = []
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            result.append(URL(fileURLWithPath: (override as NSString).expandingTildeInPath))
        }
        result += [
            home.appendingPathComponent(".bun/bin/hapi"),
            home.appendingPathComponent(".local/bin/hapi"),
            home.appendingPathComponent(".npm-global/bin/hapi"),
            URL(fileURLWithPath: "/opt/homebrew/bin/hapi"),
            URL(fileURLWithPath: "/usr/local/bin/hapi"),
            URL(fileURLWithPath: "/opt/local/bin/hapi")
        ]
        return result
    }

    func locate() -> URL? {
        let manager = FileManager.default
        for candidate in candidates where manager.fileExists(atPath: candidate.path) {
            let resolved = candidate.resolvingSymlinksInPath()
            if ["cjs", "js"].contains(resolved.pathExtension) {
                let nativePackage = resolved
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("hapi-darwin-\(Self.architecture)/bin/hapi")
                if manager.isExecutableFile(atPath: nativePackage.path) { return nativePackage }
                continue
            }
            if manager.isExecutableFile(atPath: resolved.path) { return resolved }
        }
        return nil
    }

    private static var architecture: String {
        #if arch(x86_64)
        "x64"
        #else
        "arm64"
        #endif
    }
}

@MainActor
final class AgentActivityCoordinator: ObservableObject {
    enum Status: Equatable {
        case disabled
        case notInstalled
        case checking
        case syncing
        case synced(Date)
        case cliTooOld(String?)
        case hubTooOld
        case notSignedIn
        case failed(String)

        var title: String {
            switch self {
            case .disabled: return "已关闭"
            case .notInstalled: return "未找到 hapi"
            case .checking: return "正在检查"
            case .syncing: return "正在同步"
            case .synced(let date): return "已同步 \(date.formatted(.relative(presentation: .named)))"
            case .cliTooOld(let version): return version.map { "hapi \($0) 需要升级" } ?? "hapi 需要升级"
            case .hubTooOld: return "HAPI Hub 需要升级"
            case .notSignedIn: return "HAPI 尚未登录"
            case .failed(let message): return message
            }
        }

        var isError: Bool {
            switch self {
            case .cliTooOld, .hubTooOld, .notSignedIn, .failed: return true
            default: return false
            }
        }

        var isHealthy: Bool {
            if case .synced = self { return true }
            return false
        }
    }

    @Published private(set) var sessions: [AgentActivitySession] = []
    @Published private(set) var status: Status = .disabled
    @Published private(set) var binary: URL?
    @Published private(set) var hubURL: String?

    private let store: AgentActivityStore
    private let home: URL
    private let runner: HAPIProcessRunner.Runner
    private var settings = MonitorSettings()
    private var loop: Task<Void, Never>?
    private var lastAttempt: Date?
    private var lastSuccess: Date?
    private var checkedBinary: URL?
    private var checkedVersion: String?
    private var isSyncing = false
    private let retentionDays = 31

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         store: AgentActivityStore? = nil,
         runner: @escaping HAPIProcessRunner.Runner = HAPIProcessRunner.run) {
        self.home = home
        self.store = store ?? AgentActivityStore(
            fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Still/AgentActivity.json")
        )
        self.runner = runner
        self.sessions = self.store.load(retainingSince: Date().addingTimeInterval(-TimeInterval(retentionDays) * 86_400))
    }

    func configure(_ settings: MonitorSettings, startImmediately: Bool = true) {
        let oldPath = self.settings.hapiExecutablePath
        let wasEnabled = isEnabled
        self.settings = settings
        let enabled = isEnabled
        guard enabled else {
            loop?.cancel()
            loop = nil
            status = .disabled
            binary = nil
            return
        }
        if !wasEnabled || oldPath != settings.hapiExecutablePath || loop == nil {
            if startImmediately {
                startLoop()
            } else {
                loop?.cancel()
                loop = nil
                binary = HAPIBinaryLocator(home: home, override: settings.hapiExecutablePath).locate()
                status = binary == nil ? .notInstalled : .checking
            }
        }
    }

    func requestSync() {
        guard isEnabled else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        Task { await sync() }
    }

    func syncNow() {
        Task { await sync() }
    }

    func clearSessions() {
        sessions = []
        try? store.save([], retainingSince: Date().addingTimeInterval(-TimeInterval(retentionDays) * 86_400))
    }

    func sync(now: Date = Date()) async {
        guard isEnabled, !isSyncing else { return }
        isSyncing = true
        lastAttempt = now
        defer { isSyncing = false }

        guard let binary = HAPIBinaryLocator(home: home, override: settings.hapiExecutablePath).locate() else {
            self.binary = nil
            status = .notInstalled
            return
        }
        self.binary = binary
        status = .checking
        do {
            let version = try await version(of: binary)
            guard Self.isAtLeast(version, "0.30.0") else {
                status = .cliTooOld(version)
                return
            }
            status = .syncing
            let since = now.addingTimeInterval(-TimeInterval(retentionDays) * 86_400 + 3_600)
            let output = try await runner(binary, [
                "usage", "--json",
                "--since", Self.milliseconds(since),
                "--until", Self.milliseconds(now)
            ], 60)
            guard handleExit(output, version: version) else { return }
            let report = try HAPIActivityReport.decode(output.stdout)
            hubURL = report.hubUrl
            let host = ProcessInfo.processInfo.hostName.lowercased()
            let localHosts: Set<String> = [
                host,
                host.hasSuffix(".local") ? String(host.dropLast(6)) : host + ".local"
            ]
            let incoming = HAPIActivityPlanner.plan(report, localHosts: localHosts, now: now)
            var byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
            for session in incoming {
                if let existing = byID[session.id] {
                    var merged = session
                    merged.spans = AgentActivitySession.merged(existing.spans + session.spans)
                    byID[session.id] = merged
                } else {
                    byID[session.id] = session
                }
            }
            let cutoff = now.addingTimeInterval(-TimeInterval(retentionDays) * 86_400)
            let retained = byID.values.filter { ($0.spans.last?.endedAt ?? .distantPast) >= cutoff }
            try store.save(Array(retained), retainingSince: cutoff)
            sessions = retained.sorted {
                ($0.spans.last?.endedAt ?? .distantPast) > ($1.spans.last?.endedAt ?? .distantPast)
            }
            lastSuccess = now
            status = .synced(now)
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    private var isEnabled: Bool {
        settings.agentActivityEnabled && settings.hapiSyncEnabled
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            guard let self else { return }
            await self.sync()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await self.sync()
            }
        }
    }

    private func version(of binary: URL) async throws -> String {
        if checkedBinary == binary, let checkedVersion { return checkedVersion }
        let output = try await runner(binary, ["--version"], 15)
        let text = String(decoding: output.stdout + output.stderr, as: UTF8.self)
        let value = text.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        guard output.status == 0, !value.isEmpty else { throw HAPIProcessError.launchFailed("无法读取版本") }
        checkedBinary = binary
        checkedVersion = value
        return value
    }

    func handleExit(_ output: HAPIProcessOutput, version: String) -> Bool {
        let message = String(decoding: output.stderr, as: UTF8.self)
        switch output.status {
        case 0: return true
        case 3: status = .notSignedIn
        case 4: status = .hubTooOld
        default:
            if message.localizedCaseInsensitiveContains("unknown command") {
                status = .cliTooOld(version)
            } else {
                let line = message.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                status = .failed(
                    line.map { String($0).replacingOccurrences(of: "hapi usage: ", with: "") }
                        ?? "hapi 以状态 \(output.status) 退出"
                )
            }
        }
        return false
    }

    static func isAtLeast(_ version: String, _ minimum: String) -> Bool {
        func parts(_ value: String) -> [Int]? {
            let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                .split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
            let components = clean.split(separator: ".", omittingEmptySubsequences: false)
            guard !components.isEmpty,
                  components.allSatisfy({ component in
                      !component.isEmpty && component.allSatisfy { $0.isNumber }
                  }) else { return nil }
            return components.compactMap { Int($0) }
        }
        guard let left = parts(version), let right = parts(minimum) else { return false }
        for index in 0..<max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return true
    }

    private static func milliseconds(_ date: Date) -> String {
        String(Int64(date.timeIntervalSince1970 * 1000))
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case HAPIReportError.unreadable: return "无法读取 hapi 的活动报告"
        case HAPIReportError.unsupportedSchema(let schema): return "暂不支持 \(schema) 报告格式"
        default: return error.localizedDescription
        }
    }
}

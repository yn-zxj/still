import Foundation
import Testing
@testable import Still
@testable import StillCore

@MainActor
@Suite("HAPI coordinator")
struct AgentActivityCoordinatorTests {
    @Test func versionGateRejectsOldHAPI() {
        #expect(AgentActivityCoordinator.isAtLeast("0.30.0", "0.30.0"))
        #expect(AgentActivityCoordinator.isAtLeast("v0.31.2", "0.30.0"))
        #expect(AgentActivityCoordinator.isAtLeast("1.0", "0.30.9"))
        #expect(!AgentActivityCoordinator.isAtLeast("0.29.99", "0.30.0"))
        #expect(!AgentActivityCoordinator.isAtLeast("0.30.0-beta.2", "0.30.0"))
    }

    @Test func binaryLocatorPrefersExplicitExecutableAndRejectsNonExecutableFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("still-hapi-locator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("hapi")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let locator = HAPIBinaryLocator(home: root, override: executable.path)
        #expect(locator.locate()?.path == executable.path)

        let plain = root.appendingPathComponent("plain-hapi")
        try Data("not executable".utf8).write(to: plain)
        #expect(HAPIBinaryLocator(home: root, override: plain.path).locate() == nil)
    }

    @Test func documentedExitCodesBecomeActionableStates() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("still-hapi-state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = AgentActivityCoordinator(
            store: AgentActivityStore(fileURL: root.appendingPathComponent("activity.json"))
        )
        #expect(!coordinator.handleExit(.init(status: 3, stdout: Data(), stderr: Data()), version: "0.30.0"))
        #expect(coordinator.status == .notSignedIn)
        #expect(!coordinator.handleExit(.init(status: 4, stdout: Data(), stderr: Data()), version: "0.30.0"))
        #expect(coordinator.status == .hubTooOld)
        #expect(!coordinator.handleExit(
            .init(status: 2, stdout: Data(), stderr: Data("hapi usage: unknown command".utf8)),
            version: "0.29.0"
        ))
        #expect(coordinator.status == .cliTooOld("0.29.0"))
    }

    @Test func repeatedSynchronizationMergesByHAPIIdentityAndPersists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("still-hapi-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent("hapi")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let object: [String: Any] = [
            "schema": "hapi.activity.v1",
            "generatedAt": start.timeIntervalSince1970 * 1_000,
            "hubUrl": "https://hub.example.test",
            "localMachineId": "local",
            "since": start.timeIntervalSince1970 * 1_000,
            "until": (start.timeIntervalSince1970 + 600) * 1_000,
            "sessions": [[
                "id": "same-session",
                "flavor": "codex",
                "machineId": "remote",
                "machineName": "远程构建机",
                "title": "Agent 时间去向",
                "path": "/tmp/still",
                "turns": [[
                    "start": start.timeIntervalSince1970 * 1_000,
                    "end": (start.timeIntervalSince1970 + 120) * 1_000
                ]],
                "waits": []
            ]]
        ]
        let report = try JSONSerialization.data(withJSONObject: object)
        let runner: HAPIProcessRunner.Runner = { _, arguments, _ in
            if arguments == ["--version"] {
                return HAPIProcessOutput(status: 0, stdout: Data("0.30.1\n".utf8), stderr: Data())
            }
            return HAPIProcessOutput(status: 0, stdout: report, stderr: Data())
        }
        let storeURL = root.appendingPathComponent("AgentActivity.json")
        let coordinator = AgentActivityCoordinator(
            home: root,
            store: AgentActivityStore(fileURL: storeURL),
            runner: runner
        )
        coordinator.configure(MonitorSettings(), startImmediately: false)
        let now = start.addingTimeInterval(600)
        await coordinator.sync(now: now)
        #expect(coordinator.sessions.count == 1)
        #expect(coordinator.sessions[0].locationLabel == "远程构建机")
        #expect(abs(coordinator.sessions[0].seconds(in: DateInterval(start: start, end: now)) - 120) < 0.001)

        await coordinator.sync(now: now)
        let loaded = AgentActivityStore(fileURL: storeURL).load(retainingSince: start.addingTimeInterval(-31 * 86_400))
        #expect(loaded.count == 1)
        #expect(abs(loaded[0].spans.reduce(0) { $0 + $1.seconds } - 120) < 0.001)
    }
}

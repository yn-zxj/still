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

    @Test func officialHAPIReleaseSelectsTheCurrentMacArchitectureAndChecksum() throws {
        let json = #"""
        {
          "tag_name": "v0.33.3",
          "html_url": "https://github.com/tiann/hapi/releases/tag/v0.33.3",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "checksums.txt",
              "size": 452,
              "browser_download_url": "https://github.com/tiann/hapi/releases/download/v0.33.3/checksums.txt"
            },
            {
              "name": "hapi-darwin-arm64.tar.gz",
              "size": 66082111,
              "browser_download_url": "https://github.com/tiann/hapi/releases/download/v0.33.3/hapi-darwin-arm64.tar.gz"
            },
            {
              "name": "hapi-darwin-x64.tar.gz",
              "size": 68372453,
              "browser_download_url": "https://github.com/tiann/hapi/releases/download/v0.33.3/hapi-darwin-x64.tar.gz"
            }
          ]
        }
        """#
        var release = try JSONDecoder().decode(HAPIReleaseManifest.self, from: Data(json.utf8))
        try release.validate(for: HAPIReleaseClient.repository)
        #expect(release.version == "0.33.3")
        #expect(release.asset(named: "hapi-darwin-arm64.tar.gz")?.size == 66_082_111)
        #expect(release.asset(named: "hapi-darwin-x64.tar.gz")?.size == 68_372_453)
        let checksums = """
        1375cc37f95b03866eec6f5c0b742b9ef3187ac073f92e9817d82092ac5a67e8  hapi-darwin-arm64.tar.gz
        84e0f18bec180a1b2650322973b1d5a3fc11645cd418364f81d769b065237f97  hapi-darwin-x64.tar.gz
        """
        #expect(HAPIReleaseClient.checksum(named: "hapi-darwin-arm64.tar.gz", in: checksums)
            == "1375cc37f95b03866eec6f5c0b742b9ef3187ac073f92e9817d82092ac5a67e8")
        #expect(HAPIReleaseClient.checksum(named: "missing.tar.gz", in: checksums) == nil)

        release.assets[1].downloadURL = URL(string: "https://example.com/hapi.tgz")!
        #expect(throws: HAPIInstallError.invalidRelease) {
            try release.validate(for: HAPIReleaseClient.repository)
        }
    }

    @Test func installerExtractsOnlyVerifiedHAPIBinaryIntoUserDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("still-hapi-install-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let binary = source.appendingPathComponent("hapi")
        try Data("#!/bin/sh\necho 0.33.3\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let archive = root.appendingPathComponent("hapi-darwin-arm64.tar.gz")

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", source.path, "hapi"]
        try tar.run()
        tar.waitUntilExit()
        #expect(tar.terminationStatus == 0)

        let installed = try HAPIInstaller.installVerifiedArchive(archive, version: "0.33.3", home: root)
        #expect(installed.path.hasSuffix("/Library/Application Support/Still/HAPI/bin/hapi"))
        #expect(FileManager.default.isExecutableFile(atPath: installed.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: installed.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let metadata = root.appendingPathComponent("Library/Application Support/Still/HAPI/install.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: String]
        #expect(object?["version"] == "0.33.3")
    }

    @Test func installerRejectsArchivesWithUnexpectedPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("still-hapi-unsafe-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source/nested")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("not hapi".utf8).write(to: source.appendingPathComponent("payload"))
        let archive = root.appendingPathComponent("unsafe.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", root.appendingPathComponent("source").path, "nested/payload"]
        try tar.run()
        tar.waitUntilExit()

        #expect(throws: HAPIInstallError.unsafeArchive) {
            try HAPIInstaller.installVerifiedArchive(archive, version: "0.33.3", home: root)
        }
    }
}

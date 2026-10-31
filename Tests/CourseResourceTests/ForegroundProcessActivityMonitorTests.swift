import Testing
@testable import Still

@MainActor
@Suite(.serialized)
struct ForegroundProcessActivityMonitorTests {
    @Test func requiresConsecutiveProcessActivity() {
        var cpu: UInt64 = 0
        let monitor = ForegroundProcessActivityMonitor(
            minimumCPUPerSecond: 0.002,
            requiredHotSamples: 2,
            cpuProvider: { _ in cpu }
        )

        monitor.update(processID: 100, available: true, at: 10)
        #expect(monitor.idleSeconds(at: 10) == nil)

        cpu = 1_000_000
        monitor.update(processID: 100, available: true, at: 11)
        #expect(monitor.idleSeconds(at: 11) == nil)

        cpu = 5_000_000
        monitor.update(processID: 100, available: true, at: 12)
        #expect(monitor.idleSeconds(at: 12) == nil)

        cpu = 10_000_000
        monitor.update(processID: 100, available: true, at: 13)
        #expect(monitor.idleSeconds(at: 13) == 0)
        #expect(monitor.idleSeconds(at: 14) == 1)
    }

    @Test func processChangeAndUnavailableStateResetCredit() {
        var cpu: UInt64 = 0
        let monitor = ForegroundProcessActivityMonitor(
            minimumCPUPerSecond: 0.001,
            requiredHotSamples: 1,
            cpuProvider: { _ in cpu }
        )

        monitor.update(processID: 100, available: true, at: 1)
        cpu = 5_000_000
        monitor.update(processID: 100, available: true, at: 2)
        #expect(monitor.idleSeconds(at: 2) == 0)

        monitor.update(processID: 101, available: true, at: 3)
        #expect(monitor.idleSeconds(at: 3) == nil)

        cpu = 10_000_000
        monitor.update(processID: 101, available: true, at: 4)
        #expect(monitor.idleSeconds(at: 4) == 0)

        monitor.update(processID: 101, available: false, at: 5)
        #expect(monitor.idleSeconds(at: 5) == nil)
    }
}

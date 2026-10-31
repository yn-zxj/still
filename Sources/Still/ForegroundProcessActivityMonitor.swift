import Darwin
import Foundation

/// Uses only short-term CPU time of the frontmost process tree as a privacy-safe
/// hint that an app is actively drawing or receiving streamed content.
/// Window titles, page data, pixels, text and input payloads are never read.
@MainActor
final class ForegroundProcessActivityMonitor: ObservableObject {
    @Published private(set) var status = "已运行 · 等待前台应用活动"

    private let cpuProvider: (Int32) -> UInt64?
    private let minimumCPUPerSecond: Double
    private let requiredHotSamples: Int
    private var processID: Int32?
    private var previousCPUTime: UInt64?
    private var previousSampleAt: Double?
    private var hotSamples = 0
    private var lastActivityAt: Double?

    init(
        minimumCPUPerSecond: Double = 0.0025,
        requiredHotSamples: Int = 2,
        cpuProvider: @escaping (Int32) -> UInt64? = ProcessTreeCPU.total
    ) {
        self.minimumCPUPerSecond = max(0.0001, minimumCPUPerSecond)
        self.requiredHotSamples = max(1, requiredHotSamples)
        self.cpuProvider = cpuProvider
    }

    func update(processID newProcessID: Int32?, available: Bool, at now: Double) {
        guard available, let newProcessID, newProcessID > 0 else {
            reset(status: "已暂停 · 休息或屏幕不可用时停止")
            return
        }

        if processID != newProcessID {
            processID = newProcessID
            previousCPUTime = cpuProvider(newProcessID)
            previousSampleAt = now
            hotSamples = 0
            lastActivityAt = nil
            status = "已运行 · 等待前台应用活动"
            return
        }

        guard let previousSampleAt, now > previousSampleAt,
              let current = cpuProvider(newProcessID) else {
            self.previousSampleAt = now
            return
        }

        defer {
            previousCPUTime = current
            self.previousSampleAt = now
        }
        guard let previousCPUTime, current >= previousCPUTime else {
            self.previousCPUTime = current
            hotSamples = 0
            status = "进程已重启 · 重新判断"
            return
        }

        let elapsed = now - previousSampleAt
        let cpuRatio = Double(current - previousCPUTime) / 1_000_000_000 / elapsed
        if cpuRatio >= minimumCPUPerSecond {
            hotSamples = min(requiredHotSamples, hotSamples + 1)
            if hotSamples >= requiredHotSamples {
                lastActivityAt = now
                status = "检测到前台界面活动"
            }
        } else {
            hotSamples = 0
            status = "已运行 · 等待前台应用活动"
        }
    }

    func idleSeconds(at now: Double) -> Double? {
        guard let lastActivityAt, now >= lastActivityAt else { return nil }
        return now - lastActivityAt
    }

    func shutdown() {
        reset(status: "已暂停")
    }

    private func reset(status: String) {
        processID = nil
        previousCPUTime = nil
        previousSampleAt = nil
        hotSamples = 0
        lastActivityAt = nil
        self.status = status
    }
}

private enum ProcessTreeCPU {
    static func total(for processID: Int32) -> UInt64? {
        var queue = [processID]
        var visited = Set<Int32>()
        var total: UInt64 = 0
        var readAny = false

        while let current = queue.popLast(), visited.count < 96 {
            guard visited.insert(current).inserted else { continue }
            if let value = cumulativeNanoseconds(for: current) {
                total = total &+ value
                readAny = true
            }
            queue.append(contentsOf: children(of: current))
        }
        return readAny ? total : nil
    }

    private static func cumulativeNanoseconds(for processID: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(processID, RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_user_time &+ info.ri_system_time
    }

    private static func children(of processID: Int32) -> [Int32] {
        var capacity: Int32 = 64
        var buffer = [pid_t](repeating: 0, count: Int(capacity))
        var count = proc_listchildpids(
            processID,
            &buffer,
            Int32(buffer.count * MemoryLayout<pid_t>.size)
        )
        if count >= capacity {
            capacity = count + 64
            buffer = [pid_t](repeating: 0, count: Int(capacity))
            count = proc_listchildpids(
                processID,
                &buffer,
                Int32(buffer.count * MemoryLayout<pid_t>.size)
            )
        }
        guard count > 0 else { return [] }
        return Array(buffer.prefix(Int(count))).filter { $0 > 0 }
    }
}

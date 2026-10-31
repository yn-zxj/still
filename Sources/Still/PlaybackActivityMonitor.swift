import CoreAudio
import Foundation

/// Observes whether the default audio output device is actively rendering.
/// This is used only as an activity-time signal; no audio samples or app data
/// are read, retained, or transmitted.
@MainActor
final class PlaybackActivityMonitor: ObservableObject {
    @Published private(set) var status = "已暂停 · 休息或屏幕不可用时停止"
    @Published private(set) var playing = false

    private var enabled = false
    private var lastPlaybackActivity: Double?

    func update(available: Bool) {
        enabled = available
        guard available else {
            setPlayback(false)
            lastPlaybackActivity = nil
            setStatus("已暂停 · 休息或屏幕不可用时停止")
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard let running = Self.outputIsRunning() else {
            setPlayback(false)
            setStatus("暂不可用 · 使用键鼠活动")
            return
        }
        if running {
            lastPlaybackActivity = now
        }
        setPlayback(running)
        setStatus(running ? "检测到媒体播放" : "已运行 · 等待媒体播放")
    }

    func idleSeconds(at now: Double) -> Double? {
        guard enabled, let lastPlaybackActivity, now >= lastPlaybackActivity else { return nil }
        return now - lastPlaybackActivity
    }

    func shutdown() {
        enabled = false
        lastPlaybackActivity = nil
        setPlayback(false)
        setStatus("已暂停")
    }

    private func setPlayback(_ value: Bool) {
        if playing != value { playing = value }
    }

    private func setStatus(_ value: String) {
        if status != value { status = value }
    }

    private static func outputIsRunning() -> Bool? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress, 0, nil, &deviceSize, &device
        ) == noErr, device != AudioDeviceID(kAudioObjectUnknown) else { return nil }

        var running: UInt32 = 0
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device, &runningAddress, 0, nil, &runningSize, &running
        ) == noErr else { return nil }
        return running != 0
    }
}

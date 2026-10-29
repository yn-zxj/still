import AppKit
import CoreBluetooth
import Combine
import StillCore

@MainActor
final class WatchConnection: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct Device: Identifiable { let peripheral: CBPeripheral; let name: String; var id: UUID { peripheral.identifier } }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var status = "尚未连接"
    @Published private(set) var scanning = false
    @Published private(set) var connected = false
    @Published private(set) var supportsCourses = false
    @Published private(set) var heartRate: Int?
    @Published private(set) var deviceName: String?
    @Published private(set) var lastReading: Date?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var stateCharacteristic: CBCharacteristic?
    private var scanTimer: Timer?
    private var connectionTimer: Timer?
    private var freshnessTimer: Timer?
    private var pendingScan = false
    private var writing = false
    private var queuedState: Data?
    private var lastSent: Data?
    private var currentState: Data?
    private var lastState: Date = .distantPast
    private var sessionID: UUID?
    var onCommand: ((WatchCommand) -> Void)?
    private let heartService = CBUUID(string: "180D")
    private let heartMeasurement = CBUUID(string: "2A37")
    private let stillService = CBUUID(string: WatchProtocol.service)

    func scan() {
        guard !connected, peripheral == nil else { return }
        pendingScan = true; status = "正在请求蓝牙，请留意系统权限提示"
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.pendingScan else { return }
                    self.status = "蓝牙尚未就绪，请检查系统权限或解锁 Mac"
                }
            }
        }
        else { beginScanIfReady() }
    }
    private func beginScanIfReady() {
        guard let central, central.state == .poweredOn, pendingScan else { return }
        pendingScan = false; devices = []; scanning = true; status = "正在寻找心率设备…"
        central.scanForPeripherals(withServices: [heartService, stillService], options: nil)
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopScan() }
        }
    }
    func stopScan() {
        central?.stopScan(); scanTimer?.invalidate(); scanning = false; pendingScan = false
        if !connected, peripheral == nil { status = devices.isEmpty ? "未发现心率广播" : "请选择你的设备" }
    }
    func connect(_ device: Device) {
        guard peripheral == nil else { return }
        stopScan(); peripheral = device.peripheral; deviceName = device.name
        device.peripheral.delegate = self; status = "正在连接…"
        central?.connect(device.peripheral)
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.connected else { return }
                self.disconnect(); self.status = "连接超时，请确认手表正在广播。"
            }
        }
    }
    func disconnect() {
        stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        clearConnection(); status = "已断开"
    }
    private func clearConnection() {
        peripheral = nil; connected = false; supportsCourses = false; heartRate = nil; lastReading = nil
        stateCharacteristic = nil; writing = false; queuedState = nil; lastSent = nil
        connectionTimer?.invalidate(); freshnessTimer?.invalidate()
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "蓝牙已就绪"; beginScanIfReady()
        case .poweredOff: stopScan(); clearConnection(); status = "请打开 Mac 蓝牙"
        case .unauthorized: stopScan(); clearConnection(); status = "请在系统设置中允许息间使用蓝牙"
        case .unsupported: pendingScan = false; status = "这台 Mac 不支持蓝牙低功耗"
        default: status = "蓝牙准备中…"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !devices.contains(where: { $0.id == peripheral.identifier }) else { return }
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let still = manufacturer.flatMap { String(data: $0.dropFirst(2), encoding: .utf8) } == "Still Link"
        devices.append(Device(peripheral: peripheral, name: still ? "Still Link · 手表" : advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "心率设备"))
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == self.peripheral else { return }
        status = "正在检查服务…"; peripheral.discoverServices([heartService, stillService])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }; clearConnection(); status = "连接失败，请重试"
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }; clearConnection(); status = "连接已断开"
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == self.peripheral else { return }
        guard error == nil, let services = peripheral.services, services.contains(where: { $0.uuid == heartService }) else {
            disconnect(); status = "设备未提供标准心率服务"; return
        }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == self.peripheral, error == nil else { return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == heartMeasurement, characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid == CBUUID(string: WatchProtocol.state), characteristic.properties.contains(.write) {
                stateCharacteristic = characteristic
            }
            if characteristic.uuid == CBUUID(string: WatchProtocol.control), characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral else { return }
        if characteristic.uuid == heartMeasurement {
            guard error == nil, characteristic.isNotifying else { disconnect(); status = "心率订阅失败，请在手表确认蓝牙连接"; return }
            connected = true; status = "已连接 · 等待心率"; connectionTimer?.invalidate()
            freshnessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.supportsCourses, let state = self.currentState, Date().timeIntervalSince(self.lastState) >= 2 { self.sendState(state) }
                    if let last = self.lastReading, Date().timeIntervalSince(last) > 10 { self.heartRate = nil; self.status = "已连接 · 心率暂未更新" }
                }
            }
        } else if characteristic.uuid == CBUUID(string: WatchProtocol.control) {
            supportsCourses = error == nil && characteristic.isNotifying && stateCharacteristic != nil
            if supportsCourses, let currentState { sendState(currentState) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral, error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == heartMeasurement {
            guard let measurement = HeartRateMeasurement.decode(data) else { heartRate = nil; status = "已连接 · 等待有效心率"; return }
            heartRate = measurement.bpm; lastReading = Date(); status = "已连接 · 实时心率"
        } else if characteristic.uuid == CBUUID(string: WatchProtocol.control), supportsCourses,
                  let command = WatchProtocol.command(data, sessionID: sessionID) { onCommand?(command) }
    }
    func sync(player: CoursePlayer) {
        sessionID = player.sessionID
        let token = player.sessionID.map { String($0.uuidString.prefix(8)) } ?? "-"
        let phase = player.active ? (player.playing ? "R" : "P") : "E"
        let title = String(player.title.replacingOccurrences(of: "|", with: " ").prefix(32))
        let data = Data("\(token)|\(phase)|\(Int(max(0, player.duration - player.position)))|\(title)".utf8)
        let force = currentState.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "|").prefix(2) != String(data: data, encoding: .utf8)?.split(separator: "|").prefix(2)
        currentState = data
        guard supportsCourses, force || Date().timeIntervalSince(lastState) >= 1 else { return }
        sendState(data)
    }
    private func sendState(_ data: Data) {
        guard let peripheral, let characteristic = stateCharacteristic else { return }
        if writing { queuedState = data; return }
        writing = true; lastSent = data; lastState = Date()
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral, characteristic == stateCharacteristic else { return }
        writing = false
        if error != nil { supportsCourses = false; status = "心率连接保留 · 课程同步失败"; lastSent = nil }
        if supportsCourses, let data = queuedState { queuedState = nil; sendState(data) }
    }
}

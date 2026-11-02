import AppKit
import CoreBluetooth
import Combine
import AirCore

struct Sensor: Identifiable {
    let id: String
    var samples: [Metric: Sample] = [:]
    var lastSeen: Date
    var rssi: Int
}

@MainActor
final class Monitor: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    @Published var sensors: [String: Sensor] = [:]
    @Published var now = Date()
    @Published var status = "Запуск Bluetooth…"
    @Published var poweredOn = false
    @Published var selected: Metric {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: "metric"); onChange?() }
    }
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "sensor"); onChange?() }
    }
    @Published var zones: [Metric: RedZone] {
        didSet {
            if let data = try? JSONEncoder().encode(zones) { UserDefaults.standard.set(data, forKey: "zones") }
            onChange?()
        }
    }
    var onChange: (() -> Void)?
    private var pendingSensors: [String: Sensor] = [:]
    private var publicationCadence = PublicationCadence()
    private var lastDiagnostic = Date.distantPast
    private var central: CBCentralManager!
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    override init() {
        selected = Metric(rawValue: UserDefaults.standard.string(forKey: "metric") ?? "co2") ?? .co2
        selectedID = UserDefaults.standard.string(forKey: "sensor") ?? ""
        zones = UserDefaults.standard.data(forKey: "zones").flatMap { try? JSONDecoder().decode([Metric: RedZone].self, from: $0) } ?? [:]
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date(); self?.publishPendingIfDue(); self?.onChange?() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.publicationCadence.reset()
                self.pendingSensors = self.sensors
                self.rescan()
                self.onChange?()
            }
        }
    }
    var sensor: Sensor? { sensors[selectedID] }
    var samples: [Metric: Sample] { poweredOn ? sensor?.samples ?? [:] : [:] }
    var alerts: [Metric] { DisplayPolicy.alerts(samples: samples, zones: zones, now: now) }
    var displayed: Metric { DisplayPolicy.displayed(selected: selected, samples: samples, zones: zones, now: now) }
    func fresh(_ metric: Metric) -> Sample? {
        guard let s = samples[metric], s.isFresh(at: now) else { return nil }
        return s
    }
    var connectionText: String {
        guard poweredOn else { return status }
        guard let sensor else { return "Поиск датчика поблизости…" }
        let age = max(0, Int(now.timeIntervalSince(sensor.lastSeen)))
        return age < 120 ? "Bluetooth · обновлено \(age) с назад" : "Нет сигнала · \(age) с без данных"
    }
    func rescan() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        central.scanForPeripherals(withServices: [CBUUID(string: "FDCD")], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        poweredOn = central.state == .poweredOn
        switch central.state {
        case .poweredOn:
            status = "Поиск датчика…"
            now = Date()
            publicationCadence.reset()
            pendingSensors = sensors
            rescan()
        case .poweredOff: status = "Bluetooth выключен"
        case .unauthorized: status = "Разрешите Bluetooth в настройках macOS"
        case .unsupported: status = "Bluetooth недоступен"
        default: status = "Ожидание Bluetooth…"
        }
        onChange?()
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let services = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let data = services[CBUUID(string: "FDCD")], let reading = Advertisement.decode(data) else { return }
        let time = Date()
        var sensor = pendingSensors[reading.deviceID] ?? Sensor(id: reading.deviceID, lastSeen: time, rssi: RSSI.intValue)
        for metric in Metric.allCases {
            if let value = metric.value(in: reading) { sensor.samples[metric] = Sample(value: value, date: time) }
        }
        sensor.lastSeen = time; sensor.rssi = RSSI.intValue
        pendingSensors[sensor.id] = sensor
        publishPendingIfDue(at: time)
        if CommandLine.arguments.contains("--diagnostics"), time.timeIntervalSince(lastDiagnostic) >= 10 {
            let values = Metric.allCases.compactMap { metric -> String? in
                guard let value = metric.value(in: reading) else { return nil }
                return "\(metric.rawValue)=\(value)"
            }
            print("BLE reading: " + values.joined(separator: " "))
            fflush(stdout)
            lastDiagnostic = time
        }
    }
    private func publishPendingIfDue(at time: Date? = nil) {
        let time = time ?? now
        var changed = false
        for (id, pending) in pendingSensors {
            // Never advance the publication clock by re-emitting an unchanged cached reading.
            guard sensors[id].map({ pending.lastSeen > $0.lastSeen }) ?? true,
                  publicationCadence.shouldPublish(deviceID: id, at: time) else { continue }
            sensors[id] = pending
            if selectedID.isEmpty { selectedID = id }
            changed = true
        }
        if changed {
            now = time
            onChange?()
        }
    }
}

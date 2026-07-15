import CoreBluetooth
import Foundation

@MainActor
final class BluetoothProbe: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [PeripheralSnapshot] = []
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDeviceCount = 0
    @Published private(set) var result: ProbeResult = .waiting
    @Published private(set) var logLines: [String] = []
    @Published var selectedDeviceID: UUID?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var snapshots: [UUID: PeripheralSnapshot] = [:]
    private var scanTask: Task<Void, Never>?
    private var wantsScan = false
    private var autoConnectAttempted = Set<UUID>()
    private var seenPeripheralIDs = Set<UUID>()

    let logFileURL: URL

    override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFileURL = documents.appendingPathComponent("buds-bluetooth-probe.log")
        super.init()
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        appendLog("Probe initialized. Public CoreBluetooth only; no private entitlements.")
    }

    var candidateDevices: [PeripheralSnapshot] {
        devices.filter(\.isCandidate)
    }

    var selectedDevice: PeripheralSnapshot? {
        guard let selectedDeviceID else { return candidateDevices.first }
        return snapshots[selectedDeviceID]
    }

    var hasWritableGatt: Bool {
        candidateDevices.contains { $0.writableCharacteristicCount > 0 }
    }

    var canControlBuds: Bool {
        // A writable characteristic alone is not enough; the Samsung packet mapping must be validated first.
        false
    }

    func startScan() {
        wantsScan = true
        guard central.state == .poweredOn else {
            appendLog("Scan queued; Bluetooth state is \(central.state.debugName).")
            return
        }

        scanTask?.cancel()
        snapshots.removeAll()
        devices.removeAll()
        peripherals.removeAll()
        autoConnectAttempted.removeAll()
        seenPeripheralIDs.removeAll()
        discoveredDeviceCount = 0
        selectedDeviceID = nil
        result = .scanning
        isScanning = true

        let matchOptions: [CBConnectionEventMatchingOption: Any] = [
            .serviceUUIDs: [BudsProtocol.samsungSPPService, BudsProtocol.leAudioService]
        ]
        central.registerForConnectionEvents(options: matchOptions)

        let connected = central.retrieveConnectedPeripherals(withServices: [
            BudsProtocol.samsungSPPService,
            BudsProtocol.leAudioService
        ])
        appendLog("Connected-peripheral lookup returned \(connected.count) device(s).")
        for peripheral in connected {
            recordRetrieved(peripheral)
        }

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        appendLog("Foreground scan started without a service filter.")

        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        appendLog("Scan stopped. Discovered \(discoveredDeviceCount) device(s), \(candidateDevices.count) Buds candidate(s).")
        refreshResult()
    }

    func connect(to id: UUID) {
        guard let peripheral = peripherals[id] else { return }
        selectedDeviceID = id
        appendLog("Connecting to \(displayName(for: peripheral)) [\(id.uuidString)]...")
        central.connect(peripheral)
    }

    func disconnect() {
        guard let selectedDeviceID, let peripheral = peripherals[selectedDeviceID] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func clearLog() {
        logLines.removeAll()
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        appendLog("Log cleared.")
    }

    private func recordRetrieved(_ peripheral: CBPeripheral) {
        let candidate = BudsProtocol.isCandidate(
            name: peripheral.name,
            manufacturerData: nil,
            serviceUUIDs: []
        )
        guard candidate else { return }
        peripherals[peripheral.identifier] = peripheral
        snapshots[peripheral.identifier] = PeripheralSnapshot(
            id: peripheral.identifier,
            name: displayName(for: peripheral),
            rssi: 0,
            isCandidate: candidate,
            manufacturerHex: nil,
            advertisedServiceUUIDs: [],
            isConnected: peripheral.state == .connected,
            services: []
        )
        publishSnapshots()
        if candidate {
            connectCandidateIfNeeded(peripheral)
        }
    }

    private func connectCandidateIfNeeded(_ peripheral: CBPeripheral) {
        guard !autoConnectAttempted.contains(peripheral.identifier) else { return }
        autoConnectAttempted.insert(peripheral.identifier)
        selectedDeviceID = peripheral.identifier
        appendLog("Buds candidate matched; attempting automatic GATT connection.")
        central.connect(peripheral)
    }

    private func publishSnapshots() {
        devices = snapshots.values.sorted {
            if $0.isCandidate != $1.isCandidate { return $0.isCandidate && !$1.isCandidate }
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func refreshResult() {
        if isScanning {
            result = .scanning
        } else if candidateDevices.isEmpty {
            result = .noCandidate
        } else if candidateDevices.contains(where: { $0.isConnected && $0.services.isEmpty }) {
            result = .connectedNoServices
        } else if hasWritableGatt {
            result = .writableGatt
        } else if candidateDevices.contains(where: { !$0.services.isEmpty }) {
            result = .gattReadOnly
        } else {
            result = .candidateFound
        }
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        logLines.append(line)
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
        guard let data = (line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        print("[BudsProbe] \(message)")
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "未命名蓝牙设备"
    }
}

extension BluetoothProbe: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = central.state
            appendLog("Bluetooth state changed to \(central.state.debugName).")
            if central.state == .poweredOn, wantsScan {
                startScan()
            } else if central.state != .poweredOn {
                isScanning = false
                result = .waiting
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            if seenPeripheralIDs.insert(peripheral.identifier).inserted {
                discoveredDeviceCount = seenPeripheralIDs.count
            }
            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let name = localName ?? peripheral.name
            let candidate = BudsProtocol.isCandidate(
                name: name,
                manufacturerData: manufacturerData,
                serviceUUIDs: serviceUUIDs
            )
            guard candidate else { return }

            peripherals[peripheral.identifier] = peripheral
            let wasKnown = snapshots[peripheral.identifier] != nil
            let oldServices = snapshots[peripheral.identifier]?.services ?? []
            snapshots[peripheral.identifier] = PeripheralSnapshot(
                id: peripheral.identifier,
                name: name?.nilIfEmpty ?? "未命名蓝牙设备",
                rssi: RSSI.intValue,
                isCandidate: candidate,
                manufacturerHex: manufacturerData?.upperHex,
                advertisedServiceUUIDs: serviceUUIDs.map(\.uuidString).sorted(),
                isConnected: peripheral.state == .connected,
                services: oldServices
            )
            publishSnapshots()

            if !wasKnown {
                appendLog(
                    "Discovered \(name ?? "<unnamed>") rssi=\(RSSI) "
                    + "candidate=\(candidate) services=\(serviceUUIDs.map(\.uuidString)) "
                    + "manufacturer=\(manufacturerData?.upperHex ?? "none")"
                )
            }

            if candidate {
                result = .candidateFound
                connectCandidateIfNeeded(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            if var snapshot = snapshots[peripheral.identifier] {
                snapshot.isConnected = true
                snapshots[peripheral.identifier] = snapshot
            }
            selectedDeviceID = peripheral.identifier
            publishSnapshots()
            result = .connectedNoServices
            appendLog("Connected to \(displayName(for: peripheral)); discovering all services.")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            appendLog("Connection failed for \(displayName(for: peripheral)): \(error?.localizedDescription ?? "unknown error")")
            refreshResult()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        Task { @MainActor in
            if var snapshot = snapshots[peripheral.identifier] {
                snapshot.isConnected = false
                snapshots[peripheral.identifier] = snapshot
            }
            publishSnapshots()
            appendLog("Disconnected from \(displayName(for: peripheral)): \(error?.localizedDescription ?? "normal")")
            refreshResult()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        connectionEventDidOccur event: CBConnectionEvent,
        for peripheral: CBPeripheral
    ) {
        Task { @MainActor in
            appendLog("System connection event \(event.rawValue) for \(displayName(for: peripheral)).")
            recordRetrieved(peripheral)
        }
    }
}

extension BluetoothProbe: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                appendLog("Service discovery failed: \(error.localizedDescription)")
                return
            }
            let services = peripheral.services ?? []
            appendLog("Discovered \(services.count) service(s): \(services.map { $0.uuid.uuidString })")
            if var snapshot = snapshots[peripheral.identifier] {
                snapshot.services = services.map {
                    ServiceSnapshot(id: $0.uuid.uuidString, uuid: $0.uuid.uuidString, characteristics: [])
                }
                snapshots[peripheral.identifier] = snapshot
                publishSnapshots()
            }
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
            refreshResult()
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                appendLog("Characteristic discovery failed for \(service.uuid): \(error.localizedDescription)")
                return
            }
            let characteristics = service.characteristics ?? []
            let records = characteristics.map {
                CharacteristicSnapshot(
                    id: "\(service.uuid.uuidString)/\($0.uuid.uuidString)",
                    uuid: $0.uuid.uuidString,
                    properties: $0.properties.readableNames,
                    lastValueHex: nil
                )
            }
            appendLog(
                "Service \(service.uuid.uuidString) characteristics: "
                + records.map { "\($0.uuid){\($0.properties.joined(separator: ","))}" }.joined(separator: " ")
            )

            if var snapshot = snapshots[peripheral.identifier],
               let index = snapshot.services.firstIndex(where: { $0.uuid == service.uuid.uuidString }) {
                snapshot.services[index].characteristics = records
                snapshots[peripheral.identifier] = snapshot
                publishSnapshots()
            }

            for characteristic in characteristics {
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            refreshResult()
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                appendLog("Read/notify failed for \(characteristic.uuid): \(error.localizedDescription)")
                return
            }
            let value = characteristic.value?.upperHex ?? "<empty>"
            appendLog("Value \(characteristic.service?.uuid.uuidString ?? "?")/\(characteristic.uuid.uuidString): \(value)")

            guard var snapshot = snapshots[peripheral.identifier],
                  let serviceUUID = characteristic.service?.uuid.uuidString,
                  let serviceIndex = snapshot.services.firstIndex(where: { $0.uuid == serviceUUID }),
                  let characteristicIndex = snapshot.services[serviceIndex].characteristics.firstIndex(
                    where: { $0.uuid == characteristic.uuid.uuidString }
                  ) else { return }
            snapshot.services[serviceIndex].characteristics[characteristicIndex].lastValueHex = value
            snapshots[peripheral.identifier] = snapshot
            publishSnapshots()
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            appendLog(
                "Notify \(characteristic.uuid.uuidString) active=\(characteristic.isNotifying) "
                + "error=\(error?.localizedDescription ?? "none")"
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension CBManagerState {
    var debugName: String {
        switch self {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "future(\(rawValue))"
        }
    }
}

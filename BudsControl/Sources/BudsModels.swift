import CoreBluetooth
import Foundation

enum NoiseControlMode: String, CaseIterable, Identifiable {
    case off
    case ambient
    case adaptive
    case noiseCancelling

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "关闭"
        case .ambient: "环境声"
        case .adaptive: "自适应"
        case .noiseCancelling: "降噪"
        }
    }

    var symbol: String {
        switch self {
        case .off: "speaker.slash"
        case .ambient: "ear"
        case .adaptive: "waveform.badge.magnifyingglass"
        case .noiseCancelling: "waveform.path.ecg"
        }
    }
}
enum EqualizerPreset: Int, CaseIterable, Identifiable {
    case normal
    case bassBoost
    case soft
    case dynamic
    case clear
    case trebleBoost

    var id: Self { self }

    var title: String {
        switch self {
        case .normal: "正常"
        case .bassBoost: "低音增强"
        case .soft: "柔和"
        case .dynamic: "动态"
        case .clear: "清晰"
        case .trebleBoost: "高音增强"
        }
    }
}

enum ProbeResult: Equatable {
    case waiting
    case scanning
    case noCandidate
    case candidateFound
    case connectedNoServices
    case gattReadOnly
    case writableGatt

    var title: String {
        switch self {
        case .waiting: "等待蓝牙"
        case .scanning: "正在探测控制通道"
        case .noCandidate: "未发现 Buds GATT 通道"
        case .candidateFound: "已发现 Buds，准备连接"
        case .connectedNoServices: "已连接，未发现服务"
        case .gattReadOnly: "发现 GATT，但没有可写特征"
        case .writableGatt: "发现可写 GATT 特征"
        }
    }

    var colorName: String {
        switch self {
        case .writableGatt: "green"
        case .candidateFound, .scanning: "blue"
        case .waiting: "gray"
        case .noCandidate, .connectedNoServices, .gattReadOnly: "orange"
        }
    }
}

struct CharacteristicSnapshot: Identifiable, Equatable {
    let id: String
    let uuid: String
    let properties: [String]
    var lastValueHex: String?

    var isWritable: Bool {
        properties.contains("write") || properties.contains("writeWithoutResponse")
    }
}

struct ServiceSnapshot: Identifiable, Equatable {
    let id: String
    let uuid: String
    var characteristics: [CharacteristicSnapshot]
}

struct PeripheralSnapshot: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var isCandidate: Bool
    var manufacturerHex: String?
    var advertisedServiceUUIDs: [String]
    var isConnected: Bool
    var services: [ServiceSnapshot]

    var writableCharacteristicCount: Int {
        services.flatMap(\.characteristics).filter(\.isWritable).count
    }
}

extension CBCharacteristicProperties {
    var readableNames: [String] {
        var names: [String] = []
        if contains(.broadcast) { names.append("broadcast") }
        if contains(.read) { names.append("read") }
        if contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if contains(.write) { names.append("write") }
        if contains(.notify) { names.append("notify") }
        if contains(.indicate) { names.append("indicate") }
        if contains(.authenticatedSignedWrites) { names.append("signedWrite") }
        if contains(.extendedProperties) { names.append("extended") }
        if contains(.notifyEncryptionRequired) { names.append("notifyEncrypted") }
        if contains(.indicateEncryptionRequired) { names.append("indicateEncrypted") }
        return names
    }
}

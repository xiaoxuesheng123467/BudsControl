import CoreBluetooth
import Foundation

enum NoiseControlMode: String, CaseIterable, Identifiable, Codable {
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

    var commandValue: UInt8 {
        switch self {
        case .off: 0
        case .noiseCancelling: 1
        case .ambient: 2
        case .adaptive: 3
        }
    }

    init?(commandValue: Int) {
        switch commandValue {
        case 0: self = .off
        case 1: self = .noiseCancelling
        case 2: self = .ambient
        case 3: self = .adaptive
        default: return nil
        }
    }
}

enum EqualizerPreset: Int, CaseIterable, Identifiable, Codable {
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

enum AmbientSoundLevel: Int, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high

    var id: Self { self }

    var title: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

enum AmbientSoundTone: Int, CaseIterable, Identifiable, Codable {
    case softPlus2
    case softPlus1
    case neutral
    case clearPlus1
    case clearPlus2

    var id: Self { self }

    var title: String {
        switch self {
        case .softPlus2: "柔和 +2"
        case .softPlus1: "柔和 +1"
        case .neutral: "均衡"
        case .clearPlus1: "清晰 +1"
        case .clearPlus2: "清晰 +2"
        }
    }
}

enum VoiceDetectTimeout: Int, CaseIterable, Identifiable, Codable {
    case fiveSeconds
    case tenSeconds
    case fifteenSeconds

    var id: Self { self }

    var title: String {
        switch self {
        case .fiveSeconds: "5 秒"
        case .tenSeconds: "10 秒"
        case .fifteenSeconds: "15 秒"
        }
    }
}

enum TouchAction: Int, CaseIterable, Identifiable, Codable {
    case voiceAssistant = 1
    case noiseControl = 2
    case volume = 3
    case spotify = 4

    var id: Self { self }

    var title: String {
        switch self {
        case .voiceAssistant: "语音助手"
        case .noiseControl: "切换噪声模式"
        case .volume: "音量"
        case .spotify: "Spotify"
        }
    }
}

enum NoiseControlCycle: Int, CaseIterable, Identifiable, Codable {
    case noiseCancellingAndAmbient = 8
    case noiseCancellingAndOff = 12
    case ambientAndOff = 4

    var id: Self { self }

    var title: String {
        switch self {
        case .noiseCancellingAndAmbient: "降噪 / 环境声"
        case .noiseCancellingAndOff: "降噪 / 关闭"
        case .ambientAndOff: "环境声 / 关闭"
        }
    }
}

enum FitTestResult: Int, Equatable, Codable {
    case bad
    case good
    case failed

    var title: String {
        switch self {
        case .bad: "需要调整"
        case .good: "贴合良好"
        case .failed: "测试失败"
        }
    }
}

enum FeatureVerification: String {
    case hardwareVerified
    case protocolMapped
    case experimental
    case readOnly

    var title: String {
        switch self {
        case .hardwareVerified: "真机确认"
        case .protocolMapped: "待真机验证"
        case .experimental: "实验功能"
        case .readOnly: "只读状态"
        }
    }
}

struct BudsDeviceSettings: Equatable, Codable {
    var revision: Int?
    var noiseMode: NoiseControlMode?
    var equalizer: EqualizerPreset?
    var ambientVolume = AmbientSoundLevel.medium
    var noiseReductionHigh = true
    var ambientCustomizationEnabled = false
    var ambientVolumeLeft = 2
    var ambientVolumeRight = 2
    var ambientTone = AmbientSoundTone.neutral
    var voiceDetectEnabled = false
    var voiceDetectTimeout = VoiceDetectTimeout.fiveSeconds
    var noiseControlWithOneEarbud = false
    var touchLocked = false
    var singleTapEnabled = true
    var doubleTapEnabled = true
    var tripleTapEnabled = true
    var touchAndHoldEnabled = true
    var doubleTapCallEnabled = true
    var touchAndHoldCallEnabled = true
    var leftTouchAction = TouchAction.noiseControl
    var rightTouchAction = TouchAction.noiseControl
    var leftNoiseCycle = NoiseControlCycle.noiseCancellingAndAmbient
    var rightNoiseCycle = NoiseControlCycle.noiseCancellingAndAmbient
    var edgeDoubleTapVolume = false
    var stereoBalance = 16
    var seamlessConnection = true
    var sidetoneEnabled = false
    var callPathControlEnabled = true
    var extraClearCallEnabled = false
    var extraHighAmbientEnabled = false
    var spatialAudioEnabled = false
    var gamingModeEnabled = false
    var autoPauseResumeEnabled = true
    var adaptiveVolumeEnabled = false
    var sirenDetectEnabled = false
    var lightingControl: Int?
    var hotCommandEnabled: Bool?
    var adaptSoundEnabled: Bool?
    var fitTestLeft: FitTestResult?
    var fitTestRight: FitTestResult?

    static let demo: BudsDeviceSettings = {
        var settings = BudsDeviceSettings()
        settings.revision = 1
        settings.noiseMode = .noiseCancelling
        settings.equalizer = .dynamic
        settings.voiceDetectEnabled = true
        settings.noiseControlWithOneEarbud = true
        settings.edgeDoubleTapVolume = true
        settings.extraClearCallEnabled = true
        settings.autoPauseResumeEnabled = true
        settings.lightingControl = 1
        settings.hotCommandEnabled = false
        settings.adaptSoundEnabled = false
        return settings
    }()
}

struct BudsCommandLogEntry: Identifiable, Equatable {
    enum Outcome: String {
        case acknowledged = "耳机 ACK"
        case written = "已写入"
        case simulated = "离线模拟"
        case failed = "失败"
    }

    let id = UUID()
    let date: Date
    let title: String
    let packetHex: String
    let outcome: Outcome
    let detail: String
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

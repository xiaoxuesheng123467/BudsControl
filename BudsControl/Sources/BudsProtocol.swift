import CoreBluetooth
import Foundation

enum BudsProtocol {
    static let samsungSPPService = CBUUID(string: "2E73A4AD-332D-41FC-90E2-16BEF06523F2")
    static let standardSPPService = CBUUID(string: "00001101-0000-1000-8000-00805F9B34FB")
    static let leAudioService = CBUUID(string: "0000184E-0000-1000-8000-00805F9B34FB")
    static let targetNames = ["galaxy buds3 pro", "galaxy buds", "buds3 pro", "sm-r630"]

    static func isCandidate(
        name: String?,
        manufacturerData: Data?,
        serviceUUIDs: [CBUUID]
    ) -> Bool {
        let normalizedName = name?.lowercased() ?? ""
        if targetNames.contains(where: normalizedName.contains) {
            return true
        }

        if serviceUUIDs.contains(samsungSPPService) || serviceUUIDs.contains(leAudioService) {
            return true
        }

        // Samsung's company identifier is shared by phones, watches, TVs, and other
        // accessories, so manufacturer data alone is deliberately not a match.
        return false
    }
}

enum BudsMessageID: UInt8 {
    case extraClearCall = 0x48
    case requestDebugState = 0x26
    case pauseWhenRemoved = 0x6C
    case callPathControl = 0x6E
    case noiseControlWithOneEarbud = 0x6F
    case noiseControls = 0x78
    case touchNoiseCycle = 0x79
    case voiceDetect = 0x7A
    case voiceDetectTimeout = 0x7B
    case spatialAudio = 0x7C
    case customizeAmbient = 0x82
    case noiseReductionLevel = 0x83
    case ambientVolume = 0x84
    case equalizer = 0x86
    case gamingMode = 0x87
    case sidetone = 0x8B
    case hearingEnhancements = 0x8F
    case touchLock = 0x90
    case touchAndHold = 0x92
    case outsideDoubleTap = 0x95
    case extraHighAmbient = 0x96
    case fitTest = 0x9D
    case fitTestResult = 0x9E
    case findEarbudsStop = 0xA1
    case muteEarbuds = 0xA2
    case findEarbudsStartWhileWearing = 0xA6
    case seamlessConnection = 0xAF
    case adaptiveVolume = 0xC5
    case sirenDetect = 0xDE
}

enum BudsNoiseCommand: UInt8 {
    case off = 0
    case noiseCancelling = 1
    case ambient = 2
}

enum BudsEqualizerCommand: UInt8 {
    case normal = 0
    case bassBoost = 1
    case soft = 2
    case dynamic = 3
    case clear = 4
    case trebleBoost = 5
}

struct BudsSPPPacket: Equatable {
    static let startByte: UInt8 = 0xFD
    static let endByte: UInt8 = 0xDD

    let messageID: UInt8
    let payload: Data

    init(messageID: BudsMessageID, payload: Data = Data()) {
        self.messageID = messageID.rawValue
        self.payload = payload
    }

    init(messageID: UInt8, payload: Data = Data()) {
        self.messageID = messageID
        self.payload = payload
    }

    var encoded: Data {
        var packet = Data([Self.startByte])
        let messageSize = UInt16(1 + payload.count + 2)
        packet.append(UInt8(messageSize & 0x00FF))
        packet.append(UInt8((messageSize & 0xFF00) >> 8))
        packet.append(messageID)
        packet.append(payload)

        let checksum = Self.crc16CCITT(Data([messageID]) + payload)
        packet.append(UInt8(checksum & 0x00FF))
        packet.append(UInt8((checksum & 0xFF00) >> 8))
        packet.append(Self.endByte)
        return packet
    }

    static func noiseControl(_ mode: BudsNoiseCommand) -> BudsSPPPacket {
        BudsSPPPacket(messageID: .noiseControls, payload: Data([mode.rawValue]))
    }

    static func equalizer(_ preset: BudsEqualizerCommand) -> BudsSPPPacket {
        BudsSPPPacket(messageID: .equalizer, payload: Data([preset.rawValue]))
    }

    static var requestDebugState: BudsSPPPacket {
        BudsSPPPacket(messageID: .requestDebugState)
    }

    static func crc16CCITT(_ bytes: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }
}

enum BudsCommandName: String, CaseIterable {
    case noiseControl
    case equalizer
    case ambientVolume
    case ambientCustomization
    case noiseReductionLevel
    case voiceDetect
    case voiceDetectTimeout
    case noiseControlWithOneEarbud
    case touchLock
    case touchActions
    case touchNoiseCycle
    case edgeDoubleTapVolume
    case stereoBalance
    case seamlessConnection
    case sidetone
    case callPathControl
    case extraClearCall
    case extraHighAmbient
    case spatialAudio
    case gamingMode
    case autoPauseResume
    case fitTest
    case adaptiveVolume
    case sirenDetect
    case findEarbudsStart
    case findEarbudsStop
    case muteEarbuds
}

struct BudsCommand: Equatable {
    let name: BudsCommandName
    let messageID: BudsMessageID
    let payload: Data
    let title: String
    let verification: FeatureVerification

    var packet: BudsSPPPacket {
        BudsSPPPacket(messageID: messageID, payload: payload)
    }

    var jsonValues: [Int] { payload.map(Int.init) }

    static func noiseControl(_ mode: NoiseControlMode) -> BudsCommand {
        BudsCommand(
            name: .noiseControl,
            messageID: .noiseControls,
            payload: Data([mode.commandValue]),
            title: "噪音控制：\(mode.title)",
            verification: mode == .adaptive ? .protocolMapped : .hardwareVerified
        )
    }

    static func equalizer(_ preset: EqualizerPreset) -> BudsCommand {
        BudsCommand(
            name: .equalizer,
            messageID: .equalizer,
            payload: Data([UInt8(preset.rawValue)]),
            title: "均衡器：\(preset.title)",
            verification: .hardwareVerified
        )
    }

    static func ambientVolume(_ level: AmbientSoundLevel) -> BudsCommand {
        oneByte(.ambientVolume, .ambientVolume, level.rawValue, "环境声级别：\(level.title)")
    }

    static func ambientCustomization(enabled: Bool, left: Int, right: Int, tone: AmbientSoundTone) -> BudsCommand {
        BudsCommand(
            name: .ambientCustomization,
            messageID: .customizeAmbient,
            payload: Data([enabled.byteValue, UInt8(left), UInt8(right), UInt8(tone.rawValue)]),
            title: enabled ? "自定义环境声" : "关闭自定义环境声",
            verification: .protocolMapped
        )
    }

    static func noiseReductionLevel(high: Bool) -> BudsCommand {
        boolean(.noiseReductionLevel, .noiseReductionLevel, high, high ? "强降噪" : "标准降噪")
    }

    static func voiceDetect(_ enabled: Bool) -> BudsCommand {
        boolean(.voiceDetect, .voiceDetect, enabled, enabled ? "开启语音检测" : "关闭语音检测")
    }

    static func voiceDetectTimeout(_ timeout: VoiceDetectTimeout) -> BudsCommand {
        oneByte(.voiceDetectTimeout, .voiceDetectTimeout, timeout.rawValue, "语音检测恢复：\(timeout.title)")
    }

    static func noiseControlWithOneEarbud(_ enabled: Bool) -> BudsCommand {
        boolean(
            .noiseControlWithOneEarbud,
            .noiseControlWithOneEarbud,
            enabled,
            enabled ? "允许单耳噪音控制" : "关闭单耳噪音控制"
        )
    }

    static func touchLock(
        locked: Bool,
        singleTap: Bool,
        doubleTap: Bool,
        tripleTap: Bool,
        touchAndHold: Bool,
        doubleTapCall: Bool,
        touchAndHoldCall: Bool
    ) -> BudsCommand {
        BudsCommand(
            name: .touchLock,
            messageID: .touchLock,
            payload: Data([
                (!locked).byteValue,
                singleTap.byteValue,
                doubleTap.byteValue,
                tripleTap.byteValue,
                touchAndHold.byteValue,
                doubleTapCall.byteValue,
                touchAndHoldCall.byteValue
            ]),
            title: locked ? "锁定耳机控制" : "更新耳机手势",
            verification: .protocolMapped
        )
    }

    static func touchActions(left: TouchAction, right: TouchAction) -> BudsCommand {
        BudsCommand(
            name: .touchActions,
            messageID: .touchAndHold,
            payload: Data([UInt8(left.rawValue), UInt8(right.rawValue)]),
            title: "长捏动作：左 \(left.title)，右 \(right.title)",
            verification: .protocolMapped
        )
    }

    static func touchNoiseCycle(left: NoiseControlCycle, right: NoiseControlCycle) -> BudsCommand {
        BudsCommand(
            name: .touchNoiseCycle,
            messageID: .touchNoiseCycle,
            payload: Data([UInt8(left.rawValue), UInt8(right.rawValue)]),
            title: "长捏噪音循环",
            verification: .protocolMapped
        )
    }

    static func edgeDoubleTapVolume(_ enabled: Bool) -> BudsCommand {
        boolean(.edgeDoubleTapVolume, .outsideDoubleTap, enabled, enabled ? "开启双击耳边调音量" : "关闭双击耳边调音量")
    }

    static func stereoBalance(_ value: Int) -> BudsCommand {
        oneByte(.stereoBalance, .hearingEnhancements, value, "左右声音平衡：\(value)/32")
    }

    static func seamlessConnection(_ enabled: Bool) -> BudsCommand {
        oneByte(
            .seamlessConnection,
            .seamlessConnection,
            enabled ? 0 : 1,
            enabled ? "开启无缝连接" : "关闭无缝连接"
        )
    }

    static func sidetone(_ enabled: Bool) -> BudsCommand {
        boolean(.sidetone, .sidetone, enabled, enabled ? "开启通话环境声" : "关闭通话环境声")
    }

    static func callPathControl(_ enabled: Bool) -> BudsCommand {
        oneByte(
            .callPathControl,
            .callPathControl,
            enabled ? 0 : 1,
            enabled ? "摘下双耳时切回手机" : "通话保持在耳机"
        )
    }

    static func extraClearCall(_ enabled: Bool) -> BudsCommand {
        boolean(.extraClearCall, .extraClearCall, enabled, enabled ? "开启清晰通话" : "关闭清晰通话")
    }

    static func extraHighAmbient(_ enabled: Bool) -> BudsCommand {
        boolean(.extraHighAmbient, .extraHighAmbient, enabled, enabled ? "开启超高环境声" : "关闭超高环境声")
    }

    static func spatialAudio(_ enabled: Bool) -> BudsCommand {
        boolean(.spatialAudio, .spatialAudio, enabled, enabled ? "开启 360 音频" : "关闭 360 音频")
    }

    static func gamingMode(_ enabled: Bool) -> BudsCommand {
        boolean(.gamingMode, .gamingMode, enabled, enabled ? "开启游戏模式" : "关闭游戏模式")
    }

    static func autoPauseResume(_ enabled: Bool) -> BudsCommand {
        boolean(
            .autoPauseResume,
            .pauseWhenRemoved,
            enabled,
            enabled ? "开启佩戴自动暂停" : "关闭佩戴自动暂停"
        )
    }

    static func fitTest(active: Bool) -> BudsCommand {
        boolean(.fitTest, .fitTest, active, active ? "开始耳塞贴合度测试" : "停止耳塞贴合度测试")
    }

    static func adaptiveVolume(_ enabled: Bool) -> BudsCommand {
        experimentalBoolean(
            .adaptiveVolume,
            .adaptiveVolume,
            enabled,
            enabled ? "开启自适应音量" : "关闭自适应音量"
        )
    }

    static func sirenDetect(_ enabled: Bool) -> BudsCommand {
        experimentalBoolean(.sirenDetect, .sirenDetect, enabled, enabled ? "开启警笛检测" : "关闭警笛检测")
    }

    static var findEarbudsStart: BudsCommand {
        BudsCommand(
            name: .findEarbudsStart,
            messageID: .findEarbudsStartWhileWearing,
            payload: Data(),
            title: "开始查找耳机",
            verification: .protocolMapped
        )
    }

    static var findEarbudsStop: BudsCommand {
        BudsCommand(
            name: .findEarbudsStop,
            messageID: .findEarbudsStop,
            payload: Data(),
            title: "停止查找耳机",
            verification: .protocolMapped
        )
    }

    static func muteEarbuds(left: Bool, right: Bool) -> BudsCommand {
        BudsCommand(
            name: .muteEarbuds,
            messageID: .muteEarbuds,
            payload: Data([left.byteValue, right.byteValue]),
            title: "查找响铃：左\(left ? "静音" : "响铃")，右\(right ? "静音" : "响铃")",
            verification: .protocolMapped
        )
    }

    private static func boolean(
        _ name: BudsCommandName,
        _ messageID: BudsMessageID,
        _ enabled: Bool,
        _ title: String
    ) -> BudsCommand {
        BudsCommand(
            name: name,
            messageID: messageID,
            payload: Data([enabled.byteValue]),
            title: title,
            verification: .protocolMapped
        )
    }

    private static func experimentalBoolean(
        _ name: BudsCommandName,
        _ messageID: BudsMessageID,
        _ enabled: Bool,
        _ title: String
    ) -> BudsCommand {
        BudsCommand(
            name: name,
            messageID: messageID,
            payload: Data([enabled.byteValue]),
            title: title,
            verification: .experimental
        )
    }

    private static func oneByte(
        _ name: BudsCommandName,
        _ messageID: BudsMessageID,
        _ value: Int,
        _ title: String
    ) -> BudsCommand {
        BudsCommand(
            name: name,
            messageID: messageID,
            payload: Data([UInt8(value)]),
            title: title,
            verification: .protocolMapped
        )
    }
}

private extension Bool {
    var byteValue: UInt8 { self ? 1 : 0 }
}

extension Data {
    var upperHex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

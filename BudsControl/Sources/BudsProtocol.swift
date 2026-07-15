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
    case requestDebugState = 0x26
    case noiseControls = 0x78
    case touchNoiseCycle = 0x79
    case customizeAmbient = 0x82
    case equalizer = 0x86
    case touchLock = 0x90
    case touchAndHold = 0x92
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

extension Data {
    var upperHex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

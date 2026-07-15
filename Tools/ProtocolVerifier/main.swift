import Foundation

let vectors: [(String, Data, String)] = [
    ("ANC", BudsSPPPacket.noiseControl(.noiseCancelling).encoded, "FD 04 00 78 01 D1 91 DD"),
    ("Ambient", BudsSPPPacket.noiseControl(.ambient).encoded, "FD 04 00 78 02 B2 A1 DD"),
    ("Off", BudsSPPPacket.noiseControl(.off).encoded, "FD 04 00 78 00 F0 81 DD"),
    ("Dynamic EQ", BudsSPPPacket.equalizer(.dynamic).encoded, "FD 04 00 86 03 5D 81 DD"),
    ("State request", BudsSPPPacket.requestDebugState.encoded, "FD 03 00 26 A4 44 DD")
]

for (name, packet, expected) in vectors {
    guard packet.upperHex == expected else {
        fatalError("\(name) mismatch: \(packet.upperHex) != \(expected)")
    }
    print("PASS \(name): \(expected)")
}

let mappedCommands: [BudsCommand] = [
    .noiseControl(.adaptive),
    .ambientVolume(.high),
    .ambientCustomization(enabled: true, left: 2, right: 1, tone: .clearPlus1),
    .voiceDetect(true),
    .voiceDetectTimeout(.fifteenSeconds),
    .noiseControlWithOneEarbud(true),
    .touchLock(
        locked: false,
        singleTap: true,
        doubleTap: true,
        tripleTap: true,
        touchAndHold: true,
        doubleTapCall: true,
        touchAndHoldCall: true
    ),
    .touchActions(left: .noiseControl, right: .volume),
    .touchNoiseCycle(left: .noiseCancellingAndAmbient, right: .noiseCancellingAndOff),
    .edgeDoubleTapVolume(true),
    .stereoBalance(16),
    .seamlessConnection(true),
    .callPathControl(true),
    .fitTest(active: true),
    .findEarbudsStart,
    .findEarbudsStop,
    .muteEarbuds(left: false, right: true)
]

for command in mappedCommands {
    print("MAP \(command.name.rawValue): \(command.packet.encoded.upperHex)")
}

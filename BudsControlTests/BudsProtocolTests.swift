import CoreBluetooth
import XCTest
@testable import BudsControl

final class BudsProtocolTests: XCTestCase {
    func testMatchesGalaxyBudsName() {
        XCTAssertTrue(
            BudsProtocol.isCandidate(
                name: "Galaxy Buds3 Pro",
                manufacturerData: nil,
                serviceUUIDs: []
            )
        )
    }

    func testDoesNotMatchSamsungCompanyIdentifierAlone() {
        XCTAssertFalse(
            BudsProtocol.isCandidate(
                name: nil,
                manufacturerData: Data([0x75, 0x00, 0x01]),
                serviceUUIDs: []
            )
        )
    }

    func testMatchesSamsungControlService() {
        XCTAssertTrue(
            BudsProtocol.isCandidate(
                name: nil,
                manufacturerData: nil,
                serviceUUIDs: [BudsProtocol.samsungSPPService]
            )
        )
    }

    func testRejectsUnrelatedPeripheral() {
        XCTAssertFalse(
            BudsProtocol.isCandidate(
                name: "Keyboard",
                manufacturerData: Data([0x4C, 0x00]),
                serviceUUIDs: []
            )
        )
    }

    func testEncodesNoiseControlCommands() {
        XCTAssertEqual(
            BudsSPPPacket.noiseControl(.noiseCancelling).encoded.upperHex,
            "FD 04 00 78 01 D1 91 DD"
        )
        XCTAssertEqual(
            BudsSPPPacket.noiseControl(.ambient).encoded.upperHex,
            "FD 04 00 78 02 B2 A1 DD"
        )
        XCTAssertEqual(
            BudsSPPPacket.noiseControl(.off).encoded.upperHex,
            "FD 04 00 78 00 F0 81 DD"
        )
    }

    func testEncodesDynamicEqualizerAndStateRequest() {
        XCTAssertEqual(
            BudsSPPPacket.equalizer(.dynamic).encoded.upperHex,
            "FD 04 00 86 03 5D 81 DD"
        )
        XCTAssertEqual(
            BudsSPPPacket.requestDebugState.encoded.upperHex,
            "FD 03 00 26 A4 44 DD"
        )
    }
}

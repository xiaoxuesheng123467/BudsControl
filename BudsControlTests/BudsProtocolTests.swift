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

    func testEncodesMappedBuds3ProCommands() {
        let vectors: [(BudsCommand, String)] = [
            (.noiseControl(.adaptive), "FD 04 00 78 03 93 B1 DD"),
            (.ambientVolume(.high), "FD 04 00 84 02 1E F7 DD"),
            (
                .ambientCustomization(enabled: true, left: 2, right: 1, tone: .clearPlus1),
                "FD 07 00 82 01 02 01 03 D5 7D DD"
            ),
            (.voiceDetect(true), "FD 04 00 7A 01 B3 F7 DD"),
            (.voiceDetectTimeout(.fifteenSeconds), "FD 04 00 7B 02 E1 F4 DD"),
            (.noiseControlWithOneEarbud(true), "FD 04 00 6F 01 35 0B DD"),
            (
                .touchLock(
                    locked: false,
                    singleTap: true,
                    doubleTap: true,
                    tripleTap: true,
                    touchAndHold: true,
                    doubleTapCall: true,
                    touchAndHoldCall: true
                ),
                "FD 0A 00 90 01 01 01 01 01 01 01 31 F5 DD"
            ),
            (.touchActions(left: .noiseControl, right: .volume), "FD 05 00 92 02 03 58 40 DD"),
            (
                .touchNoiseCycle(left: .noiseCancellingAndAmbient, right: .noiseCancellingAndOff),
                "FD 05 00 79 08 0C BC 0E DD"
            ),
            (.edgeDoubleTapVolume(true), "FD 04 00 95 01 3F F7 DD"),
            (.stereoBalance(16), "FD 04 00 8F 10 97 19 DD"),
            (.seamlessConnection(true), "FD 04 00 AF 00 40 0D DD"),
            (.callPathControl(true), "FD 04 00 6E 00 25 28 DD"),
            (.fitTest(active: true), "FD 04 00 9D 01 96 7E DD"),
            (.findEarbudsStart, "FD 03 00 A6 2C D5 DD"),
            (.findEarbudsStop, "FD 03 00 A1 CB A5 DD"),
            (.muteEarbuds(left: false, right: true), "FD 05 00 A2 00 01 DD C3 DD")
        ]

        for (command, expected) in vectors {
            XCTAssertEqual(command.packet.encoded.upperHex, expected, command.name.rawValue)
        }
    }

    func testInvertedBooleanCommandsUseSamsungWireValues() {
        XCTAssertEqual(BudsCommand.seamlessConnection(true).payload, Data([0]))
        XCTAssertEqual(BudsCommand.seamlessConnection(false).payload, Data([1]))
        XCTAssertEqual(BudsCommand.callPathControl(true).payload, Data([0]))
        XCTAssertEqual(BudsCommand.callPathControl(false).payload, Data([1]))
        XCTAssertEqual(
            BudsCommand.touchLock(
                locked: true,
                singleTap: true,
                doubleTap: true,
                tripleTap: true,
                touchAndHold: true,
                doubleTapCall: true,
                touchAndHoldCall: true
            ).payload.first,
            0
        )
    }

    func testRememberedSettingsRoundTrip() throws {
        var settings = BudsDeviceSettings.demo
        settings.leftTouchAction = .volume
        settings.rightNoiseCycle = .ambientAndOff
        settings.stereoBalance = 9

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(BudsDeviceSettings.self, from: encoded)

        XCTAssertEqual(decoded, settings)
    }

    func testEveryNamedCommandHasAStableUniqueName() {
        let names = BudsCommandName.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names.count, 27)
    }

    func testBridgeHTTPWaitsForTheDeclaredBodyThenParsesWithoutEOF() throws {
        let body = Data(#"{"ready":true}"#.utf8)
        let header = Data(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8
        )
        let response = header + body

        XCTAssertNil(try BridgeHTTP.completeResponseBody(from: response.dropLast()))
        XCTAssertEqual(try BridgeHTTP.completeResponseBody(from: response), body)
    }

    func testBridgeHTTPRejectsCompletedErrorResponse() {
        let body = Data(#"{"message":"配对密钥不正确"}"#.utf8)
        let response = Data(
            "HTTP/1.1 401 Unauthorized\r\nContent-Length: \(body.count)\r\n\r\n".utf8
        ) + body

        XCTAssertThrowsError(try BridgeHTTP.completeResponseBody(from: response)) { error in
            guard case BridgeHTTP.RequestError.server(let status, let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertEqual(message, "配对密钥不正确")
        }
    }

    func testBridgeStatusAcceptsBooleanAndIntegerSwitches() throws {
        let payload = Data(#"""
        {
            "ready": true,
            "hasExtendedState": 1,
            "noiseReductionHigh": 0,
            "singleTapEnabled": true,
            "seamlessConnection": 1,
            "fitTestActive": null
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(BridgeStatusPayload.self, from: payload)

        XCTAssertEqual(decoded.hasExtendedState, true)
        XCTAssertEqual(decoded.noiseReductionHigh, false)
        XCTAssertEqual(decoded.singleTapEnabled, true)
        XCTAssertEqual(decoded.seamlessConnection, true)
        XCTAssertNil(decoded.voiceDetectEnabled)
        XCTAssertNil(decoded.fitTestActive)
    }

    func testBridgeStatusRejectsInvalidIntegerSwitch() {
        let payload = Data(#"{"ready":true,"singleTapEnabled":2}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(BridgeStatusPayload.self, from: payload))
    }
}

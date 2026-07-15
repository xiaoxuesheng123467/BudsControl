package com.qiao.budscontrol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.junit.Test;

public final class BudsProtocolTest {
    @Test
    public void hardwareVerifiedPacketsMatchIosVectors() {
        assertPacket(BudsProtocol.noiseControl(1), "FD 04 00 78 01 D1 91 DD");
        assertPacket(BudsProtocol.noiseControl(2), "FD 04 00 78 02 B2 A1 DD");
        assertPacket(BudsProtocol.noiseControl(0), "FD 04 00 78 00 F0 81 DD");
        assertPacket(BudsProtocol.equalizer(3), "FD 04 00 86 03 5D 81 DD");
        assertEquals("FD 03 00 26 A4 44 DD", BudsProtocol.hex(BudsProtocol.stateRequest()));
    }

    @Test
    public void mappedPacketsMatchIosVectors() {
        assertPacket(BudsProtocol.noiseControl(3), "FD 04 00 78 03 93 B1 DD");
        assertPacket(BudsProtocol.ambientVolume(2), "FD 04 00 84 02 1E F7 DD");
        assertPacket(BudsProtocol.ambientCustomization(true, 2, 1, 3), "FD 07 00 82 01 02 01 03 D5 7D DD");
        assertPacket(BudsProtocol.voiceDetect(true), "FD 04 00 7A 01 B3 F7 DD");
        assertPacket(BudsProtocol.voiceDetectTimeout(2), "FD 04 00 7B 02 E1 F4 DD");
        assertPacket(BudsProtocol.oneEarNoiseControl(true), "FD 04 00 6F 01 35 0B DD");
        assertPacket(BudsProtocol.touchLock(false, true, true, true, true, true, true), "FD 0A 00 90 01 01 01 01 01 01 01 31 F5 DD");
        assertPacket(BudsProtocol.touchActions(2, 3), "FD 05 00 92 02 03 58 40 DD");
        assertPacket(BudsProtocol.touchNoiseCycle(8, 12), "FD 05 00 79 08 0C BC 0E DD");
        assertPacket(BudsProtocol.edgeDoubleTap(true), "FD 04 00 95 01 3F F7 DD");
        assertPacket(BudsProtocol.stereoBalance(16), "FD 04 00 8F 10 97 19 DD");
        assertPacket(BudsProtocol.seamlessConnection(true), "FD 04 00 AF 00 40 0D DD");
        assertPacket(BudsProtocol.callPathControl(true), "FD 04 00 6E 00 25 28 DD");
        assertPacket(BudsProtocol.fitTest(true), "FD 04 00 9D 01 96 7E DD");
        assertPacket(BudsProtocol.findStart(), "FD 03 00 A6 2C D5 DD");
        assertPacket(BudsProtocol.findStop(), "FD 03 00 A1 CB A5 DD");
        assertPacket(BudsProtocol.muteEarbuds(false, true), "FD 05 00 A2 00 01 DD C3 DD");
    }

    @Test
    public void invertedBooleansUseSamsungWireAndAckValues() {
        BudsProtocol.Command seamlessOn = BudsProtocol.seamlessConnection(true);
        BudsProtocol.Command seamlessOff = BudsProtocol.seamlessConnection(false);
        assertEquals(0, seamlessOn.payload[0]);
        assertEquals(1, seamlessOn.expectedAcknowledgementPrefix[0]);
        assertEquals(1, seamlessOff.payload[0]);
        assertEquals(0, seamlessOff.expectedAcknowledgementPrefix[0]);
    }

    @Test
    public void crcRejectsModifiedFrame() {
        byte[] packet = BudsProtocol.noiseControl(1).packet();
        assertTrue(BudsProtocol.hasValidCrc(packet));
        packet[4] = 2;
        assertFalse(BudsProtocol.hasValidCrc(packet));
    }

    @Test
    public void invalidValuesAreRejected() {
        expectIllegal(() -> BudsProtocol.noiseControl(4));
        expectIllegal(() -> BudsProtocol.ambientCustomization(true, 3, 1, 2));
        expectIllegal(() -> BudsProtocol.touchActions(0, 2));
        expectIllegal(() -> BudsProtocol.touchNoiseCycle(3, 8));
        expectIllegal(() -> BudsProtocol.stereoBalance(33));
    }

    private static void assertPacket(BudsProtocol.Command command, String expected) {
        assertEquals(command.key, expected, BudsProtocol.hex(command.packet()));
        assertTrue(command.key, BudsProtocol.hasValidCrc(command.packet()));
    }

    private static void expectIllegal(Runnable operation) {
        try {
            operation.run();
            fail("Expected IllegalArgumentException");
        } catch (IllegalArgumentException expected) {
            // Expected.
        }
    }
}


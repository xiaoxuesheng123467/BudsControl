package com.qiao.budscontrol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class BudsSettingsTest {
    @Test
    public void extendedStatusUpdatesKnownBuds3ProFields() {
        byte[] payload = new byte[58];
        payload[0] = 1;
        payload[9] = 3;
        payload[10] = (byte) 0xBF;
        payload[11] = 0x23;
        payload[12] = 3;
        payload[19] = 0;
        payload[23] = 2;
        payload[24] = 1;
        payload[25] = 9;
        payload[26] = 1;
        payload[27] = 2;
        payload[28] = 1;
        payload[29] = 1;
        payload[30] = 0x21;
        payload[31] = 3;
        payload[32] = 1;
        payload[33] = 1;
        payload[34] = 0;
        payload[35] = 1;
        payload[47] = 1;
        payload[48] = 1;
        payload[49] = 1;
        payload[50] = 0;
        payload[53] = 1;
        payload[54] = 2;
        payload[56] = 1;
        payload[57] = 0;

        BudsSettings settings = new BudsSettings();
        settings.applyExtendedPayload(payload);

        assertEquals(1, settings.revision);
        assertEquals(3, settings.equalizer);
        assertFalse(settings.touchLocked);
        assertTrue(settings.singleTapEnabled);
        assertEquals(2, settings.leftTouchAction);
        assertEquals(3, settings.rightTouchAction);
        assertEquals(3, settings.noiseMode);
        assertTrue(settings.seamlessConnection);
        assertEquals(2, settings.ambientVolume);
        assertEquals(9, settings.stereoBalance);
        assertTrue(settings.voiceDetectEnabled);
        assertEquals(2, settings.voiceDetectTimeout);
        assertTrue(settings.oneEarNoiseControl);
        assertTrue(settings.ambientCustomizationEnabled);
        assertEquals(2, settings.ambientVolumeLeft);
        assertEquals(1, settings.ambientVolumeRight);
        assertEquals(3, settings.ambientTone);
        assertTrue(settings.edgeDoubleTapVolume);
        assertTrue(settings.sidetoneEnabled);
        assertTrue(settings.callPathControlEnabled);
        assertTrue(settings.spatialAudioEnabled);
        assertTrue(settings.extraClearCallEnabled);
        assertTrue(settings.extraHighAmbientEnabled);
        assertTrue(settings.autoPauseResumeEnabled);
        assertTrue(settings.adaptiveVolumeEnabled);
        assertEquals(2, settings.lightingControl);
        assertTrue(settings.sirenDetectEnabled);
    }
}


package com.qiao.budscontrol;

import android.content.SharedPreferences;

final class BudsSettings {
    int revision = -1;
    int noiseMode = -1;
    int equalizer = 3;
    int ambientVolume = 1;
    boolean noiseReductionHigh = true;
    boolean ambientCustomizationEnabled;
    int ambientVolumeLeft = 2;
    int ambientVolumeRight = 2;
    int ambientTone = 2;
    boolean voiceDetectEnabled;
    int voiceDetectTimeout;
    boolean oneEarNoiseControl;
    boolean touchLocked;
    boolean singleTapEnabled = true;
    boolean doubleTapEnabled = true;
    boolean tripleTapEnabled = true;
    boolean touchAndHoldEnabled = true;
    boolean doubleTapCallEnabled = true;
    boolean touchAndHoldCallEnabled = true;
    int leftTouchAction = 2;
    int rightTouchAction = 2;
    int leftNoiseCycle = 8;
    int rightNoiseCycle = 8;
    boolean edgeDoubleTapVolume;
    int stereoBalance = 16;
    boolean seamlessConnection = true;
    boolean sidetoneEnabled;
    boolean callPathControlEnabled = true;
    boolean extraClearCallEnabled;
    boolean extraHighAmbientEnabled;
    boolean spatialAudioEnabled;
    boolean gamingModeEnabled;
    boolean autoPauseResumeEnabled = true;
    boolean adaptiveVolumeEnabled;
    boolean sirenDetectEnabled;
    int lightingControl = -1;
    int hotCommandEnabled = -1;
    int adaptSoundEnabled = -1;
    int fitTestLeft = -1;
    int fitTestRight = -1;

    static BudsSettings demo() {
        BudsSettings settings = new BudsSettings();
        settings.revision = 1;
        settings.noiseMode = 1;
        settings.equalizer = 3;
        settings.voiceDetectEnabled = true;
        settings.oneEarNoiseControl = true;
        settings.edgeDoubleTapVolume = true;
        settings.extraClearCallEnabled = true;
        settings.lightingControl = 1;
        settings.hotCommandEnabled = 0;
        settings.adaptSoundEnabled = 0;
        return settings;
    }

    static BudsSettings load(SharedPreferences preferences) {
        BudsSettings settings = new BudsSettings();
        if (!preferences.getBoolean("settings_saved", false)) return settings;
        settings.revision = preferences.getInt("revision", settings.revision);
        settings.noiseMode = preferences.getInt("noise_mode", settings.noiseMode);
        settings.equalizer = preferences.getInt("equalizer", settings.equalizer);
        settings.ambientVolume = preferences.getInt("ambient_volume", settings.ambientVolume);
        settings.noiseReductionHigh = preferences.getBoolean("noise_reduction_high", settings.noiseReductionHigh);
        settings.ambientCustomizationEnabled = preferences.getBoolean("ambient_custom", settings.ambientCustomizationEnabled);
        settings.ambientVolumeLeft = preferences.getInt("ambient_left", settings.ambientVolumeLeft);
        settings.ambientVolumeRight = preferences.getInt("ambient_right", settings.ambientVolumeRight);
        settings.ambientTone = preferences.getInt("ambient_tone", settings.ambientTone);
        settings.voiceDetectEnabled = preferences.getBoolean("voice_detect", settings.voiceDetectEnabled);
        settings.voiceDetectTimeout = preferences.getInt("voice_timeout", settings.voiceDetectTimeout);
        settings.oneEarNoiseControl = preferences.getBoolean("one_ear_noise", settings.oneEarNoiseControl);
        settings.touchLocked = preferences.getBoolean("touch_locked", settings.touchLocked);
        settings.singleTapEnabled = preferences.getBoolean("single_tap", settings.singleTapEnabled);
        settings.doubleTapEnabled = preferences.getBoolean("double_tap", settings.doubleTapEnabled);
        settings.tripleTapEnabled = preferences.getBoolean("triple_tap", settings.tripleTapEnabled);
        settings.touchAndHoldEnabled = preferences.getBoolean("touch_hold", settings.touchAndHoldEnabled);
        settings.doubleTapCallEnabled = preferences.getBoolean("double_call", settings.doubleTapCallEnabled);
        settings.touchAndHoldCallEnabled = preferences.getBoolean("hold_call", settings.touchAndHoldCallEnabled);
        settings.leftTouchAction = preferences.getInt("touch_left", settings.leftTouchAction);
        settings.rightTouchAction = preferences.getInt("touch_right", settings.rightTouchAction);
        settings.leftNoiseCycle = preferences.getInt("cycle_left", settings.leftNoiseCycle);
        settings.rightNoiseCycle = preferences.getInt("cycle_right", settings.rightNoiseCycle);
        settings.edgeDoubleTapVolume = preferences.getBoolean("edge_double", settings.edgeDoubleTapVolume);
        settings.stereoBalance = preferences.getInt("stereo_balance", settings.stereoBalance);
        settings.seamlessConnection = preferences.getBoolean("seamless", settings.seamlessConnection);
        settings.sidetoneEnabled = preferences.getBoolean("sidetone", settings.sidetoneEnabled);
        settings.callPathControlEnabled = preferences.getBoolean("call_path", settings.callPathControlEnabled);
        settings.extraClearCallEnabled = preferences.getBoolean("clear_call", settings.extraClearCallEnabled);
        settings.extraHighAmbientEnabled = preferences.getBoolean("extra_ambient", settings.extraHighAmbientEnabled);
        settings.spatialAudioEnabled = preferences.getBoolean("spatial_audio", settings.spatialAudioEnabled);
        settings.gamingModeEnabled = preferences.getBoolean("gaming", settings.gamingModeEnabled);
        settings.autoPauseResumeEnabled = preferences.getBoolean("auto_pause", settings.autoPauseResumeEnabled);
        settings.adaptiveVolumeEnabled = preferences.getBoolean("adaptive_volume", settings.adaptiveVolumeEnabled);
        settings.sirenDetectEnabled = preferences.getBoolean("siren", settings.sirenDetectEnabled);
        settings.lightingControl = preferences.getInt("lighting", settings.lightingControl);
        settings.hotCommandEnabled = preferences.getInt("hot_command", settings.hotCommandEnabled);
        settings.adaptSoundEnabled = preferences.getInt("adapt_sound", settings.adaptSoundEnabled);
        return settings;
    }

    void save(SharedPreferences preferences) {
        preferences.edit()
                .putBoolean("settings_saved", true)
                .putInt("revision", revision)
                .putInt("noise_mode", noiseMode)
                .putInt("equalizer", equalizer)
                .putInt("ambient_volume", ambientVolume)
                .putBoolean("noise_reduction_high", noiseReductionHigh)
                .putBoolean("ambient_custom", ambientCustomizationEnabled)
                .putInt("ambient_left", ambientVolumeLeft)
                .putInt("ambient_right", ambientVolumeRight)
                .putInt("ambient_tone", ambientTone)
                .putBoolean("voice_detect", voiceDetectEnabled)
                .putInt("voice_timeout", voiceDetectTimeout)
                .putBoolean("one_ear_noise", oneEarNoiseControl)
                .putBoolean("touch_locked", touchLocked)
                .putBoolean("single_tap", singleTapEnabled)
                .putBoolean("double_tap", doubleTapEnabled)
                .putBoolean("triple_tap", tripleTapEnabled)
                .putBoolean("touch_hold", touchAndHoldEnabled)
                .putBoolean("double_call", doubleTapCallEnabled)
                .putBoolean("hold_call", touchAndHoldCallEnabled)
                .putInt("touch_left", leftTouchAction)
                .putInt("touch_right", rightTouchAction)
                .putInt("cycle_left", leftNoiseCycle)
                .putInt("cycle_right", rightNoiseCycle)
                .putBoolean("edge_double", edgeDoubleTapVolume)
                .putInt("stereo_balance", stereoBalance)
                .putBoolean("seamless", seamlessConnection)
                .putBoolean("sidetone", sidetoneEnabled)
                .putBoolean("call_path", callPathControlEnabled)
                .putBoolean("clear_call", extraClearCallEnabled)
                .putBoolean("extra_ambient", extraHighAmbientEnabled)
                .putBoolean("spatial_audio", spatialAudioEnabled)
                .putBoolean("gaming", gamingModeEnabled)
                .putBoolean("auto_pause", autoPauseResumeEnabled)
                .putBoolean("adaptive_volume", adaptiveVolumeEnabled)
                .putBoolean("siren", sirenDetectEnabled)
                .putInt("lighting", lightingControl)
                .putInt("hot_command", hotCommandEnabled)
                .putInt("adapt_sound", adaptSoundEnabled)
                .apply();
    }

    void applyExtendedPayload(byte[] payload) {
        if (payload.length < 8) return;
        revision = unsigned(payload[0]);
        if (payload.length > 9 && unsigned(payload[9]) <= 5) equalizer = unsigned(payload[9]);
        if (payload.length > 10) {
            int touch = unsigned(payload[10]);
            touchLocked = (touch & 0x80) == 0;
            singleTapEnabled = (touch & 0x08) != 0;
            doubleTapEnabled = (touch & 0x04) != 0;
            tripleTapEnabled = (touch & 0x02) != 0;
            touchAndHoldEnabled = (touch & 0x01) != 0;
            doubleTapCallEnabled = (touch & 0x10) != 0;
            touchAndHoldCallEnabled = (touch & 0x20) != 0;
        }
        if (payload.length > 11) {
            int actions = unsigned(payload[11]);
            int left = (actions & 0xF0) >> 4;
            int right = actions & 0x0F;
            if (left >= 1 && left <= 4) leftTouchAction = left;
            if (right >= 1 && right <= 4) rightTouchAction = right;
        }
        if (payload.length > 12 && unsigned(payload[12]) <= 3) noiseMode = unsigned(payload[12]);
        if (payload.length > 19) seamlessConnection = unsigned(payload[19]) == 0;
        if (payload.length > 23 && unsigned(payload[23]) <= 2) ambientVolume = unsigned(payload[23]);
        if (payload.length > 24) noiseReductionHigh = unsigned(payload[24]) == 1;
        if (payload.length > 25 && unsigned(payload[25]) <= 32) stereoBalance = unsigned(payload[25]);
        if (payload.length > 26) voiceDetectEnabled = unsigned(payload[26]) == 1;
        if (payload.length > 27 && unsigned(payload[27]) <= 2) voiceDetectTimeout = unsigned(payload[27]);
        if (payload.length > 28) oneEarNoiseControl = unsigned(payload[28]) == 1;
        if (payload.length > 29) ambientCustomizationEnabled = unsigned(payload[29]) == 1;
        if (payload.length > 30) {
            int custom = unsigned(payload[30]);
            int left = (custom & 0xF0) >> 4;
            int right = custom & 0x0F;
            if (left <= 2) ambientVolumeLeft = left;
            if (right <= 2) ambientVolumeRight = right;
        }
        if (payload.length > 31 && unsigned(payload[31]) <= 4) ambientTone = unsigned(payload[31]);
        if (payload.length > 32) edgeDoubleTapVolume = unsigned(payload[32]) == 1;
        if (payload.length > 33) sidetoneEnabled = unsigned(payload[33]) == 1;
        if (payload.length > 34) callPathControlEnabled = unsigned(payload[34]) == 0;
        if (payload.length > 35) spatialAudioEnabled = unsigned(payload[35]) == 1;
        if (payload.length > 47) extraClearCallEnabled = unsigned(payload[47]) == 1;
        if (payload.length > 48) extraHighAmbientEnabled = unsigned(payload[48]) == 1;
        if (payload.length > 49) autoPauseResumeEnabled = unsigned(payload[49]) == 1;
        if (payload.length > 50) hotCommandEnabled = unsigned(payload[50]) == 1 ? 1 : 0;
        if (payload.length > 53) adaptiveVolumeEnabled = unsigned(payload[53]) == 1;
        if (payload.length > 54) lightingControl = unsigned(payload[54]);
        if (payload.length > 56) sirenDetectEnabled = unsigned(payload[56]) == 1;
        if (payload.length > 57) adaptSoundEnabled = unsigned(payload[57]) == 1 ? 1 : 0;
    }

    private static int unsigned(byte value) {
        return value & 0xFF;
    }
}


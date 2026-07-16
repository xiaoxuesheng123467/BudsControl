namespace BudsControl.Core;

public sealed class BudsSettings
{
    public int Revision { get; set; } = -1;
    public int NoiseMode { get; set; } = -1;
    public int Equalizer { get; set; } = 3;
    public int AmbientVolume { get; set; } = 1;
    public bool NoiseReductionHigh { get; set; } = true;
    public bool AmbientCustomizationEnabled { get; set; }
    public int AmbientVolumeLeft { get; set; } = 2;
    public int AmbientVolumeRight { get; set; } = 2;
    public int AmbientTone { get; set; } = 2;
    public bool VoiceDetectEnabled { get; set; }
    public int VoiceDetectTimeout { get; set; }
    public bool OneEarNoiseControl { get; set; }
    public bool TouchLocked { get; set; }
    public bool SingleTapEnabled { get; set; } = true;
    public bool DoubleTapEnabled { get; set; } = true;
    public bool TripleTapEnabled { get; set; } = true;
    public bool TouchAndHoldEnabled { get; set; } = true;
    public bool DoubleTapCallEnabled { get; set; } = true;
    public bool TouchAndHoldCallEnabled { get; set; } = true;
    public int LeftTouchAction { get; set; } = 2;
    public int RightTouchAction { get; set; } = 2;
    public int LeftNoiseCycle { get; set; } = 8;
    public int RightNoiseCycle { get; set; } = 8;
    public bool EdgeDoubleTapVolume { get; set; }
    public int StereoBalance { get; set; } = 16;
    public bool SeamlessConnection { get; set; } = true;
    public bool SidetoneEnabled { get; set; }
    public bool CallPathControlEnabled { get; set; } = true;
    public bool ExtraClearCallEnabled { get; set; }
    public bool ExtraHighAmbientEnabled { get; set; }
    public bool SpatialAudioEnabled { get; set; }
    public bool GamingModeEnabled { get; set; }
    public bool AutoPauseResumeEnabled { get; set; } = true;
    public bool AdaptiveVolumeEnabled { get; set; }
    public bool SirenDetectEnabled { get; set; }
    public int LightingControl { get; set; } = -1;
    public int HotCommandEnabled { get; set; } = -1;
    public int AdaptSoundEnabled { get; set; } = -1;
    public int FitTestLeft { get; set; } = -1;
    public int FitTestRight { get; set; } = -1;

    public static BudsSettings Demo() => new()
    {
        Revision = 1,
        NoiseMode = 1,
        Equalizer = 3,
        VoiceDetectEnabled = true,
        OneEarNoiseControl = true,
        EdgeDoubleTapVolume = true,
        ExtraClearCallEnabled = true,
        LightingControl = 1,
        HotCommandEnabled = 0,
        AdaptSoundEnabled = 0,
    };

    public BudsSettings Clone() => (BudsSettings)MemberwiseClone();

    public void ApplyExtendedPayload(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 8)
        {
            return;
        }

        Revision = payload[0];
        if (payload.Length > 9 && payload[9] <= 5) Equalizer = payload[9];
        if (payload.Length > 10)
        {
            int touch = payload[10];
            TouchLocked = (touch & 0x80) == 0;
            SingleTapEnabled = (touch & 0x08) != 0;
            DoubleTapEnabled = (touch & 0x04) != 0;
            TripleTapEnabled = (touch & 0x02) != 0;
            TouchAndHoldEnabled = (touch & 0x01) != 0;
            DoubleTapCallEnabled = (touch & 0x10) != 0;
            TouchAndHoldCallEnabled = (touch & 0x20) != 0;
        }
        if (payload.Length > 11)
        {
            int actions = payload[11];
            int left = (actions & 0xF0) >> 4;
            int right = actions & 0x0F;
            if (left is >= 1 and <= 4) LeftTouchAction = left;
            if (right is >= 1 and <= 4) RightTouchAction = right;
        }
        if (payload.Length > 12 && payload[12] <= 3) NoiseMode = payload[12];
        if (payload.Length > 19) SeamlessConnection = payload[19] == 0;
        if (payload.Length > 23 && payload[23] <= 2) AmbientVolume = payload[23];
        if (payload.Length > 24) NoiseReductionHigh = payload[24] == 1;
        if (payload.Length > 25 && payload[25] <= 32) StereoBalance = payload[25];
        if (payload.Length > 26) VoiceDetectEnabled = payload[26] == 1;
        if (payload.Length > 27 && payload[27] <= 2) VoiceDetectTimeout = payload[27];
        if (payload.Length > 28) OneEarNoiseControl = payload[28] == 1;
        if (payload.Length > 29) AmbientCustomizationEnabled = payload[29] == 1;
        if (payload.Length > 30)
        {
            int custom = payload[30];
            int left = (custom & 0xF0) >> 4;
            int right = custom & 0x0F;
            if (left <= 2) AmbientVolumeLeft = left;
            if (right <= 2) AmbientVolumeRight = right;
        }
        if (payload.Length > 31 && payload[31] <= 4) AmbientTone = payload[31];
        if (payload.Length > 32) EdgeDoubleTapVolume = payload[32] == 1;
        if (payload.Length > 33) SidetoneEnabled = payload[33] == 1;
        if (payload.Length > 34) CallPathControlEnabled = payload[34] == 0;
        if (payload.Length > 35) SpatialAudioEnabled = payload[35] == 1;
        if (payload.Length > 47) ExtraClearCallEnabled = payload[47] == 1;
        if (payload.Length > 48) ExtraHighAmbientEnabled = payload[48] == 1;
        if (payload.Length > 49) AutoPauseResumeEnabled = payload[49] == 1;
        if (payload.Length > 50) HotCommandEnabled = payload[50] == 1 ? 1 : 0;
        if (payload.Length > 53) AdaptiveVolumeEnabled = payload[53] == 1;
        if (payload.Length > 54) LightingControl = payload[54];
        if (payload.Length > 56) SirenDetectEnabled = payload[56] == 1;
        if (payload.Length > 57) AdaptSoundEnabled = payload[57] == 1 ? 1 : 0;
    }
}

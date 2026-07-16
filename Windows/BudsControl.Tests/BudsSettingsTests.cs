using BudsControl.Core;

namespace BudsControl.Tests;

public sealed class BudsSettingsTests
{
    [Fact]
    public void ExtendedStatusUpdatesKnownBuds3ProFields()
    {
        byte[] payload = new byte[58];
        payload[0] = 1;
        payload[9] = 3;
        payload[10] = 0xBF;
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

        BudsSettings settings = new();
        settings.ApplyExtendedPayload(payload);

        Assert.Equal(1, settings.Revision);
        Assert.Equal(3, settings.Equalizer);
        Assert.False(settings.TouchLocked);
        Assert.True(settings.SingleTapEnabled);
        Assert.Equal(2, settings.LeftTouchAction);
        Assert.Equal(3, settings.RightTouchAction);
        Assert.Equal(3, settings.NoiseMode);
        Assert.True(settings.SeamlessConnection);
        Assert.Equal(2, settings.AmbientVolume);
        Assert.Equal(9, settings.StereoBalance);
        Assert.True(settings.VoiceDetectEnabled);
        Assert.Equal(2, settings.VoiceDetectTimeout);
        Assert.True(settings.OneEarNoiseControl);
        Assert.True(settings.AmbientCustomizationEnabled);
        Assert.Equal(2, settings.AmbientVolumeLeft);
        Assert.Equal(1, settings.AmbientVolumeRight);
        Assert.Equal(3, settings.AmbientTone);
        Assert.True(settings.EdgeDoubleTapVolume);
        Assert.True(settings.SidetoneEnabled);
        Assert.True(settings.CallPathControlEnabled);
        Assert.True(settings.SpatialAudioEnabled);
        Assert.True(settings.ExtraClearCallEnabled);
        Assert.True(settings.ExtraHighAmbientEnabled);
        Assert.True(settings.AutoPauseResumeEnabled);
        Assert.True(settings.AdaptiveVolumeEnabled);
        Assert.Equal(2, settings.LightingControl);
        Assert.True(settings.SirenDetectEnabled);
    }
}

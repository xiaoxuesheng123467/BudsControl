using BudsControl.Core;

namespace BudsControl.Tests;

public sealed class BudsProtocolTests
{
    [Theory]
    [InlineData(0, "FD 04 00 78 00 F0 81 DD")]
    [InlineData(1, "FD 04 00 78 01 D1 91 DD")]
    [InlineData(2, "FD 04 00 78 02 B2 A1 DD")]
    [InlineData(3, "FD 04 00 78 03 93 B1 DD")]
    public void NoiseControlPacketsMatchSharedVectors(int mode, string expected)
    {
        AssertPacket(BudsProtocol.NoiseControl(mode), expected);
    }

    [Fact]
    public void CoreAndMappedPacketsMatchSharedVectors()
    {
        AssertPacket(BudsProtocol.Equalizer(3), "FD 04 00 86 03 5D 81 DD");
        AssertPacket(BudsProtocol.AmbientVolume(2), "FD 04 00 84 02 1E F7 DD");
        AssertPacket(BudsProtocol.AmbientCustomization(true, 2, 1, 3), "FD 07 00 82 01 02 01 03 D5 7D DD");
        AssertPacket(BudsProtocol.VoiceDetect(true), "FD 04 00 7A 01 B3 F7 DD");
        AssertPacket(BudsProtocol.VoiceDetectTimeout(2), "FD 04 00 7B 02 E1 F4 DD");
        AssertPacket(BudsProtocol.OneEarNoiseControl(true), "FD 04 00 6F 01 35 0B DD");
        AssertPacket(BudsProtocol.TouchLock(false, true, true, true, true, true, true), "FD 0A 00 90 01 01 01 01 01 01 01 31 F5 DD");
        AssertPacket(BudsProtocol.TouchActions(2, 3), "FD 05 00 92 02 03 58 40 DD");
        AssertPacket(BudsProtocol.TouchNoiseCycle(8, 12), "FD 05 00 79 08 0C BC 0E DD");
        AssertPacket(BudsProtocol.EdgeDoubleTap(true), "FD 04 00 95 01 3F F7 DD");
        AssertPacket(BudsProtocol.StereoBalance(16), "FD 04 00 8F 10 97 19 DD");
        AssertPacket(BudsProtocol.SeamlessConnection(true), "FD 04 00 AF 00 40 0D DD");
        AssertPacket(BudsProtocol.CallPathControl(true), "FD 04 00 6E 00 25 28 DD");
        AssertPacket(BudsProtocol.FitTest(true), "FD 04 00 9D 01 96 7E DD");
        AssertPacket(BudsProtocol.FindStart(), "FD 03 00 A6 2C D5 DD");
        AssertPacket(BudsProtocol.FindStop(), "FD 03 00 A1 CB A5 DD");
        AssertPacket(BudsProtocol.MuteEarbuds(false, true), "FD 05 00 A2 00 01 DD C3 DD");
        Assert.Equal("FD 03 00 26 A4 44 DD", BudsProtocol.Hex(BudsProtocol.StateRequest()));
    }

    [Fact]
    public void InvertedBooleanUsesWireAndSemanticAcknowledgementValues()
    {
        BudsCommand enabled = BudsProtocol.SeamlessConnection(true);
        BudsCommand disabled = BudsProtocol.SeamlessConnection(false);

        Assert.Equal(0, enabled.Payload[0]);
        Assert.Equal(1, enabled.ExpectedAcknowledgementPrefix![0]);
        Assert.Equal(1, disabled.Payload[0]);
        Assert.Equal(0, disabled.ExpectedAcknowledgementPrefix![0]);
    }

    [Fact]
    public void CrcRejectsModifiedFrame()
    {
        byte[] packet = BudsProtocol.NoiseControl(1).Packet;
        Assert.True(BudsProtocol.HasValidCrc(packet));
        packet[4] = 2;
        Assert.False(BudsProtocol.HasValidCrc(packet));
    }

    [Fact]
    public void InvalidValuesAreRejected()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => BudsProtocol.NoiseControl(4));
        Assert.Throws<ArgumentOutOfRangeException>(() => BudsProtocol.AmbientCustomization(true, 3, 1, 2));
        Assert.Throws<ArgumentOutOfRangeException>(() => BudsProtocol.TouchActions(0, 2));
        Assert.Throws<ArgumentOutOfRangeException>(() => BudsProtocol.TouchNoiseCycle(3, 8));
        Assert.Throws<ArgumentOutOfRangeException>(() => BudsProtocol.StereoBalance(33));
    }

    private static void AssertPacket(BudsCommand command, string expected)
    {
        Assert.Equal(expected, BudsProtocol.Hex(command.Packet));
        Assert.True(BudsProtocol.HasValidCrc(command.Packet));
    }
}

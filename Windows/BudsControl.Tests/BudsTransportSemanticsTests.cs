using BudsControl.Core;

namespace BudsControl.Tests;

public sealed class BudsTransportSemanticsTests
{
    [Fact]
    public void AcknowledgementRequiresMessageAndExpectedPrefix()
    {
        Assert.True(BudsTransportSemantics.MatchesAcknowledgement([0x78, 0x01, 0x99], 0x78, [0x01]));
        Assert.True(BudsTransportSemantics.MatchesAcknowledgement([0x90], 0x90, []));
        Assert.False(BudsTransportSemantics.MatchesAcknowledgement([0x86, 0x01], 0x78, [0x01]));
        Assert.False(BudsTransportSemantics.MatchesAcknowledgement([0x78, 0x02], 0x78, [0x01]));
        Assert.False(BudsTransportSemantics.MatchesAcknowledgement([0x78, 0x01], 0x78, [0x01, 0x02]));
        Assert.False(BudsTransportSemantics.MatchesAcknowledgement([], 0x78, []));
    }

    [Theory]
    [InlineData(0, false, 0)]
    [InlineData(0, true, -1)]
    [InlineData(100, true, 100)]
    [InlineData(101, false, -1)]
    [InlineData(255, true, -1)]
    public void BatteryLevelHandlesUnavailableValues(byte value, bool zeroMeansUnavailable, int expected)
    {
        Assert.Equal(expected, BudsTransportSemantics.BatteryLevel(value, zeroMeansUnavailable));
    }
}

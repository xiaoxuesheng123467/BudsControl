using BudsControl.Core;

namespace BudsControl.Tests;

public sealed class BudsFrameParserTests
{
    [Fact]
    public void ParserBuffersPartialFramesAndReturnsMultipleFrames()
    {
        byte[] first = BudsProtocol.NoiseControl(1).Packet;
        byte[] second = BudsProtocol.Equalizer(3).Packet;
        BudsFrameParser parser = new();

        Assert.Empty(parser.Append(first.AsSpan(0, 3)));

        byte[] remainder = [.. first.AsSpan(3), .. second];
        IReadOnlyList<byte[]> frames = parser.Append(remainder);

        Assert.Equal(2, frames.Count);
        Assert.Equal(first, frames[0]);
        Assert.Equal(second, frames[1]);
    }

    [Fact]
    public void ParserSkipsNoiseAndCorruptedFrames()
    {
        byte[] corrupted = BudsProtocol.NoiseControl(1).Packet;
        corrupted[4] = 2;
        byte[] valid = BudsProtocol.Equalizer(3).Packet;
        byte[] input = [0x11, 0x22, .. corrupted, .. valid];

        IReadOnlyList<byte[]> frames = new BudsFrameParser().Append(input);

        Assert.Single(frames);
        Assert.Equal(valid, frames[0]);
    }
}

namespace BudsControl.Core;

public sealed class BudsFrameParser
{
    private readonly List<byte> _buffer = [];

    public IReadOnlyList<byte[]> Append(ReadOnlySpan<byte> chunk)
    {
        foreach (byte value in chunk)
        {
            _buffer.Add(value);
        }

        List<byte[]> frames = [];
        while (_buffer.Count >= 7)
        {
            int start = _buffer.IndexOf(0xFD);
            if (start < 0)
            {
                _buffer.Clear();
                break;
            }
            if (start > 0)
            {
                _buffer.RemoveRange(0, start);
            }
            if (_buffer.Count < 7)
            {
                break;
            }

            int messageSize = _buffer[1] | ((_buffer[2] & 0x03) << 8);
            int frameLength = messageSize + 4;
            if (frameLength is < 7 or > 4096)
            {
                _buffer.RemoveAt(0);
                continue;
            }
            if (_buffer.Count < frameLength)
            {
                break;
            }

            byte[] frame = _buffer.GetRange(0, frameLength).ToArray();
            _buffer.RemoveRange(0, frameLength);
            if (BudsProtocol.HasValidCrc(frame))
            {
                frames.Add(frame);
            }
        }

        return frames;
    }

    public void Reset() => _buffer.Clear();
}

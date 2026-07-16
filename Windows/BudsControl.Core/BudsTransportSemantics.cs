namespace BudsControl.Core;

public static class BudsTransportSemantics
{
    public static bool MatchesAcknowledgement(
        ReadOnlySpan<byte> payload,
        byte messageId,
        ReadOnlySpan<byte> expectedPrefix)
    {
        if (payload.IsEmpty || payload[0] != messageId)
        {
            return false;
        }

        ReadOnlySpan<byte> parameters = payload[1..];
        return parameters.Length >= expectedPrefix.Length &&
               parameters[..expectedPrefix.Length].SequenceEqual(expectedPrefix);
    }

    public static int BatteryLevel(byte value, bool zeroMeansUnavailable = false) =>
        value > 100 || (zeroMeansUnavailable && value == 0) ? -1 : value;
}

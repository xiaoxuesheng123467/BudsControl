namespace BudsControl.Windows;

public enum BluetoothConnectionState
{
    Disconnected,
    Connecting,
    Connected,
}

public sealed record BluetoothDeviceOption(string Name, string Address)
{
    public override string ToString() => $"{Name}  ·  {Address}";
}

public sealed record CommandResult(bool Success, bool Acknowledged, string Detail);
public sealed record BatteryReading(int Left, int Right, int Case);
public sealed record FitResult(int Left, int Right);

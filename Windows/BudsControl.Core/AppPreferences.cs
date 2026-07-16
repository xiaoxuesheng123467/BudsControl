namespace BudsControl.Core;

public sealed class AppPreferences
{
    public bool DemoMode { get; set; }
    public bool ExperimentalCommands { get; set; }
    public bool RememberSettings { get; set; } = true;
    public string? LastDeviceAddress { get; set; }
    public bool HasSavedSettings { get; set; }
    public BudsSettings Settings { get; set; } = new();
}

public sealed record CommandLogEntry(
    DateTimeOffset Timestamp,
    string Title,
    string Packet,
    string Result,
    string Detail);

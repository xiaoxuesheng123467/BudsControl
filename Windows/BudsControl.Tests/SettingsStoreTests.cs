using BudsControl.Core;

namespace BudsControl.Tests;

public sealed class SettingsStoreTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "BudsControlTests", Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task StoreRoundTripsLastDeviceAndSettings()
    {
        string path = Path.Combine(_directory, "settings.json");
        SettingsStore store = new(path);
        AppPreferences input = new()
        {
            DemoMode = true,
            ExperimentalCommands = true,
            RememberSettings = true,
            HasSavedSettings = true,
            LastDeviceAddress = "001122AABBCC",
            Settings = new BudsSettings { NoiseMode = 3, Equalizer = 5 },
        };

        await store.SaveAsync(input);
        AppPreferences output = await store.LoadAsync();

        Assert.True(output.DemoMode);
        Assert.True(output.ExperimentalCommands);
        Assert.Equal("001122AABBCC", output.LastDeviceAddress);
        Assert.Equal(3, output.Settings.NoiseMode);
        Assert.Equal(5, output.Settings.Equalizer);
    }

    [Fact]
    public async Task DisabledMemoryDoesNotRestoreEarbudSettings()
    {
        string path = Path.Combine(_directory, "settings.json");
        SettingsStore store = new(path);
        await store.SaveAsync(new AppPreferences
        {
            RememberSettings = false,
            HasSavedSettings = true,
            Settings = new BudsSettings { NoiseMode = 3 },
        });

        AppPreferences output = await store.LoadAsync();

        Assert.Equal(-1, output.Settings.NoiseMode);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, true);
        }
    }
}

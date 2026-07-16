using System.Text.Json;

namespace BudsControl.Core;

public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public SettingsStore(string? filePath = null)
    {
        FilePath = filePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "BudsControl",
            "settings.json");
    }

    public string FilePath { get; }

    public async Task<AppPreferences> LoadAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            if (!File.Exists(FilePath))
            {
                return new AppPreferences();
            }

            await using FileStream stream = File.OpenRead(FilePath);
            AppPreferences? preferences = await JsonSerializer.DeserializeAsync<AppPreferences>(stream, JsonOptions, cancellationToken);
            if (preferences is null)
            {
                return new AppPreferences();
            }

            preferences.Settings ??= new BudsSettings();
            if (!preferences.RememberSettings || !preferences.HasSavedSettings)
            {
                preferences.Settings = new BudsSettings();
            }
            return preferences;
        }
        catch (JsonException)
        {
            return new AppPreferences();
        }
        catch (IOException)
        {
            return new AppPreferences();
        }
    }

    public async Task SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default)
    {
        string? directory = Path.GetDirectoryName(FilePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        string temporaryPath = FilePath + ".tmp";
        await using (FileStream stream = new(
            temporaryPath,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None,
            4096,
            FileOptions.Asynchronous))
        {
            await JsonSerializer.SerializeAsync(stream, preferences, JsonOptions, cancellationToken);
            await stream.FlushAsync(cancellationToken);
        }

        File.Move(temporaryPath, FilePath, true);
    }

    public void Delete()
    {
        if (File.Exists(FilePath))
        {
            File.Delete(FilePath);
        }
        string temporaryPath = FilePath + ".tmp";
        if (File.Exists(temporaryPath))
        {
            File.Delete(temporaryPath);
        }
    }
}

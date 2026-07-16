using BudsControl.Core;
using System.Globalization;
using System.IO;
using System.Text;

namespace BudsControl.Windows;

public sealed class BudsRepository : IAsyncDisposable
{
    private readonly WindowsBluetoothTransport _transport;
    private readonly SettingsStore _store;
    private readonly SemaphoreSlim _saveGate = new(1, 1);
    private readonly List<CommandLogEntry> _commandLog = [];
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private AppPreferences _preferences = new();
    private IReadOnlyList<BluetoothDeviceOption> _devices = [];
    private bool _initialized;
    private bool _disposed;

    public BudsRepository(WindowsBluetoothTransport? transport = null, SettingsStore? store = null)
    {
        _transport = transport ?? new WindowsBluetoothTransport();
        _store = store ?? new SettingsStore();
        _transport.ConnectionChanged += OnConnectionChanged;
        _transport.BatteryReceived += OnBatteryReceived;
        _transport.ExtendedStatusReceived += OnExtendedStatusReceived;
        _transport.FitResultReceived += OnFitResultReceived;
        _transport.FindStopped += OnFindStopped;
    }

    public event EventHandler? Changed;

    public BudsSettings Settings { get; private set; } = new();
    public IReadOnlyList<BluetoothDeviceOption> Devices => _devices;
    public IReadOnlyList<CommandLogEntry> CommandLog => _commandLog.ToArray();
    public BluetoothConnectionState ConnectionState => DemoMode ? BluetoothConnectionState.Connected : _transport.State;
    public string ConnectionDetail { get; private set; } = "尚未连接";
    public int LeftBattery { get; private set; } = -1;
    public int RightBattery { get; private set; } = -1;
    public int CaseBattery { get; private set; } = -1;
    public bool HasExtendedState { get; private set; }
    public bool DemoMode => _preferences.DemoMode;
    public bool ExperimentalCommands => _preferences.ExperimentalCommands;
    public bool RememberSettings => _preferences.RememberSettings;
    public string? LastDeviceAddress => _preferences.LastDeviceAddress;
    public bool FitTestActive { get; private set; }
    public bool FindActive { get; private set; }
    public bool FindLeftMuted { get; private set; }
    public bool FindRightMuted { get; private set; }
    public bool CanControl => DemoMode || _transport.State == BluetoothConnectionState.Connected;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        if (_initialized)
        {
            return;
        }

        _preferences = await _store.LoadAsync(cancellationToken);
        Settings = _preferences.Settings.Clone();
        _initialized = true;

        if (DemoMode)
        {
            ActivateDemo();
            return;
        }

        await RefreshDevicesAsync(cancellationToken);
        BluetoothDeviceOption? previous = _devices.FirstOrDefault(device =>
            string.Equals(device.Address, LastDeviceAddress, StringComparison.OrdinalIgnoreCase));
        if (previous is not null)
        {
            try
            {
                await ConnectAsync(previous, cancellationToken);
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                ConnectionDetail = $"自动连接失败：{SafeMessage(error)}";
                NotifyChanged();
            }
        }
    }

    public async Task RefreshDevicesAsync(CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        try
        {
            _devices = await _transport.GetPairedBudsAsync(cancellationToken);
            if (_devices.Count == 0)
            {
                ConnectionDetail = "未找到已配对的 Galaxy Buds，请先在 Windows 蓝牙设置中配对";
            }
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            _devices = [];
            ConnectionDetail = $"读取已配对设备失败：{SafeMessage(error)}";
        }
        NotifyChanged();
    }

    public async Task ConnectAsync(BluetoothDeviceOption device, CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        if (DemoMode)
        {
            await SetDemoModeAsync(false, cancellationToken);
        }

        _preferences.LastDeviceAddress = device.Address;
        await SavePreferencesAsync(cancellationToken);
        try
        {
            await _transport.ConnectAsync(device, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            ConnectionDetail = "连接已取消";
            NotifyChanged();
            throw;
        }
        catch (Exception error)
        {
            ConnectionDetail = $"RFCOMM 连接失败：{SafeMessage(error)}";
            NotifyChanged();
            throw;
        }
    }

    public Task DisconnectAsync() => _transport.DisconnectAsync();

    public async Task SetDemoModeAsync(bool enabled, CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        if (_preferences.DemoMode == enabled)
        {
            return;
        }

        _preferences.DemoMode = enabled;
        if (enabled)
        {
            await _transport.DisconnectAsync();
            ActivateDemo();
        }
        else
        {
            LeftBattery = -1;
            RightBattery = -1;
            CaseBattery = -1;
            HasExtendedState = false;
            FitTestActive = false;
            FindActive = false;
            FindLeftMuted = false;
            FindRightMuted = false;
            ConnectionDetail = "尚未连接";
            NotifyChanged();
        }
        await SavePreferencesAsync(cancellationToken);
    }

    public async Task SetExperimentalCommandsAsync(bool enabled, CancellationToken cancellationToken = default)
    {
        _preferences.ExperimentalCommands = enabled;
        await SavePreferencesAsync(cancellationToken);
        NotifyChanged();
    }

    public async Task SetRememberSettingsAsync(bool enabled, CancellationToken cancellationToken = default)
    {
        _preferences.RememberSettings = enabled;
        _preferences.HasSavedSettings = enabled;
        _preferences.Settings = enabled ? Settings.Clone() : new BudsSettings();
        await SavePreferencesAsync(cancellationToken);
        NotifyChanged();
    }

    public Task SetNoiseModeAsync(int mode) => ExecuteAsync(BudsProtocol.NoiseControl(mode), value => value.NoiseMode = mode);
    public Task SetEqualizerAsync(int preset) => ExecuteAsync(BudsProtocol.Equalizer(preset), value => value.Equalizer = preset);
    public Task SetAmbientVolumeAsync(int level) => ExecuteAsync(BudsProtocol.AmbientVolume(level), value => value.AmbientVolume = level);
    public Task SetNoiseReductionHighAsync(bool enabled) => ExecuteAsync(BudsProtocol.NoiseReductionLevel(enabled), value => value.NoiseReductionHigh = enabled);
    public Task SetVoiceDetectAsync(bool enabled) => ExecuteAsync(BudsProtocol.VoiceDetect(enabled), value => value.VoiceDetectEnabled = enabled);
    public Task SetVoiceDetectTimeoutAsync(int timeout) => ExecuteAsync(BudsProtocol.VoiceDetectTimeout(timeout), value => value.VoiceDetectTimeout = timeout);
    public Task SetOneEarNoiseControlAsync(bool enabled) => ExecuteAsync(BudsProtocol.OneEarNoiseControl(enabled), value => value.OneEarNoiseControl = enabled);
    public Task SetEdgeDoubleTapAsync(bool enabled) => ExecuteAsync(BudsProtocol.EdgeDoubleTap(enabled), value => value.EdgeDoubleTapVolume = enabled);
    public Task SetStereoBalanceAsync(int balance) => ExecuteAsync(BudsProtocol.StereoBalance(balance), value => value.StereoBalance = balance);
    public Task SetSeamlessConnectionAsync(bool enabled) => ExecuteAsync(BudsProtocol.SeamlessConnection(enabled), value => value.SeamlessConnection = enabled);
    public Task SetSidetoneAsync(bool enabled) => ExecuteAsync(BudsProtocol.Sidetone(enabled), value => value.SidetoneEnabled = enabled);
    public Task SetCallPathControlAsync(bool enabled) => ExecuteAsync(BudsProtocol.CallPathControl(enabled), value => value.CallPathControlEnabled = enabled);
    public Task SetExtraClearCallAsync(bool enabled) => ExecuteAsync(BudsProtocol.ExtraClearCall(enabled), value => value.ExtraClearCallEnabled = enabled);
    public Task SetExtraHighAmbientAsync(bool enabled) => ExecuteAsync(BudsProtocol.ExtraHighAmbient(enabled), value => value.ExtraHighAmbientEnabled = enabled);
    public Task SetSpatialAudioAsync(bool enabled) => ExecuteAsync(BudsProtocol.SpatialAudio(enabled), value => value.SpatialAudioEnabled = enabled);
    public Task SetGamingModeAsync(bool enabled) => ExecuteAsync(BudsProtocol.GamingMode(enabled), value => value.GamingModeEnabled = enabled);
    public Task SetAutoPauseResumeAsync(bool enabled) => ExecuteAsync(BudsProtocol.AutoPauseResume(enabled), value => value.AutoPauseResumeEnabled = enabled);
    public Task SetAdaptiveVolumeAsync(bool enabled) => ExecuteAsync(BudsProtocol.AdaptiveVolume(enabled), value => value.AdaptiveVolumeEnabled = enabled);
    public Task SetSirenDetectAsync(bool enabled) => ExecuteAsync(BudsProtocol.SirenDetect(enabled), value => value.SirenDetectEnabled = enabled);

    public Task SetAmbientCustomizationAsync(bool enabled, int left, int right, int tone) =>
        ExecuteAsync(BudsProtocol.AmbientCustomization(enabled, left, right, tone), value =>
        {
            value.AmbientCustomizationEnabled = enabled;
            value.AmbientVolumeLeft = left;
            value.AmbientVolumeRight = right;
            value.AmbientTone = tone;
        });

    public Task SetTouchLockedAsync(bool locked)
    {
        BudsSettings value = Settings;
        return ExecuteAsync(
            BudsProtocol.TouchLock(locked, value.SingleTapEnabled, value.DoubleTapEnabled, value.TripleTapEnabled,
                value.TouchAndHoldEnabled, value.DoubleTapCallEnabled, value.TouchAndHoldCallEnabled),
            settings => settings.TouchLocked = locked);
    }

    public Task SetGestureAsync(string key, bool enabled)
    {
        BudsSettings current = Settings;
        bool single = key == "single" ? enabled : current.SingleTapEnabled;
        bool doubleTap = key == "double" ? enabled : current.DoubleTapEnabled;
        bool triple = key == "triple" ? enabled : current.TripleTapEnabled;
        bool hold = key == "hold" ? enabled : current.TouchAndHoldEnabled;
        bool callDouble = key == "callDouble" ? enabled : current.DoubleTapCallEnabled;
        bool callHold = key == "callHold" ? enabled : current.TouchAndHoldCallEnabled;
        return ExecuteAsync(
            BudsProtocol.TouchLock(current.TouchLocked, single, doubleTap, triple, hold, callDouble, callHold),
            settings =>
            {
                settings.SingleTapEnabled = single;
                settings.DoubleTapEnabled = doubleTap;
                settings.TripleTapEnabled = triple;
                settings.TouchAndHoldEnabled = hold;
                settings.DoubleTapCallEnabled = callDouble;
                settings.TouchAndHoldCallEnabled = callHold;
            });
    }

    public Task SetTouchActionsAsync(int left, int right) =>
        ExecuteAsync(BudsProtocol.TouchActions(left, right), value =>
        {
            value.LeftTouchAction = left;
            value.RightTouchAction = right;
        });

    public Task SetNoiseCyclesAsync(int left, int right) =>
        ExecuteAsync(BudsProtocol.TouchNoiseCycle(left, right), value =>
        {
            value.LeftNoiseCycle = left;
            value.RightNoiseCycle = right;
        });

    public async Task SetFitTestAsync(bool active)
    {
        bool success = await ExecuteAsync(BudsProtocol.FitTest(active), value =>
        {
            value.FitTestLeft = -1;
            value.FitTestRight = -1;
        });
        if (!success)
        {
            return;
        }

        FitTestActive = active;
        NotifyChanged();
        if (DemoMode && active)
        {
            _ = CompleteDemoFitTestAsync(_lifetimeCancellation.Token);
        }
    }

    public async Task SetFindActiveAsync(bool active)
    {
        bool success = await ExecuteAsync(active ? BudsProtocol.FindStart() : BudsProtocol.FindStop(), _ => { });
        if (!success)
        {
            return;
        }
        FindActive = active;
        if (!active)
        {
            FindLeftMuted = false;
            FindRightMuted = false;
        }
        NotifyChanged();
    }

    public async Task SetFindMuteAsync(bool left, bool right)
    {
        bool success = await ExecuteAsync(BudsProtocol.MuteEarbuds(left, right), _ => { });
        if (!success)
        {
            return;
        }
        FindLeftMuted = left;
        FindRightMuted = right;
        NotifyChanged();
    }

    public void ClearCommandLog()
    {
        _commandLog.Clear();
        NotifyChanged();
    }

    public string CreateValidationReport()
    {
        StringBuilder report = new();
        report.AppendLine("BudsControl Windows 0.1.0 验证记录");
        report.Append("生成时间：").AppendLine(DateTimeOffset.Now.ToString("F", CultureInfo.CurrentCulture));
        report.Append("模式：").AppendLine(DemoMode ? "离线演示" : "Bluetooth Classic RFCOMM 直连");
        report.Append("连接：").AppendLine(ConnectionDetail);
        report.Append("扩展状态：").AppendLine(HasExtendedState ? "已读取" : "未读取");
        report.AppendLine();
        if (_commandLog.Count == 0)
        {
            report.AppendLine("尚未发送命令。");
            return report.ToString();
        }

        foreach (CommandLogEntry entry in _commandLog)
        {
            report.Append('[').Append(entry.Timestamp.ToLocalTime().ToString("T", CultureInfo.CurrentCulture)).Append("] ")
                .Append(entry.Result).Append(" | ")
                .Append(entry.Title).Append(" | ")
                .Append(entry.Packet).Append(" | ")
                .AppendLine(entry.Detail);
        }
        return report.ToString();
    }

    private async Task<bool> ExecuteAsync(BudsCommand command, Action<BudsSettings> mutation)
    {
        ThrowIfDisposed();
        if (command.Verification == VerificationLevel.Experimental && !ExperimentalCommands)
        {
            AppendLog(command, "失败", "实验命令未授权");
            ConnectionDetail = "请先在验证中心开启实验命令";
            NotifyChanged();
            return false;
        }

        if (DemoMode)
        {
            await Task.Delay(150, _lifetimeCancellation.Token);
            mutation(Settings);
            await PersistSettingsAsync();
            AppendLog(command, "离线模拟", "未发送到耳机");
            NotifyChanged();
            return true;
        }

        if (_transport.State != BluetoothConnectionState.Connected)
        {
            AppendLog(command, "失败", "耳机未连接");
            ConnectionDetail = "请先连接已配对的 Buds3 Pro";
            NotifyChanged();
            return false;
        }

        CommandResult result = await _transport.SendAsync(command, _lifetimeCancellation.Token);
        if (result.Success)
        {
            mutation(Settings);
            await PersistSettingsAsync();
        }
        string status = result.Success ? (result.Acknowledged ? "耳机 ACK" : "已写入") : "失败";
        AppendLog(command, status, result.Detail);
        ConnectionDetail = result.Detail;
        NotifyChanged();
        return result.Success;
    }

    private async Task CompleteDemoFitTestAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromMilliseconds(1500), cancellationToken);
            if (!DemoMode || !FitTestActive)
            {
                return;
            }
            Settings.FitTestLeft = 1;
            Settings.FitTestRight = 1;
            FitTestActive = false;
            await PersistSettingsAsync();
            NotifyChanged();
        }
        catch (OperationCanceledException)
        {
        }
    }

    private void ActivateDemo()
    {
        if (!_preferences.HasSavedSettings)
        {
            Settings = BudsSettings.Demo();
        }
        LeftBattery = 86;
        RightBattery = 83;
        CaseBattery = 74;
        HasExtendedState = true;
        ConnectionDetail = "离线演示模式";
        NotifyChanged();
    }

    private void AppendLog(BudsCommand command, string result, string detail)
    {
        _commandLog.Add(new CommandLogEntry(DateTimeOffset.Now, command.Title, BudsProtocol.Hex(command.Packet), result, detail));
        if (_commandLog.Count > 100)
        {
            _commandLog.RemoveRange(0, _commandLog.Count - 100);
        }
    }

    private async Task PersistSettingsAsync()
    {
        if (!RememberSettings)
        {
            return;
        }
        _preferences.HasSavedSettings = true;
        _preferences.Settings = Settings.Clone();
        await SavePreferencesAsync(_lifetimeCancellation.Token);
    }

    private async Task SavePreferencesAsync(CancellationToken cancellationToken)
    {
        await _saveGate.WaitAsync(cancellationToken);
        try
        {
            await _store.SaveAsync(_preferences, cancellationToken);
        }
        finally
        {
            _saveGate.Release();
        }
    }

    private void OnConnectionChanged(object? sender, (BluetoothConnectionState State, string Detail) change)
    {
        ConnectionDetail = change.Detail;
        if (change.State != BluetoothConnectionState.Connected)
        {
            HasExtendedState = false;
            FitTestActive = false;
            FindActive = false;
            FindLeftMuted = false;
            FindRightMuted = false;
        }
        NotifyChanged();
    }

    private void OnBatteryReceived(object? sender, BatteryReading reading)
    {
        if (reading.Left >= 0) LeftBattery = reading.Left;
        if (reading.Right >= 0) RightBattery = reading.Right;
        if (reading.Case >= 0) CaseBattery = reading.Case;
        NotifyChanged();
    }

    private void OnExtendedStatusReceived(object? sender, byte[] payload)
    {
        Settings.ApplyExtendedPayload(payload);
        HasExtendedState = true;
        _ = PersistAfterTransportEventAsync();
        NotifyChanged();
    }

    private void OnFitResultReceived(object? sender, FitResult result)
    {
        Settings.FitTestLeft = result.Left;
        Settings.FitTestRight = result.Right;
        FitTestActive = false;
        _ = PersistAfterTransportEventAsync();
        NotifyChanged();
    }

    private void OnFindStopped(object? sender, EventArgs eventArgs)
    {
        FindActive = false;
        FindLeftMuted = false;
        FindRightMuted = false;
        NotifyChanged();
    }

    private async Task PersistAfterTransportEventAsync()
    {
        try
        {
            await PersistSettingsAsync();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or OperationCanceledException)
        {
            if (!_disposed)
            {
                ConnectionDetail = $"状态已读取，但保存失败：{SafeMessage(error)}";
                NotifyChanged();
            }
        }
    }

    private void NotifyChanged() => Changed?.Invoke(this, EventArgs.Empty);
    private static string SafeMessage(Exception error) => string.IsNullOrWhiteSpace(error.Message) ? error.GetType().Name : error.Message;
    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _lifetimeCancellation.Cancel();
        _transport.ConnectionChanged -= OnConnectionChanged;
        _transport.BatteryReceived -= OnBatteryReceived;
        _transport.ExtendedStatusReceived -= OnExtendedStatusReceived;
        _transport.FitResultReceived -= OnFitResultReceived;
        _transport.FindStopped -= OnFindStopped;
        await _transport.DisposeAsync();
        await _saveGate.WaitAsync();
        _saveGate.Release();
        _lifetimeCancellation.Dispose();
        _saveGate.Dispose();
    }
}

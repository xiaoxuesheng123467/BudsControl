using BudsControl.Core;
using Microsoft.Win32;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;

namespace BudsControl.Windows;

public sealed class MainViewModel : INotifyPropertyChanged, IAsyncDisposable
{
    private static readonly int[] NoiseCycleValues = [4, 8, 12];
    private readonly BudsRepository _repository;
    private readonly Dispatcher _dispatcher;
    private BluetoothDeviceOption? _selectedDevice;
    private bool _isBusy;
    private string? _operationError;
    private bool _disposed;

    public MainViewModel(BudsRepository? repository = null)
    {
        _repository = repository ?? new BudsRepository();
        _dispatcher = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
        _repository.Changed += OnRepositoryChanged;

        RefreshDevicesCommand = new AsyncRelayCommand(_ => RunAsync(RefreshDevicesAsync), _ => !IsBusy);
        ConnectCommand = new AsyncRelayCommand(_ => RunAsync(ConnectAsync), _ => CanConnect);
        DisconnectCommand = new AsyncRelayCommand(_ => RunAsync(_repository.DisconnectAsync), _ => CanDisconnect);
        SetNoiseModeCommand = new AsyncRelayCommand(parameter => RunAsync(() => _repository.SetNoiseModeAsync(ParseInt(parameter))), _ => CanControl);
        ToggleFitTestCommand = new AsyncRelayCommand(_ => RunAsync(() => _repository.SetFitTestAsync(!FitTestActive)), _ => CanControl);
        ToggleFindCommand = new AsyncRelayCommand(_ => RunAsync(() => _repository.SetFindActiveAsync(!FindActive)), _ => CanControl);
        ClearLogCommand = new RelayCommand(_ => _repository.ClearCommandLog(), _ => CommandCount > 0);
        CopyReportCommand = new RelayCommand(_ => CopyReport());
        SaveReportCommand = new RelayCommand(_ => SaveReport());
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ICommand RefreshDevicesCommand { get; }
    public ICommand ConnectCommand { get; }
    public ICommand DisconnectCommand { get; }
    public ICommand SetNoiseModeCommand { get; }
    public ICommand ToggleFitTestCommand { get; }
    public ICommand ToggleFindCommand { get; }
    public ICommand ClearLogCommand { get; }
    public ICommand CopyReportCommand { get; }
    public ICommand SaveReportCommand { get; }

    public IReadOnlyList<BluetoothDeviceOption> Devices => _repository.Devices;
    public IReadOnlyList<CommandLogEntry> CommandLog => _repository.CommandLog.Reverse().Take(50).ToArray();
    public int CommandCount => _repository.CommandLog.Count;

    public BluetoothDeviceOption? SelectedDevice
    {
        get => _selectedDevice;
        set
        {
            if (SetField(ref _selectedDevice, value))
            {
                OnPropertyChanged(nameof(CanConnect));
                RaiseCommandState();
            }
        }
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set
        {
            if (SetField(ref _isBusy, value))
            {
                OnPropertyChanged(nameof(CanControl));
                RaiseCommandState();
                OnPropertyChanged(nameof(CanConnect));
                OnPropertyChanged(nameof(CanDisconnect));
                OnPropertyChanged(nameof(GestureControlsEnabled));
                OnPropertyChanged(nameof(AmbientCustomizationControlsEnabled));
                OnPropertyChanged(nameof(VoiceTimeoutEnabled));
                OnPropertyChanged(nameof(FindMuteEnabled));
                OnPropertyChanged(nameof(ExperimentalControlsEnabled));
                OnPropertyChanged(nameof(ValidationControlsEnabled));
            }
        }
    }

    public bool CanControl => !IsBusy && _repository.CanControl;
    public bool CanConnect => !IsBusy &&
                              !DemoMode &&
                              SelectedDevice is not null &&
                              _repository.ConnectionState == BluetoothConnectionState.Disconnected;
    public bool CanDisconnect => !IsBusy && !DemoMode && _repository.ConnectionState != BluetoothConnectionState.Disconnected;
    public bool GestureControlsEnabled => CanControl && !TouchLocked;
    public bool AmbientCustomizationControlsEnabled => CanControl && AmbientCustomizationEnabled;
    public bool VoiceTimeoutEnabled => CanControl && VoiceDetectEnabled;
    public bool FindMuteEnabled => CanControl && FindActive;
    public bool ExperimentalControlsEnabled => CanControl && ExperimentalCommands;
    public bool ValidationControlsEnabled => !IsBusy;
    public string ConnectionStateText => _repository.ConnectionState switch
    {
        BluetoothConnectionState.Connected => DemoMode ? "演示" : "已连接",
        BluetoothConnectionState.Connecting => "连接中",
        _ => "未连接",
    };
    public string ConnectionDetail => _operationError ?? _repository.ConnectionDetail;
    public string ControlPath => DemoMode ? "离线演示" : "Windows Bluetooth Classic RFCOMM 直连";
    public string ExtendedStateText => _repository.HasExtendedState ? "已读取" : "未读取";
    public string LeftBattery => BatteryText(_repository.LeftBattery);
    public string RightBattery => BatteryText(_repository.RightBattery);
    public string CaseBattery => BatteryText(_repository.CaseBattery);

    public int NoiseMode => _repository.Settings.NoiseMode;
    public int EqualizerIndex { get => _repository.Settings.Equalizer; set => ChangeSetting(value, EqualizerIndex, () => _repository.SetEqualizerAsync(value)); }
    public int AmbientVolumeIndex { get => _repository.Settings.AmbientVolume; set => ChangeSetting(value, AmbientVolumeIndex, () => _repository.SetAmbientVolumeAsync(value)); }
    public bool NoiseReductionHigh { get => _repository.Settings.NoiseReductionHigh; set => ChangeSetting(value, NoiseReductionHigh, () => _repository.SetNoiseReductionHighAsync(value)); }
    public bool ExtraHighAmbientEnabled { get => _repository.Settings.ExtraHighAmbientEnabled; set => ChangeSetting(value, ExtraHighAmbientEnabled, () => _repository.SetExtraHighAmbientAsync(value)); }
    public bool AmbientCustomizationEnabled
    {
        get => _repository.Settings.AmbientCustomizationEnabled;
        set => ChangeSetting(value, AmbientCustomizationEnabled, () => _repository.SetAmbientCustomizationAsync(value, AmbientVolumeLeft, AmbientVolumeRight, AmbientToneIndex));
    }
    public int AmbientVolumeLeft
    {
        get => _repository.Settings.AmbientVolumeLeft;
        set => ChangeSetting(value, AmbientVolumeLeft, () => _repository.SetAmbientCustomizationAsync(true, value, AmbientVolumeRight, AmbientToneIndex));
    }
    public int AmbientVolumeRight
    {
        get => _repository.Settings.AmbientVolumeRight;
        set => ChangeSetting(value, AmbientVolumeRight, () => _repository.SetAmbientCustomizationAsync(true, AmbientVolumeLeft, value, AmbientToneIndex));
    }
    public int AmbientToneIndex
    {
        get => _repository.Settings.AmbientTone;
        set => ChangeSetting(value, AmbientToneIndex, () => _repository.SetAmbientCustomizationAsync(true, AmbientVolumeLeft, AmbientVolumeRight, value));
    }
    public bool VoiceDetectEnabled { get => _repository.Settings.VoiceDetectEnabled; set => ChangeSetting(value, VoiceDetectEnabled, () => _repository.SetVoiceDetectAsync(value)); }
    public int VoiceDetectTimeoutIndex { get => _repository.Settings.VoiceDetectTimeout; set => ChangeSetting(value, VoiceDetectTimeoutIndex, () => _repository.SetVoiceDetectTimeoutAsync(value)); }
    public bool OneEarNoiseControl { get => _repository.Settings.OneEarNoiseControl; set => ChangeSetting(value, OneEarNoiseControl, () => _repository.SetOneEarNoiseControlAsync(value)); }

    public bool TouchLocked { get => _repository.Settings.TouchLocked; set => ChangeSetting(value, TouchLocked, () => _repository.SetTouchLockedAsync(value)); }
    public bool SingleTapEnabled { get => _repository.Settings.SingleTapEnabled; set => ChangeGesture(value, SingleTapEnabled, "single"); }
    public bool DoubleTapEnabled { get => _repository.Settings.DoubleTapEnabled; set => ChangeGesture(value, DoubleTapEnabled, "double"); }
    public bool TripleTapEnabled { get => _repository.Settings.TripleTapEnabled; set => ChangeGesture(value, TripleTapEnabled, "triple"); }
    public bool TouchAndHoldEnabled { get => _repository.Settings.TouchAndHoldEnabled; set => ChangeGesture(value, TouchAndHoldEnabled, "hold"); }
    public bool DoubleTapCallEnabled { get => _repository.Settings.DoubleTapCallEnabled; set => ChangeGesture(value, DoubleTapCallEnabled, "callDouble"); }
    public bool TouchAndHoldCallEnabled { get => _repository.Settings.TouchAndHoldCallEnabled; set => ChangeGesture(value, TouchAndHoldCallEnabled, "callHold"); }
    public int LeftTouchActionIndex
    {
        get => _repository.Settings.LeftTouchAction - 1;
        set => ChangeSetting(value, LeftTouchActionIndex, () => _repository.SetTouchActionsAsync(value + 1, _repository.Settings.RightTouchAction));
    }
    public int RightTouchActionIndex
    {
        get => _repository.Settings.RightTouchAction - 1;
        set => ChangeSetting(value, RightTouchActionIndex, () => _repository.SetTouchActionsAsync(_repository.Settings.LeftTouchAction, value + 1));
    }
    public int LeftNoiseCycleIndex
    {
        get => CycleIndex(_repository.Settings.LeftNoiseCycle);
        set => ChangeSetting(value, LeftNoiseCycleIndex, () => _repository.SetNoiseCyclesAsync(CycleValue(value), _repository.Settings.RightNoiseCycle));
    }
    public int RightNoiseCycleIndex
    {
        get => CycleIndex(_repository.Settings.RightNoiseCycle);
        set => ChangeSetting(value, RightNoiseCycleIndex, () => _repository.SetNoiseCyclesAsync(_repository.Settings.LeftNoiseCycle, CycleValue(value)));
    }
    public bool EdgeDoubleTapVolume { get => _repository.Settings.EdgeDoubleTapVolume; set => ChangeSetting(value, EdgeDoubleTapVolume, () => _repository.SetEdgeDoubleTapAsync(value)); }

    public int StereoBalance
    {
        get => _repository.Settings.StereoBalance;
        set => ChangeSetting(value, StereoBalance, () => _repository.SetStereoBalanceAsync(value));
    }
    public string StereoBalanceText => BalanceText(StereoBalance);
    public bool SeamlessConnection { get => _repository.Settings.SeamlessConnection; set => ChangeSetting(value, SeamlessConnection, () => _repository.SetSeamlessConnectionAsync(value)); }
    public bool SidetoneEnabled { get => _repository.Settings.SidetoneEnabled; set => ChangeSetting(value, SidetoneEnabled, () => _repository.SetSidetoneAsync(value)); }
    public bool CallPathControlEnabled { get => _repository.Settings.CallPathControlEnabled; set => ChangeSetting(value, CallPathControlEnabled, () => _repository.SetCallPathControlAsync(value)); }
    public bool ExtraClearCallEnabled { get => _repository.Settings.ExtraClearCallEnabled; set => ChangeSetting(value, ExtraClearCallEnabled, () => _repository.SetExtraClearCallAsync(value)); }
    public bool SpatialAudioEnabled { get => _repository.Settings.SpatialAudioEnabled; set => ChangeSetting(value, SpatialAudioEnabled, () => _repository.SetSpatialAudioAsync(value)); }
    public bool GamingModeEnabled { get => _repository.Settings.GamingModeEnabled; set => ChangeSetting(value, GamingModeEnabled, () => _repository.SetGamingModeAsync(value)); }
    public bool AutoPauseResumeEnabled { get => _repository.Settings.AutoPauseResumeEnabled; set => ChangeSetting(value, AutoPauseResumeEnabled, () => _repository.SetAutoPauseResumeAsync(value)); }
    public string LightingControlText => _repository.Settings.LightingControl < 0 ? "未读取" : _repository.Settings.LightingControl.ToString(CultureInfo.CurrentCulture);
    public string HotCommandText => TriState(_repository.Settings.HotCommandEnabled);
    public string AdaptSoundText => TriState(_repository.Settings.AdaptSoundEnabled);

    public bool FitTestActive => _repository.FitTestActive;
    public string FitTestButtonText => FitTestActive ? "停止测试" : "开始测试";
    public string FitTestLeftText => FitText(_repository.Settings.FitTestLeft, FitTestActive);
    public string FitTestRightText => FitText(_repository.Settings.FitTestRight, FitTestActive);
    public bool FindActive => _repository.FindActive;
    public string FindStatusText => FindActive ? "正在响铃" : "已停止";
    public string FindButtonText => FindActive ? "停止响铃" : "开始查找";
    public bool FindLeftMuted
    {
        get => _repository.FindLeftMuted;
        set => ChangeSetting(value, FindLeftMuted, () => _repository.SetFindMuteAsync(value, FindRightMuted));
    }
    public bool FindRightMuted
    {
        get => _repository.FindRightMuted;
        set => ChangeSetting(value, FindRightMuted, () => _repository.SetFindMuteAsync(FindLeftMuted, value));
    }
    public bool AdaptiveVolumeEnabled { get => _repository.Settings.AdaptiveVolumeEnabled; set => ChangeSetting(value, AdaptiveVolumeEnabled, () => _repository.SetAdaptiveVolumeAsync(value)); }
    public bool SirenDetectEnabled { get => _repository.Settings.SirenDetectEnabled; set => ChangeSetting(value, SirenDetectEnabled, () => _repository.SetSirenDetectAsync(value)); }

    public bool DemoMode { get => _repository.DemoMode; set => ChangeSetting(value, DemoMode, () => _repository.SetDemoModeAsync(value)); }
    public bool ExperimentalCommands { get => _repository.ExperimentalCommands; set => ChangeSetting(value, ExperimentalCommands, () => _repository.SetExperimentalCommandsAsync(value)); }
    public bool RememberSettings { get => _repository.RememberSettings; set => ChangeSetting(value, RememberSettings, () => _repository.SetRememberSettingsAsync(value)); }

    public async Task InitializeAsync()
    {
        await RunAsync(() => _repository.InitializeAsync());
        SelectPreferredDevice();
        RefreshAll();
    }

    private async Task RefreshDevicesAsync()
    {
        await _repository.RefreshDevicesAsync();
        SelectPreferredDevice();
    }

    private async Task ConnectAsync()
    {
        if (SelectedDevice is null)
        {
            return;
        }
        await _repository.ConnectAsync(SelectedDevice);
    }

    private async Task RunAsync(Func<Task> action)
    {
        if (_disposed || IsBusy)
        {
            return;
        }
        IsBusy = true;
        _operationError = null;
        OnPropertyChanged(nameof(ConnectionDetail));
        try
        {
            await action();
        }
        catch (OperationCanceledException)
        {
            _operationError = "操作已取消";
        }
        catch (Exception error)
        {
            _operationError = string.IsNullOrWhiteSpace(error.Message) ? error.GetType().Name : error.Message;
        }
        finally
        {
            IsBusy = false;
            RefreshAll();
        }
    }

    private void ChangeSetting<T>(T value, T current, Func<Task> action)
    {
        if (_disposed || IsBusy || EqualityComparer<T>.Default.Equals(value, current))
        {
            return;
        }
        _ = RunAsync(action);
    }

    private void ChangeGesture(bool value, bool current, string key) =>
        ChangeSetting(value, current, () => _repository.SetGestureAsync(key, value));

    private void SelectPreferredDevice()
    {
        BluetoothDeviceOption? previous = Devices.FirstOrDefault(device =>
            string.Equals(device.Address, SelectedDevice?.Address, StringComparison.OrdinalIgnoreCase));
        SelectedDevice = previous
            ?? Devices.FirstOrDefault(device => string.Equals(device.Address, _repository.LastDeviceAddress, StringComparison.OrdinalIgnoreCase))
            ?? Devices.FirstOrDefault();
    }

    private void CopyReport()
    {
        try
        {
            Clipboard.SetText(_repository.CreateValidationReport());
            _operationError = "验证记录已复制";
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            _operationError = $"复制失败：{error.Message}";
        }
        OnPropertyChanged(nameof(ConnectionDetail));
    }

    private void SaveReport()
    {
        SaveFileDialog dialog = new()
        {
            Title = "保存 BudsControl 验证记录",
            FileName = $"BudsControl-Windows-{DateTime.Now:yyyyMMdd-HHmmss}.txt",
            DefaultExt = ".txt",
            Filter = "文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*",
            AddExtension = true,
        };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        try
        {
            File.WriteAllText(dialog.FileName, _repository.CreateValidationReport());
            _operationError = $"验证记录已保存到 {dialog.FileName}";
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            _operationError = $"保存失败：{error.Message}";
        }
        OnPropertyChanged(nameof(ConnectionDetail));
    }

    private void OnRepositoryChanged(object? sender, EventArgs eventArgs)
    {
        if (_dispatcher.CheckAccess())
        {
            RefreshAll();
        }
        else
        {
            _dispatcher.BeginInvoke(RefreshAll);
        }
    }

    private void RefreshAll()
    {
        if (_disposed)
        {
            return;
        }
        OnPropertyChanged(string.Empty);
        RaiseCommandState();
    }

    private static int ParseInt(object? value) => Convert.ToInt32(value, CultureInfo.InvariantCulture);
    private static string BatteryText(int value) => value < 0 ? "--" : $"{value}%";
    private static string TriState(int value) => value < 0 ? "未读取" : value == 1 ? "已开启" : "关闭";
    private static string BalanceText(int value) => value == 16 ? "居中" : value < 16 ? $"左 +{16 - value}" : $"右 +{value - 16}";
    private static string FitText(int value, bool active) => active ? "测试中" : value switch { 0 => "需要调整", 1 => "贴合良好", 2 => "测试失败", _ => "尚未测试" };
    private static int CycleIndex(int value)
    {
        int index = Array.IndexOf(NoiseCycleValues, value);
        return index >= 0 ? index : 1;
    }
    private static int CycleValue(int index) => index >= 0 && index < NoiseCycleValues.Length ? NoiseCycleValues[index] : 8;

    private void RaiseCommandState() => CommandManager.InvalidateRequerySuggested();

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _repository.Changed -= OnRepositoryChanged;
        await _repository.DisposeAsync();
    }
}

public sealed class AsyncRelayCommand(Func<object?, Task> execute, Predicate<object?>? canExecute = null) : ICommand
{
    private bool _isExecuting;

    public event EventHandler? CanExecuteChanged
    {
        add => CommandManager.RequerySuggested += value;
        remove => CommandManager.RequerySuggested -= value;
    }

    public bool CanExecute(object? parameter) => !_isExecuting && (canExecute?.Invoke(parameter) ?? true);

    public async void Execute(object? parameter)
    {
        if (!CanExecute(parameter))
        {
            return;
        }
        _isExecuting = true;
        CommandManager.InvalidateRequerySuggested();
        try
        {
            await execute(parameter);
        }
        finally
        {
            _isExecuting = false;
            CommandManager.InvalidateRequerySuggested();
        }
    }
}

public sealed class RelayCommand(Action<object?> execute, Predicate<object?>? canExecute = null) : ICommand
{
    public event EventHandler? CanExecuteChanged
    {
        add => CommandManager.RequerySuggested += value;
        remove => CommandManager.RequerySuggested -= value;
    }

    public bool CanExecute(object? parameter) => canExecute?.Invoke(parameter) ?? true;
    public void Execute(object? parameter) => execute(parameter);
}

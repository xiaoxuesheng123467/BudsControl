package com.qiao.budscontrol;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;

import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;

final class BudsRepository implements BudsConnectionManager.Listener {
    interface Listener {
        void onRepositoryChanged();
    }

    interface SettingsMutation {
        void apply(BudsSettings settings);
    }

    static final class DeviceOption {
        final BluetoothDevice device;
        final String name;
        final String address;

        DeviceOption(BluetoothDevice device, String name, String address) {
            this.device = device;
            this.name = name;
            this.address = address;
        }

        @Override
        public String toString() {
            return name + "\n" + address;
        }
    }

    static final class CommandLogEntry {
        final Date date;
        final String title;
        final String packet;
        final String result;
        final String detail;

        CommandLogEntry(Date date, String title, String packet, String result, String detail) {
            this.date = date;
            this.title = title;
            this.packet = packet;
            this.result = result;
            this.detail = detail;
        }
    }

    private static BudsRepository instance;

    static synchronized BudsRepository get(Context context) {
        if (instance == null) instance = new BudsRepository(context.getApplicationContext());
        return instance;
    }

    private final SharedPreferences appPreferences;
    private final SharedPreferences settingsPreferences;
    private final BluetoothAdapter adapter;
    private final BudsConnectionManager connectionManager;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final CopyOnWriteArrayList<Listener> listeners = new CopyOnWriteArrayList<>();
    private final ArrayList<CommandLogEntry> commandLog = new ArrayList<>();

    private BudsSettings settings;
    private BudsConnectionManager.State connectionState = BudsConnectionManager.State.DISCONNECTED;
    private String connectionDetail = "尚未连接";
    private int leftBattery = -1;
    private int rightBattery = -1;
    private int caseBattery = -1;
    private boolean hasExtendedState;
    private boolean demoMode;
    private boolean experimentalCommands;
    private boolean rememberSettings;
    private boolean fitTestActive;
    private boolean findActive;
    private boolean findLeftMuted;
    private boolean findRightMuted;

    private BudsRepository(Context context) {
        appPreferences = context.getSharedPreferences("buds_app", Context.MODE_PRIVATE);
        settingsPreferences = context.getSharedPreferences("buds_settings", Context.MODE_PRIVATE);
        rememberSettings = appPreferences.getBoolean("remember_settings", true);
        demoMode = appPreferences.getBoolean("demo_mode", false);
        experimentalCommands = appPreferences.getBoolean("experimental_commands", false);
        settings = rememberSettings ? BudsSettings.load(settingsPreferences) : new BudsSettings();

        BluetoothManager manager = context.getSystemService(BluetoothManager.class);
        adapter = manager == null ? null : manager.getAdapter();
        connectionManager = adapter == null ? null : new BudsConnectionManager(adapter);
        if (connectionManager != null) connectionManager.setListener(this);

        if (demoMode) activateDemo();
    }

    void addListener(Listener listener) {
        listeners.addIfAbsent(listener);
    }

    void removeListener(Listener listener) {
        listeners.remove(listener);
    }

    BluetoothAdapter getAdapter() {
        return adapter;
    }

    BudsSettings getSettings() {
        return settings;
    }

    BudsConnectionManager.State getConnectionState() {
        return demoMode ? BudsConnectionManager.State.CONNECTED : connectionState;
    }

    String getConnectionDetail() {
        return demoMode ? "离线演示模式" : connectionDetail;
    }

    int getLeftBattery() { return leftBattery; }
    int getRightBattery() { return rightBattery; }
    int getCaseBattery() { return caseBattery; }
    boolean hasExtendedState() { return hasExtendedState; }
    boolean isDemoMode() { return demoMode; }
    boolean isExperimentalCommandsEnabled() { return experimentalCommands; }
    boolean isRememberSettingsEnabled() { return rememberSettings; }
    boolean isFitTestActive() { return fitTestActive; }
    boolean isFindActive() { return findActive; }
    boolean isFindLeftMuted() { return findLeftMuted; }
    boolean isFindRightMuted() { return findRightMuted; }

    boolean canControl() {
        return demoMode || connectionState == BudsConnectionManager.State.CONNECTED;
    }

    List<CommandLogEntry> getCommandLog() {
        return new ArrayList<>(commandLog);
    }

    @SuppressLint("MissingPermission")
    List<DeviceOption> pairedBuds() {
        ArrayList<DeviceOption> result = new ArrayList<>();
        if (adapter == null) return result;
        try {
            Set<BluetoothDevice> bonded = adapter.getBondedDevices();
            for (BluetoothDevice device : bonded) {
                String name = device.getName();
                String normalized = name == null ? "" : name.toLowerCase(Locale.ROOT);
                if (normalized.contains("buds3 pro") || normalized.contains("galaxy buds") || normalized.contains("sm-r630")) {
                    result.add(new DeviceOption(
                            device,
                            name == null || name.isBlank() ? "Galaxy Buds" : name,
                            device.getAddress()
                    ));
                }
            }
            result.sort(Comparator.comparing(option -> option.name));
        } catch (SecurityException ignored) {
        }
        return result;
    }

    void connect(DeviceOption option) {
        if (connectionManager == null) {
            connectionDetail = "这台设备不支持 Bluetooth Classic";
            notifyChanged();
            return;
        }
        if (demoMode) setDemoMode(false);
        appPreferences.edit().putString("last_device", option.address).apply();
        connectionManager.connect(option.device);
    }

    void autoConnectLast() {
        if (demoMode || connectionState != BudsConnectionManager.State.DISCONNECTED) return;
        String address = appPreferences.getString("last_device", null);
        if (address == null) return;
        for (DeviceOption option : pairedBuds()) {
            if (option.address.equals(address)) {
                connect(option);
                return;
            }
        }
    }

    void disconnect() {
        if (connectionManager != null) connectionManager.disconnect();
    }

    void setDemoMode(boolean enabled) {
        if (enabled == demoMode) return;
        demoMode = enabled;
        appPreferences.edit().putBoolean("demo_mode", enabled).apply();
        if (enabled) {
            if (connectionManager != null) connectionManager.disconnect();
            activateDemo();
        } else {
            leftBattery = rightBattery = caseBattery = -1;
            hasExtendedState = false;
            connectionState = BudsConnectionManager.State.DISCONNECTED;
            connectionDetail = "尚未连接";
            notifyChanged();
        }
    }

    void setExperimentalCommands(boolean enabled) {
        experimentalCommands = enabled;
        appPreferences.edit().putBoolean("experimental_commands", enabled).apply();
        notifyChanged();
    }

    void setRememberSettings(boolean enabled) {
        rememberSettings = enabled;
        appPreferences.edit().putBoolean("remember_settings", enabled).apply();
        if (enabled) settings.save(settingsPreferences);
        else settingsPreferences.edit().clear().apply();
        notifyChanged();
    }

    void setNoiseMode(int mode) {
        execute(BudsProtocol.noiseControl(mode), value -> value.noiseMode = mode);
    }

    void setEqualizer(int preset) {
        execute(BudsProtocol.equalizer(preset), value -> value.equalizer = preset);
    }

    void setAmbientVolume(int level) {
        execute(BudsProtocol.ambientVolume(level), value -> value.ambientVolume = level);
    }

    void updateAmbientCustomization(boolean enabled, int left, int right, int tone) {
        execute(BudsProtocol.ambientCustomization(enabled, left, right, tone), value -> {
            value.ambientCustomizationEnabled = enabled;
            value.ambientVolumeLeft = left;
            value.ambientVolumeRight = right;
            value.ambientTone = tone;
        });
    }

    void setNoiseReductionHigh(boolean enabled) {
        execute(BudsProtocol.noiseReductionLevel(enabled), value -> value.noiseReductionHigh = enabled);
    }

    void setVoiceDetect(boolean enabled) {
        execute(BudsProtocol.voiceDetect(enabled), value -> value.voiceDetectEnabled = enabled);
    }

    void setVoiceDetectTimeout(int timeout) {
        execute(BudsProtocol.voiceDetectTimeout(timeout), value -> value.voiceDetectTimeout = timeout);
    }

    void setOneEarNoiseControl(boolean enabled) {
        execute(BudsProtocol.oneEarNoiseControl(enabled), value -> value.oneEarNoiseControl = enabled);
    }

    void setTouchLocked(boolean locked) {
        BudsSettings current = settings;
        execute(BudsProtocol.touchLock(
                locked,
                current.singleTapEnabled,
                current.doubleTapEnabled,
                current.tripleTapEnabled,
                current.touchAndHoldEnabled,
                current.doubleTapCallEnabled,
                current.touchAndHoldCallEnabled
        ), value -> value.touchLocked = locked);
    }

    void setGesture(String key, boolean enabled) {
        BudsSettings current = settings;
        boolean single = key.equals("single") ? enabled : current.singleTapEnabled;
        boolean dual = key.equals("double") ? enabled : current.doubleTapEnabled;
        boolean triple = key.equals("triple") ? enabled : current.tripleTapEnabled;
        boolean hold = key.equals("hold") ? enabled : current.touchAndHoldEnabled;
        boolean callDouble = key.equals("call_double") ? enabled : current.doubleTapCallEnabled;
        boolean callHold = key.equals("call_hold") ? enabled : current.touchAndHoldCallEnabled;
        execute(BudsProtocol.touchLock(current.touchLocked, single, dual, triple, hold, callDouble, callHold), value -> {
            value.singleTapEnabled = single;
            value.doubleTapEnabled = dual;
            value.tripleTapEnabled = triple;
            value.touchAndHoldEnabled = hold;
            value.doubleTapCallEnabled = callDouble;
            value.touchAndHoldCallEnabled = callHold;
        });
    }

    void setTouchActions(int left, int right) {
        execute(BudsProtocol.touchActions(left, right), value -> {
            value.leftTouchAction = left;
            value.rightTouchAction = right;
        });
    }

    void setNoiseCycles(int left, int right) {
        execute(BudsProtocol.touchNoiseCycle(left, right), value -> {
            value.leftNoiseCycle = left;
            value.rightNoiseCycle = right;
        });
    }

    void setEdgeDoubleTap(boolean enabled) {
        execute(BudsProtocol.edgeDoubleTap(enabled), value -> value.edgeDoubleTapVolume = enabled);
    }

    void setStereoBalance(int balance) {
        execute(BudsProtocol.stereoBalance(balance), value -> value.stereoBalance = balance);
    }

    void setSeamlessConnection(boolean enabled) {
        execute(BudsProtocol.seamlessConnection(enabled), value -> value.seamlessConnection = enabled);
    }

    void setSidetone(boolean enabled) {
        execute(BudsProtocol.sidetone(enabled), value -> value.sidetoneEnabled = enabled);
    }

    void setCallPathControl(boolean enabled) {
        execute(BudsProtocol.callPathControl(enabled), value -> value.callPathControlEnabled = enabled);
    }

    void setExtraClearCall(boolean enabled) {
        execute(BudsProtocol.extraClearCall(enabled), value -> value.extraClearCallEnabled = enabled);
    }

    void setExtraHighAmbient(boolean enabled) {
        execute(BudsProtocol.extraHighAmbient(enabled), value -> value.extraHighAmbientEnabled = enabled);
    }

    void setSpatialAudio(boolean enabled) {
        execute(BudsProtocol.spatialAudio(enabled), value -> value.spatialAudioEnabled = enabled);
    }

    void setGamingMode(boolean enabled) {
        execute(BudsProtocol.gamingMode(enabled), value -> value.gamingModeEnabled = enabled);
    }

    void setAutoPauseResume(boolean enabled) {
        execute(BudsProtocol.autoPauseResume(enabled), value -> value.autoPauseResumeEnabled = enabled);
    }

    void setAdaptiveVolume(boolean enabled) {
        execute(BudsProtocol.adaptiveVolume(enabled), value -> value.adaptiveVolumeEnabled = enabled);
    }

    void setSirenDetect(boolean enabled) {
        execute(BudsProtocol.sirenDetect(enabled), value -> value.sirenDetectEnabled = enabled);
    }

    void setFitTest(boolean active) {
        execute(BudsProtocol.fitTest(active), value -> {
            value.fitTestLeft = -1;
            value.fitTestRight = -1;
        }, () -> {
            fitTestActive = active;
            if (demoMode && active) {
                mainHandler.postDelayed(() -> {
                    if (!demoMode || !fitTestActive) return;
                    settings.fitTestLeft = 1;
                    settings.fitTestRight = 1;
                    fitTestActive = false;
                    persistSettings();
                    notifyChanged();
                }, 1500);
            }
        });
    }

    void setFindActive(boolean active) {
        execute(active ? BudsProtocol.findStart() : BudsProtocol.findStop(), value -> {}, () -> {
            findActive = active;
            if (!active) findLeftMuted = findRightMuted = false;
        });
    }

    void setFindMute(boolean left, boolean right) {
        execute(BudsProtocol.muteEarbuds(left, right), value -> {}, () -> {
            findLeftMuted = left;
            findRightMuted = right;
        });
    }

    void clearCommandLog() {
        commandLog.clear();
        notifyChanged();
    }

    String validationReport() {
        StringBuilder report = new StringBuilder();
        report.append("BudsControl Android 0.1.0 验证记录\n");
        report.append("生成时间：").append(DateFormat.getDateTimeInstance().format(new Date())).append('\n');
        report.append("模式：").append(demoMode ? "离线演示" : "Bluetooth Classic 直连").append('\n');
        report.append("连接：").append(getConnectionDetail()).append('\n');
        report.append("扩展状态：").append(hasExtendedState ? "已读取" : "未读取").append("\n\n");
        if (commandLog.isEmpty()) return report.append("尚未发送命令。\n").toString();
        DateFormat time = DateFormat.getTimeInstance();
        for (CommandLogEntry entry : commandLog) {
            report.append('[').append(time.format(entry.date)).append("] ")
                    .append(entry.result).append(" | ")
                    .append(entry.title).append(" | ")
                    .append(entry.packet).append(" | ")
                    .append(entry.detail).append('\n');
        }
        return report.toString();
    }

    private void execute(BudsProtocol.Command command, SettingsMutation mutation) {
        execute(command, mutation, null);
    }

    private void execute(BudsProtocol.Command command, SettingsMutation mutation, Runnable onSuccess) {
        if (command.verification == BudsProtocol.Verification.EXPERIMENTAL && !experimentalCommands) {
            appendLog(command, "失败", "实验命令未授权");
            connectionDetail = "请先在验证中心开启实验命令";
            notifyChanged();
            return;
        }
        if (demoMode) {
            mainHandler.postDelayed(() -> {
                mutation.apply(settings);
                if (onSuccess != null) onSuccess.run();
                persistSettings();
                appendLog(command, "离线模拟", "未发送到耳机");
                notifyChanged();
            }, 150);
            return;
        }
        if (connectionManager == null || connectionState != BudsConnectionManager.State.CONNECTED) {
            appendLog(command, "失败", "耳机未连接");
            connectionDetail = "请先连接已配对的 Buds3 Pro";
            notifyChanged();
            return;
        }

        connectionManager.send(command, (success, acknowledged, detail) -> {
            if (success) {
                mutation.apply(settings);
                if (onSuccess != null) onSuccess.run();
                persistSettings();
            }
            appendLog(command, success ? (acknowledged ? "耳机 ACK" : "已写入") : "失败", detail);
            connectionDetail = detail;
            notifyChanged();
        });
    }

    private void appendLog(BudsProtocol.Command command, String result, String detail) {
        commandLog.add(new CommandLogEntry(new Date(), command.title, BudsProtocol.hex(command.packet()), result, detail));
        while (commandLog.size() > 100) commandLog.remove(0);
    }

    private void persistSettings() {
        if (rememberSettings) settings.save(settingsPreferences);
    }

    private void activateDemo() {
        if (!settingsPreferences.getBoolean("settings_saved", false)) settings = BudsSettings.demo();
        leftBattery = 86;
        rightBattery = 83;
        caseBattery = 74;
        hasExtendedState = true;
        connectionDetail = "离线演示模式";
        notifyChanged();
    }

    private void notifyChanged() {
        for (Listener listener : listeners) listener.onRepositoryChanged();
    }

    @Override
    public void onConnectionState(BudsConnectionManager.State state, String detail) {
        connectionState = state;
        connectionDetail = detail;
        if (state != BudsConnectionManager.State.CONNECTED) {
            hasExtendedState = false;
            fitTestActive = false;
            findActive = false;
            findLeftMuted = false;
            findRightMuted = false;
        }
        notifyChanged();
    }

    @Override
    public void onBattery(int left, int right, int chargingCase) {
        if (left >= 0) leftBattery = left;
        if (right >= 0) rightBattery = right;
        if (chargingCase >= 0) caseBattery = chargingCase;
        notifyChanged();
    }

    @Override
    public void onExtendedStatus(byte[] payload) {
        settings.applyExtendedPayload(payload);
        hasExtendedState = true;
        persistSettings();
        notifyChanged();
    }

    @Override
    public void onFitResult(int left, int right) {
        settings.fitTestLeft = left;
        settings.fitTestRight = right;
        fitTestActive = false;
        persistSettings();
        notifyChanged();
    }

    @Override
    public void onFindStopped() {
        findActive = false;
        findLeftMuted = false;
        findRightMuted = false;
        notifyChanged();
    }
}

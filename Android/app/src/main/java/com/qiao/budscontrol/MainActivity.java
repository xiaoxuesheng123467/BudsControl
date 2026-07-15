package com.qiao.budscontrol;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Space;
import android.widget.Spinner;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

@SuppressLint("MissingPermission")
public final class MainActivity extends Activity implements BudsRepository.Listener {
    private static final int REQUEST_BLUETOOTH_PERMISSION = 41;
    private static final int REQUEST_ENABLE_BLUETOOTH = 42;

    private static final int COLOR_BACKGROUND = Color.rgb(242, 246, 244);
    private static final int COLOR_SURFACE = Color.WHITE;
    private static final int COLOR_TEXT = Color.rgb(23, 32, 29);
    private static final int COLOR_TEXT_SECONDARY = Color.rgb(88, 100, 95);
    private static final int COLOR_GREEN = Color.rgb(22, 138, 67);
    private static final int COLOR_GREEN_DARK = Color.rgb(18, 55, 43);
    private static final int COLOR_ORANGE = Color.rgb(194, 87, 47);
    private static final int COLOR_LINE = Color.rgb(222, 228, 225);

    private enum Page {
        DASHBOARD,
        AMBIENT,
        TOUCH,
        AUDIO,
        ADVANCED,
        VERIFY
    }

    private BudsRepository repository;
    private Page page = Page.DASHBOARD;
    private Page renderedPage;
    private ScrollView activeScrollView;
    private boolean rendering;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(COLOR_BACKGROUND);
        getWindow().setNavigationBarColor(COLOR_BACKGROUND);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
        repository = BudsRepository.get(this);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                    this::handleBack
            );
        }
        render();
        ensureBluetoothReady();
    }

    @Override
    protected void onStart() {
        super.onStart();
        repository.addListener(this);
    }

    @Override
    protected void onStop() {
        repository.removeListener(this);
        super.onStop();
    }

    @Override
    public void onRepositoryChanged() {
        if (rendering || isFinishing()) return;
        runOnUiThread(this::render);
    }

    @SuppressLint("GestureBackNavigation")
    @Override
    public void onBackPressed() {
        handleBack();
    }

    private void handleBack() {
        if (page == Page.DASHBOARD) {
            finish();
            return;
        }
        stopTransientActions();
        page = Page.DASHBOARD;
        render();
    }

    private void render() {
        rendering = true;
        int previousScroll = renderedPage == page && activeScrollView != null ? activeScrollView.getScrollY() : 0;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(COLOR_BACKGROUND);
        root.setFitsSystemWindows(false);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            int top;
            int bottom;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                top = bars.top;
                bottom = bars.bottom;
            } else {
                top = insets.getSystemWindowInsetTop();
                bottom = insets.getSystemWindowInsetBottom();
            }
            view.setPadding(0, top, 0, bottom);
            return insets;
        });

        root.addView(toolbar());
        ScrollView scroll = new ScrollView(this);
        activeScrollView = scroll;
        renderedPage = page;
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        LinearLayout content = vertical();
        content.setPadding(dp(16), dp(12), dp(16), dp(40));
        scroll.addView(content, matchWrap());
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        setContentView(root);
        if (previousScroll > 0) scroll.post(() -> scroll.scrollTo(0, previousScroll));

        switch (page) {
            case DASHBOARD -> renderDashboard(content);
            case AMBIENT -> renderAmbient(content);
            case TOUCH -> renderTouch(content);
            case AUDIO -> renderAudio(content);
            case ADVANCED -> renderAdvanced(content);
            case VERIFY -> renderVerification(content);
        }
        rendering = false;
    }

    private View toolbar() {
        LinearLayout bar = horizontal();
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(10), 0, dp(10), 0);
        bar.setBackgroundColor(COLOR_SURFACE);
        bar.setElevation(dp(2));

        if (page != Page.DASHBOARD) {
            Button back = iconButton("‹", "返回");
            back.setOnClickListener(view -> onBackPressed());
            bar.addView(back, fixed(dp(48), dp(56)));
        } else {
            Space spacer = new Space(this);
            bar.addView(spacer, fixed(dp(48), dp(56)));
        }

        TextView title = text(pageTitle(), 18, COLOR_TEXT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        bar.addView(title, new LinearLayout.LayoutParams(0, dp(56), 1));

        Button refresh = iconButton("↻", "刷新连接");
        refresh.setOnClickListener(view -> {
            if (repository.getConnectionState() == BudsConnectionManager.State.CONNECTED && !repository.isDemoMode()) {
                repository.disconnect();
            }
            ensureBluetoothReady();
        });
        bar.addView(refresh, fixed(dp(48), dp(56)));
        return bar;
    }

    private String pageTitle() {
        return switch (page) {
            case DASHBOARD -> "BudsControl";
            case AMBIENT -> "环境声与自动检测";
            case TOUCH -> "耳机控制";
            case AUDIO -> "音质与连接";
            case ADVANCED -> "高级与测试";
            case VERIFY -> "验证中心";
        };
    }

    private void renderDashboard(LinearLayout content) {
        TextView product = text("Galaxy Buds3 Pro", 30, COLOR_TEXT, Typeface.BOLD);
        product.setPadding(0, dp(8), 0, dp(4));
        content.addView(product);
        TextView tagline = text(getString(R.string.product_tagline), 15, COLOR_TEXT_SECONDARY, Typeface.NORMAL);
        tagline.setPadding(0, 0, 0, dp(16));
        content.addView(tagline);

        LinearLayout connection = section("直连耳机");
        connection.addView(statusRow());
        if (!hasBluetoothPermission()) {
            connection.addView(bodyText(getString(R.string.bluetooth_permission_reason)));
            Button grant = primaryButton("允许附近设备权限");
            grant.setOnClickListener(view -> requestBluetoothPermission());
            connection.addView(grant);
        } else if (repository.getAdapter() == null) {
            connection.addView(bodyText("这台设备不支持 Bluetooth Classic。"));
        } else if (!repository.getAdapter().isEnabled()) {
            Button enable = primaryButton("打开蓝牙");
            enable.setOnClickListener(view -> requestBluetoothEnable());
            connection.addView(enable);
        } else {
            addDeviceSelector(connection);
        }
        content.addView(connection);

        LinearLayout batteries = section("电量");
        LinearLayout metrics = horizontal();
        metrics.addView(metric("左耳", battery(repository.getLeftBattery())), weighted());
        metrics.addView(metric("右耳", battery(repository.getRightBattery())), weighted());
        metrics.addView(metric("充电盒", battery(repository.getCaseBattery())), weighted());
        batteries.addView(metrics);
        content.addView(batteries);

        BudsSettings settings = repository.getSettings();
        LinearLayout noise = section("噪音控制");
        LinearLayout noiseButtons = horizontal();
        String[] modes = {"关闭", "降噪", "环境声", "自适应"};
        for (int index = 0; index < modes.length; index++) {
            final int mode = index;
            Button button = choiceButton(modes[index], settings.noiseMode == index);
            button.setEnabled(repository.canControl());
            button.setOnClickListener(view -> repository.setNoiseMode(mode));
            noiseButtons.addView(button, weightedWithMargin(3));
        }
        noise.addView(noiseButtons);
        noise.addView(verificationText("降噪 / 环境声 / 关闭已真机确认；自适应待验证"));
        content.addView(noise);

        LinearLayout equalizer = section("均衡器");
        equalizer.addView(spinnerRow(
                "预设",
                new String[]{"正常", "低音增强", "柔和", "动态", "清晰", "高音增强"},
                settings.equalizer,
                repository.canControl(),
                repository::setEqualizer
        ));
        equalizer.addView(verificationText("六组预设已通过 SM-R630 真机确认"));
        content.addView(equalizer);

        LinearLayout pages = section("更多设置");
        pages.addView(navigationRow("环境声与自动检测", "环境声级别、左右耳定制、语音检测", Page.AMBIENT));
        pages.addView(divider());
        pages.addView(navigationRow("耳机控制", "捏合、长捏、噪音循环与锁定", Page.TOUCH));
        pages.addView(divider());
        pages.addView(navigationRow("音质与连接", "左右平衡、无缝连接与通话", Page.AUDIO));
        pages.addView(divider());
        pages.addView(navigationRow("高级与测试", "贴合度、查找耳机与实验功能", Page.ADVANCED));
        pages.addView(divider());
        pages.addView(navigationRow("验证中心", "离线演示、配置记忆与命令记录", Page.VERIFY));
        content.addView(pages);
    }

    private void renderAmbient(LinearLayout content) {
        content.addView(statusSection());
        BudsSettings value = repository.getSettings();
        boolean enabled = repository.canControl();

        LinearLayout ambient = section("环境声");
        ambient.addView(spinnerRow("环境声级别", new String[]{"低", "中", "高"}, value.ambientVolume, enabled, repository::setAmbientVolume));
        ambient.addView(switchRow("超高环境声", value.extraHighAmbientEnabled, enabled, repository::setExtraHighAmbient));
        ambient.addView(switchRow("强降噪", value.noiseReductionHigh, enabled, repository::setNoiseReductionHigh));
        ambient.addView(verificationText("协议已映射，等待 Buds3 Pro 真机逐项验证"));
        content.addView(ambient);

        LinearLayout custom = section("左右耳定制");
        custom.addView(switchRow("自定义环境声", value.ambientCustomizationEnabled, enabled, checked ->
                repository.updateAmbientCustomization(checked, value.ambientVolumeLeft, value.ambientVolumeRight, value.ambientTone)));
        custom.addView(seekRow("左耳强度", value.ambientVolumeLeft, 2, customVolume(value.ambientVolumeLeft), enabled && value.ambientCustomizationEnabled, progress ->
                repository.updateAmbientCustomization(true, progress, value.ambientVolumeRight, value.ambientTone)));
        custom.addView(seekRow("右耳强度", value.ambientVolumeRight, 2, customVolume(value.ambientVolumeRight), enabled && value.ambientCustomizationEnabled, progress ->
                repository.updateAmbientCustomization(true, value.ambientVolumeLeft, progress, value.ambientTone)));
        custom.addView(spinnerRow(
                "音色",
                new String[]{"柔和 +2", "柔和 +1", "均衡", "清晰 +1", "清晰 +2"},
                value.ambientTone,
                enabled && value.ambientCustomizationEnabled,
                tone -> repository.updateAmbientCustomization(true, value.ambientVolumeLeft, value.ambientVolumeRight, tone)
        ));
        content.addView(custom);

        LinearLayout automatic = section("自动环境声");
        automatic.addView(switchRow("检测我的声音", value.voiceDetectEnabled, enabled, repository::setVoiceDetect));
        automatic.addView(spinnerRow("恢复时间", new String[]{"5 秒", "10 秒", "15 秒"}, value.voiceDetectTimeout, enabled && value.voiceDetectEnabled, repository::setVoiceDetectTimeout));
        automatic.addView(switchRow("允许单耳使用噪音控制", value.oneEarNoiseControl, enabled, repository::setOneEarNoiseControl));
        content.addView(automatic);
    }

    private void renderTouch(LinearLayout content) {
        content.addView(statusSection());
        BudsSettings value = repository.getSettings();
        boolean enabled = repository.canControl();
        boolean gestureEnabled = enabled && !value.touchLocked;

        LinearLayout lock = section("控制锁");
        lock.addView(switchRow("锁定耳机控制", value.touchLocked, enabled, repository::setTouchLocked));
        lock.addView(verificationText("Buds3 Pro 七字节高级触控锁格式，待真机验证"));
        content.addView(lock);

        LinearLayout gestures = section("捏合手势");
        gestures.addView(switchRow("捏一下：播放或暂停", value.singleTapEnabled, gestureEnabled, checked -> repository.setGesture("single", checked)));
        gestures.addView(switchRow("捏两下：下一首", value.doubleTapEnabled, gestureEnabled, checked -> repository.setGesture("double", checked)));
        gestures.addView(switchRow("捏三下：上一首", value.tripleTapEnabled, gestureEnabled, checked -> repository.setGesture("triple", checked)));
        gestures.addView(switchRow("长捏", value.touchAndHoldEnabled, gestureEnabled, checked -> repository.setGesture("hold", checked)));
        gestures.addView(switchRow("捏两下接听或结束通话", value.doubleTapCallEnabled, gestureEnabled, checked -> repository.setGesture("call_double", checked)));
        gestures.addView(switchRow("长捏拒接来电", value.touchAndHoldCallEnabled, gestureEnabled, checked -> repository.setGesture("call_hold", checked)));
        content.addView(gestures);

        LinearLayout actions = section("长捏动作");
        String[] actionLabels = {"语音助手", "切换噪声模式", "音量", "Spotify"};
        actions.addView(spinnerRow("左耳", actionLabels, value.leftTouchAction - 1, gestureEnabled, selected -> repository.setTouchActions(selected + 1, value.rightTouchAction)));
        actions.addView(spinnerRow("右耳", actionLabels, value.rightTouchAction - 1, gestureEnabled, selected -> repository.setTouchActions(value.leftTouchAction, selected + 1)));
        String[] cycleLabels = {"环境声 / 关闭", "降噪 / 环境声", "降噪 / 关闭"};
        int[] cycleValues = {4, 8, 12};
        if (value.leftTouchAction == 2) {
            actions.addView(spinnerRow("左耳噪音循环", cycleLabels, indexOf(cycleValues, value.leftNoiseCycle), gestureEnabled, selected -> repository.setNoiseCycles(cycleValues[selected], value.rightNoiseCycle)));
        }
        if (value.rightTouchAction == 2) {
            actions.addView(spinnerRow("右耳噪音循环", cycleLabels, indexOf(cycleValues, value.rightNoiseCycle), gestureEnabled, selected -> repository.setNoiseCycles(value.leftNoiseCycle, cycleValues[selected])));
        }
        actions.addView(switchRow("双击耳边调节音量", value.edgeDoubleTapVolume, gestureEnabled, repository::setEdgeDoubleTap));
        content.addView(actions);
    }

    private void renderAudio(LinearLayout content) {
        content.addView(statusSection());
        BudsSettings value = repository.getSettings();
        boolean enabled = repository.canControl();

        LinearLayout sound = section("音质");
        sound.addView(seekRow("左右声音平衡", value.stereoBalance, 32, balance(value.stereoBalance), enabled, repository::setStereoBalance));
        sound.addView(switchRow("360 音频", value.spatialAudioEnabled, enabled, repository::setSpatialAudio));
        sound.addView(switchRow("清晰通话", value.extraClearCallEnabled, enabled, repository::setExtraClearCall));
        sound.addView(verificationText("360 音频只切换耳机端状态；内容和系统仍要提供对应音源"));
        content.addView(sound);

        LinearLayout connection = section("连接与通话");
        connection.addView(switchRow("无缝耳机连接", value.seamlessConnection, enabled, repository::setSeamlessConnection));
        connection.addView(switchRow("摘下双耳时把通话切回手机", value.callPathControlEnabled, enabled, repository::setCallPathControl));
        connection.addView(switchRow("通话期间使用环境声", value.sidetoneEnabled, enabled, repository::setSidetone));
        connection.addView(switchRow("游戏模式", value.gamingModeEnabled, enabled, repository::setGamingMode));
        connection.addView(switchRow("摘下耳机时自动暂停", value.autoPauseResumeEnabled, enabled, repository::setAutoPauseResume));
        content.addView(connection);

        LinearLayout readOnly = section("耳机回报状态");
        readOnly.addView(valueRow("Blade Light", value.lightingControl < 0 ? "未读取" : String.valueOf(value.lightingControl)));
        readOnly.addView(valueRow("免唤醒语音", triState(value.hotCommandEnabled)));
        readOnly.addView(valueRow("Adapt Sound", triState(value.adaptSoundEnabled)));
        readOnly.addView(verificationText("只读展示；复合配置没有可靠写入格式"));
        content.addView(readOnly);
    }

    private void renderAdvanced(LinearLayout content) {
        content.addView(statusSection());
        BudsSettings value = repository.getSettings();
        boolean enabled = repository.canControl();

        LinearLayout fit = section("耳塞贴合度测试");
        fit.addView(valueRow("左耳", fitResult(value.fitTestLeft, repository.isFitTestActive())));
        fit.addView(valueRow("右耳", fitResult(value.fitTestRight, repository.isFitTestActive())));
        Button fitButton = primaryButton(repository.isFitTestActive() ? "停止测试" : "开始测试");
        fitButton.setEnabled(enabled);
        fitButton.setOnClickListener(view -> repository.setFitTest(!repository.isFitTestActive()));
        fit.addView(fitButton);
        fit.addView(verificationText("双耳佩戴后开始；收到结果会自动停止"));
        content.addView(fit);

        LinearLayout find = section("查找我的耳机");
        find.addView(valueRow("状态", repository.isFindActive() ? "正在响铃" : "已停止"));
        find.addView(switchRow("左耳静音", repository.isFindLeftMuted(), enabled && repository.isFindActive(), checked -> repository.setFindMute(checked, repository.isFindRightMuted())));
        find.addView(switchRow("右耳静音", repository.isFindRightMuted(), enabled && repository.isFindActive(), checked -> repository.setFindMute(repository.isFindLeftMuted(), checked)));
        Button findButton = primaryButton(repository.isFindActive() ? "停止响铃" : "开始查找");
        findButton.setEnabled(enabled);
        findButton.setOnClickListener(view -> {
            if (repository.isFindActive()) repository.setFindActive(false);
            else confirmFindStart();
        });
        find.addView(findButton);
        find.addView(bodyText("响铃可能很大声。开始前先确认耳机没有戴在耳朵里。"));
        content.addView(find);

        LinearLayout experimental = section("实验功能");
        experimental.addView(switchRow("自适应音量", value.adaptiveVolumeEnabled, enabled && repository.isExperimentalCommandsEnabled(), repository::setAdaptiveVolume));
        experimental.addView(switchRow("警笛检测", value.sirenDetectEnabled, enabled && repository.isExperimentalCommandsEnabled(), repository::setSirenDetect));
        experimental.addView(verificationText("默认禁用；当前只交叉确认了消息 ID"));
        content.addView(experimental);

        LinearLayout unavailable = section("暂未开放");
        unavailable.addView(valueRow("Blade Light 写入", "等待参数语义"));
        unavailable.addView(valueRow("9 段自定义 EQ", "没有安全写入格式"));
        unavailable.addView(valueRow("固件更新", "不执行未验证刷写"));
        content.addView(unavailable);
    }

    private void renderVerification(LinearLayout content) {
        content.addView(statusSection());
        LinearLayout switches = section("验证开关");
        switches.addView(switchRow("离线演示模式", repository.isDemoMode(), true, repository::setDemoMode));
        switches.addView(switchRow("允许实验命令", repository.isExperimentalCommandsEnabled(), true, repository::setExperimentalCommands));
        switches.addView(switchRow("记住上次设置", repository.isRememberSettingsEnabled(), true, repository::setRememberSettings));
        switches.addView(bodyText("成功修改后保存；下次启动先显示记忆值，再由耳机扩展状态逐项校正。"));
        content.addView(switches);

        LinearLayout state = section("当前状态");
        state.addView(valueRow("版本", appVersion()));
        state.addView(valueRow("控制链路", repository.isDemoMode() ? "离线演示" : "Bluetooth Classic 直连"));
        state.addView(valueRow("扩展状态", repository.hasExtendedState() ? "已读取" : "未读取"));
        state.addView(valueRow("命令记录", repository.getCommandLog().size() + " 条"));
        content.addView(state);

        LinearLayout checklist = section("真机验证顺序");
        checklist.addView(bodyText("1. 自适应、环境声级别、语音检测与单耳控制"));
        checklist.addView(bodyText("2. 触控锁、左右长捏、噪音循环与双击耳边"));
        checklist.addView(bodyText("3. 左右平衡、连接、通话、佩戴与实验功能"));
        content.addView(checklist);

        LinearLayout log = section("命令记录");
        List<BudsRepository.CommandLogEntry> entries = repository.getCommandLog();
        if (entries.isEmpty()) {
            log.addView(bodyText("尚未发送命令。"));
        } else {
            int start = Math.max(0, entries.size() - 20);
            for (int index = entries.size() - 1; index >= start; index--) {
                BudsRepository.CommandLogEntry entry = entries.get(index);
                log.addView(logRow(entry));
                if (index > start) log.addView(divider());
            }
        }
        Button share = secondaryButton("导出验证记录");
        share.setOnClickListener(view -> shareReport());
        log.addView(share);
        Button clear = secondaryButton("清空记录");
        clear.setEnabled(!entries.isEmpty());
        clear.setOnClickListener(view -> repository.clearCommandLog());
        log.addView(clear);
        content.addView(log);
    }

    private View statusSection() {
        LinearLayout section = section("设备状态");
        section.addView(statusRow());
        return section;
    }

    private View statusRow() {
        LinearLayout row = horizontal();
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView dot = text("●", 14, statusColor(), Typeface.NORMAL);
        row.addView(dot, fixed(dp(24), dp(48)));
        LinearLayout labels = vertical();
        labels.addView(text(repository.getConnectionDetail(), 15, COLOR_TEXT, Typeface.BOLD));
        String secondary = repository.hasExtendedState()
                ? "已读取耳机扩展状态"
                : repository.isRememberSettingsEnabled() ? "显示上次保存的设置" : "等待耳机状态";
        labels.addView(text(secondary, 12, COLOR_TEXT_SECONDARY, Typeface.NORMAL));
        row.addView(labels, weighted());
        return row;
    }

    private int statusColor() {
        if (repository.isDemoMode()) return Color.rgb(117, 66, 166);
        return switch (repository.getConnectionState()) {
            case CONNECTED -> COLOR_GREEN;
            case CONNECTING -> COLOR_ORANGE;
            case DISCONNECTED -> COLOR_TEXT_SECONDARY;
        };
    }

    private void addDeviceSelector(LinearLayout parent) {
        List<BudsRepository.DeviceOption> options = repository.pairedBuds();
        if (options.isEmpty()) {
            parent.addView(bodyText("没有找到已配对的 Buds3 Pro。先在系统蓝牙设置完成配对，再返回刷新。"));
            Button settings = secondaryButton("打开蓝牙设置");
            settings.setOnClickListener(view -> startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS)));
            parent.addView(settings);
            return;
        }

        Spinner spinner = new Spinner(this);
        ArrayAdapter<BudsRepository.DeviceOption> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, options);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinner.setAdapter(adapter);
        spinner.setMinimumHeight(dp(50));
        parent.addView(spinner, matchWrap());

        Button connect = primaryButton(repository.getConnectionState() == BudsConnectionManager.State.CONNECTED ? "重新连接" : "直连耳机");
        connect.setEnabled(repository.getConnectionState() != BudsConnectionManager.State.CONNECTING);
        connect.setOnClickListener(view -> repository.connect(options.get(spinner.getSelectedItemPosition())));
        parent.addView(connect);

        if (repository.getConnectionState() == BudsConnectionManager.State.CONNECTED && !repository.isDemoMode()) {
            Button disconnect = secondaryButton("断开控制通道");
            disconnect.setOnClickListener(view -> repository.disconnect());
            parent.addView(disconnect);
        }
    }

    private View navigationRow(String title, String subtitle, Page target) {
        LinearLayout row = horizontal();
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(6), 0, dp(6));
        LinearLayout labels = vertical();
        labels.addView(text(title, 16, COLOR_TEXT, Typeface.BOLD));
        labels.addView(text(subtitle, 12, COLOR_TEXT_SECONDARY, Typeface.NORMAL));
        row.addView(labels, weighted());
        TextView arrow = text("›", 28, COLOR_TEXT_SECONDARY, Typeface.NORMAL);
        arrow.setGravity(Gravity.CENTER);
        row.addView(arrow, fixed(dp(36), dp(52)));
        row.setBackground(selectableBackground());
        row.setClickable(true);
        row.setFocusable(true);
        row.setContentDescription(title + "，" + subtitle);
        row.setOnClickListener(view -> {
            page = target;
            render();
        });
        return row;
    }

    private View switchRow(String title, boolean checked, boolean enabled, CheckedAction action) {
        Switch toggle = new Switch(this);
        toggle.setText(title);
        toggle.setTextSize(15);
        toggle.setTextColor(COLOR_TEXT);
        toggle.setGravity(Gravity.CENTER_VERTICAL);
        toggle.setPadding(0, dp(4), 0, dp(4));
        toggle.setChecked(checked);
        toggle.setEnabled(enabled);
        toggle.setOnCheckedChangeListener((button, value) -> action.run(value));
        return toggle;
    }

    private View spinnerRow(String title, String[] labels, int selection, boolean enabled, IntAction action) {
        LinearLayout row = horizontal();
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView label = text(title, 15, COLOR_TEXT, Typeface.NORMAL);
        row.addView(label, weighted());
        Spinner spinner = new Spinner(this);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, labels);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinner.setAdapter(adapter);
        spinner.setSelection(Math.max(0, Math.min(selection, labels.length - 1)), false);
        spinner.setEnabled(enabled);
        spinner.setOnItemSelectedListener(new SimpleItemSelectedListener(position -> {
            if (!rendering) action.run(position);
        }));
        row.addView(spinner, fixed(dp(170), dp(52)));
        return row;
    }

    private View seekRow(String title, int value, int maximum, String display, boolean enabled, IntAction action) {
        LinearLayout block = vertical();
        block.setPadding(0, dp(5), 0, dp(5));
        LinearLayout heading = horizontal();
        heading.addView(text(title, 15, COLOR_TEXT, Typeface.NORMAL), weighted());
        TextView valueLabel = text(display, 13, COLOR_TEXT_SECONDARY, Typeface.NORMAL);
        heading.addView(valueLabel);
        block.addView(heading);
        SeekBar seek = new SeekBar(this);
        seek.setMax(maximum);
        seek.setProgress(value);
        seek.setEnabled(enabled);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                if (fromUser) valueLabel.setText(progressText(title, progress));
            }
            @Override public void onStartTrackingTouch(SeekBar bar) {}
            @Override public void onStopTrackingTouch(SeekBar bar) { action.run(bar.getProgress()); }
        });
        block.addView(seek, matchWrap());
        return block;
    }

    private String progressText(String title, int progress) {
        if (title.contains("平衡")) return balance(progress);
        if (title.contains("强度")) return customVolume(progress);
        return String.valueOf(progress);
    }

    private View valueRow(String title, String value) {
        LinearLayout row = horizontal();
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(6), 0, dp(6));
        row.addView(text(title, 15, COLOR_TEXT, Typeface.NORMAL), weighted());
        TextView detail = text(value, 14, COLOR_TEXT_SECONDARY, Typeface.NORMAL);
        detail.setGravity(Gravity.END);
        row.addView(detail);
        return row;
    }

    private View logRow(BudsRepository.CommandLogEntry entry) {
        LinearLayout row = vertical();
        row.setPadding(0, dp(8), 0, dp(8));
        LinearLayout top = horizontal();
        top.addView(text(entry.title, 14, COLOR_TEXT, Typeface.BOLD), weighted());
        int resultColor = entry.result.equals("失败") ? Color.rgb(180, 45, 45) : COLOR_TEXT_SECONDARY;
        top.addView(text(entry.result, 12, resultColor, Typeface.BOLD));
        row.addView(top);
        TextView packet = text(entry.packet, 11, COLOR_TEXT_SECONDARY, Typeface.MONOSPACE.getStyle());
        packet.setTypeface(Typeface.MONOSPACE);
        packet.setTextIsSelectable(true);
        row.addView(packet);
        return row;
    }

    private LinearLayout section(String title) {
        LinearLayout outer = vertical();
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, 0, 0, dp(14));
        outer.setLayoutParams(params);
        outer.setPadding(dp(16), dp(14), dp(16), dp(14));
        outer.setBackground(rounded(COLOR_SURFACE, 8));
        TextView heading = text(title, 13, COLOR_TEXT_SECONDARY, Typeface.BOLD);
        heading.setAllCaps(true);
        heading.setPadding(0, 0, 0, dp(8));
        outer.addView(heading);
        return outer;
    }

    private View metric(String title, String value) {
        LinearLayout metric = vertical();
        metric.setGravity(Gravity.CENTER);
        metric.addView(text(value, 20, COLOR_TEXT, Typeface.BOLD));
        metric.addView(text(title, 12, COLOR_TEXT_SECONDARY, Typeface.NORMAL));
        return metric;
    }

    private TextView bodyText(String value) {
        TextView text = text(value, 13, COLOR_TEXT_SECONDARY, Typeface.NORMAL);
        text.setLineSpacing(0, 1.35f);
        text.setPadding(0, dp(6), 0, dp(6));
        return text;
    }

    private TextView verificationText(String value) {
        TextView text = bodyText(value);
        text.setTextColor(COLOR_ORANGE);
        return text;
    }

    private Button primaryButton(String title) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextSize(14);
        button.setTextColor(Color.WHITE);
        button.setAllCaps(false);
        button.setBackground(rounded(COLOR_GREEN, 6));
        LinearLayout.LayoutParams params = matchWrap();
        params.height = dp(48);
        params.setMargins(0, dp(8), 0, 0);
        button.setLayoutParams(params);
        return button;
    }

    private Button secondaryButton(String title) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextSize(14);
        button.setTextColor(COLOR_TEXT);
        button.setAllCaps(false);
        button.setBackground(rounded(Color.rgb(236, 241, 239), 6));
        LinearLayout.LayoutParams params = matchWrap();
        params.height = dp(46);
        params.setMargins(0, dp(8), 0, 0);
        button.setLayoutParams(params);
        return button;
    }

    private Button choiceButton(String title, boolean selected) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextSize(12);
        button.setTextColor(selected ? Color.WHITE : COLOR_TEXT);
        button.setAllCaps(false);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setPadding(dp(3), 0, dp(3), 0);
        button.setBackground(rounded(selected ? COLOR_GREEN : Color.rgb(238, 242, 240), 6));
        return button;
    }

    private Button iconButton(String symbol, String description) {
        Button button = new Button(this);
        button.setText(symbol);
        button.setTextSize(28);
        button.setTextColor(COLOR_TEXT);
        button.setContentDescription(description);
        button.setAllCaps(false);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setPadding(0, 0, 0, 0);
        button.setBackgroundColor(Color.TRANSPARENT);
        return button;
    }

    private View divider() {
        View line = new View(this);
        line.setBackgroundColor(COLOR_LINE);
        line.setLayoutParams(fixed(ViewGroup.LayoutParams.MATCH_PARENT, 1));
        return line;
    }

    private TextView text(String value, float size, int color, int style) {
        TextView text = new TextView(this);
        text.setText(value);
        text.setTextSize(size);
        text.setTextColor(color);
        text.setTypeface(Typeface.create(Typeface.DEFAULT, style));
        text.setLetterSpacing(0);
        return text;
    }

    private LinearLayout vertical() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private LinearLayout horizontal() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        return layout;
    }

    private GradientDrawable rounded(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private Drawable selectableBackground() {
        android.util.TypedValue value = new android.util.TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackground, value, true);
        return getDrawable(value.resourceId);
    }

    private void confirmFindStart() {
        new AlertDialog.Builder(this)
                .setTitle("开始让耳机响铃？")
                .setMessage("先确认耳机没有戴在耳朵里。响铃声音可能很大。")
                .setNegativeButton("取消", null)
                .setPositiveButton("开始", (dialog, which) -> repository.setFindActive(true))
                .show();
    }

    private void stopTransientActions() {
        if (repository.isFitTestActive()) repository.setFitTest(false);
        if (repository.isFindActive()) repository.setFindActive(false);
    }

    private void shareReport() {
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("text/plain");
        intent.putExtra(Intent.EXTRA_SUBJECT, "BudsControl Android 验证记录");
        intent.putExtra(Intent.EXTRA_TEXT, repository.validationReport());
        startActivity(Intent.createChooser(intent, "导出验证记录"));
    }

    private void ensureBluetoothReady() {
        if (!hasBluetoothPermission()) {
            requestBluetoothPermission();
            return;
        }
        BluetoothAdapter adapter = repository.getAdapter();
        if (adapter != null && !adapter.isEnabled()) {
            requestBluetoothEnable();
            return;
        }
        repository.autoConnectLast();
        render();
    }

    private boolean hasBluetoothPermission() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT}, REQUEST_BLUETOOTH_PERMISSION);
        }
    }

    private void requestBluetoothEnable() {
        try {
            startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_BLUETOOTH);
        } catch (SecurityException error) {
            requestBluetoothPermission();
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQUEST_BLUETOOTH_PERMISSION) return;
        boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        if (granted) ensureBluetoothReady();
        else {
            Toast.makeText(this, "没有附近设备权限就无法连接耳机", Toast.LENGTH_LONG).show();
            render();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_ENABLE_BLUETOOTH) ensureBluetoothReady();
    }

    private String appVersion() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (PackageManager.NameNotFoundException error) {
            return "0.1.0";
        }
    }

    private String battery(int value) {
        return value < 0 ? "--" : value + "%";
    }

    private String customVolume(int value) {
        return new String[]{"-2", "-1", "标准"}[Math.max(0, Math.min(2, value))];
    }

    private String balance(int value) {
        if (value == 16) return "居中";
        return value < 16 ? "左 +" + (16 - value) : "右 +" + (value - 16);
    }

    private String triState(int value) {
        if (value < 0) return "未读取";
        return value == 1 ? "已开启" : "关闭";
    }

    private String fitResult(int value, boolean active) {
        if (active) return "测试中";
        return switch (value) {
            case 0 -> "需要调整";
            case 1 -> "贴合良好";
            case 2 -> "测试失败";
            default -> "尚未测试";
        };
    }

    private int indexOf(int[] values, int target) {
        for (int index = 0; index < values.length; index++) if (values[index] == target) return index;
        return 0;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams fixed(int width, int height) {
        return new LinearLayout.LayoutParams(width, height);
    }

    private LinearLayout.LayoutParams weighted() {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
    }

    private LinearLayout.LayoutParams weightedWithMargin(int marginDp) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(48), 1);
        params.setMargins(dp(marginDp), 0, dp(marginDp), 0);
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private interface CheckedAction { void run(boolean checked); }
    private interface IntAction { void run(int value); }

    private static final class SimpleItemSelectedListener implements android.widget.AdapterView.OnItemSelectedListener {
        private final IntAction action;
        private boolean initial = true;

        SimpleItemSelectedListener(IntAction action) {
            this.action = action;
        }

        @Override
        public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) {
            if (initial) {
                initial = false;
                return;
            }
            action.run(position);
        }

        @Override
        public void onNothingSelected(android.widget.AdapterView<?> parent) {}
    }
}

import SwiftUI

private func asyncBinding<Value>(
    get: @escaping () -> Value,
    set: @escaping (Value) async -> Void
) -> Binding<Value> {
    Binding(
        get: get,
        set: { value in Task { await set(value) } }
    )
}

private struct ControlAvailabilitySection: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bridge.phase.isReady ? bridge.phase.title : "耳机控制通道未连接")
                        .font(.subheadline.weight(.semibold))
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: bridge.isDemoMode ? "testtube.2" : bridge.phase.isReady ? "checkmark.seal" : "lock.shield")
                    .foregroundStyle(bridge.isDemoMode ? .purple : bridge.phase.isReady ? .green : .secondary)
            }
        }
    }

    private var statusDetail: String {
        if bridge.isDemoMode { return "操作只写入离线模拟状态，不会发送到耳机" }
        if bridge.hasExtendedState { return "已读取耳机扩展状态；成功修改会自动记忆" }
        if bridge.phase.isReady { return "已连接，正在等待耳机扩展状态" }
        return bridge.rememberSettingsEnabled ? "暂时显示上次保存的设置" : bridge.phase.title
    }
}

private struct VerificationLabel: View {
    let verification: FeatureVerification

    var body: some View {
        Label(verification.title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch verification {
        case .hardwareVerified: "checkmark.seal.fill"
        case .protocolMapped: "checkmark.circle.badge.questionmark"
        case .experimental: "testtube.2"
        case .readOnly: "eye"
        }
    }

    private var color: Color {
        switch verification {
        case .hardwareVerified: .green
        case .protocolMapped: .orange
        case .experimental: .purple
        case .readOnly: .secondary
        }
    }
}

private struct IntegerSettingSlider: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let valueText: (Int) -> String
    let onCommit: (Int) async -> Void

    @State private var draft = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText(Int(draft.rounded())))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $draft,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1,
                onEditingChanged: { editing in
                    guard !editing else { return }
                    let committed = Int(draft.rounded())
                    Task { await onCommit(committed) }
                }
            )
            .accessibilityValue(valueText(Int(draft.rounded())))
        }
        .padding(.vertical, 3)
        .onAppear { draft = Double(value) }
        .onChange(of: value) { _, newValue in draft = Double(newValue) }
    }
}

struct AutomaticAmbientView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section {
                Toggle(
                    "检测我的声音",
                    isOn: asyncBinding(
                        get: { bridge.settings.voiceDetectEnabled },
                        set: bridge.setVoiceDetect
                    )
                )
                Picker(
                    "恢复时间",
                    selection: asyncBinding(
                        get: { bridge.settings.voiceDetectTimeout },
                        set: bridge.setVoiceDetectTimeout
                    )
                ) {
                    ForEach(VoiceDetectTimeout.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!bridge.settings.voiceDetectEnabled)
                Toggle(
                    "允许单耳使用噪音控制",
                    isOn: asyncBinding(
                        get: { bridge.settings.noiseControlWithOneEarbud },
                        set: bridge.setNoiseControlWithOneEarbud
                    )
                )
            } header: {
                Text("自动环境声")
            } footer: {
                VerificationLabel(verification: .protocolMapped)
            }
            .disabled(!bridge.canControl)

            Section {
                Toggle(
                    "警笛检测",
                    isOn: asyncBinding(
                        get: { bridge.settings.sirenDetectEnabled },
                        set: bridge.setSirenDetect
                    )
                )
            } header: {
                Text("实验功能")
            } footer: {
                Text("只在验证中心开启实验命令后可发送；当前只确认了消息 ID，尚未确认 Buds3 Pro 的 ACK 行为。")
            }
            .disabled(!bridge.canControl || !bridge.experimentalCommandsEnabled)
        }
        .navigationTitle("自动环境声")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AmbientSoundCustomizationView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section {
                Picker(
                    "环境声级别",
                    selection: asyncBinding(
                        get: { bridge.settings.ambientVolume },
                        set: bridge.setAmbientVolume
                    )
                ) {
                    ForEach(AmbientSoundLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(
                    "超高环境声",
                    isOn: asyncBinding(
                        get: { bridge.settings.extraHighAmbientEnabled },
                        set: bridge.setExtraHighAmbient
                    )
                )
            } header: {
                Text("环境声")
            } footer: {
                VerificationLabel(verification: .protocolMapped)
            }
            .disabled(!bridge.canControl)

            Section {
                Toggle(
                    "自定义环境声",
                    isOn: asyncBinding(
                        get: { bridge.settings.ambientCustomizationEnabled },
                        set: { enabled in
                            await bridge.updateAmbientCustomization { $0.ambientCustomizationEnabled = enabled }
                        }
                    )
                )
                .disabled(!bridge.canControl)
                IntegerSettingSlider(
                    title: "左耳强度",
                    value: bridge.settings.ambientVolumeLeft,
                    range: 0...2,
                    valueText: customVolumeText,
                    onCommit: { value in
                        await bridge.updateAmbientCustomization { $0.ambientVolumeLeft = value }
                    }
                )
                .disabled(!bridge.canControl || !bridge.settings.ambientCustomizationEnabled)
                IntegerSettingSlider(
                    title: "右耳强度",
                    value: bridge.settings.ambientVolumeRight,
                    range: 0...2,
                    valueText: customVolumeText,
                    onCommit: { value in
                        await bridge.updateAmbientCustomization { $0.ambientVolumeRight = value }
                    }
                )
                .disabled(!bridge.canControl || !bridge.settings.ambientCustomizationEnabled)
                Picker(
                    "音色",
                    selection: asyncBinding(
                        get: { bridge.settings.ambientTone },
                        set: { tone in
                            await bridge.updateAmbientCustomization { $0.ambientTone = tone }
                        }
                    )
                ) {
                    ForEach(AmbientSoundTone.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!bridge.canControl || !bridge.settings.ambientCustomizationEnabled)
            } header: {
                Text("左右耳定制")
            } footer: {
                Text("四个参数会作为同一条三星命令一起发送。")
            }
        }
        .navigationTitle("环境声设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func customVolumeText(_ value: Int) -> String {
        ["-2", "-1", "标准"][value]
    }
}

struct SoundQualityView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section {
                Picker(
                    "均衡器预设",
                    selection: asyncBinding(
                        get: { bridge.settings.equalizer ?? .normal },
                        set: bridge.setEqualizer
                    )
                ) {
                    ForEach(EqualizerPreset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            } header: {
                Text("均衡器")
            } footer: {
                VerificationLabel(verification: .hardwareVerified)
            }
            .disabled(!bridge.canControl)

            Section {
                IntegerSettingSlider(
                    title: "左右声音平衡",
                    value: bridge.settings.stereoBalance,
                    range: 0...32,
                    valueText: balanceText,
                    onCommit: bridge.setStereoBalance
                )
            } footer: {
                VerificationLabel(verification: .protocolMapped)
            }
            .disabled(!bridge.canControl)

            Section {
                NavigationLink("环境声级别与左右耳定制") {
                    AmbientSoundCustomizationView()
                }
                Toggle(
                    "360 音频",
                    isOn: asyncBinding(
                        get: { bridge.settings.spatialAudioEnabled },
                        set: bridge.setSpatialAudio
                    )
                )
                Toggle(
                    "清晰通话",
                    isOn: asyncBinding(
                        get: { bridge.settings.extraClearCallEnabled },
                        set: bridge.setExtraClearCall
                    )
                )
                NavigationLink("耳塞贴合度测试") {
                    FitTestView()
                }
            } header: {
                Text("音效")
            } footer: {
                Text("360 音频的耳机端开关已映射；iOS 音源是否提供对应空间音频仍由系统和内容决定。")
            }
            .disabled(!bridge.canControl)

            Section {
                LabeledContent("9 段自定义 EQ", value: "未开放")
                LabeledContent("UHQ 24-bit / 96 kHz", value: "需三星音频链路")
            } footer: {
                Text("当前没有可验证的 Buds3 Pro 自定义 EQ 写入格式，因此不发送猜测数据。")
            }
            .foregroundStyle(.secondary)
        }
        .navigationTitle("音质和音效")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func balanceText(_ value: Int) -> String {
        if value == 16 { return "居中" }
        return value < 16 ? "左 +\(16 - value)" : "右 +\(value - 16)"
    }
}

struct EarbudControlsView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section {
                Toggle(
                    "锁定耳机控制",
                    isOn: touchBinding(get: { bridge.settings.touchLocked }) { $0.touchLocked = $1 }
                )
            } footer: {
                VerificationLabel(verification: .protocolMapped)
            }
            .disabled(!bridge.canControl)

            Section("捏合手势") {
                Toggle("捏一下：播放或暂停", isOn: touchBinding(get: { bridge.settings.singleTapEnabled }) { $0.singleTapEnabled = $1 })
                Toggle("捏两下：下一首", isOn: touchBinding(get: { bridge.settings.doubleTapEnabled }) { $0.doubleTapEnabled = $1 })
                Toggle("捏三下：上一首", isOn: touchBinding(get: { bridge.settings.tripleTapEnabled }) { $0.tripleTapEnabled = $1 })
                Toggle("长捏", isOn: touchBinding(get: { bridge.settings.touchAndHoldEnabled }) { $0.touchAndHoldEnabled = $1 })
            }
            .disabled(!bridge.canControl || bridge.settings.touchLocked)

            Section("通话手势") {
                Toggle("捏两下接听或结束通话", isOn: touchBinding(get: { bridge.settings.doubleTapCallEnabled }) { $0.doubleTapCallEnabled = $1 })
                Toggle("长捏拒接来电", isOn: touchBinding(get: { bridge.settings.touchAndHoldCallEnabled }) { $0.touchAndHoldCallEnabled = $1 })
            }
            .disabled(!bridge.canControl || bridge.settings.touchLocked)

            Section("长捏动作") {
                Picker(
                    "左耳",
                    selection: asyncBinding(
                        get: { bridge.settings.leftTouchAction },
                        set: { action in await bridge.updateTouchActions { $0.leftTouchAction = action } }
                    )
                ) {
                    ForEach(TouchAction.allCases) { Text($0.title).tag($0) }
                }
                Picker(
                    "右耳",
                    selection: asyncBinding(
                        get: { bridge.settings.rightTouchAction },
                        set: { action in await bridge.updateTouchActions { $0.rightTouchAction = action } }
                    )
                ) {
                    ForEach(TouchAction.allCases) { Text($0.title).tag($0) }
                }
                if bridge.settings.leftTouchAction == .noiseControl {
                    Picker(
                        "左耳噪音循环",
                        selection: asyncBinding(
                            get: { bridge.settings.leftNoiseCycle },
                            set: { cycle in await bridge.updateNoiseCycles { $0.leftNoiseCycle = cycle } }
                        )
                    ) {
                        ForEach(NoiseControlCycle.allCases) { Text($0.title).tag($0) }
                    }
                }
                if bridge.settings.rightTouchAction == .noiseControl {
                    Picker(
                        "右耳噪音循环",
                        selection: asyncBinding(
                            get: { bridge.settings.rightNoiseCycle },
                            set: { cycle in await bridge.updateNoiseCycles { $0.rightNoiseCycle = cycle } }
                        )
                    ) {
                        ForEach(NoiseControlCycle.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .disabled(!bridge.canControl || bridge.settings.touchLocked)

            Section {
                Toggle(
                    "双击耳边调节音量",
                    isOn: asyncBinding(
                        get: { bridge.settings.edgeDoubleTapVolume },
                        set: bridge.setEdgeDoubleTapVolume
                    )
                )
            } footer: {
                Text("该开关对应三星 Outside Double Tap 命令。")
            }
            .disabled(!bridge.canControl || bridge.settings.touchLocked)
        }
        .navigationTitle("耳机控制")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func touchBinding(
        get: @escaping () -> Bool,
        _ update: @escaping (inout BudsDeviceSettings, Bool) -> Void
    ) -> Binding<Bool> {
        return Binding(
            get: get,
            set: { value in Task { await bridge.updateTouchControls { update(&$0, value) } } }
        )
    }
}

struct VoiceControlsView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section {
                NavigationLink("语音检测与恢复时间") {
                    AutomaticAmbientView()
                }
                LabeledContent("免唤醒语音控制", value: readOnlyState(bridge.settings.hotCommandEnabled))
                LabeledContent("Adapt Sound", value: readOnlyState(bridge.settings.adaptSoundEnabled))
            } header: {
                Text("语音与听力")
            } footer: {
                VerificationLabel(verification: .readOnly)
            }

            Section {
                Text("耳机能回报免唤醒语音和 Adapt Sound 状态，但官方命令还包含语言模型与听力测试数据。当前版本不会用单个布尔值覆盖这些复合配置。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("语音控制")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func readOnlyState(_ value: Bool?) -> String {
        guard let value else { return "未读取" }
        return value ? "已开启" : "关闭"
    }
}

struct ConnectionManagementView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section {
                Toggle(
                    "无缝耳机连接",
                    isOn: asyncBinding(
                        get: { bridge.settings.seamlessConnection },
                        set: bridge.setSeamlessConnection
                    )
                )
                Toggle(
                    "摘下双耳时把通话切回 iPhone",
                    isOn: asyncBinding(
                        get: { bridge.settings.callPathControlEnabled },
                        set: bridge.setCallPathControl
                    )
                )
                Toggle(
                    "游戏模式",
                    isOn: asyncBinding(
                        get: { bridge.settings.gamingModeEnabled },
                        set: bridge.setGamingMode
                    )
                )
            } header: {
                Text("设备切换")
            } footer: {
                VerificationLabel(verification: .protocolMapped)
            }
            .disabled(!bridge.canControl)

            Section {
                Toggle(
                    "记住上次设置",
                    isOn: Binding(
                        get: { bridge.rememberSettingsEnabled },
                        set: bridge.setRememberSettingsEnabled
                    )
                )
                LabeledContent("保存时机", value: "命令成功后")
                LabeledContent("连接后", value: bridge.hasExtendedState ? "以耳机状态校正" : "显示上次设置")
            } header: {
                Text("配置记忆")
            } footer: {
                Text("关闭后会删除本机保存的耳机配置；桥接密钥仍单独保存。")
            }

            Section {
                LabeledContent("通话与音频连接", value: "由 iOS 蓝牙设置管理")
                Button("重置耳机", role: .destructive) { }
                    .disabled(true)
            } footer: {
                Text("重置会清除配对信息，当前版本不提供远程执行。")
            }
        }
        .navigationTitle("连接管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AdvancedFeaturesView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section("佩戴与通话") {
                Toggle(
                    "摘下耳机时自动暂停",
                    isOn: asyncBinding(
                        get: { bridge.settings.autoPauseResumeEnabled },
                        set: bridge.setAutoPauseResume
                    )
                )
                Toggle(
                    "通话期间使用环境声",
                    isOn: asyncBinding(
                        get: { bridge.settings.sidetoneEnabled },
                        set: bridge.setSidetone
                    )
                )
                Toggle(
                    "清晰通话",
                    isOn: asyncBinding(
                        get: { bridge.settings.extraClearCallEnabled },
                        set: bridge.setExtraClearCall
                    )
                )
            }
            .disabled(!bridge.canControl)

            Section {
                Toggle(
                    "自适应音量",
                    isOn: asyncBinding(
                        get: { bridge.settings.adaptiveVolumeEnabled },
                        set: bridge.setAdaptiveVolume
                    )
                )
                Toggle(
                    "警笛检测",
                    isOn: asyncBinding(
                        get: { bridge.settings.sirenDetectEnabled },
                        set: bridge.setSirenDetect
                    )
                )
            } header: {
                Text("实验功能")
            } footer: {
                VerificationLabel(verification: .experimental)
            }
            .disabled(!bridge.canControl || !bridge.experimentalCommandsEnabled)

            Section("Blade Light") {
                LabeledContent("耳机回报值", value: lightingText)
                LabeledContent("写入控制", value: "等待协议参数")
            }
            .foregroundStyle(.secondary)

            Section("其他") {
                NavigationLink("耳塞贴合度测试") { FitTestView() }
                NavigationLink("查找我的耳机") { FindMyEarbudsView() }
                Button("软件更新") { }
                    .disabled(true)
            }
        }
        .navigationTitle("高级功能")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lightingText: String {
        bridge.settings.lightingControl.map(String.init) ?? "未读取"
    }
}

struct FindMyEarbudsView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient
    @State private var showsStartConfirmation = false

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section {
                LabeledContent("查找状态", value: bridge.findMyEarbudsActive ? "正在响铃" : "已停止")
                Toggle(
                    "左耳静音",
                    isOn: asyncBinding(
                        get: { bridge.findLeftMuted },
                        set: { muted in
                            await bridge.setFindEarbudMute(left: muted, right: bridge.findRightMuted)
                        }
                    )
                )
                .disabled(!bridge.findMyEarbudsActive)
                Toggle(
                    "右耳静音",
                    isOn: asyncBinding(
                        get: { bridge.findRightMuted },
                        set: { muted in
                            await bridge.setFindEarbudMute(left: bridge.findLeftMuted, right: muted)
                        }
                    )
                )
                .disabled(!bridge.findMyEarbudsActive)
            } footer: {
                VerificationLabel(verification: .protocolMapped)
            }

            Section {
                Button {
                    if bridge.findMyEarbudsActive {
                        Task { await bridge.setFindMyEarbuds(active: false) }
                    } else {
                        showsStartConfirmation = true
                    }
                } label: {
                    Label(
                        bridge.findMyEarbudsActive ? "停止响铃" : "开始查找",
                        systemImage: bridge.findMyEarbudsActive ? "stop.fill" : "speaker.wave.3.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(!bridge.canControl)
            } footer: {
                Text("响铃声音可能很大。Buds3 Pro 使用支持佩戴状态的查找命令，但仍应先摘下耳机。")
            }
        }
        .navigationTitle("查找我的耳机")
        .navigationBarTitleDisplayMode(.inline)
        .alert("开始让耳机响铃？", isPresented: $showsStartConfirmation) {
            Button("取消", role: .cancel) { }
            Button("开始") { Task { await bridge.setFindMyEarbuds(active: true) } }
        } message: {
            Text("先确认耳机没有戴在耳朵里。离开此页面时会自动停止。")
        }
        .onDisappear {
            guard bridge.findMyEarbudsActive else { return }
            Task { await bridge.setFindMyEarbuds(active: false) }
        }
    }
}

struct FitTestView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            ControlAvailabilitySection()

            Section("测试结果") {
                resultRow("左耳", result: bridge.settings.fitTestLeft)
                resultRow("右耳", result: bridge.settings.fitTestRight)
            }

            Section {
                Button {
                    Task { await bridge.setFitTest(active: !bridge.fitTestActive) }
                } label: {
                    Label(
                        bridge.fitTestActive ? "停止测试" : "开始测试",
                        systemImage: bridge.fitTestActive ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(!bridge.canControl)
            } footer: {
                Text("测试时双耳都要佩戴。收到结果后 App 会自动发送停止命令。")
            }
        }
        .navigationTitle("耳塞贴合度测试")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            guard bridge.fitTestActive else { return }
            Task { await bridge.setFitTest(active: false) }
        }
    }

    private func resultRow(_ title: String, result: FitTestResult?) -> some View {
        LabeledContent {
            Label(result?.title ?? (bridge.fitTestActive ? "测试中" : "尚未测试"), systemImage: resultSymbol(result))
                .foregroundStyle(result == .good ? .green : result == nil ? .secondary : .orange)
        } label: {
            Text(title)
        }
    }

    private func resultSymbol(_ result: FitTestResult?) -> String {
        switch result {
        case .good: "checkmark.circle.fill"
        case .bad: "exclamationmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case nil: bridge.fitTestActive ? "waveform" : "minus.circle"
        }
    }
}

struct VerificationCenterView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Form {
            Section {
                Toggle(
                    "离线演示模式",
                    isOn: Binding(get: { bridge.isDemoMode }, set: bridge.setDemoMode)
                )
                Toggle(
                    "允许实验命令",
                    isOn: Binding(
                        get: { bridge.experimentalCommandsEnabled },
                        set: bridge.setExperimentalCommandsEnabled
                    )
                )
                Toggle(
                    "记住上次设置",
                    isOn: Binding(
                        get: { bridge.rememberSettingsEnabled },
                        set: bridge.setRememberSettingsEnabled
                    )
                )
            } header: {
                Text("验证开关")
            } footer: {
                Text("离线演示不会连接 Mac 或耳机。实验命令只有消息 ID 可交叉验证，明天应逐项测试。")
            }

            Section("当前状态") {
                LabeledContent("版本", value: versionText)
                LabeledContent("控制链路", value: bridge.phase.title)
                LabeledContent("扩展状态", value: bridge.hasExtendedState ? "已读取" : "未读取")
                LabeledContent("已记录命令", value: "\(bridge.commandLog.count) 条")
            }

            Section("明日真机顺序") {
                Label("先验证自适应、环境声级别和语音检测", systemImage: "1.circle")
                Label("再验证触控锁、左右长捏和噪音循环", systemImage: "2.circle")
                Label("最后验证通话、佩戴与实验功能", systemImage: "3.circle")
            }

            Section {
                if bridge.commandLog.isEmpty {
                    Text("尚未发送命令")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bridge.commandLog.suffix(20).reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(entry.outcome.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(entry.outcome == .failed ? .red : .secondary)
                            }
                            Text(entry.packetHex)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
                ShareLink(item: bridge.validationReport) {
                    Label("导出验证记录", systemImage: "square.and.arrow.up")
                }
                Button("清空记录", role: .destructive) { bridge.clearCommandLog() }
                    .disabled(bridge.commandLog.isEmpty)
            } header: {
                Text("命令记录")
            } footer: {
                Text("记录保留在本次 App 运行期间；导出文本包含数据包和 ACK / 写入结果。")
            }
        }
        .navigationTitle("验证中心")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }
}

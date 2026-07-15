import SwiftUI

private struct ControlAvailabilitySection: View {
    @EnvironmentObject private var bridge: BudsBridgeClient

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bridge.phase.isReady ? "Mac 桥接已连接" : "耳机控制通道未连接")
                        .font(.subheadline.weight(.semibold))
                    Text(bridge.phase.isReady ? "当前仅开放降噪模式和 EQ 预设" : bridge.phase.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: bridge.phase.isReady ? "checkmark.seal" : "lock.shield")
                    .foregroundStyle(bridge.phase.isReady ? .green : .secondary)
            }
        }
    }
}

struct AutomaticAmbientView: View {
    @State private var voiceDetect = false
    @State private var sirenDetect = false
    @State private var ambientDuringCalls = false
    @State private var voiceDetectTimeout = 5

    var body: some View {
        Form {
            ControlAvailabilitySection()
            Section("自动环境声") {
                Toggle("检测我的声音", isOn: $voiceDetect)
                Picker("恢复时间", selection: $voiceDetectTimeout) {
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                    Text("15 秒").tag(15)
                }
                .disabled(!voiceDetect)
                Toggle("警笛检测", isOn: $sirenDetect)
                Toggle("通话期间使用环境声", isOn: $ambientDuringCalls)
            }
            .disabled(true)
        }
        .navigationTitle("自动环境声")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SoundQualityView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient
    @State private var preset: EqualizerPreset = .normal
    @State private var gains = Array(repeating: 0.0, count: 9)
    @State private var spatialAudio = false
    @State private var headTracking = false
    @State private var dialogueEnhancement = false
    @State private var loudnessNormalization = false
    @State private var wearAdjustment = false
    @State private var uhqAudio = false
    @State private var superWideBand = false

    private let frequencies = ["63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var body: some View {
        Form {
            ControlAvailabilitySection()
            Section("均衡器") {
                Picker("预设", selection: $preset) {
                    ForEach(EqualizerPreset.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
            .disabled(!bridge.canControl)
            .onChange(of: preset) { _, newValue in
                Task { await bridge.setEqualizer(newValue) }
            }

            Section("自定义均衡器") {
                ForEach(frequencies.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text(frequencies[index])
                            .font(.caption.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                        Slider(value: $gains[index], in: -10...10, step: 1)
                        Text("\(Int(gains[index]))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 24, alignment: .trailing)
                    }
                    .frame(minHeight: 34)
                }
            }
            .disabled(true)

            Section("360 音频") {
                Toggle("360 音频", isOn: $spatialAudio)
                Toggle("头部跟踪", isOn: $headTracking)
                    .disabled(!spatialAudio)
            }
            .disabled(true)

            Section("音效") {
                Toggle("增强对白", isOn: $dialogueEnhancement)
                Toggle("响度标准化", isOn: $loudnessNormalization)
                Toggle("根据佩戴状态调整声音", isOn: $wearAdjustment)
            }
            .disabled(true)

            Section("高级音质") {
                Toggle("UHQ 24-bit / 96 kHz", isOn: $uhqAudio)
                Toggle("Super Wide Band 通话", isOn: $superWideBand)
            }
            .disabled(true)

            Section {
                Button("耳塞贴合度测试") { }
                    .disabled(true)
            }
        }
        .navigationTitle("音质和音效")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum LongPressAction: String, CaseIterable, Identifiable {
    case noiseControl = "切换噪声模式"
    case assistant = "语音助手"
    case interpreter = "同声传译"
    case mindfulness = "正念音乐"

    var id: Self { self }
}

struct EarbudControlsView: View {
    @State private var mediaControls = true
    @State private var singlePinch = true
    @State private var doublePinch = true
    @State private var triplePinch = true
    @State private var swipeVolume = true
    @State private var leftLongPress: LongPressAction = .noiseControl
    @State private var rightLongPress: LongPressAction = .noiseControl
    @State private var answerCalls = true
    @State private var rejectCalls = true
    @State private var lockControls = false

    var body: some View {
        Form {
            ControlAvailabilitySection()
            Section("媒体控制") {
                Toggle("媒体控制", isOn: $mediaControls)
                Toggle("捏一下：播放或暂停", isOn: $singlePinch)
                Toggle("捏两下：下一首", isOn: $doublePinch)
                Toggle("捏三下：上一首", isOn: $triplePinch)
                Toggle("上下滑动：调节音量", isOn: $swipeVolume)
            }
            .disabled(true)

            Section("长捏") {
                Picker("左耳", selection: $leftLongPress) {
                    ForEach(LongPressAction.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("右耳", selection: $rightLongPress) {
                    ForEach(LongPressAction.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            .disabled(true)

            Section("通话控制") {
                Toggle("捏一下接听或结束通话", isOn: $answerCalls)
                Toggle("长捏拒接来电", isOn: $rejectCalls)
            }
            .disabled(true)

            Section {
                Toggle("锁定耳机控制", isOn: $lockControls)
            }
            .disabled(true)
        }
        .navigationTitle("耳机控制")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VoiceControlsView: View {
    @State private var enabled = false
    @State private var media = true
    @State private var track = true
    @State private var volume = true
    @State private var calls = true

    var body: some View {
        Form {
            ControlAvailabilitySection()
            Section {
                Toggle("免唤醒语音控制", isOn: $enabled)
            }
            .disabled(true)
            Section("可用命令") {
                Toggle("播放或停止音乐", isOn: $media)
                Toggle("上一首或下一首", isOn: $track)
                Toggle("调高或调低音量", isOn: $volume)
                Toggle("接听或拒接来电", isOn: $calls)
            }
            .disabled(true)
        }
        .navigationTitle("语音控制")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConnectionManagementView: View {
    @State private var calls = true
    @State private var audio = true
    @State private var seamless = true
    @State private var autoSwitch = false

    var body: some View {
        Form {
            ControlAvailabilitySection()
            Section("用途") {
                Toggle("通话", isOn: $calls)
                Toggle("音频", isOn: $audio)
            }
            .disabled(true)
            Section("设备切换") {
                Toggle("无缝耳机连接", isOn: $seamless)
                Toggle("Auto Switch Buds", isOn: $autoSwitch)
            }
            .disabled(true)
            Section {
                Button("重置耳机", role: .destructive) { }
                    .disabled(true)
            }
        }
        .navigationTitle("连接管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum BladeLightMode: String, CaseIterable, Identifiable {
    case blinking = "闪烁"
    case breathing = "渐亮渐暗"
    case steady = "常亮"

    var id: Self { self }
}

struct AdvancedFeaturesView: View {
    @State private var bladeLight = false
    @State private var bladeMode: BladeLightMode = .breathing
    @State private var pauseWhenRemoved = true
    @State private var resumeWhenWorn = true
    @State private var switchCallsToPhone = true
    @State private var neckStretch = false
    @State private var gamingMode = false

    var body: some View {
        Form {
            ControlAvailabilitySection()
            Section("Blade Light") {
                Toggle("耳机灯", isOn: $bladeLight)
                Picker("灯效", selection: $bladeMode) {
                    ForEach(BladeLightMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(!bladeLight)
            }
            .disabled(true)

            Section("佩戴检测") {
                Toggle("摘下一耳时暂停媒体", isOn: $pauseWhenRemoved)
                Toggle("重新佩戴时继续播放", isOn: $resumeWhenWorn)
                Toggle("摘下双耳时把通话切回手机", isOn: $switchCallsToPhone)
            }
            .disabled(true)

            Section("其他") {
                Toggle("颈部伸展提醒", isOn: $neckStretch)
                Toggle("Gaming mode", isOn: $gamingMode)
                    .disabled(true)
                Button("查找我的耳机") { }
                    .disabled(true)
                Button("软件更新") { }
                    .disabled(true)
            }
        }
        .navigationTitle("高级功能")
        .navigationBarTitleDisplayMode(.inline)
    }
}

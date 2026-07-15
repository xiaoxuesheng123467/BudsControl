import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var bridge: BudsBridgeClient
    @State private var showsDiagnostics = false

    private let pageBackground = Color(red: 0.956, green: 0.969, blue: 0.976)
    private let accent = Color(red: 0.075, green: 0.655, blue: 0.251)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 22) {
                    deviceHeader
                    noiseControlSection
                    equalizerSection
                    settingsMenuSection
                    discoverySection
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("Buds 控制台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsDiagnostics = true
                    } label: {
                        Image(systemName: "waveform.path.ecg.rectangle")
                    }
                    .accessibilityLabel("蓝牙诊断")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        bridge.restartDiscovery()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重新发现 Mac 桥接")
                }
            }
            .sheet(isPresented: $showsDiagnostics) {
                DiagnosticsHostView()
            }
        }
        .tint(accent)
    }

    private var deviceHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Galaxy Buds3 Pro")
                        .font(.system(size: 27, weight: .bold))
                    Label(bridge.phase.title, systemImage: statusSymbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(statusColor)
                }
                Spacer(minLength: 8)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: 82, height: 82)
                    Image(systemName: "earbuds")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 0) {
                batteryMetric("左耳", value: batteryText(bridge.leftBattery))
                Divider().frame(height: 34)
                batteryMetric("右耳", value: batteryText(bridge.rightBattery))
                Divider().frame(height: 34)
                batteryMetric("充电盒", value: batteryText(bridge.caseBattery))
            }
            .frame(height: 48)

            if bridge.phase.isBusy {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(accent)
                    .accessibilityLabel("正在扫描")
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    private var noiseControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("噪音控制", locked: !bridge.canControl)
            HStack(spacing: 8) {
                ForEach(NoiseControlMode.allCases) { mode in
                    Button {
                        Task { await bridge.setNoiseMode(mode) }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(height: 24)
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(bridge.selectedNoiseMode == mode ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 78)
                        .background(
                            bridge.selectedNoiseMode == mode ? accent : Color.white,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.07), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!bridge.canControl)
                    .opacity(bridge.canControl ? 1 : 0.52)
                }
            }

            NavigationLink {
                AutomaticAmbientView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.wave.2")
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动切换到环境声")
                            .font(.subheadline.weight(.semibold))
                        Text(bridge.settings.voiceDetectEnabled ? "已开启" : "关闭")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("均衡器", locked: !bridge.canControl)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(EqualizerPreset.allCases) { preset in
                    Button {
                        Task { await bridge.setEqualizer(preset) }
                    } label: {
                        Text(preset.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(bridge.selectedEqualizer == preset ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                bridge.selectedEqualizer == preset ? Color.black : Color.white,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.07), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!bridge.canControl)
                    .opacity(bridge.canControl ? 1 : 0.52)
                }
            }
        }
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("控制链路")
                    .font(.headline)
                Spacer()
                Button("蓝牙诊断") {
                    showsDiagnostics = true
                }
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 12) {
                Image(systemName: bridge.phase.isReady ? "macbook.and.iphone" : "network")
                    .font(.title2)
                    .foregroundStyle(bridge.phase.isReady ? accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bridge.phase.title)
                        .font(.subheadline.weight(.semibold))
                    Text(bridge.phase.isReady ? "RFCOMM 经局域网桥接" : "请在同一网络的 Mac 上运行 BudsBridge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))

            if case .pairing = bridge.phase {
                HStack(spacing: 10) {
                    TextField("32 位配对密钥", text: $bridge.pairingCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        bridge.submitPairingCode()
                    } label: {
                        Image(systemName: "key.fill")
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bridge.pairingCode.count != 32)
                    .accessibilityLabel("提交配对密钥")
                }
            }

            if let message = bridge.lastCommandMessage {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                    Text(message)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        bridge.clearMessage()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭提示")
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
        }
    }

    private var settingsMenuSection: some View {
        VStack(spacing: 10) {
            menuGroup {
                NavigationLink { SoundQualityView() } label: {
                    menuRow("音质和音效", symbol: "speaker.wave.3")
                }
                Divider().padding(.leading, 50)
                NavigationLink { EarbudControlsView() } label: {
                    menuRow("耳机控制", symbol: "hand.tap")
                }
                Divider().padding(.leading, 50)
                NavigationLink { VoiceControlsView() } label: {
                    menuRow("语音控制", symbol: "mic")
                }
            }

            menuGroup {
                NavigationLink { ConnectionManagementView() } label: {
                    menuRow("连接管理", symbol: "arrow.triangle.2.circlepath")
                }
                Divider().padding(.leading, 50)
                NavigationLink { AdvancedFeaturesView() } label: {
                    menuRow("高级功能", symbol: "gearshape.2")
                }
                Divider().padding(.leading, 50)
                NavigationLink { VerificationCenterView() } label: {
                    menuRow("验证中心", symbol: "checkmark.circle.badge.questionmark")
                }
            }
        }
    }

    private func menuGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
    }

    private func menuRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 24)
            Text(title)
                .font(.body.weight(.medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 50)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    private func sectionTitle(_ title: String, locked: Bool) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.headline)
            if locked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if locked {
                Text(bridge.phase.isReady ? "发送中" : "等待 Mac 桥接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func batteryMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func batteryText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "--"
    }

    private var statusSymbol: String {
        switch bridge.phase {
        case .ready: "checkmark.seal.fill"
        case .demo: "testtube.2"
        case .searching: "dot.radiowaves.left.and.right"
        case .connecting: "link.badge.plus"
        case .pairing: "key.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch bridge.phase {
        case .ready: accent
        case .demo: .purple
        case .searching, .connecting: .blue
        case .pairing, .unavailable: .orange
        }
    }
}

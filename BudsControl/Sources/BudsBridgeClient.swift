import Foundation
import Network
import Security

enum BridgePhase: Equatable {
    case searching
    case connecting(String)
    case pairing(String)
    case ready(String)
    case demo
    case unavailable(String)

    var title: String {
        switch self {
        case .searching:
            "正在寻找 Mac 桥接"
        case .connecting(let name):
            "正在连接 \(name)"
        case .pairing:
            "请粘贴 Mac 上显示的配对密钥"
        case .ready(let name):
            "已通过 \(name) 连接"
        case .demo:
            "离线演示模式"
        case .unavailable(let reason):
            reason
        }
    }

    var isReady: Bool {
        switch self {
        case .ready, .demo: true
        default: false
        }
    }

    var isBusy: Bool {
        switch self {
        case .searching, .connecting:
            true
        case .pairing, .ready, .demo, .unavailable:
            false
        }
    }
}

struct BridgeConnectionIssue: Equatable {
    let guidance: String
    let technicalDetail: String
    let offersSettingsShortcut: Bool
}

private struct BridgeStatusPayload: Decodable {
    let ready: Bool
    let serviceName: String?
    let deviceName: String?
    let message: String?
    let leftBattery: Int?
    let rightBattery: Int?
    let caseBattery: Int?
    let hasExtendedState: Bool?
    let revision: Int?
    let noiseMode: Int?
    let equalizer: Int?
    let ambientVolume: Int?
    let noiseReductionHigh: Bool?
    let ambientCustomizationEnabled: Bool?
    let ambientVolumeLeft: Int?
    let ambientVolumeRight: Int?
    let ambientTone: Int?
    let voiceDetectEnabled: Bool?
    let voiceDetectTimeout: Int?
    let noiseControlWithOneEarbud: Bool?
    let touchLocked: Bool?
    let singleTapEnabled: Bool?
    let doubleTapEnabled: Bool?
    let tripleTapEnabled: Bool?
    let touchAndHoldEnabled: Bool?
    let doubleTapCallEnabled: Bool?
    let touchAndHoldCallEnabled: Bool?
    let leftTouchAction: Int?
    let rightTouchAction: Int?
    let edgeDoubleTapVolume: Bool?
    let stereoBalance: Int?
    let seamlessConnection: Bool?
    let sidetoneEnabled: Bool?
    let callPathControlEnabled: Bool?
    let extraClearCallEnabled: Bool?
    let extraHighAmbientEnabled: Bool?
    let spatialAudioEnabled: Bool?
    let autoPauseResumeEnabled: Bool?
    let adaptiveVolumeEnabled: Bool?
    let sirenDetectEnabled: Bool?
    let lightingControl: Int?
    let hotCommandEnabled: Bool?
    let adaptSoundEnabled: Bool?
    let fitTestActive: Bool?
    let fitTestLeft: Int?
    let fitTestRight: Int?
    let stateUpdatedAt: TimeInterval?
}

private struct BridgeCommandPayload: Decodable {
    let sent: Bool
    let acknowledged: Bool?
    let confirmation: String?
    let message: String?
}

@MainActor
final class BudsBridgeClient: ObservableObject {
    @Published private(set) var phase: BridgePhase = .searching
    @Published private(set) var settings: BudsDeviceSettings
    @Published private(set) var isSending = false
    @Published private(set) var lastCommandMessage: String?
    @Published private(set) var connectionIssue: BridgeConnectionIssue?
    @Published private(set) var leftBattery: Int?
    @Published private(set) var rightBattery: Int?
    @Published private(set) var caseBattery: Int?
    @Published private(set) var hasExtendedState = false
    @Published private(set) var commandLog: [BudsCommandLogEntry] = []
    @Published private(set) var isDemoMode: Bool
    @Published private(set) var experimentalCommandsEnabled: Bool
    @Published private(set) var rememberSettingsEnabled: Bool
    @Published private(set) var fitTestActive = false
    @Published private(set) var findMyEarbudsActive = false
    @Published private(set) var findLeftMuted = false
    @Published private(set) var findRightMuted = false
    @Published var pairingCode: String {
        didSet {
            let hexadecimal = String(pairingCode.uppercased().filter(\.isHexDigit).prefix(32))
            if hexadecimal != pairingCode {
                pairingCode = hexadecimal
            }
            UserDefaults.standard.set(hexadecimal, forKey: Self.pairingCodeKey)
        }
    }

    private static let pairingCodeKey = "budsBridgePairingCode"
    private static let settingsKey = "budsRememberedDeviceSettings.v2"
    private static let demoModeKey = "budsDemoMode"
    private static let experimentalKey = "budsExperimentalCommands"
    private static let rememberSettingsKey = "budsRememberSettings"
    private let queue = DispatchQueue(label: "com.qiao.budscontrol.bridge-browser")
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var readyEndpoint: NWEndpoint?
    private var pollTask: Task<Void, Never>?
    private var statusRequestGeneration = 0
    private var statusRequestInFlight = false
    private var statusRefreshPending = false
    private var consecutiveStatusFailures = 0

    var canControl: Bool {
        !isSending && (isDemoMode || (phase.isReady && endpoint == readyEndpoint))
    }

    var hasDiscoveredBridge: Bool {
        endpoint != nil
    }

    var shouldShowPairingControls: Bool {
        !isDemoMode && endpoint != nil && !phase.isReady
    }

    var selectedNoiseMode: NoiseControlMode? { settings.noiseMode }
    var selectedEqualizer: EqualizerPreset? { settings.equalizer }

    init() {
        settings = Self.loadRememberedSettings() ?? BudsDeviceSettings()
        pairingCode = UserDefaults.standard.string(forKey: Self.pairingCodeKey) ?? ""
        isDemoMode = UserDefaults.standard.bool(forKey: Self.demoModeKey)
        experimentalCommandsEnabled = UserDefaults.standard.bool(forKey: Self.experimentalKey)
        rememberSettingsEnabled = UserDefaults.standard.object(forKey: Self.rememberSettingsKey) as? Bool ?? true
        if isDemoMode {
            activateDemoMode()
        } else {
            startDiscovery()
        }
    }

    deinit {
        browser?.cancel()
        pollTask?.cancel()
    }

    func restartDiscovery() {
        if isDemoMode {
            activateDemoMode()
            return
        }
        browser?.cancel()
        pollTask?.cancel()
        endpoint = nil
        readyEndpoint = nil
        findMyEarbudsActive = false
        hasExtendedState = false
        connectionIssue = nil
        lastCommandMessage = nil
        statusRefreshPending = false
        consecutiveStatusFailures = 0
        statusRequestGeneration += 1
        phase = .searching
        startDiscovery()
    }

    func refreshStatus() async {
        guard !isDemoMode else { return }
        guard let endpoint else {
            phase = .searching
            return
        }
        guard pairingCode.count == 32 else {
            readyEndpoint = nil
            phase = .pairing(endpoint.displayName)
            return
        }
        guard !statusRequestInFlight else {
            statusRefreshPending = true
            return
        }
        statusRequestInFlight = true
        defer { finishStatusRequest() }

        let requestedEndpoint = endpoint
        statusRequestGeneration += 1
        let generation = statusRequestGeneration

        do {
            let body = try await BridgeHTTP.request(
                endpoint: endpoint,
                method: "GET",
                path: "/v1/status",
                pairingCode: pairingCode
            )
            let status = try JSONDecoder().decode(BridgeStatusPayload.self, from: body)
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            let serviceName = status.serviceName ?? status.deviceName ?? endpoint.displayName
            leftBattery = status.leftBattery
            rightBattery = status.rightBattery
            caseBattery = status.caseBattery
            apply(status)
            connectionIssue = nil
            consecutiveStatusFailures = 0
            if status.ready {
                readyEndpoint = requestedEndpoint
                phase = .ready(serviceName)
            } else {
                readyEndpoint = nil
                hasExtendedState = false
                phase = .connecting(serviceName)
                lastCommandMessage = status.message
            }
        } catch BridgeHTTP.RequestError.authentication {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            consecutiveStatusFailures = 0
            readyEndpoint = nil
            hasExtendedState = false
            phase = .pairing(endpoint.displayName)
            connectionIssue = nil
            lastCommandMessage = "配对密钥不正确"
        } catch BridgeHTTP.RequestError.server(let status, let message) where status == 401 {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            consecutiveStatusFailures = 0
            readyEndpoint = nil
            hasExtendedState = false
            phase = .pairing(endpoint.displayName)
            connectionIssue = nil
            lastCommandMessage = message
        } catch BridgeHTTP.RequestError.localNetworkDenied(let detail) {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            guard shouldPresentTransientFailure() else { return }
            readyEndpoint = nil
            hasExtendedState = false
            phase = .unavailable("iPhone 未允许本地网络访问")
            lastCommandMessage = nil
            connectionIssue = BridgeConnectionIssue(
                guidance: "在“设置 > 隐私与安全性 > 本地网络”中允许“Buds 控制台”，返回后点重新发现。",
                technicalDetail: detail,
                offersSettingsShortcut: true
            )
        } catch BridgeHTTP.RequestError.connection(let detail) {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            guard shouldPresentTransientFailure() else { return }
            readyEndpoint = nil
            hasExtendedState = false
            phase = .unavailable("Mac 桥接暂不可用")
            lastCommandMessage = nil
            connectionIssue = BridgeConnectionIssue(
                guidance: "已发现 Mac 桥接，但连接没有建立。请检查本地网络权限、两台设备是否在同一 Wi-Fi，并确认 Mac 防火墙未拦截 BudsBridge。",
                technicalDetail: detail,
                offersSettingsShortcut: true
            )
        } catch BridgeHTTP.RequestError.timedOut {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            guard shouldPresentTransientFailure() else { return }
            readyEndpoint = nil
            hasExtendedState = false
            phase = .unavailable("连接 Mac 桥接超时")
            lastCommandMessage = nil
            connectionIssue = BridgeConnectionIssue(
                guidance: "已发现 Mac 桥接，但请求没有完成。请先检查 iPhone 的本地网络权限，再确认同一 Wi-Fi 和 Mac 防火墙后重试。",
                technicalDetail: BridgeHTTP.RequestError.timedOut.localizedDescription,
                offersSettingsShortcut: true
            )
        } catch {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            guard shouldPresentTransientFailure() else { return }
            readyEndpoint = nil
            hasExtendedState = false
            phase = .unavailable("Mac 桥接暂不可用")
            lastCommandMessage = nil
            connectionIssue = BridgeConnectionIssue(
                guidance: "桥接状态请求失败。请重新发现；如果问题持续，请重启 Mac 上的 BudsBridge。",
                technicalDetail: error.localizedDescription,
                offersSettingsShortcut: false
            )
        }
    }

    private func finishStatusRequest() {
        statusRequestInFlight = false
        guard statusRefreshPending, !isDemoMode else {
            statusRefreshPending = false
            return
        }
        statusRefreshPending = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.refreshStatus()
        }
    }

    private func shouldPresentTransientFailure() -> Bool {
        consecutiveStatusFailures += 1
        return !phase.isReady || consecutiveStatusFailures >= 2
    }

    func setNoiseMode(_ mode: NoiseControlMode) async {
        await perform(.noiseControl(mode)) { $0.noiseMode = mode }
    }

    func setEqualizer(_ preset: EqualizerPreset) async {
        await perform(.equalizer(preset)) { $0.equalizer = preset }
    }

    func setAmbientVolume(_ level: AmbientSoundLevel) async {
        await perform(.ambientVolume(level)) { $0.ambientVolume = level }
    }

    func updateAmbientCustomization(_ update: (inout BudsDeviceSettings) -> Void) async {
        var candidate = settings
        update(&candidate)
        let command = BudsCommand.ambientCustomization(
            enabled: candidate.ambientCustomizationEnabled,
            left: candidate.ambientVolumeLeft,
            right: candidate.ambientVolumeRight,
            tone: candidate.ambientTone
        )
        await perform(command) { current in
            current.ambientCustomizationEnabled = candidate.ambientCustomizationEnabled
            current.ambientVolumeLeft = candidate.ambientVolumeLeft
            current.ambientVolumeRight = candidate.ambientVolumeRight
            current.ambientTone = candidate.ambientTone
        }
    }

    func setNoiseReductionHigh(_ enabled: Bool) async {
        await perform(.noiseReductionLevel(high: enabled)) { $0.noiseReductionHigh = enabled }
    }

    func setVoiceDetect(_ enabled: Bool) async {
        await perform(.voiceDetect(enabled)) { $0.voiceDetectEnabled = enabled }
    }

    func setVoiceDetectTimeout(_ timeout: VoiceDetectTimeout) async {
        await perform(.voiceDetectTimeout(timeout)) { $0.voiceDetectTimeout = timeout }
    }

    func setNoiseControlWithOneEarbud(_ enabled: Bool) async {
        await perform(.noiseControlWithOneEarbud(enabled)) { $0.noiseControlWithOneEarbud = enabled }
    }

    func updateTouchControls(_ update: (inout BudsDeviceSettings) -> Void) async {
        var candidate = settings
        update(&candidate)
        let command = BudsCommand.touchLock(
            locked: candidate.touchLocked,
            singleTap: candidate.singleTapEnabled,
            doubleTap: candidate.doubleTapEnabled,
            tripleTap: candidate.tripleTapEnabled,
            touchAndHold: candidate.touchAndHoldEnabled,
            doubleTapCall: candidate.doubleTapCallEnabled,
            touchAndHoldCall: candidate.touchAndHoldCallEnabled
        )
        await perform(command) { current in
            current.touchLocked = candidate.touchLocked
            current.singleTapEnabled = candidate.singleTapEnabled
            current.doubleTapEnabled = candidate.doubleTapEnabled
            current.tripleTapEnabled = candidate.tripleTapEnabled
            current.touchAndHoldEnabled = candidate.touchAndHoldEnabled
            current.doubleTapCallEnabled = candidate.doubleTapCallEnabled
            current.touchAndHoldCallEnabled = candidate.touchAndHoldCallEnabled
        }
    }

    func updateTouchActions(_ update: (inout BudsDeviceSettings) -> Void) async {
        var candidate = settings
        update(&candidate)
        await perform(.touchActions(left: candidate.leftTouchAction, right: candidate.rightTouchAction)) { current in
            current.leftTouchAction = candidate.leftTouchAction
            current.rightTouchAction = candidate.rightTouchAction
        }
    }

    func updateNoiseCycles(_ update: (inout BudsDeviceSettings) -> Void) async {
        var candidate = settings
        update(&candidate)
        await perform(.touchNoiseCycle(left: candidate.leftNoiseCycle, right: candidate.rightNoiseCycle)) { current in
            current.leftNoiseCycle = candidate.leftNoiseCycle
            current.rightNoiseCycle = candidate.rightNoiseCycle
        }
    }

    func setEdgeDoubleTapVolume(_ enabled: Bool) async {
        await perform(.edgeDoubleTapVolume(enabled)) { $0.edgeDoubleTapVolume = enabled }
    }

    func setStereoBalance(_ value: Int) async {
        await perform(.stereoBalance(value)) { $0.stereoBalance = value }
    }

    func setSeamlessConnection(_ enabled: Bool) async {
        await perform(.seamlessConnection(enabled)) { $0.seamlessConnection = enabled }
    }

    func setSidetone(_ enabled: Bool) async {
        await perform(.sidetone(enabled)) { $0.sidetoneEnabled = enabled }
    }

    func setCallPathControl(_ enabled: Bool) async {
        await perform(.callPathControl(enabled)) { $0.callPathControlEnabled = enabled }
    }

    func setExtraClearCall(_ enabled: Bool) async {
        await perform(.extraClearCall(enabled)) { $0.extraClearCallEnabled = enabled }
    }

    func setExtraHighAmbient(_ enabled: Bool) async {
        await perform(.extraHighAmbient(enabled)) { $0.extraHighAmbientEnabled = enabled }
    }

    func setSpatialAudio(_ enabled: Bool) async {
        await perform(.spatialAudio(enabled)) { $0.spatialAudioEnabled = enabled }
    }

    func setGamingMode(_ enabled: Bool) async {
        await perform(.gamingMode(enabled)) { $0.gamingModeEnabled = enabled }
    }

    func setAutoPauseResume(_ enabled: Bool) async {
        await perform(.autoPauseResume(enabled)) { $0.autoPauseResumeEnabled = enabled }
    }

    func setAdaptiveVolume(_ enabled: Bool) async {
        await perform(.adaptiveVolume(enabled)) { $0.adaptiveVolumeEnabled = enabled }
    }

    func setSirenDetect(_ enabled: Bool) async {
        await perform(.sirenDetect(enabled)) { $0.sirenDetectEnabled = enabled }
    }

    func setFitTest(active: Bool) async {
        let succeeded = await perform(.fitTest(active: active)) { current in
            current.fitTestLeft = nil
            current.fitTestRight = nil
        }
        if succeeded {
            fitTestActive = active
            if isDemoMode && active {
                try? await Task.sleep(for: .seconds(2))
                guard isDemoMode, fitTestActive else { return }
                settings.fitTestLeft = .good
                settings.fitTestRight = .good
                fitTestActive = false
                persistSettings()
            }
        }
    }

    func setFindMyEarbuds(active: Bool) async {
        let command: BudsCommand = active ? .findEarbudsStart : .findEarbudsStop
        let succeeded = await perform(command) { _ in }
        if succeeded {
            findMyEarbudsActive = active
            if !active {
                findLeftMuted = false
                findRightMuted = false
            }
        }
    }

    func setFindEarbudMute(left: Bool, right: Bool) async {
        let succeeded = await perform(.muteEarbuds(left: left, right: right)) { _ in }
        if succeeded {
            findLeftMuted = left
            findRightMuted = right
        }
    }

    func clearMessage() {
        lastCommandMessage = nil
    }

    func submitPairingCode() {
        guard pairingCode.count == 32 else {
            lastCommandMessage = "请粘贴完整的 32 位配对密钥"
            return
        }
        guard let endpoint else {
            lastCommandMessage = "尚未发现 Mac 桥接，请确认两台设备在同一 Wi-Fi"
            return
        }
        connectionIssue = nil
        lastCommandMessage = nil
        phase = .connecting(endpoint.displayName)
        Task { await refreshStatus() }
    }

    func setDemoMode(_ enabled: Bool) {
        guard enabled != isDemoMode else { return }
        isDemoMode = enabled
        UserDefaults.standard.set(enabled, forKey: Self.demoModeKey)
        statusRefreshPending = false
        consecutiveStatusFailures = 0
        statusRequestGeneration += 1
        if enabled {
            browser?.cancel()
            pollTask?.cancel()
            endpoint = nil
            readyEndpoint = nil
            connectionIssue = nil
            activateDemoMode()
        } else {
            leftBattery = nil
            rightBattery = nil
            caseBattery = nil
            hasExtendedState = false
            connectionIssue = nil
            phase = .searching
            startDiscovery()
        }
    }

    func setExperimentalCommandsEnabled(_ enabled: Bool) {
        experimentalCommandsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.experimentalKey)
    }

    func setRememberSettingsEnabled(_ enabled: Bool) {
        rememberSettingsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.rememberSettingsKey)
        if enabled {
            persistSettings()
        } else {
            UserDefaults.standard.removeObject(forKey: Self.settingsKey)
        }
    }

    func clearCommandLog() {
        commandLog.removeAll()
    }

    var validationReport: String {
        var lines = [
            "BudsControl 0.2.0 验证记录",
            "生成时间：\(Date().formatted(date: .numeric, time: .standard))",
            "模式：\(isDemoMode ? "离线演示" : "真实桥接")",
            "连接：\(phase.title)",
            "扩展状态：\(hasExtendedState ? "已读取" : "未读取")",
            ""
        ]
        if commandLog.isEmpty {
            lines.append("尚未发送命令。")
        } else {
            lines.append(contentsOf: commandLog.reversed().map { entry in
                "[\(entry.date.formatted(date: .omitted, time: .standard))] \(entry.outcome.rawValue) | \(entry.title) | \(entry.packetHex) | \(entry.detail)"
            })
        }
        return lines.joined(separator: "\n")
    }

    private func startDiscovery() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_budscontrol._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.browser === browser else { return }
                switch state {
                case .ready:
                    if self.endpoint == nil {
                        self.phase = .searching
                        self.connectionIssue = nil
                    }
                case .waiting(let error):
                    self.presentDiscoveryIssue(error, failed: false)
                case .failed(let error):
                    self.presentDiscoveryIssue(error, failed: true)
                case .cancelled:
                    break
                default:
                    self.phase = .searching
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let ordered = results.sorted {
                if $0.endpoint.bridgePriority != $1.endpoint.bridgePriority {
                    return $0.endpoint.bridgePriority < $1.endpoint.bridgePriority
                }
                return $0.endpoint.displayName < $1.endpoint.displayName
            }
            Task { @MainActor in
                guard let self, self.browser === browser else { return }
                guard !ordered.isEmpty else {
                    if self.phase.isReady, self.endpoint == self.readyEndpoint {
                        return
                    }
                    self.endpoint = nil
                    self.readyEndpoint = nil
                    self.consecutiveStatusFailures = 0
                    self.statusRequestGeneration += 1
                    self.connectionIssue = nil
                    self.phase = .searching
                    return
                }
                let first = ordered.first(where: { $0.endpoint == self.endpoint }) ?? ordered[0]
                let changed = self.endpoint != first.endpoint
                self.endpoint = first.endpoint
                if changed {
                    self.readyEndpoint = nil
                    self.consecutiveStatusFailures = 0
                    self.statusRequestGeneration += 1
                    self.phase = .connecting(first.endpoint.displayName)
                    self.connectionIssue = nil
                    self.beginPolling()
                }
                await self.refreshStatus()
            }
        }

        browser.start(queue: queue)
    }

    private func presentDiscoveryIssue(_ error: NWError, failed: Bool) {
        lastCommandMessage = nil
        if phase.isReady, endpoint == readyEndpoint {
            connectionIssue = BridgeConnectionIssue(
                guidance: "桥接发现暂时波动，当前控制链路仍可用；App 会继续用现有连接自动重试。",
                technicalDetail: error.localizedDescription,
                offersSettingsShortcut: error.indicatesLocalNetworkDenial
            )
            return
        }
        if error.indicatesLocalNetworkDenial {
            phase = .unavailable("iPhone 未允许本地网络访问")
            connectionIssue = BridgeConnectionIssue(
                guidance: "在“设置 > 隐私与安全性 > 本地网络”中允许“Buds 控制台”，返回后点重新发现。",
                technicalDetail: error.localizedDescription,
                offersSettingsShortcut: true
            )
        } else {
            phase = .unavailable(failed ? "桥接发现失败" : "桥接发现正在等待网络")
            connectionIssue = BridgeConnectionIssue(
                guidance: "请检查 iPhone 的本地网络权限，并确认 Mac 与 iPhone 在同一 Wi-Fi、BudsBridge 正在运行，然后重新发现。",
                technicalDetail: error.localizedDescription,
                offersSettingsShortcut: true
            )
        }
    }

    private func beginPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if case .pairing = self?.phase { continue }
                await self?.refreshStatus()
            }
        }
    }

    @discardableResult
    private func perform(
        _ command: BudsCommand,
        applying update: (inout BudsDeviceSettings) -> Void
    ) async -> Bool {
        if command.verification == .experimental && !experimentalCommandsEnabled {
            lastCommandMessage = "请先在验证中心开启实验命令"
            appendLog(command, outcome: .failed, detail: "实验命令未授权")
            return false
        }

        if isDemoMode {
            isSending = true
            try? await Task.sleep(for: .milliseconds(180))
            update(&settings)
            persistSettings()
            isSending = false
            lastCommandMessage = "离线模拟：\(command.title)"
            appendLog(command, outcome: .simulated, detail: "未发送到耳机")
            return true
        }

        guard let endpoint, endpoint == readyEndpoint, phase.isReady else {
            lastCommandMessage = "请先在 Mac 上启动 BudsBridge"
            appendLog(command, outcome: .failed, detail: "桥接未连接")
            return false
        }

        isSending = true
        defer { isSending = false }

        do {
            let data = try JSONSerialization.data(withJSONObject: [
                "command": command.name.rawValue,
                "values": command.jsonValues
            ])
            let body = try await BridgeHTTP.request(
                endpoint: endpoint,
                method: "POST",
                path: "/v1/command",
                pairingCode: pairingCode,
                body: data
            )
            let result = try JSONDecoder().decode(BridgeCommandPayload.self, from: body)
            guard result.sent else {
                lastCommandMessage = result.message ?? "耳机没有接受命令"
                appendLog(command, outcome: .failed, detail: lastCommandMessage ?? "命令被拒绝")
                return false
            }
            update(&settings)
            persistSettings()
            let acknowledged = result.acknowledged == true || result.confirmation == "acknowledged"
            let outcome: BudsCommandLogEntry.Outcome = acknowledged ? .acknowledged : .written
            lastCommandMessage = acknowledged
                ? "耳机已确认：\(command.title)"
                : "已写入：\(command.title)，等待状态包确认"
            appendLog(command, outcome: outcome, detail: result.message ?? "命令成功")
            return true
        } catch {
            lastCommandMessage = error.localizedDescription
            appendLog(command, outcome: .failed, detail: error.localizedDescription)
            await refreshStatus()
            return false
        }
    }

    private func apply(_ status: BridgeStatusPayload) {
        hasExtendedState = status.hasExtendedState == true
        guard status.hasExtendedState == true else {
            if let left = status.fitTestLeft.flatMap(FitTestResult.init(rawValue:)) {
                settings.fitTestLeft = left
            }
            if let right = status.fitTestRight.flatMap(FitTestResult.init(rawValue:)) {
                settings.fitTestRight = right
            }
            fitTestActive = status.fitTestActive ?? fitTestActive
            return
        }

        hasExtendedState = true
        settings.revision = status.revision ?? settings.revision
        if let value = status.noiseMode.flatMap(NoiseControlMode.init(commandValue:)) { settings.noiseMode = value }
        if let value = status.equalizer.flatMap(EqualizerPreset.init(rawValue:)) { settings.equalizer = value }
        if let value = status.ambientVolume.flatMap(AmbientSoundLevel.init(rawValue:)) { settings.ambientVolume = value }
        if let value = status.noiseReductionHigh { settings.noiseReductionHigh = value }
        if let value = status.ambientCustomizationEnabled { settings.ambientCustomizationEnabled = value }
        if let value = status.ambientVolumeLeft, (0...2).contains(value) { settings.ambientVolumeLeft = value }
        if let value = status.ambientVolumeRight, (0...2).contains(value) { settings.ambientVolumeRight = value }
        if let value = status.ambientTone.flatMap(AmbientSoundTone.init(rawValue:)) { settings.ambientTone = value }
        if let value = status.voiceDetectEnabled { settings.voiceDetectEnabled = value }
        if let value = status.voiceDetectTimeout.flatMap(VoiceDetectTimeout.init(rawValue:)) { settings.voiceDetectTimeout = value }
        if let value = status.noiseControlWithOneEarbud { settings.noiseControlWithOneEarbud = value }
        if let value = status.touchLocked { settings.touchLocked = value }
        if let value = status.singleTapEnabled { settings.singleTapEnabled = value }
        if let value = status.doubleTapEnabled { settings.doubleTapEnabled = value }
        if let value = status.tripleTapEnabled { settings.tripleTapEnabled = value }
        if let value = status.touchAndHoldEnabled { settings.touchAndHoldEnabled = value }
        if let value = status.doubleTapCallEnabled { settings.doubleTapCallEnabled = value }
        if let value = status.touchAndHoldCallEnabled { settings.touchAndHoldCallEnabled = value }
        if let value = status.leftTouchAction.flatMap(TouchAction.init(rawValue:)) { settings.leftTouchAction = value }
        if let value = status.rightTouchAction.flatMap(TouchAction.init(rawValue:)) { settings.rightTouchAction = value }
        if let value = status.edgeDoubleTapVolume { settings.edgeDoubleTapVolume = value }
        if let value = status.stereoBalance, (0...32).contains(value) { settings.stereoBalance = value }
        if let value = status.seamlessConnection { settings.seamlessConnection = value }
        if let value = status.sidetoneEnabled { settings.sidetoneEnabled = value }
        if let value = status.callPathControlEnabled { settings.callPathControlEnabled = value }
        if let value = status.extraClearCallEnabled { settings.extraClearCallEnabled = value }
        if let value = status.extraHighAmbientEnabled { settings.extraHighAmbientEnabled = value }
        if let value = status.spatialAudioEnabled { settings.spatialAudioEnabled = value }
        if let value = status.autoPauseResumeEnabled { settings.autoPauseResumeEnabled = value }
        if let value = status.adaptiveVolumeEnabled { settings.adaptiveVolumeEnabled = value }
        if let value = status.sirenDetectEnabled { settings.sirenDetectEnabled = value }
        settings.lightingControl = status.lightingControl ?? settings.lightingControl
        settings.hotCommandEnabled = status.hotCommandEnabled ?? settings.hotCommandEnabled
        settings.adaptSoundEnabled = status.adaptSoundEnabled ?? settings.adaptSoundEnabled
        if let value = status.fitTestLeft.flatMap(FitTestResult.init(rawValue:)) { settings.fitTestLeft = value }
        if let value = status.fitTestRight.flatMap(FitTestResult.init(rawValue:)) { settings.fitTestRight = value }
        fitTestActive = status.fitTestActive ?? fitTestActive
        persistSettings()
    }

    private func activateDemoMode() {
        if Self.loadRememberedSettings() == nil { settings = .demo }
        leftBattery = 86
        rightBattery = 83
        caseBattery = 74
        hasExtendedState = true
        phase = .demo
    }

    private func appendLog(
        _ command: BudsCommand,
        outcome: BudsCommandLogEntry.Outcome,
        detail: String
    ) {
        commandLog.append(BudsCommandLogEntry(
            date: Date(),
            title: command.title,
            packetHex: command.packet.encoded.upperHex,
            outcome: outcome,
            detail: detail
        ))
        if commandLog.count > 100 { commandLog.removeFirst(commandLog.count - 100) }
    }

    private func persistSettings() {
        guard rememberSettingsEnabled else { return }
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    private static func loadRememberedSettings() -> BudsDeviceSettings? {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(BudsDeviceSettings.self, from: data)
    }
}

enum BridgeHTTP {
    enum RequestError: LocalizedError {
        case authentication
        case localNetworkDenied(String)
        case connection(String)
        case invalidResponse
        case server(Int, String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .authentication: "配对密钥不正确"
            case .localNetworkDenied: "iPhone 未允许本地网络访问"
            case .connection(let message): message
            case .invalidResponse: "Mac 桥接返回了无效响应"
            case .server(_, let message): message
            case .timedOut: "连接 Mac 桥接超时"
            }
        }

        static func from(_ error: NWError) -> RequestError {
            if case .tls = error { return .authentication }
            if error.indicatesLocalNetworkDenial {
                return .localNetworkDenied(error.localizedDescription)
            }
            return .connection(error.localizedDescription)
        }
    }

    private final class RequestOperation {
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "com.qiao.budscontrol.bridge-request")
        private let requestData: Data
        private let continuation: CheckedContinuation<Data, Error>
        private var response = Data()
        private var completed = false
        private var requestSent = false

        init(
            endpoint: NWEndpoint,
            pairingCode: String,
            requestData: Data,
            continuation: CheckedContinuation<Data, Error>
        ) {
            connection = NWConnection(to: endpoint, using: BridgeHTTP.secureParameters(pairingCode: pairingCode))
            self.requestData = requestData
            self.continuation = continuation
        }

        func start() {
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready where !requestSent:
                    requestSent = true
                    connection.send(content: requestData, completion: .contentProcessed { [self] error in
                        if let error {
                            finish(.failure(RequestError.from(error)))
                        } else {
                            receiveNext()
                        }
                    })
                case .failed(let error):
                    finish(.failure(RequestError.from(error)))
                case .cancelled where !completed:
                    finish(.failure(RequestError.connection("连接已取消")))
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + 4) { [self] in
                finish(.failure(RequestError.timedOut))
            }
            connection.start(queue: queue)
        }

        private func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
                if let data {
                    guard response.count + data.count <= 64 * 1024 else {
                        finish(.failure(RequestError.invalidResponse))
                        return
                    }
                    response.append(data)
                }
                do {
                    if let body = try BridgeHTTP.completeResponseBody(from: response) {
                        finish(.success(body))
                        return
                    }
                } catch {
                    finish(.failure(error))
                    return
                }
                if let error {
                    finish(.failure(RequestError.from(error)))
                } else if isComplete {
                    finish(.failure(RequestError.invalidResponse))
                } else {
                    receiveNext()
                }
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard !completed else { return }
            completed = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(with: result)
        }
    }

    static func request(
        endpoint: NWEndpoint,
        method: String,
        path: String,
        pairingCode: String,
        body: Data? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let requestData = makeRequest(
                method: method,
                path: path,
                pairingCode: pairingCode,
                body: body
            )
            RequestOperation(
                endpoint: endpoint,
                pairingCode: pairingCode,
                requestData: requestData,
                continuation: continuation
            ).start()
        }
    }

    private static func secureParameters(pairingCode: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        pairingCode.withCString { BudsConfigureTLSPSK(tls.securityProtocolOptions, $0) }
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }

    private static func makeRequest(method: String, path: String, pairingCode: String, body: Data?) -> Data {
        let payload = body ?? Data()
        var lines = [
            "\(method) \(path) HTTP/1.1",
            "Host: budscontrol.local",
            "Accept: application/json",
            "X-Buds-Pairing-Code: \(pairingCode)",
            "Connection: close",
            "Content-Length: \(payload.count)"
        ]
        if body != nil { lines.append("Content-Type: application/json") }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + payload
    }

    static func completeResponseBody(from data: Data) throws -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return nil }
        guard let header = String(data: data[..<range.lowerBound], encoding: .utf8) else {
            throw RequestError.invalidResponse
        }

        let contentLengthLine = header.components(separatedBy: "\r\n").first {
            $0.lowercased().hasPrefix("content-length:")
        }
        guard let contentLengthLine,
              let contentLength = Int(contentLengthLine.dropFirst("content-length:".count)
                .trimmingCharacters(in: .whitespaces)),
              (0 ... 64 * 1024).contains(contentLength) else {
            throw RequestError.invalidResponse
        }

        let responseLength = range.upperBound + contentLength
        guard data.count >= responseLength else { return nil }
        return try parseResponse(Data(data.prefix(responseLength)))
    }

    private static func parseResponse(_ data: Data) throws -> Data {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8),
              let statusLine = header.components(separatedBy: "\r\n").first else {
            throw RequestError.invalidResponse
        }

        let fields = statusLine.split(separator: " ", maxSplits: 2)
        guard fields.count >= 2, let status = Int(fields[1]) else {
            throw RequestError.invalidResponse
        }

        let body = Data(data[range.upperBound...])
        guard (200...299).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["message"] as? String
            throw RequestError.server(status, message ?? "Mac 桥接返回错误 \(status)")
        }
        return body
    }
}

private extension NWError {
    var indicatesLocalNetworkDenial: Bool {
        switch self {
        case .posix(let code):
            return code == .EPERM || code == .EACCES
        case .dns(let code):
            // DNS-SD reports local-network privacy denial as PolicyDenied (-65570).
            return code == -65_570
        default:
            return false
        }
    }
}

private extension NWEndpoint {
    var displayName: String {
        switch self {
        case .service(let name, _, _, _): name
        case .hostPort(let host, let port): "\(host):\(port)"
        default: "Mac"
        }
    }

    var bridgePriority: Int {
        guard case .service(_, _, _, let interface) = self else { return 2 }
        switch interface?.type {
        case .wifi: return 0
        case .wiredEthernet: return 1
        case .other, nil: return 2
        case .cellular: return 3
        case .loopback: return 4
        @unknown default: return 3
        }
    }
}

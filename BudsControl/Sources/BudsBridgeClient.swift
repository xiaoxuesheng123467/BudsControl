import Foundation
import Network
import Security

enum BridgePhase: Equatable {
    case searching
    case connecting(String)
    case pairing(String)
    case ready(String)
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
        case .unavailable(let reason):
            reason
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .searching, .connecting:
            true
        case .pairing, .ready, .unavailable:
            false
        }
    }
}

private struct BridgeStatusPayload: Decodable {
    let ready: Bool
    let serviceName: String?
    let deviceName: String?
    let message: String?
    let leftBattery: Int?
    let rightBattery: Int?
    let caseBattery: Int?
}

private struct BridgeCommandPayload: Decodable {
    let sent: Bool
    let message: String?
}

@MainActor
final class BudsBridgeClient: ObservableObject {
    @Published private(set) var phase: BridgePhase = .searching
    @Published private(set) var selectedNoiseMode: NoiseControlMode?
    @Published private(set) var selectedEqualizer: EqualizerPreset?
    @Published private(set) var isSending = false
    @Published private(set) var lastCommandMessage: String?
    @Published private(set) var leftBattery: Int?
    @Published private(set) var rightBattery: Int?
    @Published private(set) var caseBattery: Int?
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
    private let queue = DispatchQueue(label: "com.qiao.budscontrol.bridge-browser")
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var readyEndpoint: NWEndpoint?
    private var pollTask: Task<Void, Never>?
    private var statusRequestGeneration = 0

    var canControl: Bool { phase.isReady && endpoint == readyEndpoint && !isSending }

    init() {
        pairingCode = UserDefaults.standard.string(forKey: Self.pairingCodeKey) ?? ""
        startDiscovery()
    }

    deinit {
        browser?.cancel()
        pollTask?.cancel()
    }

    func restartDiscovery() {
        browser?.cancel()
        pollTask?.cancel()
        endpoint = nil
        readyEndpoint = nil
        selectedNoiseMode = nil
        selectedEqualizer = nil
        statusRequestGeneration += 1
        phase = .searching
        startDiscovery()
    }

    func refreshStatus() async {
        guard let endpoint else {
            phase = .searching
            return
        }
        guard pairingCode.count == 32 else {
            readyEndpoint = nil
            selectedNoiseMode = nil
            selectedEqualizer = nil
            phase = .pairing(endpoint.displayName)
            return
        }
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
            if status.ready {
                readyEndpoint = requestedEndpoint
                phase = .ready(serviceName)
            } else {
                readyEndpoint = nil
                selectedNoiseMode = nil
                selectedEqualizer = nil
                phase = .connecting(serviceName)
                lastCommandMessage = status.message
            }
        } catch BridgeHTTP.RequestError.authentication {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            readyEndpoint = nil
            selectedNoiseMode = nil
            selectedEqualizer = nil
            phase = .pairing(endpoint.displayName)
            lastCommandMessage = "配对密钥不正确"
        } catch BridgeHTTP.RequestError.server(let status, let message) where status == 401 {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            readyEndpoint = nil
            selectedNoiseMode = nil
            selectedEqualizer = nil
            phase = .pairing(endpoint.displayName)
            lastCommandMessage = message
        } catch {
            guard self.endpoint == requestedEndpoint, statusRequestGeneration == generation else { return }
            readyEndpoint = nil
            selectedNoiseMode = nil
            selectedEqualizer = nil
            phase = .unavailable("Mac 桥接暂不可用")
            lastCommandMessage = error.localizedDescription
        }
    }

    func setNoiseMode(_ mode: NoiseControlMode) async {
        guard mode != .adaptive else {
            lastCommandMessage = "自适应模式的数据包尚未完成真机验证"
            return
        }

        let value: Int
        switch mode {
        case .off: value = 0
        case .noiseCancelling: value = 1
        case .ambient: value = 2
        case .adaptive: return
        }

        let succeeded = await sendCommand(path: "/v1/noise", value: value)
        if succeeded {
            selectedNoiseMode = mode
            lastCommandMessage = "耳机已确认：\(mode.title)"
        }
    }

    func setEqualizer(_ preset: EqualizerPreset) async {
        let succeeded = await sendCommand(path: "/v1/equalizer", value: preset.rawValue)
        if succeeded {
            selectedEqualizer = preset
            lastCommandMessage = "耳机已确认：\(preset.title)"
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
        Task { await refreshStatus() }
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
                    if self.endpoint == nil { self.phase = .searching }
                case .failed(let error):
                    self.phase = .unavailable("桥接发现失败")
                    self.lastCommandMessage = error.localizedDescription
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
                    self.endpoint = nil
                    self.readyEndpoint = nil
                    self.selectedNoiseMode = nil
                    self.selectedEqualizer = nil
                    self.statusRequestGeneration += 1
                    self.phase = .searching
                    return
                }
                let first = ordered.first(where: { $0.endpoint == self.endpoint }) ?? ordered[0]
                let changed = self.endpoint != first.endpoint
                self.endpoint = first.endpoint
                if changed {
                    self.readyEndpoint = nil
                    self.selectedNoiseMode = nil
                    self.selectedEqualizer = nil
                    self.statusRequestGeneration += 1
                    self.phase = .connecting(first.endpoint.displayName)
                    self.beginPolling()
                }
                await self.refreshStatus()
            }
        }

        browser.start(queue: queue)
    }

    private func beginPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                if case .pairing = self?.phase { continue }
                await self?.refreshStatus()
            }
        }
    }

    private func sendCommand(path: String, value: Int) async -> Bool {
        guard let endpoint, endpoint == readyEndpoint, phase.isReady else {
            lastCommandMessage = "请先在 Mac 上启动 BudsBridge"
            return false
        }

        isSending = true
        defer { isSending = false }

        do {
            let data = try JSONSerialization.data(withJSONObject: ["value": value])
            let body = try await BridgeHTTP.request(
                endpoint: endpoint,
                method: "POST",
                path: path,
                pairingCode: pairingCode,
                body: data
            )
            let result = try JSONDecoder().decode(BridgeCommandPayload.self, from: body)
            guard result.sent else {
                lastCommandMessage = result.message ?? "耳机没有接受命令"
                return false
            }
            return true
        } catch {
            lastCommandMessage = error.localizedDescription
            await refreshStatus()
            return false
        }
    }
}

private enum BridgeHTTP {
    enum RequestError: LocalizedError {
        case authentication
        case connection(String)
        case invalidResponse
        case server(Int, String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .authentication: "配对密钥不正确"
            case .connection(let message): message
            case .invalidResponse: "Mac 桥接返回了无效响应"
            case .server(_, let message): message
            case .timedOut: "连接 Mac 桥接超时"
            }
        }

        static func from(_ error: NWError) -> RequestError {
            if case .tls = error { return .authentication }
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
            queue.asyncAfter(deadline: .now() + 5) { [self] in
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
                if let error {
                    finish(.failure(RequestError.from(error)))
                } else if isComplete {
                    finish(Result { try BridgeHTTP.parseResponse(response) })
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

import Foundation
import Network

/// Bonjour で Mac の SaberStage を探し、UDP で姿勢を送る。
/// `includePeerToPeer` を有効にしているので、同じ Wi-Fi に入っていなくても AWDL 経由でつながる。
/// 可変状態はすべて `queue` 上でだけ触る。
final class StageConnection: @unchecked Sendable {
    enum State: Sendable, Equatable {
        case searching
        case connecting(String)
        /// Mac からのハートビートが届いている
        case ready(String)
        case failed(String)
    }

    private let onStateChange: @Sendable (State) -> Void
    private let onMessage: @Sendable (StageMessage) -> Void
    private let queue = DispatchQueue(label: "jp.shilokuma.SaberMock.StageConnection", qos: .userInteractive)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var browser: NWBrowser?
    private var monitor: DispatchSourceTimer?
    private var connection: NWConnection?
    private var connectionName = ""
    private var connectedAt: TimeInterval = 0
    private var lastHeartbeat: TimeInterval?
    private var latestResults: Set<NWBrowser.Result> = []

    init(
        onStateChange: @escaping @Sendable (State) -> Void,
        onMessage: @escaping @Sendable (StageMessage) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onMessage = onMessage
    }

    func start() {
        queue.async {
            self.startBrowsing()
            self.startMonitor()
        }
    }

    func stop() {
        queue.async {
            self.browser?.cancel()
            self.browser = nil
            self.monitor?.cancel()
            self.monitor = nil
            self.disconnect()
        }
    }

    func send(_ message: ControllerMessage) {
        queue.async {
            guard let connection = self.connection, connection.state == .ready,
                  let data = try? self.encoder.encode(message) else { return }
            connection.send(content: data, completion: .idempotent)
        }
    }

    // MARK: - Browsing

    private func startBrowsing() {
        guard browser == nil else { return }
        onStateChange(.searching)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: ControllerProtocol.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.latestResults = results
            self?.connectIfNeeded()
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.onStateChange(.failed(error.localizedDescription))
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// ハートビートが途絶えた接続を捨てて、名前解決からやり直す
    private func startMonitor() {
        guard monitor == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, connection != nil else { return }
            let lastSign = lastHeartbeat ?? connectedAt
            if ProcessInfo.processInfo.systemUptime - lastSign > ControllerProtocol.heartbeatTimeout {
                disconnect()
                connectIfNeeded()
            }
        }
        timer.resume()
        monitor = timer
    }

    // MARK: - Connection

    private func connectIfNeeded() {
        guard connection == nil else { return }
        // 複数の Mac が見つかったときは名前順で最初のものにつなぐ
        guard let endpoint = latestResults.map(\.endpoint).min(by: { name(of: $0) < name(of: $1) }) else {
            onStateChange(.searching)
            return
        }
        let serviceName = name(of: endpoint)
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state, of: connection)
        }
        self.connection = connection
        connectionName = serviceName
        connectedAt = ProcessInfo.processInfo.systemUptime
        lastHeartbeat = nil
        onStateChange(.connecting(serviceName))
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func disconnect() {
        connection?.cancel()
        connection = nil
        lastHeartbeat = nil
    }

    private func handle(_ state: NWConnection.State, of connection: NWConnection) {
        guard self.connection === connection else { return }
        switch state {
        case .failed(let error), .waiting(let error):
            onStateChange(.failed(error.localizedDescription))
            disconnect()
            // 少し待ってからつなぎ直す
            queue.asyncAfter(deadline: .now() + 1) { self.connectIfNeeded() }
        default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.connection === connection else { return }
            if let data, let message = try? decoder.decode(StageMessage.self, from: data) {
                handle(message)
            }
            if error == nil {
                receive(on: connection)
            }
        }
    }

    private func handle(_ message: StageMessage) {
        switch message {
        case .heartbeat:
            if lastHeartbeat == nil {
                onStateChange(.ready(connectionName))
            }
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
        case .haptic:
            onMessage(message)
        }
    }

    private func name(of endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }
        return endpoint.debugDescription
    }
}

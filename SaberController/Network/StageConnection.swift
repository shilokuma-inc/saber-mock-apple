import Foundation
import Network

/// Bonjour で Mac の SaberStage を探し、UDP で姿勢を送る。
/// `includePeerToPeer` を有効にしているので、同じ Wi-Fi に入っていなくても AWDL 経由でつながる。
/// 可変状態はすべて `queue` 上でだけ触る。
final class StageConnection: @unchecked Sendable {
    enum State: Sendable, Equatable {
        case searching
        case connecting(String)
        case ready(String)
        case failed(String)
    }

    private let onStateChange: @Sendable (State) -> Void
    private let onMessage: @Sendable (StageMessage) -> Void
    private let queue = DispatchQueue(label: "jp.shilokuma.SaberMock.StageConnection", qos: .userInteractive)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var latestResults: Set<NWBrowser.Result> = []

    init(
        onStateChange: @escaping @Sendable (State) -> Void,
        onMessage: @escaping @Sendable (StageMessage) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onMessage = onMessage
    }

    func start() {
        queue.async { self.startBrowsing() }
    }

    func stop() {
        queue.async {
            self.browser?.cancel()
            self.browser = nil
            self.connection?.cancel()
            self.connection = nil
        }
    }

    func send(_ message: ControllerMessage) {
        queue.async {
            guard let connection = self.connection, connection.state == .ready,
                  let data = try? self.encoder.encode(message) else { return }
            connection.send(content: data, completion: .idempotent)
        }
    }

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
            self?.handle(state, of: connection, name: serviceName)
        }
        self.connection = connection
        onStateChange(.connecting(serviceName))
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func handle(_ state: NWConnection.State, of connection: NWConnection, name: String) {
        switch state {
        case .ready:
            onStateChange(.ready(name))
        case .failed(let error), .waiting(let error):
            onStateChange(.failed(error.localizedDescription))
            connection.cancel()
            if self.connection === connection {
                self.connection = nil
            }
            // 少し待ってからつなぎ直す
            queue.asyncAfter(deadline: .now() + 1) { self.connectIfNeeded() }
        default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let message = try? self.decoder.decode(StageMessage.self, from: data) {
                self.onMessage(message)
            }
            if error == nil, self.connection === connection {
                self.receive(on: connection)
            }
        }
    }

    private func name(of endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }
        return endpoint.debugDescription
    }
}

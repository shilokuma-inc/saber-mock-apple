import Foundation
import Network

enum ListenerStatus: Sendable, Equatable {
    case starting
    case ready(port: UInt16)
    case failed(String)
}

/// iPhone コントローラーからの UDP を受ける。
/// Bonjour で `_sabermock._udp` を広告し、`includePeerToPeer` で Wi-Fi ルーターが無い場所でも
/// AWDL（ピアツーピア Wi-Fi）経由でつながるようにしている。
/// 可変状態はすべて `queue` 上でだけ触る。
final class ControllerServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jp.shilokuma.SaberMock.ControllerServer", qos: .userInteractive)
    private let store: ControllerStore
    private let onStatusChange: @Sendable (ListenerStatus) -> Void
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// 振動を返す先。最後にその手のデータを送ってきた接続
    private var connectionByHand: [Hand: NWConnection] = [:]

    init(store: ControllerStore, onStatusChange: @escaping @Sendable (ListenerStatus) -> Void) {
        self.store = store
        self.onStatusChange = onStatusChange
    }

    func start() {
        queue.async { self.startListener() }
    }

    func sendHaptic(to hand: Hand, intensity: Double) {
        queue.async {
            guard let connection = self.connectionByHand[hand],
                  let data = try? self.encoder.encode(StageMessage.haptic(intensity: intensity)) else { return }
            connection.send(content: data, completion: .idempotent)
        }
    }

    private func startListener() {
        guard listener == nil else { return }
        onStatusChange(.starting)
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        do {
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(type: ControllerProtocol.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            onStatusChange(.failed(error.localizedDescription))
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            onStatusChange(.ready(port: listener?.port?.rawValue ?? 0))
        case .failed(let error):
            onStatusChange(.failed(error.localizedDescription))
            listener?.cancel()
            listener = nil
            // 少し待って張り直す
            queue.asyncAfter(deadline: .now() + 2) { self.startListener() }
        case .waiting(let error):
            onStatusChange(.failed(error.localizedDescription))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.remove(key)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func remove(_ key: ObjectIdentifier) {
        guard let connection = connections.removeValue(forKey: key) else { return }
        connectionByHand = connectionByHand.filter { $0.value !== connection }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let message = try? self.decoder.decode(ControllerMessage.self, from: data) {
                self.handle(message, from: connection)
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }

    private func handle(_ message: ControllerMessage, from connection: NWConnection) {
        switch message {
        case .motion(let sample):
            connectionByHand[sample.hand] = connection
            store.update(with: sample)
        case .calibrate(let hand):
            connectionByHand[hand] = connection
            store.calibrate(hand)
        }
    }
}

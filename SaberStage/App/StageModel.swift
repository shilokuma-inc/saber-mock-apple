import Observation

/// Mac アプリ全体の組み立てと、HUD に出す状態を持つ
@MainActor
@Observable
final class StageModel {
    private(set) var hud = HUDSnapshot()
    private(set) var listenerStatus = ListenerStatus.starting

    @ObservationIgnored let engine: GameEngine
    @ObservationIgnored private let store: ControllerStore
    @ObservationIgnored private let server: ControllerServer

    init() {
        // 受信スレッド・描画スレッドから届く更新を、初期化後の self に中継する
        let relay = Relay()
        let store = ControllerStore()
        let server = ControllerServer(store: store) { status in
            Task { @MainActor in relay.model?.listenerStatus = status }
        }
        self.store = store
        self.server = server
        self.engine = GameEngine(
            store: store,
            haptics: { hand, intensity in server.sendHaptic(to: hand, intensity: intensity) },
            onHUDChange: { snapshot in
                Task { @MainActor in relay.model?.hud = snapshot }
            }
        )
        relay.model = self
    }

    func start() {
        server.start()
    }

    func togglePlaying() {
        engine.send(hud.isPlaying ? .stop : .start)
    }

    func calibrateAll() {
        store.calibrateAll()
    }

    @MainActor
    private final class Relay {
        weak var model: StageModel?
    }
}

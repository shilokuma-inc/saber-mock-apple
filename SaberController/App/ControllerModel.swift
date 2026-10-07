import Observation
import Synchronization
import UIKit

@MainActor
@Observable
final class ControllerModel {
    private static let handKey = "selectedHand"

    var hand: Hand {
        didSet {
            guard hand != oldValue else { return }
            UserDefaults.standard.set(hand.rawValue, forKey: Self.handKey)
            sequencer.setHand(hand)
            if isRunning {
                // 疑似モーションは手によって振る位置が変わるので作り直す
                stopMotion()
                startMotion()
            }
        }
    }

    private(set) var connectionState = StageConnection.State.searching
    private(set) var calibrationCount = 0
    let usesDemoMotion: Bool

    @ObservationIgnored private var connection: StageConnection?
    @ObservationIgnored private var motionSource: (any MotionSource)?
    @ObservationIgnored private let sequencer: Sequencer
    @ObservationIgnored private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private var isRunning = false

    init() {
        let savedHand = UserDefaults.standard.string(forKey: Self.handKey).flatMap(Hand.init(rawValue:))
        let hand = savedHand ?? .right
        self.hand = hand
        self.sequencer = Sequencer(hand: hand)
        self.usesDemoMotion = !DeviceMotionSource().isAvailable
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let connection = StageConnection(
            onStateChange: { [weak self] state in
                Task { @MainActor in self?.connectionState = state }
            },
            onMessage: { [weak self] message in
                Task { @MainActor in self?.handle(message) }
            }
        )
        self.connection = connection
        connection.start()
        startMotion()
        haptic.prepare()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopMotion()
        connection?.stop()
        connection = nil
    }

    /// 今の向きを画面の正面として Mac に合わせてもらう
    func calibrate() {
        connection?.send(.calibrate(hand))
        calibrationCount += 1
    }

    private func startMotion() {
        guard let connection else { return }
        let source: any MotionSource = usesDemoMotion ? DemoMotionSource(hand: hand) : DeviceMotionSource()
        let sequencer = sequencer
        source.start { attitude, rotationRate in
            connection.send(.motion(sequencer.makeSample(attitude: attitude, rotationRate: rotationRate)))
        }
        motionSource = source
    }

    private func stopMotion() {
        motionSource?.stop()
        motionSource = nil
    }

    private func handle(_ message: StageMessage) {
        switch message {
        case .haptic(let intensity):
            haptic.impactOccurred(intensity: intensity)
            haptic.prepare()
        }
    }
}

/// モーションの受信スレッドで連番と手の情報を付けてサンプルを作る
private final class Sequencer: Sendable {
    private let state: Mutex<(hand: Hand, sequence: UInt32)>

    init(hand: Hand) {
        state = Mutex((hand, 0))
    }

    func setHand(_ hand: Hand) {
        state.withLock { $0.hand = hand }
    }

    func makeSample(attitude: Quaternion, rotationRate: Vector3) -> MotionSample {
        let (hand, sequence) = state.withLock { state in
            state.sequence &+= 1
            return (state.hand, state.sequence)
        }
        return MotionSample(hand: hand, sequence: sequence, attitude: attitude, rotationRate: rotationRate)
    }
}

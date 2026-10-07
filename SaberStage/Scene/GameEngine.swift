import AppKit
import SceneKit
import Synchronization
import simd

enum GameCommand: Sendable {
    case start
    case stop
}

enum JudgementKind: Sendable, Equatable {
    case good
    case bad
    case miss
}

struct ControllerStatus: Sendable, Equatable {
    var isConnected = false
    var isCalibrated = false
    var packetRate = 0
}

/// HUD に表示する値
struct HUDSnapshot: Sendable, Equatable {
    var isPlaying = false
    var scoreBoard = ScoreBoard()
    var lastJudgement: JudgementKind?
    /// 同じ判定が続いても表示を更新するための通し番号
    var judgementSerial = 0
    var controllers: [Hand: ControllerStatus] = [:]
}

/// ゲームループ。SceneKit の描画スレッドから毎フレーム呼ばれる。
/// ノードとゲームの状態は描画スレッドでだけ触り、外からの操作は `send(_:)` でコマンドとして渡す。
final class GameEngine: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    let scene: SCNScene
    let cameraNode: SCNNode

    private let store: ControllerStore
    private let haptics: @Sendable (Hand, Double) -> Void
    private let onHUDChange: @Sendable (HUDSnapshot) -> Void
    private let commands = Mutex<[GameCommand]>([])

    // 以下は描画スレッド専用
    private let saberNodes: [Hand: SCNNode]
    private var previousPoses: [Hand: BladePose] = [:]
    private var activeNotes: [ActiveNote] = []
    private var pendingNotes: [Note] = []
    private var chart = ChartGenerator()
    private var songTime: Double = 0
    private var lastFrameTime: TimeInterval?
    private var hud = HUDSnapshot()
    private var publishedHUD: HUDSnapshot?

    private struct ActiveNote {
        let note: Note
        let node: SCNNode
    }

    private struct Swing {
        let previous: BladePose
        let current: BladePose
        let tipVelocity: SIMD3<Double>
    }

    init(
        store: ControllerStore,
        haptics: @escaping @Sendable (Hand, Double) -> Void,
        onHUDChange: @escaping @Sendable (HUDSnapshot) -> Void
    ) {
        self.store = store
        self.haptics = haptics
        self.onHUDChange = onHUDChange
        (scene, cameraNode) = StageSceneBuilder.makeScene()
        var saberNodes: [Hand: SCNNode] = [:]
        for hand in Hand.allCases {
            let node = StageSceneBuilder.makeSaber(for: hand)
            scene.rootNode.addChildNode(node)
            saberNodes[hand] = node
        }
        self.saberNodes = saberNodes
        super.init()
    }

    func send(_ command: GameCommand) {
        commands.withLock { $0.append(command) }
    }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let deltaTime = lastFrameTime.map { min(time - $0, 0.1) } ?? 0
        lastFrameTime = time
        applyCommands()

        let readings = store.readings()
        let swings = updateSabers(with: readings)
        if hud.isPlaying, deltaTime > 0 {
            advance(by: deltaTime, swings: swings)
        }
        hud.controllers = readings.mapValues {
            ControllerStatus(isConnected: $0.isConnected, isCalibrated: $0.isCalibrated, packetRate: $0.packetRate)
        }
        if hud != publishedHUD {
            publishedHUD = hud
            onHUDChange(hud)
        }
    }

    // MARK: - Commands

    private func applyCommands() {
        let pending = commands.withLock { commands in
            let pending = commands
            commands.removeAll()
            return pending
        }
        for command in pending {
            switch command {
            case .start:
                clearNotes()
                chart = ChartGenerator()
                songTime = 0
                hud.scoreBoard = ScoreBoard()
                hud.lastJudgement = nil
                hud.isPlaying = true
            case .stop:
                clearNotes()
                hud.isPlaying = false
            }
        }
    }

    private func clearNotes() {
        for active in activeNotes {
            active.node.removeFromParentNode()
        }
        activeNotes.removeAll()
        pendingNotes.removeAll()
    }

    // MARK: - Sabers

    private func updateSabers(with readings: [Hand: ControllerReading]) -> [Hand: Swing] {
        var swings: [Hand: Swing] = [:]
        for hand in Hand.allCases {
            let orientation: simd_quatd
            let rotationRate: SIMD3<Double>
            if let reading = readings[hand], reading.isConnected {
                orientation = SaberMath.worldOrientation(attitude: reading.attitude, yawOffset: reading.yawOffset ?? 0)
                rotationRate = reading.rotationRate
            } else {
                orientation = SaberRig.restingOrientation(for: hand)
                rotationRate = .zero
            }
            let pose = SaberRig.pose(for: hand, orientation: orientation)
            if let node = saberNodes[hand] {
                node.simdPosition = SIMD3<Float>(pose.grip)
                node.simdOrientation = simd_quatf(vector: SIMD4<Float>(orientation.vector))
            }
            swings[hand] = Swing(
                previous: previousPoses[hand] ?? pose,
                current: pose,
                tipVelocity: SaberRig.tipVelocity(
                    for: hand,
                    orientation: orientation,
                    rotationRate: rotationRate,
                    tip: pose.tip
                )
            )
            previousPoses[hand] = pose
        }
        return swings
    }

    // MARK: - Notes

    private func advance(by deltaTime: Double, swings: [Hand: Swing]) {
        songTime += deltaTime
        spawnNotes()

        var remaining: [ActiveNote] = []
        for active in activeNotes {
            let position = StageLayout.position(of: active.note, at: songTime)
            active.node.simdPosition = SIMD3<Float>(position)

            if let (hand, judgement, swing) = detectCut(of: active.note, at: position, swings: swings) {
                resolveCut(active, by: hand, judgement: judgement, swing: swing)
            } else if position.z > StageLayout.missZ {
                active.node.removeFromParentNode()
                hud.scoreBoard.registerMiss()
                showJudgement(.miss)
            } else {
                remaining.append(active)
            }
        }
        activeNotes = remaining
    }

    private func spawnNotes() {
        while true {
            if pendingNotes.isEmpty {
                pendingNotes = chart.nextBeat()
            }
            guard let next = pendingNotes.first, next.time - songTime <= StageLayout.travelTime else { return }
            pendingNotes.removeFirst()
            let node = StageSceneBuilder.makeNote(next)
            node.simdPosition = SIMD3<Float>(StageLayout.position(of: next, at: songTime))
            scene.rootNode.addChildNode(node)
            activeNotes.append(ActiveNote(note: next, node: node))
        }
    }

    private func detectCut(
        of note: Note,
        at position: SIMD3<Double>,
        swings: [Hand: Swing]
    ) -> (Hand, CutJudgement, Swing)? {
        // 刃が届かない奥のノーツは調べない
        guard position.z > StageLayout.hitZ - 1.5 else { return nil }
        for hand in Hand.allCases {
            guard let swing = swings[hand],
                  HitJudge.sweptHit(
                      from: swing.previous,
                      to: swing.current,
                      center: position,
                      halfExtent: StageLayout.hitHalfExtent
                  ) else { continue }
            let judgement = HitJudge.judge(
                noteColor: note.color,
                noteDirection: note.direction,
                saber: hand,
                tipVelocity: swing.tipVelocity
            )
            if judgement != .tooSlow {
                return (hand, judgement, swing)
            }
        }
        return nil
    }

    private func resolveCut(_ active: ActiveNote, by hand: Hand, judgement: CutJudgement, swing: Swing) {
        if judgement == .good {
            active.node.removeFromParentNode()
            let halves = StageSceneBuilder.makeSlicedHalves(
                color: active.note.color,
                at: active.node.simdPosition,
                swing: SIMD2(swing.tipVelocity.x, swing.tipVelocity.y)
            )
            scene.rootNode.addChildNode(halves)
            hud.scoreBoard.registerGood()
            showJudgement(.good)
            haptics(hand, 1)
            Self.playHitSound()
        } else {
            StageSceneBuilder.runBadCutAnimation(on: active.node)
            hud.scoreBoard.registerBad()
            showJudgement(.bad)
            haptics(hand, 0.4)
        }
    }

    private func showJudgement(_ kind: JudgementKind) {
        hud.lastJudgement = kind
        hud.judgementSerial += 1
    }

    private static func playHitSound() {
        DispatchQueue.main.async {
            (NSSound(named: "Pop")?.copy() as? NSSound)?.play()
        }
    }
}

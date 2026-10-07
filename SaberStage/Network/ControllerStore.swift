import Foundation
import Synchronization
import simd

/// 描画側に渡すコントローラーの最新状態
struct ControllerReading: Sendable {
    var attitude: simd_quatd
    /// 端末座標での角速度（rad/s）
    var rotationRate: SIMD3<Double>
    /// nil のときはまだ向きを合わせられていない
    var yawOffset: Double?
    var isConnected: Bool
    /// ユーザーが明示的にキャリブレーションしたか（初回受信時の自動補正だけなら false）
    var isCalibrated: Bool
    var packetRate: Int
}

/// iPhone から届いた最新の姿勢を保持する。
/// 受信スレッドで書き込み、描画スレッドで読み出すため Mutex で守る。
final class ControllerStore: Sendable {
    private struct Entry {
        var attitude = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        var rotationRate = SIMD3<Double>.zero
        var yawOffset: Double?
        var isCalibrated = false
        var lastReceived: TimeInterval = -.infinity
        var windowStart: TimeInterval = 0
        var windowCount = 0
        var packetRate = 0
    }

    /// 最後の受信からこの秒数を過ぎたら未接続とみなす
    static let connectionTimeout: TimeInterval = 1

    private let entries = Mutex<[Hand: Entry]>([:])
    private let clock: @Sendable () -> TimeInterval

    init(clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    func update(with sample: MotionSample) {
        let now = clock()
        entries.withLock { entries in
            var entry = entries[sample.hand] ?? Entry()
            entry.attitude = simd_quatd(sample.attitude)
            entry.rotationRate = SIMD3(sample.rotationRate.x, sample.rotationRate.y, sample.rotationRate.z)
            if entry.yawOffset == nil {
                // 最初の 1 回は、そのとき向いている方向をひとまず正面にしておく
                entry.yawOffset = SaberMath.calibrationYaw(for: entry.attitude)
            }
            entry.lastReceived = now
            entry.windowCount += 1
            let elapsed = now - entry.windowStart
            if elapsed >= 1 {
                entry.packetRate = Int((Double(entry.windowCount) / elapsed).rounded())
                entry.windowStart = now
                entry.windowCount = 0
            }
            entries[sample.hand] = entry
        }
    }

    /// 今の向きを画面の正面に合わせる。剣先が真上・真下を向いているなどで合わせられなければ false
    @discardableResult
    func calibrate(_ hand: Hand) -> Bool {
        entries.withLock { entries in
            guard var entry = entries[hand], let yaw = SaberMath.calibrationYaw(for: entry.attitude) else {
                return false
            }
            entry.yawOffset = yaw
            entry.isCalibrated = true
            entries[hand] = entry
            return true
        }
    }

    func calibrateAll() {
        for hand in Hand.allCases {
            calibrate(hand)
        }
    }

    func readings() -> [Hand: ControllerReading] {
        let now = clock()
        return entries.withLock { entries in
            entries.mapValues { entry in
                let isConnected = now - entry.lastReceived < Self.connectionTimeout
                return ControllerReading(
                    attitude: entry.attitude,
                    rotationRate: entry.rotationRate,
                    yawOffset: entry.yawOffset,
                    isConnected: isConnected,
                    isCalibrated: entry.isCalibrated,
                    packetRate: isConnected ? entry.packetRate : 0
                )
            }
        }
    }
}

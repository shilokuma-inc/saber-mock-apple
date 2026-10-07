import CoreMotion
import Foundation
import simd

/// 姿勢と角速度の供給元
protocol MotionSource: AnyObject {
    func start(handler: @escaping @Sendable (Quaternion, Vector3) -> Void)
    func stop()
}

/// 実機の CoreMotion から姿勢を取る
final class DeviceMotionSource: MotionSource {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(handler: @escaping @Sendable (Quaternion, Vector3) -> Void) {
        manager.deviceMotionUpdateInterval = 1.0 / 100
        // Z が鉛直上向き。水平方向の基準は任意だが、Mac 側のキャリブレーションで正面に合わせる
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { motion, _ in
            guard let motion else { return }
            let attitude = motion.attitude.quaternion
            let rate = motion.rotationRate
            handler(
                Quaternion(x: attitude.x, y: attitude.y, z: attitude.z, w: attitude.w),
                Vector3(x: rate.x, y: rate.y, z: rate.z)
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

/// Simulator など CoreMotion が使えない環境向けの疑似モーション。
/// 正面に向けたまま、振り下ろしと振り上げを一定のリズムで繰り返す。
final class DemoMotionSource: MotionSource, @unchecked Sendable {
    private let hand: Hand
    private let queue = DispatchQueue(label: "jp.shilokuma.SaberMock.DemoMotion", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    /// 1 往復（振り下ろし + 振り上げ）の秒数
    private let period = 1.2

    init(hand: Hand) {
        self.hand = hand
    }

    func start(handler: @escaping @Sendable (Quaternion, Vector3) -> Void) {
        let startTime = ProcessInfo.processInfo.systemUptime
        let baseYaw = hand == .left ? 0.25 : -0.25
        let angularFrequency = 2 * Double.pi / period
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler {
            let elapsed = ProcessInfo.processInfo.systemUptime - startTime
            // 端末を水平に置いた状態から、Z 軸回り（ヨー）→ X 軸回り（ピッチ）の順に回す
            let pitch = 0.2 + 0.9 * sin(elapsed * angularFrequency)
            let pitchRate = 0.9 * angularFrequency * cos(elapsed * angularFrequency)
            let attitude = simd_quatd(angle: baseYaw, axis: SIMD3(0, 0, 1))
                * simd_quatd(angle: pitch, axis: SIMD3(1, 0, 0))
            handler(Quaternion(attitude), Vector3(x: pitchRate, y: 0, z: 0))
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

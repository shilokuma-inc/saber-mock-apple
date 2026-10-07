import Foundation
import simd
import Testing
@testable import SaberStage

struct SaberMathTests {
    private func isClose(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>, tolerance: Double = 1e-9) -> Bool {
        simd_length(lhs - rhs) < tolerance
    }

    @Test(arguments: [0.0, 0.7, -1.3, Double.pi])
    func calibratedForwardPointsIntoScreen(heading: Double) throws {
        // 剣先を水平に構え、参照座標で任意の方向を向いている状態
        let attitude = simd_quatd(angle: heading, axis: SIMD3(0, 0, 1))
        let yaw = try #require(SaberMath.calibrationYaw(for: attitude))

        let orientation = SaberMath.worldOrientation(attitude: attitude, yawOffset: yaw)

        #expect(isClose(orientation.act(SaberMath.bladeAxis), SIMD3(0, 0, -1)))
    }

    @Test
    func pitchIsKeptAfterCalibration() throws {
        let attitude = simd_quatd(angle: 0.4, axis: SIMD3(0, 0, 1))
        let yaw = try #require(SaberMath.calibrationYaw(for: attitude))
        // キャリブレーション後に剣先を 30° 上げる
        let raised = attitude * simd_quatd(angle: .pi / 6, axis: SIMD3(1, 0, 0))

        let blade = SaberMath.worldOrientation(attitude: raised, yawOffset: yaw).act(SaberMath.bladeAxis)

        #expect(isClose(blade, SIMD3(0, sin(.pi / 6), -cos(.pi / 6))))
    }

    @Test
    func turningLeftMovesBladeToNegativeX() throws {
        let attitude = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        let yaw = try #require(SaberMath.calibrationYaw(for: attitude))
        // 上から見て反時計回り（左）に 90° 向ける
        let turned = simd_quatd(angle: .pi / 2, axis: SIMD3(0, 0, 1)) * attitude

        let blade = SaberMath.worldOrientation(attitude: turned, yawOffset: yaw).act(SaberMath.bladeAxis)

        #expect(isClose(blade, SIMD3(-1, 0, 0)))
    }

    @Test
    func calibrationIsRejectedWhenPointingStraightUp() {
        let pointingUp = simd_quatd(angle: .pi / 2, axis: SIMD3(1, 0, 0))

        #expect(SaberMath.calibrationYaw(for: pointingUp) == nil)
    }

    @Test
    func tipVelocityOfDownSwingPointsDown() {
        // 正面を向いた状態から、端末の X 軸回りに剣先を下げる方向へ回す
        let orientation = SaberMath.referenceToWorld
        let pose = SaberRig.pose(for: .right, orientation: orientation)

        let velocity = SaberRig.tipVelocity(
            for: .right,
            orientation: orientation,
            rotationRate: SIMD3(-5, 0, 0),
            tip: pose.tip
        )

        #expect(velocity.y < -5)
        #expect(abs(velocity.x) < 1e-9)
    }
}

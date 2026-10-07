import Synchronization
import simd
import Testing
@testable import SaberStage

struct ControllerStoreTests {
    private final class FakeClock: Sendable {
        private let value = Mutex<Double>(100)

        var now: Double { value.withLock { $0 } }

        func advance(by seconds: Double) {
            value.withLock { $0 += seconds }
        }
    }

    private func sample(_ hand: Hand, heading: Double) -> MotionSample {
        MotionSample(
            hand: hand,
            sequence: 0,
            attitude: Quaternion(simd_quatd(angle: heading, axis: SIMD3(0, 0, 1))),
            rotationRate: .zero
        )
    }

    @Test
    func firstSampleIsAutoCalibratedButNotMarkedCalibrated() throws {
        let clock = FakeClock()
        let store = ControllerStore(clock: { clock.now })

        store.update(with: sample(.left, heading: 1.0))

        let reading = try #require(store.readings()[.left])
        #expect(reading.isConnected)
        #expect(!reading.isCalibrated)
        let blade = SaberMath.worldOrientation(attitude: reading.attitude, yawOffset: try #require(reading.yawOffset))
            .act(SaberMath.bladeAxis)
        #expect(simd_length(blade - SIMD3(0, 0, -1)) < 1e-9)
    }

    @Test
    func calibrateUsesLatestAttitude() throws {
        let clock = FakeClock()
        let store = ControllerStore(clock: { clock.now })
        store.update(with: sample(.right, heading: 0))
        store.update(with: sample(.right, heading: 0.5))

        #expect(store.calibrate(.right))

        let reading = try #require(store.readings()[.right])
        #expect(reading.isCalibrated)
        // 剣先（端末の +Y）は向き 0 のときすでに正面なので、補正は回した分を戻すだけになる
        #expect(abs(try #require(reading.yawOffset) - (-0.5)) < 1e-9)
    }

    @Test
    func calibrateWithoutDataFails() {
        let store = ControllerStore()

        #expect(!store.calibrate(.left))
    }

    @Test
    func controllerTimesOutWithoutPackets() throws {
        let clock = FakeClock()
        let store = ControllerStore(clock: { clock.now })
        store.update(with: sample(.left, heading: 0))

        clock.advance(by: ControllerStore.connectionTimeout + 0.1)

        #expect(try #require(store.readings()[.left]).isConnected == false)
    }
}

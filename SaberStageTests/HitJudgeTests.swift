import simd
import Testing
@testable import SaberStage

struct HitJudgeTests {
    private func blade(tipX: Double, tipY: Double) -> BladePose {
        let grip = SIMD3<Double>(0, 1.1, 0)
        let tip = SIMD3(tipX, tipY, -1.2)
        return BladePose(grip: grip, base: grip + (tip - grip) * 0.15, tip: tip)
    }

    @Test
    func sweepThroughNoteIsDetectedEvenIfBothFramesMiss() {
        // 前フレームはノーツの上、今フレームはノーツの下。どちらの姿勢も箱には入っていない
        let above = blade(tipX: 0, tipY: 2.0)
        let below = blade(tipX: 0, tipY: 0.2)
        let center = SIMD3<Double>(0, 1.1, -1.0)

        #expect(!HitJudge.sweptHit(from: above, to: above, center: center, halfExtent: 0.2))
        #expect(!HitJudge.sweptHit(from: below, to: below, center: center, halfExtent: 0.2))
        #expect(HitJudge.sweptHit(from: above, to: below, center: center, halfExtent: 0.2))
    }

    @Test
    func sweepBesideNoteIsNotDetected() {
        let above = blade(tipX: 0.8, tipY: 2.0)
        let below = blade(tipX: 0.8, tipY: 0.2)

        #expect(!HitJudge.sweptHit(from: above, to: below, center: SIMD3(-0.5, 1.1, -1.0), halfExtent: 0.2))
    }

    @Test
    func downSwingOnDownNoteIsGood() {
        let judgement = HitJudge.judge(noteColor: .left, noteDirection: .down, saber: .left, tipVelocity: SIMD3(0.3, -4, 1))

        #expect(judgement == .good)
    }

    @Test
    func upSwingOnDownNoteIsWrongDirection() {
        let judgement = HitJudge.judge(noteColor: .left, noteDirection: .down, saber: .left, tipVelocity: SIMD3(0, 4, 0))

        #expect(judgement == .wrongDirection)
    }

    @Test
    func otherSaberIsWrongColor() {
        let judgement = HitJudge.judge(noteColor: .left, noteDirection: .any, saber: .right, tipVelocity: SIMD3(0, -4, 0))

        #expect(judgement == .wrongColor)
    }

    @Test
    func slowTouchIsIgnored() {
        // 画面と垂直な方向（突き）はいくら速くても振りとはみなさない
        let judgement = HitJudge.judge(noteColor: .right, noteDirection: .any, saber: .right, tipVelocity: SIMD3(0.5, 0.5, -6))

        #expect(judgement == .tooSlow)
    }
}

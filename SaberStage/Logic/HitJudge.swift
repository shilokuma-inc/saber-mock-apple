import simd

/// ノーツに描かれた矢印（斬る方向）
enum CutDirection: CaseIterable, Sendable {
    case up
    case down
    case left
    case right
    /// 方向は問わない（丸印）
    case any

    /// 画面に向かって見たときの XY 平面上の向き
    var vector: SIMD2<Double>? {
        switch self {
        case .up: SIMD2(0, 1)
        case .down: SIMD2(0, -1)
        case .left: SIMD2(-1, 0)
        case .right: SIMD2(1, 0)
        case .any: nil
        }
    }
}

enum CutJudgement: Equatable, Sendable {
    case good
    case wrongColor
    case wrongDirection
    /// 振りが遅すぎるので斬ったことにしない（そのまま通過すればミスになる）
    case tooSlow
}

enum HitJudge {
    /// 前フレームから今フレームまでに刃が掃いた範囲が、立方体のノーツに触れたか。
    /// 高速で振ると 1 フレームで刃が大きく動くため、2 つの姿勢の間を補間して点で調べる。
    static func sweptHit(
        from previous: BladePose,
        to current: BladePose,
        center: SIMD3<Double>,
        halfExtent: Double,
        subSteps: Int = 8,
        samplesPerBlade: Int = 12
    ) -> Bool {
        let extent = SIMD3(repeating: halfExtent)
        for step in 0...subSteps {
            let t = Double(step) / Double(subSteps)
            let base = simd_mix(previous.base, current.base, SIMD3(repeating: t))
            let tip = simd_mix(previous.tip, current.tip, SIMD3(repeating: t))
            for sample in 0...samplesPerBlade {
                let u = Double(sample) / Double(samplesPerBlade)
                let point = base + (tip - base) * u
                if all(abs(point - center) .<= extent) {
                    return true
                }
            }
        }
        return false
    }

    /// 刃がノーツに触れたときの判定。
    /// 振りの方向は剣先の速度を画面と平行な面（XY）に投影して求める。
    static func judge(
        noteColor: Hand,
        noteDirection: CutDirection,
        saber: Hand,
        tipVelocity: SIMD3<Double>,
        minSpeed: Double = 1.5,
        minAlignment: Double = 0.4
    ) -> CutJudgement {
        let planar = SIMD2(tipVelocity.x, tipVelocity.y)
        let speed = simd_length(planar)
        guard speed >= minSpeed else { return .tooSlow }
        guard noteColor == saber else { return .wrongColor }
        if let required = noteDirection.vector, simd_dot(planar / speed, required) < minAlignment {
            return .wrongDirection
        }
        return .good
    }
}

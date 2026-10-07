import simd

/// 座標系の約束
/// - CoreMotion の参照座標（`.xArbitraryCorrectedZVertical`）: Z が鉛直上向き。水平の X/Y の向きは起動ごとに任意
/// - SceneKit のワールド座標: Y が上、-Z が画面の奥（プレイヤーの正面）。単位はメートル
/// - iPhone の上端（端末座標の +Y）を剣先の向きとして扱う
enum SaberMath {
    static let bladeAxis = SIMD3<Double>(0, 1, 0)

    /// 参照座標 → ワールド座標（参照の +Y がワールドの -Z、参照の +Z がワールドの +Y になる）
    static let referenceToWorld = simd_quatd(angle: -.pi / 2, axis: SIMD3(1, 0, 0))

    /// 剣先の水平方向を参照座標の +Y（= ワールドの正面）に合わせるためのヨー角。
    /// 剣先がほぼ真上・真下を向いていて水平方向が決まらないときは nil を返す。
    static func calibrationYaw(for attitude: simd_quatd) -> Double? {
        let blade = attitude.act(bladeAxis)
        let horizontal = SIMD2(blade.x, blade.y)
        guard simd_length(horizontal) > 0.3 else { return nil }
        return .pi / 2 - atan2(horizontal.y, horizontal.x)
    }

    /// iPhone の姿勢をワールド座標での向きに変換する。
    /// ヨーだけを補正し、ピッチ・ロールは重力基準の値をそのまま使う。
    static func worldOrientation(attitude: simd_quatd, yawOffset: Double) -> simd_quatd {
        referenceToWorld * simd_quatd(angle: yawOffset, axis: SIMD3(0, 0, 1)) * attitude
    }
}

/// 刃の位置（ワールド座標）
struct BladePose: Sendable, Equatable {
    /// 手で握っている位置
    var grip: SIMD3<Double>
    /// 刃の根元
    var base: SIMD3<Double>
    /// 剣先
    var tip: SIMD3<Double>
}

/// 手の位置を推定する簡易アームモデル。
/// iPhone からは向きしか取れないため、肩を固定の支点とし、剣先の方向へ腕を伸ばした位置に手があるとみなす。
enum SaberRig {
    static let shoulderHeight = 1.3
    static let shoulderOffsetX = 0.2
    static let armReach = 0.3
    static let hiltLength = 0.15
    static let bladeLength = 1.0

    static func shoulder(for hand: Hand) -> SIMD3<Double> {
        SIMD3(hand == .left ? -shoulderOffsetX : shoulderOffsetX, shoulderHeight, 0)
    }

    static func pose(for hand: Hand, orientation: simd_quatd) -> BladePose {
        let direction = orientation.act(SaberMath.bladeAxis)
        let grip = shoulder(for: hand) + direction * armReach
        return BladePose(
            grip: grip,
            base: grip + direction * hiltLength,
            tip: grip + direction * (hiltLength + bladeLength)
        )
    }

    /// 剣先の速度。ジャイロの角速度から求めるので、描画のフレーム間隔や受信の揺らぎに左右されない
    static func tipVelocity(
        for hand: Hand,
        orientation: simd_quatd,
        rotationRate: SIMD3<Double>,
        tip: SIMD3<Double>
    ) -> SIMD3<Double> {
        let angularVelocity = orientation.act(rotationRate)
        return simd_cross(angularVelocity, tip - shoulder(for: hand))
    }

    /// コントローラーが未接続のときの構え（正面やや外側に、斜め上へ向ける）
    static func restingOrientation(for hand: Hand) -> simd_quatd {
        let yaw = hand == .left ? 0.25 : -0.25
        return simd_quatd(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatd(angle: -0.95, axis: SIMD3(1, 0, 0))
    }
}

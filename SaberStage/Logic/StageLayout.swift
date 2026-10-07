import simd

/// ステージの寸法（ワールド座標、単位はメートル）
enum StageLayout {
    static let laneX: [Double] = [-0.54, -0.18, 0.18, 0.54]
    static let rowY: [Double] = [0.75, 1.1, 1.45]
    /// ノーツを斬る位置（プレイヤーの少し前）
    static let hitZ = -1.0
    static let spawnZ = -24.0
    /// ここを過ぎたノーツはミス
    static let missZ = 0.6
    static let noteSpeed = 11.0
    static let noteSize = 0.3
    /// 当たり判定の半径。見た目（noteSize / 2）より少しだけ広くして判定を甘くしている
    static let hitHalfExtent = 0.2

    /// 出現してからヒット位置に届くまでの秒数
    static var travelTime: Double { (hitZ - spawnZ) / noteSpeed }

    static func position(of note: Note, at songTime: Double) -> SIMD3<Double> {
        SIMD3(laneX[note.lane], rowY[note.row], hitZ - (note.time - songTime) * noteSpeed)
    }
}

/// 1 つのノーツ
struct Note: Sendable, Equatable, Identifiable {
    let id: Int
    /// ヒット位置に到達する時刻（曲の開始からの秒数）
    let time: Double
    /// 0...3（左から）
    let lane: Int
    /// 0...2（下から）
    let row: Int
    let color: Hand
    let direction: CutDirection
}

/// モック用に譜面をその場で生成する。
/// 拍ごとに左右交互にノーツを出し、4 拍に 1 回は両手同時にする。
/// 各手は「振り下ろし → 振り上げ」を交互に繰り返し、ときどき横振りや方向自由を混ぜる。
struct ChartGenerator: Sendable {
    let bpm: Double
    /// 最初のノーツが届くまでの秒数
    let leadIn: Double

    private var random: SplitMix64
    private var beat = 0
    private var nextID = 0
    private var flow: [Hand: CutDirection] = [.left: .down, .right: .down]

    init(bpm: Double = 100, leadIn: Double = 3, seed: UInt64 = 0x5AB3_2026) {
        self.bpm = bpm
        self.leadIn = leadIn
        self.random = SplitMix64(seed: seed)
    }

    var secondsPerBeat: Double { 60 / bpm }

    mutating func nextBeat() -> [Note] {
        defer { beat += 1 }
        let time = leadIn + Double(beat) * secondsPerBeat
        let hands: [Hand] = beat % 4 == 3 ? [.left, .right] : [beat.isMultiple(of: 2) ? .left : .right]
        return hands.map { makeNote(for: $0, at: time) }
    }

    private mutating func makeNote(for hand: Hand, at time: Double) -> Note {
        let direction = nextDirection(for: hand)
        let lanes = hand == .left ? [0, 1] : [2, 3]
        let lane = lanes[Int.random(in: 0...1, using: &random)]
        let row = switch direction {
        case .up: 0
        case .down: Int.random(in: 0...1, using: &random)
        case .left, .right: 1
        case .any: Int.random(in: 0...2, using: &random)
        }
        defer { nextID += 1 }
        return Note(id: nextID, time: time, lane: lane, row: row, color: hand, direction: direction)
    }

    private mutating func nextDirection(for hand: Hand) -> CutDirection {
        let roll = Double.random(in: 0..<1, using: &random)
        if roll < 0.12 {
            // 外側へ払う横振り
            return hand == .left ? .left : .right
        }
        if roll < 0.2 {
            return .any
        }
        let direction = flow[hand] ?? .down
        flow[hand] = direction == .down ? .up : .down
        return direction
    }
}

/// シードを固定できる軽量な乱数生成器（譜面の再現性とテストのため）
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

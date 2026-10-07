/// スコアとコンボの集計
struct ScoreBoard: Sendable, Equatable {
    private(set) var score = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var goodCount = 0
    private(set) var badCount = 0
    private(set) var missCount = 0

    /// コンボ数に応じた倍率（Beat Saber と同じく 1 → 2 → 4 → 8）
    var multiplier: Int {
        switch combo {
        case 14...: 8
        case 6...: 4
        case 2...: 2
        default: 1
        }
    }

    mutating func registerGood() {
        score += 100 * multiplier
        combo += 1
        maxCombo = max(maxCombo, combo)
        goodCount += 1
    }

    mutating func registerBad() {
        combo = 0
        badCount += 1
    }

    mutating func registerMiss() {
        combo = 0
        missCount += 1
    }
}

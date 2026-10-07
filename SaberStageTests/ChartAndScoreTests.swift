import Testing
@testable import SaberStage

struct ChartGeneratorTests {
    private func generate(beats: Int) -> [Note] {
        var generator = ChartGenerator(bpm: 120, leadIn: 2)
        return (0..<beats).flatMap { _ in generator.nextBeat() }
    }

    @Test
    func notesAreOnTheSideOfTheirHand() {
        for note in generate(beats: 200) {
            let expectedLanes = note.color == .left ? 0...1 : 2...3
            #expect(expectedLanes.contains(note.lane))
            #expect((0...2).contains(note.row))
        }
    }

    @Test
    func notesArriveOnBeats() {
        let notes = generate(beats: 8)

        #expect(notes.first?.time == 2)
        #expect(notes.allSatisfy { ($0.time - 2).truncatingRemainder(dividingBy: 0.5) == 0 })
        #expect(notes.map(\.time) == notes.map(\.time).sorted())
    }

    @Test
    func everyFourthBeatHasBothHands() {
        let notes = generate(beats: 4).filter { $0.time == 2 + 3 * 0.5 }

        #expect(Set(notes.map(\.color)) == [.left, .right])
    }

    @Test
    func vertialSwingsAlternatePerHand() {
        let leftVertical = generate(beats: 100)
            .filter { $0.color == .left && ($0.direction == .up || $0.direction == .down) }
            .map(\.direction)

        for (previous, next) in zip(leftVertical, leftVertical.dropFirst()) {
            #expect(previous != next)
        }
    }

    @Test
    func sameSeedGeneratesSameChart() {
        #expect(generate(beats: 50) == generate(beats: 50))
    }
}

struct ScoreBoardTests {
    @Test
    func multiplierGrowsWithComboAndResetsOnMiss() {
        var board = ScoreBoard()
        for _ in 0..<14 {
            board.registerGood()
        }
        #expect(board.multiplier == 8)
        // 倍率 1 が 2 回、2 が 4 回、4 が 8 回
        #expect(board.score == 100 * (2 * 1 + 4 * 2 + 8 * 4))

        board.registerMiss()

        #expect(board.combo == 0)
        #expect(board.multiplier == 1)
        #expect(board.maxCombo == 14)
    }
}

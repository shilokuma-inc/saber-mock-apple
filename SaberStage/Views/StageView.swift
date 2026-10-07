import SwiftUI

struct StageView: View {
    let model: StageModel

    var body: some View {
        ZStack {
            StageSceneView(engine: model.engine)
                .ignoresSafeArea()
            VStack {
                HStack(alignment: .top) {
                    ControllerStatusPanel(controllers: model.hud.controllers)
                    Spacer()
                    ScorePanel(scoreBoard: model.hud.scoreBoard)
                }
                Spacer()
                if !model.hud.isPlaying {
                    InstructionCard()
                }
                Spacer()
                controlBar
            }
            .padding(24)
            JudgementLabel(kind: model.hud.lastJudgement, serial: model.hud.judgementSerial)
        }
        .foregroundStyle(.white)
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            ListenerStatusLabel(status: model.listenerStatus)
            Spacer()
            Button(action: model.calibrateAll) {
                Label("両手をキャリブレーション（C）", systemImage: "scope")
            }
            .keyboardShortcut("c", modifiers: [])
            Button(action: model.togglePlaying) {
                Label(
                    model.hud.isPlaying ? "ストップ（Space）" : "スタート（Space）",
                    systemImage: model.hud.isPlaying ? "stop.fill" : "play.fill"
                )
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }
}

private struct ControllerStatusPanel: View {
    let controllers: [Hand: ControllerStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Hand.allCases) { hand in
                let status = controllers[hand] ?? ControllerStatus()
                HStack(spacing: 8) {
                    Circle()
                        .fill(status.isConnected ? Color(nsColor: StagePalette.color(for: hand)) : .gray)
                        .frame(width: 10, height: 10)
                    Text(hand.displayName)
                        .bold()
                    Text(description(of: status))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .font(.callout)
        .padding(12)
        .background(.black.opacity(0.4), in: .rect(cornerRadius: 10))
    }

    private func description(of status: ControllerStatus) -> String {
        guard status.isConnected else { return "未接続" }
        let calibration = status.isCalibrated ? "キャリブレーション済み" : "要キャリブレーション"
        return "\(status.packetRate) Hz・\(calibration)"
    }
}

private struct ScorePanel: View {
    let scoreBoard: ScoreBoard

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(scoreBoard.score, format: .number)
                .font(.largeTitle.bold())
            Text("\(scoreBoard.combo) コンボ × \(scoreBoard.multiplier)")
                .font(.title3)
            Text("GOOD \(scoreBoard.goodCount)  BAD \(scoreBoard.badCount)  MISS \(scoreBoard.missCount)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .padding(12)
        .background(.black.opacity(0.4), in: .rect(cornerRadius: 10))
    }
}

private struct JudgementLabel: View {
    let kind: JudgementKind?
    let serial: Int

    var body: some View {
        // 最初の判定でもアニメーションが走るよう、判定が無いときも空の Text を置いておく
        Text(text)
            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            .foregroundStyle(color)
            .shadow(color: color, radius: 8)
            // 判定のたびに、ふわっと出てから消える
            .keyframeAnimator(initialValue: 0.0, trigger: serial) { content, opacity in
                content
                    .opacity(opacity)
                    .scaleEffect(1 + (1 - opacity) * 0.3)
            } keyframes: { _ in
                LinearKeyframe(1.0, duration: 0.05)
                LinearKeyframe(1.0, duration: 0.35)
                LinearKeyframe(0.0, duration: 0.3)
            }
            .offset(y: -120)
            .allowsHitTesting(false)
    }

    private var text: String {
        switch kind {
        case .good: "GOOD"
        case .bad: "BAD CUT"
        case .miss: "MISS"
        case nil: ""
        }
    }

    private var color: Color {
        switch kind {
        case .good, nil: .white
        case .bad: .orange
        case .miss: .gray
        }
    }
}

private struct InstructionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("遊び方")
                .font(.title2.bold())
            Text("1. iPhone 2 台で SaberController を開き、それぞれ「左手」「右手」を選ぶ")
            Text("2. iPhone の上端を剣先にして握り、この画面の中央に向ける")
            Text("3. その姿勢で iPhone の画面をタップ（または C キー）してキャリブレーション")
            Text("4. Space でスタート。赤は左手、青は右手で、矢印の方向に振り抜く")
        }
        .font(.body)
        .padding(20)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 14))
    }
}

private struct ListenerStatusLabel: View {
    let status: ListenerStatus

    var body: some View {
        switch status {
        case .starting:
            Label("待ち受けを開始しています…", systemImage: "antenna.radiowaves.left.and.right")
        case .ready(let port):
            Label("\(ControllerProtocol.serviceType) で待ち受け中（UDP \(port)）", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label("待ち受けに失敗: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    StageView(model: StageModel())
        .frame(width: 1100, height: 700)
}

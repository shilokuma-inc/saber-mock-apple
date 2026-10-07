import SwiftUI

struct ControllerView: View {
    @Bindable var model: ControllerModel

    var body: some View {
        VStack(spacing: 20) {
            Picker("持つ手", selection: $model.hand) {
                ForEach(Hand.allCases) { hand in
                    Text(hand.displayName).tag(hand)
                }
            }
            .pickerStyle(.segmented)

            ConnectionStatusView(state: model.connectionState, usesDemoMotion: model.usesDemoMotion)

            calibrateButton

            Text("iPhone の上端を剣先にして握り、Mac の画面中央に向けたままタップすると、その向きが正面になります。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(handColor.gradient.opacity(0.85))
        .foregroundStyle(.white)
        .sensoryFeedback(.success, trigger: model.calibrationCount)
    }

    /// 握ったまま親指で押せるよう、画面の大部分をボタンにする
    private var calibrateButton: some View {
        Button(action: model.calibrate) {
            VStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.system(size: 64, weight: .bold))
                Text("キャリブレーション")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.15), in: .rect(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .accessibilityHint("今の向きを Mac の画面の正面として合わせます")
    }

    private var handColor: Color {
        switch model.hand {
        case .left: Color(red: 1, green: 0.16, blue: 0.3)
        case .right: Color(red: 0.15, green: 0.55, blue: 1)
        }
    }
}

private struct ConnectionStatusView: View {
    let state: StageConnection.State
    let usesDemoMotion: Bool

    var body: some View {
        VStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            if usesDemoMotion {
                Text("モーションセンサーが使えないため、疑似モーションを送っています")
                    .font(.caption)
            }
        }
    }

    private var title: String {
        switch state {
        case .searching: "Mac を探しています…"
        case .connecting(let name): "\(name) に接続中…"
        case .ready(let name): "\(name) に送信中"
        case .failed(let message): "接続エラー: \(message)"
        }
    }

    private var systemImage: String {
        switch state {
        case .searching, .connecting: "antenna.radiowaves.left.and.right"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

#Preview("右手") {
    ControllerView(model: ControllerModel())
}

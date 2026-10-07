import SwiftUI

@main
struct SaberControllerApp: App {
    @State private var model = ControllerModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ControllerView(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // 振っている間に画面が消えないようにし、バックグラウンドでは送信を止める
                    switch phase {
                    case .active:
                        UIApplication.shared.isIdleTimerDisabled = true
                        model.start()
                    case .background:
                        UIApplication.shared.isIdleTimerDisabled = false
                        model.stop()
                    default:
                        break
                    }
                }
        }
    }
}

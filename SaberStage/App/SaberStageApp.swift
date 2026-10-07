import SwiftUI

@main
struct SaberStageApp: App {
    @State private var model = StageModel()

    var body: some Scene {
        WindowGroup("SaberStage") {
            StageView(model: model)
                .frame(minWidth: 960, minHeight: 600)
                .task { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

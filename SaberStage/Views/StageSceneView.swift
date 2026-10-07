import SceneKit
import SwiftUI

/// GameEngine を毎フレーム呼ぶ SCNView。
/// SwiftUI の SceneView では描画ループの設定を細かく指定できないため NSViewRepresentable で包む。
struct StageSceneView: NSViewRepresentable {
    let engine: GameEngine

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = engine.scene
        view.pointOfView = engine.cameraNode
        view.delegate = engine
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 120
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = StagePalette.background
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}
}

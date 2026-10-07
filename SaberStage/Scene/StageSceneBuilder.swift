import AppKit
import SceneKit
import simd

enum StagePalette {
    static let background = NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)

    static func color(for hand: Hand) -> NSColor {
        switch hand {
        case .left: NSColor(red: 1, green: 0.16, blue: 0.3, alpha: 1)
        case .right: NSColor(red: 0.15, green: 0.55, blue: 1, alpha: 1)
        }
    }
}

/// SceneKit のノードを組み立てる
enum StageSceneBuilder {
    static func makeScene() -> (scene: SCNScene, camera: SCNNode) {
        let scene = SCNScene()
        scene.background.contents = StagePalette.background
        scene.fogStartDistance = 12
        scene.fogEndDistance = 26
        scene.fogColor = StagePalette.background

        let camera = makeCamera()
        scene.rootNode.addChildNode(camera)
        addLights(to: scene.rootNode)
        addTrack(to: scene.rootNode)
        return (scene, camera)
    }

    static func makeSaber(for hand: Hand) -> SCNNode {
        let color = StagePalette.color(for: hand)
        let hiltLength = CGFloat(SaberRig.hiltLength)
        let bladeLength = CGFloat(SaberRig.bladeLength)
        let root = SCNNode()
        root.name = "saber-\(hand.rawValue)"

        let hiltMaterial = SCNMaterial()
        hiltMaterial.lightingModel = .physicallyBased
        hiltMaterial.diffuse.contents = NSColor(white: 0.55, alpha: 1)
        hiltMaterial.metalness.contents = 0.9
        hiltMaterial.roughness.contents = 0.3
        let hilt = SCNNode(geometry: SCNCylinder(radius: 0.022, height: hiltLength))
        hilt.geometry?.materials = [hiltMaterial]
        hilt.position = SCNVector3(0, hiltLength / 2, 0)
        root.addChildNode(hilt)

        let core = SCNNode(geometry: SCNCylinder(radius: 0.012, height: bladeLength))
        core.geometry?.materials = [emissiveMaterial(color.blended(withFraction: 0.6, of: .white) ?? color)]
        core.position = SCNVector3(0, hiltLength + bladeLength / 2, 0)
        root.addChildNode(core)

        let glowMaterial = emissiveMaterial(color)
        glowMaterial.transparency = 0.45
        glowMaterial.blendMode = .add
        glowMaterial.writesToDepthBuffer = false
        let glow = SCNNode(geometry: SCNCylinder(radius: 0.032, height: bladeLength))
        glow.geometry?.materials = [glowMaterial]
        glow.position = core.position
        root.addChildNode(glow)
        return root
    }

    static func makeNote(_ note: Note) -> SCNNode {
        let size = CGFloat(StageLayout.noteSize)
        let box = SCNBox(width: size, height: size, length: size, chamferRadius: 0.04)
        box.materials = [noteMaterial(for: note.color)]
        let node = SCNNode(geometry: box)
        node.name = "note-\(note.id)"

        let symbol = makeSymbol(for: note.direction)
        symbol.position.z = size / 2 + 0.006
        node.addChildNode(symbol)
        return node
    }

    /// 斬ったノーツを、振った方向に沿って 2 つに割って飛ばす
    static func makeSlicedHalves(color: Hand, at position: SIMD3<Float>, swing: SIMD2<Double>) -> SCNNode {
        let size = CGFloat(StageLayout.noteSize)
        let direction = simd_length(swing) > 0 ? simd_normalize(swing) : SIMD2(0, -1)
        let container = SCNNode()
        container.simdPosition = position
        // ローカルの +Y を振りの方向に合わせる（切断面は振りの方向と平行になる）
        container.eulerAngles.z = CGFloat(atan2(direction.y, direction.x) - .pi / 2)

        let material = noteMaterial(for: color)
        for side: CGFloat in [-1, 1] {
            let half = SCNNode(geometry: SCNBox(width: size / 2, height: size, length: size, chamferRadius: 0.03))
            half.geometry?.materials = [material]
            half.position = SCNVector3(side * size / 4, 0, 0)
            let push = SCNAction.moveBy(x: side * 0.35, y: 0.25, z: 0, duration: 0.45)
            let spin = SCNAction.rotateBy(x: 0, y: side * 1.6, z: side * 0.8, duration: 0.45)
            push.timingMode = .easeOut
            half.runAction(.group([push, spin, .fadeOut(duration: 0.45)]))
            container.addChildNode(half)
        }
        container.runAction(.sequence([
            .moveBy(x: 0, y: 0, z: 2.5, duration: 0.45),
            .removeFromParentNode(),
        ]))
        return container
    }

    /// 方向違い・色違いで斬ったノーツは灰色にして消す
    static func runBadCutAnimation(on node: SCNNode) {
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(white: 0.3, alpha: 1)
        node.geometry?.materials = [material]
        node.runAction(.sequence([
            .group([.moveBy(x: 0, y: -0.2, z: 1.2, duration: 0.3), .fadeOut(duration: 0.3)]),
            .removeFromParentNode(),
        ]))
    }

    // MARK: - Private

    private static func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.05
        camera.zFar = 100
        camera.wantsHDR = true
        camera.bloomIntensity = 1.4
        camera.bloomThreshold = 0.5
        camera.bloomBlurRadius = 12
        let node = SCNNode()
        node.camera = camera
        // プレイヤーの後ろ・上から見下ろし、手元のセイバーと奥から来るノーツを両方映す。
        // 真後ろの目線だと正面に向けたセイバーが点にしか見えないため、高めに置いている
        node.position = SCNVector3(0, 2.2, 1.9)
        node.look(at: SCNVector3(0, 0.8, -3))
        return node
    }

    private static func addLights(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 300
        root.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 900
        directional.eulerAngles = SCNVector3(-CGFloat.pi / 3, 0.3, 0)
        root.addChildNode(directional)
    }

    private static func addTrack(to root: SCNNode) {
        let floor = SCNFloor()
        floor.reflectivity = 0.12
        floor.firstMaterial?.diffuse.contents = NSColor(white: 0.04, alpha: 1)
        root.addChildNode(SCNNode(geometry: floor))

        let track = SCNNode(geometry: SCNBox(width: 1.6, height: 0.01, length: 40, chamferRadius: 0))
        track.geometry?.firstMaterial?.diffuse.contents = NSColor(white: 0.1, alpha: 1)
        track.position = SCNVector3(0, 0.005, -18)
        root.addChildNode(track)

        for hand in Hand.allCases {
            let rail = SCNNode(geometry: SCNBox(width: 0.03, height: 0.03, length: 40, chamferRadius: 0))
            rail.geometry?.materials = [emissiveMaterial(StagePalette.color(for: hand))]
            rail.position = SCNVector3(hand == .left ? -0.8 : 0.8, 0.02, -18)
            root.addChildNode(rail)
        }
    }

    private static func makeSymbol(for direction: CutDirection) -> SCNNode {
        let material = emissiveMaterial(.white)
        guard let vector = direction.vector else {
            let dot = SCNNode(geometry: SCNSphere(radius: 0.045))
            dot.geometry?.materials = [material]
            dot.scale = SCNVector3(1, 1, 0.3)
            return dot
        }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -0.1, y: -0.035))
        path.line(to: NSPoint(x: 0.1, y: -0.035))
        path.line(to: NSPoint(x: 0, y: 0.07))
        path.close()
        let arrow = SCNNode(geometry: SCNShape(path: path, extrusionDepth: 0.01))
        arrow.geometry?.materials = [material]
        // 三角形は上向きで作っているので、矢印の方向へ回す
        arrow.eulerAngles.z = CGFloat(atan2(vector.y, vector.x) - .pi / 2)
        return arrow
    }

    private static func noteMaterial(for hand: Hand) -> SCNMaterial {
        let color = StagePalette.color(for: hand)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color.blended(withFraction: 0.3, of: .black) ?? color
        material.emission.contents = color
        material.emission.intensity = 0.25
        material.metalness.contents = 0.3
        material.roughness.contents = 0.4
        return material
    }

    private static func emissiveMaterial(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color
        return material
    }
}

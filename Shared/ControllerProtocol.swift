import Foundation

/// Mac と iPhone の間でやり取りするメッセージの定義。
/// どちらのアプリからも同じファイルを参照する。
enum ControllerProtocol {
    /// Bonjour のサービス種別。Info.plist の NSBonjourServices と一致させる
    static let serviceType = "_sabermock._udp"
}

enum Hand: String, Codable, Sendable, CaseIterable, Identifiable {
    case left
    case right

    var id: Self { self }

    var displayName: String {
        switch self {
        case .left: "左手"
        case .right: "右手"
        }
    }
}

struct Quaternion: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double

    static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)
}

struct Vector3: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)
}

/// iPhone の姿勢 1 サンプル。
/// `attitude` は CoreMotion の `.xArbitraryCorrectedZVertical`（Z が鉛直上向き）基準で、
/// 端末座標のベクトルを参照座標に回す向きのクォータニオン。
struct MotionSample: Codable, Sendable, Equatable {
    var hand: Hand
    var sequence: UInt32
    var attitude: Quaternion
    /// 端末座標での角速度（rad/s）
    var rotationRate: Vector3
}

/// iPhone → Mac
enum ControllerMessage: Codable, Sendable, Equatable {
    case motion(MotionSample)
    /// 今の向きを「画面の正面」として合わせる
    case calibrate(Hand)
}

/// Mac → iPhone
enum StageMessage: Codable, Sendable, Equatable {
    /// ノーツを斬ったときの振動（0...1）
    case haptic(intensity: Double)
    /// Mac が受信できていることを知らせる。UDP は相手がいなくなっても送信側で気づけないため、
    /// iPhone はこれが途絶えたら接続をやり直す（Mac アプリを再起動するとポートが変わる）
    case heartbeat
}

extension ControllerProtocol {
    static let heartbeatInterval: TimeInterval = 0.5
    /// この秒数ハートビートが届かなければ、iPhone は接続し直す
    static let heartbeatTimeout: TimeInterval = 2.5
}

# SaberMock

Mac に譜面を表示し、iPhone 2 台をセイバー（コントローラー）にして遊ぶ、Beat Saber 風のリズムゲームのモックです。
iPhone からは **向き（CoreMotion の姿勢）だけ** を送り、手の位置は簡易的なアームモデルで推定します。

```
iPhone（左手） ─┐  UDP / Bonjour（_sabermock._udp）
               ├──────────────────────────────▶  Mac（SaberStage）
iPhone（右手） ─┘  ◀── ハートビート・振動の指示 ──   譜面の表示・当たり判定
```

- `includePeerToPeer` を有効にしているので、Wi-Fi ルーターがない場所でも AWDL（ピアツーピア Wi-Fi）でつながります
- ノーツを斬ると、斬った側の iPhone が振動します

## 必要なもの

- Xcode 26 以降 / [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Mac: macOS 15 以降
- iPhone 2 台: iOS 18 以降

## セットアップ

```bash
xcodegen generate
open SaberMock.xcodeproj
```

1. `SaberStage` スキームを My Mac で実行する
2. `SaberController` スキームを iPhone 2 台にそれぞれインストールして起動する
3. iPhone で「ローカルネットワーク」へのアクセスを許可する

### 初回だけ必要な設定（Mac のファイアウォール）

Mac のファイアウォールが有効だと、SaberStage への受信接続がブロックされることがあります（iPhone の画面が「接続中…」のまま進まない）。
「システム設定 → ネットワーク → ファイアウォール → オプション…」で、SaberStage を「外部からの接続を許可」にしてください。

署名は Apple Development にしているので、一度許可すれば再ビルドしても設定が引き継がれます。

## 遊び方

1. iPhone で「左手」「右手」を選ぶ（画面が赤 = 左手、青 = 右手）
2. iPhone の上端を剣先にして握り、Mac の画面中央に向ける
3. その姿勢で iPhone の画面をタップしてキャリブレーションする（Mac で `C` キーを押すと両手まとめてできる）
4. Mac で `Space` を押すとスタート。赤は左手、青は右手で、矢印の方向に振り抜く

## 仕組み

| 項目 | 実装 | 主なファイル |
|---|---|---|
| 姿勢の取得 | CoreMotion `.xArbitraryCorrectedZVertical`（100Hz）。Z 軸が重力方向なので、ずれるのは水平方向（ヨー）だけ | `SaberController/Motion/MotionSource.swift` |
| キャリブレーション | 剣先の水平方向が画面の正面を向くように、ヨーだけを補正する。初回の受信時にも一度自動で合わせる | `SaberStage/Logic/SaberMath.swift` |
| 手の位置 | 肩を固定の支点とし、剣先の方向に 30cm 腕を伸ばした位置に手があるとみなす（アームモデル） | `SaberRig`（`SaberMath.swift`） |
| 当たり判定 | 前フレームと今フレームの刃の間を補間して、ノーツの立方体に触れたかを調べる。速く振ってもすり抜けない | `SaberStage/Logic/HitJudge.swift` |
| 振りの方向 | ジャイロの角速度から剣先の速度を求め、画面と平行な成分で矢印の向きと比べる | `SaberRig.tipVelocity` |
| 譜面 | 自動生成（BPM 100、左右交互、4 拍に 1 回は両手同時） | `SaberStage/Logic/ChartGenerator.swift` |
| 接続の維持 | Mac が 0.5 秒ごとにハートビートを送り、途絶えたら iPhone が名前解決からやり直す | `StageConnection` / `ControllerServer` |

判定の甘さ・ノーツの速さ・腕の長さなどは、`StageLayout`・`SaberRig`・`HitJudge.judge` の定数で調整できます。

## モックとしての制約

- 手の位置は推定なので、腕全体を動かす動き（しゃがむ、体ごと横に避けるなど）は反映されません
- 水平方向の向きは時間とともに少しずつずれます。ずれてきたら曲の合間にキャリブレーションし直してください
- 楽曲はなく、譜面は自動生成です
- Simulator では CoreMotion が使えないため、iPhone アプリは一定のリズムで振る疑似モーションを送ります

## テスト

```bash
xcodebuild -project SaberMock.xcodeproj -scheme SaberStage -destination 'platform=macOS' test
```

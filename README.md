# ギャグオセロ（Flutter 版）

顔写真がコマになる、パーティー向けオセロ。実力差を「台パン」で埋め、負けても笑える。
ブラウザ試作版（`prototype/gag-othello.html`）で遊んで調整した仕様を、Flutter に移したものです。

- 1人（コンピュータ対戦）／2人（向かい合わせ・同じ画面）
- 赤い**ストレスゲージ**がたまり、MAX になったら**台パン**（長押し 0.9 秒）で石数を同数にして救済
  - 角は完全ランダム（占有済みの角は 1/2 で相手のものに）。端数は台パンした側へ
  - 相手の手番でも使える。1ゲームで平均 2 回前後になるよう調整済み
  - 空きマス 4 以下は**ヒートアップ**：目が炎になり、BGM が速くなり、台パンは封印
- 打てる場所がないときは人間が「パス」ボタンを押す（押すとストレスがたまる。CPU は自動）
- 勝った側の変顔が画面いっぱいに出る終局演出
- 音：BGM（タイトル / 対局 / ヒート）と効果音。**タイトル画面でも対局中でも** BGM・SE の音量を調整できます
- オンライン対戦は**未実装**です
- ウェブに公開する手順は **[DEPLOY.md](DEPLOY.md)**（Firebase Hosting / GitHub Pages）

> **動作確認について（先に読んでください）**
> このプロジェクトは、Flutter / Dart が入っていない環境で書きました。**一度もコンパイル・実行していません。**
> 確認できているのは次のとおりです。
> - ゲームの規則（`lib/core/engine.dart`）は試作版の JS エンジンを 1 対 1 で移植したもので、試作版側は 14,794 局面のシミュレーションで検証済み。Dart 版との照合用に `test/golden/golden_games.json`（30 局・1,786 手）を用意しました（**Dart 側のテストは未実行**）。
> - 効果音・BGM の WAV は、試作版（Web Audio）と同じ音量・長さになることを確認済みです。
> - 括弧の対応、import、名前付き引数の突き合わせなどの機械的な検査は通しています。
>
> 初回は `flutter analyze` にエラーや警告が出る可能性があります。出力をそのまま貼ってもらえれば直します。

## はじめかた（VS Code）

### 1. 用意するもの

- [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable。Dart 3.3 以上 = Flutter 3.19 以上）
- VS Code の拡張機能 **Dart** と **Flutter**（このフォルダを開くと推奨表示が出ます）
- 実機 / エミュレータ / Chrome のどれか（`flutter doctor` で確認）

### 2. プラットフォーム用フォルダを作る（最初の 1 回だけ）

このフォルダには `lib/` とアセットだけが入っています。ターミナルで次を実行して、`android/` `ios/` `web/` を作ってください。

```bash
cd gag_othello
flutter create . --project-name gag_othello --platforms=android,ios,web
```

既存のファイル（`lib/main.dart` や `pubspec.yaml`）は上書きされないはずです。念のため `lib/main.dart` の先頭が `import 'package:flutter/material.dart'; import 'package:flutter/services.dart';` のままか確認してください。

### 3. 写真用の権限（iOS）と、ウェブ用の設定を入れる

写真を選ぶために、iOS には使用目的の説明文が必要です。次の補助スクリプトで入ります（Python 3 が必要）。同時に、ウェブ用の `web/index.html` と `web/manifest.json` も整えます（アプリ名・説明・読み込み中の画面。何度実行しても同じ結果）。iOS の部分は手作業でもかまいません。

```bash
python3 tool/post_create.py
```

手作業でやる場合：`ios/Runner/Info.plist` の `<dict>` の中に追加

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>顔写真をコマにするために、写真ライブラリから画像を選びます。</string>
<key>NSCameraUsageDescription</key>
<string>顔写真をコマにするために、カメラで撮影します。</string>
```

Android は追加の設定なしで動きます。フォントはアプリに同梱してあるので、通信は不要です。

### 4. 取得・検査・テスト・実行

```bash
flutter pub get
flutter analyze        # 静的解析。まずここで出たものを直す
flutter test           # 規則の照合テスト（engine_test.dart）
flutter run            # 接続中の端末で実行（VS Code なら F5）
flutter run -d chrome  # ブラウザで試す
```

VS Code では `F5`（`.vscode/launch.json` に debug / profile / release / Chrome を用意）。

## 遊び方の要点

1. タイトル画面でモード、名前、顔写真（通常顔・変顔）を決めて「はじめる」。写真はなくても遊べます（コードで描いた初期顔が入っています）。
2. 通常顔は切り抜きの画面で**赤い印を両目に合わせる**と、ヒートアップ時にそこが炎になります。
3. 対局中の「おと」ボタンで BGM / SE の音量とミュートを調整。「タイトルへ」は確認ダイアログつき。
4. 台パンボタンは**長押し**。ゲージ MAX でないとき、ヒートアップ中は押せません。CPU 側の台パンボタンは人間には押せません。

## フォルダ構成

```
lib/
  main.dart                  起動（縦固定・初期化・アプリの前後で音を止める）
  core/
    engine.dart              規則・ストレスゲージ・台パン・CPU（Flutter に依存しない純 Dart）
    models.dart              モード、顔の種類、文言
    util.dart                clamp の自前版
  services/
    app_state.dart           設定（モード・名前・音量・顔写真）と保存（shared_preferences）
    audio_service.dart       BGM / SE（audioplayers）。音量は スライダー値の 2 乗
    face_service.dart        顔写真と初期顔のお絵かき
  ui/
    game_controller.dart     対局の進行役（演出・タイマー・音・CPU の手番）
    game_screen.dart         対局画面
    setup_screen.dart        タイトル画面
    board_view.dart          盤（CustomPaint 1 枚）
    disc_painter.dart        コマ（顔・表情・炎・涙）の描画
    player_panel.dart        アバター・ゲージ・台パンボタン
    effects.dart             バナー・集中線・ビネット・長押しオーバーレイ
    ending_overlay.dart      終局の顔面モザイク
    crop_dialog.dart         顔写真の切り抜き
    sound_controls.dart      音量スライダー（タイトルと対局中で共用）
    theme.dart / visuals.dart
assets/audio/                BGM 3 曲と効果音（WAV。tool/render_audio.py で作成）
assets/fonts/                日本語フォント（Noto Sans CJK JP の Bold / Black を絞ったもの。OFL.txt に許諾）
test/                        engine_test.dart（照合 + 性質テスト）, golden/
tool/                        render_audio.py, build_fonts.py, gen_golden.js, sim.js, post_create.py
web/                         ウェブ用のアイコン（favicon.png, icons/）とフォントのライセンス（NOTICE-fonts.txt）
firebase.json                Firebase Hosting の設定（公開フォルダ build/web）
.github/workflows/        GitHub Pages への自動公開（deploy-pages.yml）
DEPLOY.md                    ウェブ公開の手順書
prototype/gag-othello.html   ブラウザ試作版（調整の元）
```

## 調整したいとき

| 何を | どこを |
| --- | --- |
| ゲージの増え方（角 40、5 枚以上返し 15、パス 25 / 連続 35、劣勢 5） | `lib/core/engine.dart` の `GaugeCfg` |
| 台パンの長押し時間（900ms）、ヒートアップの空きマス数（4） | 同 `Cfg` |
| CPU の強さ | 同 `pickMove`（評価値に足すノイズの幅 `* 4`） |
| 色・文字の太さ | `lib/ui/theme.dart` |

台パンの発動回数は、ボット同士の 14,794 局面で「1 ゲームあたり約 1.8 回」になるようゲージ値を決めています。値を変えたら試作版の `node tool/sim.js prototype/gag-othello.html` でボット同士の検証ができます。ただしこれは試作版（JS）のエンジンを動かすので、`prototype/gag-othello.html` の ENGINE ブロックの `CFG` も同じ値に変えてから実行してください。

## 音を作り直す

```bash
pip install numpy scipy
python3 tool/render_audio.py          # assets/audio/*.wav を書き出す
python3 tool/render_audio.py --check  # 書き出さず長さとピークだけ確認
```

バス音量（BGM 0.45、SE 0.81）は WAV に焼き込んであります。スライダーの値は 2 乗してそのままプレイヤー音量にかけます。

## フォントについて

見出しと本文は、Noto Sans CJK JP（Bold / Black。SIL Open Font License 1.1）から日本語の書体だけを取り出し、使う文字（ASCII・かな・JIS X 0208 の漢字・ソースコード内の文字）に絞ったものを同梱しています（合計 約 3 MB）。ブラウザ試作版の Google Fonts（Dela Gothic One / Zen Maru Gothic）とは字形が少し違います。好きなフォントに替えるときは `assets/fonts/` の 2 ファイルを差し替え、`pubspec.yaml` の `fonts:` を合わせてください（`tool/build_fonts.py` で作り直すこともできます）。

## 試作版との照合テストを作り直す

```bash
node tool/gen_golden.js prototype/gag-othello.html > test/golden/golden_games.json
flutter test
```

台パンは乱数に依存するので、照合テストには入れていません。台パンは `engine_test.dart` の性質テスト（占有マスを動かさない・同数・端数は台パン側・角は 1/2）で確かめます。

## つまずきやすいところ

- **文字が □ になる**：フォントはアプリに同梱（`assets/fonts/`）しているので、`pubspec.yaml` の `fonts:` と `assets/fonts/` の 2 ファイルが残っているか確認してください。手動で入力した珍しい漢字だけは、同梱フォントにない場合があります（端末のフォントで表示されます）。
- **Web で最初に音が鳴らない**：ブラウザの自動再生ルールです。画面にさわると BGM が始まります。
- **iOS で写真を選ぼうとして落ちる**：手順 3 の Info.plist の説明文が入っているか確認してください。
- **画面が進まない**：「はじめる」は画面の下に固定してあります。押しても変わらないときは、ブラウザの開発者ツール（F12）の Console に出ている赤いエラーを教えてください。
- **公開版（`--release`）で赤いエラー表示が出ない**：仕様です。公開用ビルドでは隠しています。テスターに試してもらうときは `flutter build web --release --dart-define=SHOW_ERRORS=true`。
- **Android でカメラが起動しない**：端末にカメラがない（エミュレータ等）場合は「ライブラリからえらぶ」を使ってください。
- **`flutter analyze` で deprecated の警告**：新しい SDK では一部の API（`Matrix4.translate` など）が非推奨になっています。動作には影響しませんが、気になるときは指示どおりの新 API に置き換えてください。

## オンライン対戦（未実装）の足がかり

`engine.dart` は Flutter に依存せず、乱数を使うのは台パンだけです。同期するなら「手（マスの番号 / パス / 台パン）」を送り合い、台パンだけは**結果の盤面**（`TurnResult.after`）を送って両側で同じにする形が素直です。`GameController` の `onCell` / `doPass` / `startHold` が入口になります。

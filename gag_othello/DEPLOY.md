# ウェブに公開する（Firebase Hosting）

遊べることを確認したあと、URL を知っている人なら誰でも遊べる状態にする手順です。
Firebase Hosting は **HTTPS** で配信されるので、スマホのカメラ・写真選択も使えます。無料（Spark プラン・クレジットカード不要）で始められます。

> **先に読んでください**：この手順書と `firebase.json` は、Flutter / Firebase に触れない環境で書きました。ビルドも公開も、ここでは一度も実行していません。止まったら、出たメッセージをそのまま教えてください。

## 全体の流れ

1. 公開用の設定を入れる（最初の 1 回）
2. `flutter build web --release` でビルドする
3. `firebase deploy` でアップロードする

## 1. 公開用の設定を入れる（最初の 1 回）

プロジェクトのフォルダで、次を実行します。ブラウザのタブの名前・説明・「読み込み中」の画面・ホーム画面に追加したときの名前が `ギャグオセロ` になります（アイコンは `web/` に同梱済み）。

```bash
python3 tool/post_create.py
```

何度実行しても同じ結果になります（Windows では `python3` が `python` や `py` のことがあります）。

アイコンが Flutter 標準（青い F）のままのときは、zip に入っている `web/favicon.png` と `web/icons/` を、プロジェクトの `web/` に上書きコピーしてください。`web/index.html` と `web/manifest.json` がないと「skip」と出るので、そのときは先に `flutter create . --project-name gag_othello --platforms=android,ios,web` を実行してください。

## 2. ビルドする

```bash
flutter pub get
flutter build web --release
```

できあがりは `build/web/` に入ります。公開するのはこのフォルダの中身です。

公開用ビルドでは、画面下の赤い「エラー表示」は出ません（遊んでいる人にエラー文を見せないため）。友だちに試してもらって、おかしいときに原因を読みたいなら、次の形でビルドします。

```bash
flutter build web --release --dart-define=SHOW_ERRORS=true
```

### 手元で最終確認（任意・おすすめ）

```bash
python3 -m http.server 8000 -d build/web
```

ブラウザで `http://localhost:8000` を開き、タイトル → 対局 → 終局まで通して遊べるか確かめます。確認が終わったらターミナルで `Ctrl + C`。

## 3. Firebase に公開する

### 3-1. 最初の 1 回だけ

1. **Node.js** を入れる（<https://nodejs.org/>、LTS 版）。
2. Firebase CLI を入れる。
   ```bash
   npm install -g firebase-tools
   ```
3. ログインする（ブラウザが開くので Google アカウントを選ぶ）。
   ```bash
   firebase login
   ```
4. <https://console.firebase.google.com/> で「プロジェクトを追加」。名前を入れて進める（Google アナリティクスは「無効」でかまいません）。作成後、プロジェクトの設定に出る **プロジェクト ID**（例：`gag-othello-1a2b3`）を控える。
5. 同じコンソールの左メニュー「構築」→「Hosting」→「始める」を押して、案内の最後まで進める（サイトの枠が作られます。画面にある CLI のコマンドは、この手順書では使わないので実行不要）。

### 3-2. アップロード

プロジェクトのフォルダ（`firebase.json` があるところ）で：

```bash
firebase deploy --only hosting --project プロジェクトID
```

終わりに表示される `Hosting URL:` が公開先です（`https://プロジェクトID.web.app`）。スマホでも開いて、写真の選択・撮影と音が出ることを確認してください。

`firebase.json` はすでに入っています（公開フォルダ `build/web`、`index.html` などを毎回取り直す設定つき）。

### 3-3. 更新するとき

直したあと、**ビルド → deploy** をもう一度やるだけです。

```bash
flutter build web --release
firebase deploy --only hosting --project プロジェクトID
```

すでに開いている人は、ページを 2 回読み込み直すと新しい版になります（Flutter の仕組みで、1 回目に新しい版を取り込み、2 回目から使われます）。

### 本番の前に試したいとき（任意）

本番とは別の、期限つきの URL に置けます。

```bash
firebase hosting:channel:deploy preview --project プロジェクトID
```

## 公開してから気をつけること

- **無料枠の転送量**：Hosting の無料枠は、保存 10 GB・転送 **1 日 360 MB**（公式の料金ページの表示、2026 年 10 月時点）。このアプリは初めて来た人 1 人あたり、おおよそ **7〜8 MB** 前後（音 3.3 MB + フォント 約 3 MB + アプリ本体の見込み。実際の大きさはビルド後の `build/web` で確認できます）なので、**初めての人が 1 日 40 人前後**でいっぱいになる計算です（目安）。2 回目以降はブラウザに残るので数えません。友だち・家族・イベント程度なら足ります。たくさんの人に配るなら、音を圧縮形式（mp3 など）にして軽くするか、料金プランを見直してください（音の圧縮は頼んでもらえれば対応します）。
- **カメラは HTTPS が必須**：`https://` で開いていれば問題ありません。パソコンのブラウザでは、「カメラ」を選んでもファイル選択になることがあります（ブラウザ側の仕様です）。
- **顔写真と設定はそのブラウザの中だけに保存**されます。サーバーには送っていません。そのため、次のときは保存が消えます：シークレットウィンドウで遊んだとき、サイトデータを消したとき、別の端末・別のブラウザで開いたとき。`プロジェクトID.web.app` と `プロジェクトID.firebaseapp.com` は別のサイト扱いで、保存も別になります（URL は片方に決めて配ってください）。
- **最初の読み込み**は数秒かかります（「よみこみ中…」の画面が出ます）。CanvasKit（描画エンジン）は Google のサーバー（gstatic）から読むので、そこにつながらない学校・会社のネットワークでは開けないことがあります。
- **フォントのライセンス**：同梱の日本語フォントは SIL Open Font License 1.1 です。ライセンス全文は `web/NOTICE-fonts.txt`（公開後は `https://…/NOTICE-fonts.txt`）にあります。
- **独自ドメイン**を使うなら、Firebase コンソール →「Hosting」→「ドメインを追加」。表示された DNS の設定をドメイン会社の画面に入れます。

## ほかの公開先

どれも「`flutter build web --release` でできた `build/web` の中身を置く」だけです。

| 公開先 | やりかた |
| --- | --- |
| **Netlify Drop** | <https://app.netlify.com/drop> に `build/web` フォルダをドラッグ。いちばん手軽。登録して「自分のサイト」にすると残せます |
| **Cloudflare Pages** | ダッシュボードの Workers & Pages → Pages →「Upload assets」で `build/web` を上げる。転送量の制限がゆるいと言われています（最新の条件は公式で確認してください） |
| **GitHub Pages** | 下の「GitHub Pages で公開する」を見てください（自動ビルドの設定つき） |

## GitHub Pages で公開する

`https://ユーザー名.github.io/リポジトリ名/` で公開されます。リポジトリは**公開（Public）**にしてください（無料プランの GitHub Pages は公開リポジトリのみ）。

### 「README だけ表示される」ときは

GitHub Pages の設定が「ブランチの中身をそのまま公開する」になっていると、アプリではなくリポジトリの `README.md` がページとして表示されます。Flutter のソースコードをそのまま置いても動きません（ブラウザで動くのは、`flutter build web` でできた `build/web` の中身だけです。`build/` は `.gitignore` で除外してあるので、そのままでは push もされません）。

次の「自動ビルド」に切り替えれば直ります。

### 自動ビルドで公開する（おすすめ）

`.github/workflows/deploy-pages.yml` を同梱しています。`main` ブランチに push するたびに、GitHub のサーバーが Flutter をビルドして公開します。

1. zip を展開した内容を、リポジトリに入れて push する（`.github/workflows/deploy-pages.yml` が含まれていること。先頭が `.` のフォルダなので、見えないときは隠しファイルの表示をオンに）。ブランチ名が `main` でなければ、ファイルの `branches: [main]` を合わせる。
2. GitHub のリポジトリ →「Settings」→ 左の「Pages」→「Build and deployment」の **Source** を **「GitHub Actions」** にする。
3. 「Actions」タブで `Deploy to GitHub Pages` が緑のチェックになるのを待つ（数分）。赤い × のときは、開いて出ているエラーを教えてください。
4. 公開先は `https://ユーザー名.github.io/リポジトリ名/`。Actions の実行結果にも URL が出ます。

更新は、変更を `main` に push するだけです。

注意：
- サーバー側の Flutter は最新の stable です。手元で動いている版に合わせたいときは、`deploy-pages.yml` の `# flutter-version:` の行のコメントを外して、`flutter --version` で出た版を入れてください。
- リポジトリ名が `ユーザー名.github.io` のときだけ、公開先は `https://ユーザー名.github.io/`（フォルダなし）になります。ファイルが自動で切り替えます。
- 公開先の URL のフォルダ名と、ビルド時の `--base-href` が食い違うと白い画面になります。リポジトリ名を変えたら、もう一度 push してビルドし直してください。

### 手元でビルドして置く場合

`flutter build web --release --base-href "/リポジトリ名/"` の `build/web` の中身を、`gh-pages` ブランチなどに置き、Pages の Source をそのブランチにします。`build/web` に `.nojekyll`（空のファイル）を入れておくと安全です。

## うまくいかないとき

| 症状 | 確認すること |
| --- | --- |
| `firebase: command not found` | Node.js と `npm install -g firebase-tools` が済んでいるか。ターミナルを開き直す |
| `Error: Failed to get Firebase project` | プロジェクト ID の打ち間違い。`firebase projects:list` で確認 |
| Hosting のサイトが見つからない / not found | 3-1 の 5（コンソールで Hosting の「始める」）を済ませる |
| 公開したのに白い画面のまま | ブラウザの開発者ツール（F12）→ Console の赤いエラーを教えてください。ブラウザの拡張機能（広告ブロックなど）を切って試すのも有効です |
| 更新したのに古いまま | ページを 2 回読み込み直す。それでも古ければ、ブラウザのサイトデータを消す |
| 公開版で音が最初に鳴らない | ブラウザの自動再生ルールです。画面にさわると BGM が始まります（`flutter run` のときと同じ） |
| ある日から急に見られなくなった | 無料枠の転送量が上限に達した可能性。Firebase コンソールの Hosting で使用量を確認。翌日になると戻ることがあります。プランの見直しや、音の軽量化を検討してください |

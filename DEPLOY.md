# ウェブに公開する（GitHub Pages）

`https://ユーザー名.github.io/リポジトリ名/` で、URL を知っている人なら誰でも遊べる状態にする手順です。
GitHub Pages は **HTTPS** で配信されるので、スマホのカメラ・写真選択も使えます。無料です。

> この手順書と `.github/workflows/deploy-pages.yml` は、Flutter / GitHub に触れない環境で書きました。ビルドも公開も、ここでは一度も実行していません。止まったら、出たメッセージをそのまま教えてください。

Firebase Hosting で公開したいときは [DEPLOY-firebase.md](DEPLOY-firebase.md) を見てください（今は使いません）。

## 先に知っておくこと

- ブラウザで動くのは、`flutter build web` でできた `build/web` の中身だけです。Flutter のソースコードをそのまま置いても動きません。
- そこで、`main` ブランチに push するたびに **GitHub のサーバーが自動でビルドして公開する** 設定（`.github/workflows/deploy-pages.yml`）を同梱しています。自分の PC でビルドして上げる必要はありません。
- リポジトリは **公開（Public）** にしてください（無料プランの GitHub Pages は公開リポジトリのみ）。

## 公開する（最初の 1 回）

### 1. ファイルを GitHub に上げる

zip を展開した中身を、プロジェクトのフォルダ（`C:\programing\gag_othello`）に上書きコピーしたあと、そのフォルダのターミナルで次を実行します。

```bash
git add .
git commit -m "update"
git push
```

確認すること：

- `.github/workflows/deploy-pages.yml` が入っていること（先頭が `.` のフォルダなので、見えないときは隠しファイルの表示をオン）。GitHub の画面でリポジトリを開き、`.github` フォルダがあれば OK です。
- `web/index.html` が入っていること（なければ、先に `flutter create . --project-name gag_othello --platforms=android,ios,web` を一度実行してから push）。
- ブランチ名が `main` であること（違う場合は、`deploy-pages.yml` の `branches: [main]` を合わせる）。
- GitHub の画面の「Add file → Upload files」は、フォルダごとの上げ方に失敗しやすいので使わず、`git push` で上げてください。

### 2. Pages の設定を「GitHub Actions」にする

GitHub のリポジトリ →「Settings」→ 左の「Pages」→「Build and deployment」の **Source** を **「GitHub Actions」** にします。
（「Deploy from a branch」のままだと、アプリではなく README が表示されます。）

### 3. 公開されるのを待つ

「Actions」タブで `Deploy to GitHub Pages` が緑のチェックになるのを待ちます（数分）。赤い × のときは、開いて出ているエラーを教えてください。
公開先は `https://ユーザー名.github.io/リポジトリ名/` で、Actions の実行結果にも URL が出ます。

## 更新するとき

変更したファイルを `git add .` → `git commit -m "..."` → `git push` するだけです。数分後に公開版が入れ替わります。

更新したのに古いままのときは、ページを `Ctrl + Shift + R`（スマホは閉じて開き直す）で読み込み直します。タイトル画面の一番下に出る **`ver ...`** の印が、いま動いている版です。push した版と違えば、まだ古いほうが出ています。

## 手元で動かして確かめる

| やりたいこと | 方法 |
| --- | --- |
| 開発しながら確かめる | ターミナルで `flutter run -d chrome`（保存して `r` で更新） |
| 公開と同じビルドを確かめる | `flutter build web --release` のあと、`python -m http.server 8000 -d build/web` を実行して `http://localhost:8000` を開く（Ctrl + C で止める） |

### VS Code の「Go Live」（Live Server）は使えません

Go Live は、フォルダの中身をそのまま見せる道具です。Flutter のプロジェクトは、そのままでは Web ページになっていないので、次のようになります。

- プロジェクトのフォルダで Go Live → ファイル名の一覧だけが出る（`index.html` がないため）
- `web/index.html` を Go Live → 「よみこみ中」のまま（これはビルド前の部品です）

どうしても使うなら、`flutter build web --release` のあと、VS Code の設定 `liveServer.settings.root` を `/build/web` にして、`build/web/index.html` を Go Live で開きます。

## 注意

- サーバー側の Flutter は、手元と同じ **3.24.3** に固定してあります（`deploy-pages.yml` の `flutter-version`）。手元の Flutter を新しくしたら（`flutter --version` で確認）、この行も同じ版に書き換えてください。`pubspec.lock` も一緒に push してください（手元で動いた部品の版を、サーバーでも使うため）。
- リポジトリ名が `ユーザー名.github.io` のときだけ、公開先は `https://ユーザー名.github.io/`（フォルダなし）になります。ファイルが自動で切り替えます。
- 公開先の URL のフォルダ名と、ビルド時の `--base-href` が食い違うと白い画面になります。リポジトリ名を変えたら、もう一度 push してビルドし直してください。
- 顔写真は遊んでいる人の端末（ブラウザ）の中だけに保存され、サーバーには送られません。
- 自分の PC でビルドして `gh-pages` ブランチに置く方法もあります。その場合は `flutter build web --release --base-href "/リポジトリ名/"` の `build/web` の中身を置き、空の `.nojekyll` ファイルも入れ、Pages の Source をそのブランチにします。

## うまくいかないとき

| 症状 | 確認すること |
| --- | --- |
| アプリではなく README だけ表示される | Settings → Pages → Source が「GitHub Actions」になっているか |
| Actions が赤い × | 開いて、赤くなったステップのエラー文を教えてください |
| 白い画面 / 最初の「よみこみ中」から進まない | F12 → Console の赤いエラーを教えてください。Network タブで `main.dart.js` などが赤（404）なら、URL のフォルダ名と `--base-href` の食い違いです。広告ブロックなどの拡張機能を切って試すのも有効です |
| タイトルは出るが「はじめる」を押しても進まない | 公開版のアドレスの最後に `?debug=1` を付けて開く（例：`https://ユーザー名.github.io/リポジトリ名/?debug=1`）。画面の下に赤く「エラー: …」が出るので、その文を教えてください。F12 → Console の `gag_othello:` で始まる行も手がかりになります |
| 更新したのに古いまま | `Ctrl + Shift + R`。それでも古ければ、タイトル画面下の `ver` の印を確認。ブラウザのサイトデータを消すと確実です |
| 公開版で音が最初に鳴らない | ブラウザの自動再生ルールです。画面にさわると BGM が始まります（`flutter run` のときと同じ） |
| 公開版で赤いエラー表示が出ない | 仕様です。公開用ビルドでは隠しています。`?debug=1` を付けると出ます |

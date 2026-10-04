# Git 経由で社内 PC に導入する

USB メモリを持ち込めない環境向けの手順です。

```
開発側の PC ──push──► GitHub ──clone / ZIP──► 社内 PC
```

`IsatIo.exe` はリポジトリに含めません。社内 PC で `build.bat` を実行して作ります(`csc.exe` は Windows 標準なので、追加のインストールは要りません)。

## 1. GitHub に置く(開発側 PC・初回だけ)

1. GitHub で**空の**リポジトリを作ります(README や LICENSE は追加しない)。名前の例は `isatmon` です。
2. `isatmon-repo` フォルダの中で実行します。

   ```
   git init -b main
   git config user.name  "あなたの名前"
   git config user.email "<ID>+<ユーザー名>@users.noreply.github.com"
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/<ユーザー名>/isatmon.git
   git push -u origin main
   ```

   メールアドレスを公開したくないときは、上の `users.noreply.github.com` の形(GitHub の設定画面の Email に表示されます)を使います。

3. push の前に、`git status` と `git ls-files` で次のものが**含まれていない**ことを確認します(`.gitignore` で除外済みです)。
   - `Config.ps1`(COM 番号・発信先)
   - `logs\`、`data.js`、`probe_日時.txt`(実機の値や機器の情報が入ります)
   - `IsatIo.exe`

**公開リポジトリにする場合の注意**: コミットしたものは、誰でも見られます。社内の名称・電話番号・機器の情報を、ファイルに書き込まないでください。現在のファイルには、ダミーの電話番号(`+819012345678`)しか入っていません。

## 2. 社内 PC に入れる

### 2-A. Git が入っている場合

```
git clone https://github.com/<ユーザー名>/isatmon.git
cd isatmon\app
build.bat
```

更新するときは、次のとおりです。

```
cd isatmon
git pull
```

`IsatIo.cs` が変わったときだけ、`app\build.bat` を実行し直します。
`Config.ps1`・`logs\`・`IsatIo.exe` は Git の管理外なので、`git pull` で上書きされたり消えたりしません。

### 2-B. Git が入っていない場合(Windows 11 の標準機能だけ)

ブラウザで、リポジトリのページの **Code → Download ZIP** を選びます。コマンドで取るときは、次のとおりです。

```
curl.exe -L -o isatmon.zip https://github.com/<ユーザー名>/isatmon/archive/refs/heads/main.zip
Unblock-File .\isatmon.zip
Expand-Archive .\isatmon.zip -DestinationPath .
```

(`Unblock-File` と `Expand-Archive` は PowerShell のコマンドです。`curl.exe` はコマンドプロンプトでも使えます。)

- 展開すると `isatmon-main` というフォルダができます。その中の `app` を使います。
- **`Unblock-File` を忘れないでください。** インターネットから取った ZIP は「ブロック」の印が付いていて、展開したファイルまで引き継ぎます。そのまま `.bat` を開くと、セキュリティの警告が出ます。ZIP のプロパティで「許可する」にチェックを入れても同じです。
- 更新するときは、新しい ZIP を取り直し、展開した `app` の中身を前回のフォルダへ上書きコピーします。`Config.ps1` と `logs\` は ZIP に入っていないので、残ります。

## 3. 動作確認

```
cd app
build.bat          → BUILD OK: IsatIo.exe
MonitorMock.bat    → 疑似データで画面が動く
```

そのあと、実機の手順(`Config.ps1` の `$Port` → `Probe.bat` → `Monitor.bat`)に進みます。

## 4. 社内 → 外へ持ち出すもの

- `Probe.bat` の結果(`probe_日時.txt`)や `logs\` の CSV には、実機の情報や発信先が含まれることがあります。持ち出してよい内容かを確認してから、必要な部分だけを扱ってください。
- これらはリポジトリに入れないでください(`.gitignore` で除外してあります)。

## 5. うまくいかないとき

| 症状 | 原因と対処 |
|---|---|
| `git clone` で認証を求められる | 非公開リポジトリです。公開にするか、個人アクセストークンを使います |
| 社内プロキシ経由でしか外に出られない | `git config --global http.proxy http://<プロキシ>:<ポート>` を設定します。`curl.exe` は `-x http://<プロキシ>:<ポート>` を付けます |
| `.bat` を開くとセキュリティ警告が出る | ZIP の `Unblock-File` を忘れています。展開し直してください |
| `Monitor.ps1` が「署名されていません」と出る | `.ps1` を直接実行しています。`.bat` から起動すると出ません |
| `build.bat` が `BUILD FAILED` になる | 表示の上にあるコンパイラのエラーを確認します |

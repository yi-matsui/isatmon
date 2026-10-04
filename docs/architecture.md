# 設計メモ

## データの流れ

```
Monitor.ps1 ──(1 秒ごとにループ)──┐
   ├─ 時刻が $CallTimes に一致 → IsatIo.exe ... "ATD<番号>;" <秒> "ATH"
   └─ 周期ごと                   → IsatIo.exe ... "AT+CSQ" / "AT+CREG?" / $Extras
        │
        ├─► logs/isat_YYYYMM.csv   追記 (月別)
        └─► data.js                毎回まるごと書き換え (一時ファイル → 置換)

index.html ──(3 秒ごと)── <script src="data.js?t=…"> を差し替えて読み込み → カードとグラフを更新
```

## 設計判断

### HTTP サーバを使わない

画面は `file://` で開く静的な HTML です。データは JSON を `fetch` せず、**`<script>` タグで `data.js` を読み込みます**。
`fetch` は `file://` では CORS 制約で失敗しますが、`<script>` の読み込みは制約を受けません。
HttpListener による常駐サーバ(ブロッキング、CORS、エンコードの問題)が丸ごと不要になります。
URL にクエリ(`?t=…`)を付けてキャッシュを避けています。

### C# は I/O だけ

`IsatIo.exe` は `IsatIo.exe <Port> <BaudRate> <Cmd> [WaitSec] [AfterCmd]` で動き、応答を標準出力へそのまま出します。
コマンドの種類・応答の解釈・周期などの知識は持ちません。**C# を書き換える必要が出るのは、シリアル通信そのものを変えるときだけ**にしています。

- `AfterCmd` なし:応答の終端行(`OK` / `ERROR` / `NO CARRIER` / `+CME ERROR: n` など)を受信した時点で終了。`WaitSec` は上限です。終端は、これまでに受信した全文に対して判定するので、応答が途中で分割されても取りこぼしません。
- `AfterCmd` あり:`WaitSec` 秒間受信を続け、その後 `AfterCmd` を送ります。試験発信(`ATD…;` → 呼出 → `ATH`)用です。
- 終了コード:`0` 正常、`1` 引数不足、`2` I/O エラー。

### 収集ループは 1 秒刻み

取得周期(既定 180 秒)の間も、1 秒ごとに時刻を確認します。定時発信の `HH:mm` を取りこぼしません。
同じ分に 2 度発信しないよう、`yyyyMMdd_HHmm` をキーにして制御しています。発信の直後には、すぐに 1 回取得します。

### 更新停止の検知

`data.js` に取得周期(`intervalSec`)を含め、画面側で最終更新時刻と比べます。周期の 2 倍 + 10 秒を超えると **STALE** 表示にします。
`Monitor` の停止、COM の切断、`data.js` が出力されないとき、のいずれにも気づけます。

## data.js の形式

```js
window.ISAT_DATA = {
  "mock": false,
  "intervalSec": 180,
  "current": {
    "LastUpdate": "2026-10-04 08:00:03",
    "Rssi": 19,                      // AT+CSQ の <rssi> (0-31, 99=圏外)
    "Dbm": "-75 dBm",                // -113 + 2*Rssi
    "Ber": 99,
    "RegStatus": "同期完了 (Registered)",
    "Extras": [ { "name": "Operator", "value": "..." } ]   // Config.ps1 の $Extras
  },
  "history": [ { "t": "2026-10-04 08:00:03", "r": 19 } ]   // 直近 $HistoryMax 点。圏外(99)は 0
};
```

## CSV の形式

`logs/isat_YYYYMM.csv`(UTF-8 BOM 付き、Excel でそのまま開けます)

```
Timestamp,RSSI,dBm,BER,RegStatus,Notes
2026-10-04 08:00:03,19,-75 dBm,99,同期完了 (Registered),Periodic
2026-10-04 08:00:00,,,,,TestCall +81...        ← 試験発信の記録
```

`Notes` には、`Periodic`、`CSQ no response`、COM エラーのメッセージなどが入ります。

## 文字コードの規約

`.ps1` `.cs` `probe_commands.txt` は **UTF-8(BOM 付き)・CRLF** です(`.editorconfig` と `.gitattributes` で固定)。
BOM がないファイルは、日本語環境の Windows PowerShell 5.1 と `csc.exe` が ANSI(cp932)と誤読し、日本語の文字列が壊れます。
`.bat` は cmd が cp932 を使うため、**ASCII のみ**にしています(日本語を入れないでください)。

## 補足

- `Common.ps1` の `Invoke-At` は PowerShell から `IsatIo.exe` を呼びます。コマンド文字列に `"` を含むもの(`AT+CGDCONT=1,"IP","apn"` など)は、PowerShell 5.1 のネイティブコマンド引数の扱いで壊れるため、現状は送れません。
- `-Mock` の疑似応答は `Common.ps1` の `Get-MockResponse` にあります。`$Extras` で新しいコマンドを試すときは、ここに疑似応答を足すと画面で確認できます。

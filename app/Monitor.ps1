# ============================================================
# Monitor.ps1 : IsatPhone 2 監視 (収集 + CSV 保存 + data.js 出力)
#   使い方:  Monitor.bat  (実機)   /  Monitor.bat -Mock  (疑似データ)
#   ・シリアル I/O は IsatIo.exe に任せます (AT コマンドは引数で渡す)
#   ・Web サーバは使いません。index.html が data.js を読みます
#   ・設定は Config.ps1 だけで変えられます
# ============================================================
param(
    [switch]$Mock,
    [int]$IntervalSec = 0
)

$ErrorActionPreference = 'Continue'
$Dir = $PSScriptRoot
if (-not $Dir) { $Dir = Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $Dir
if (-not (Test-Path -LiteralPath (Join-Path $Dir 'Config.ps1'))) {
    Copy-Item -LiteralPath (Join-Path $Dir 'Config.sample.ps1') -Destination (Join-Path $Dir 'Config.ps1')
    Write-Host 'Config.ps1 を Config.sample.ps1 から作成しました。COM 番号などを確認してください。' -ForegroundColor Yellow
}
. (Join-Path $Dir 'Config.ps1')
. (Join-Path $Dir 'Common.ps1')
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ($IntervalSec -le 0) {
    if ($Mock) { $IntervalSec = $MockPollSec } else { $IntervalSec = $PollSec }
}

$LogPath = Join-Path $Dir $LogDir
if (-not (Test-Path -LiteralPath $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$DataJs    = Join-Path $Dir 'data.js'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom   = New-Object System.Text.UTF8Encoding($true)

$History = New-Object System.Collections.ArrayList
$Current = @{ LastUpdate = '--'; Rssi = 0; Dbm = 'N/A'; Ber = 99; RegStatus = '初期化中'; Extras = @() }
$LastCallKey = ''

# ---------------- CSV ----------------
function Get-CsvPath {
    param([datetime]$d)
    return (Join-Path $LogPath ('isat_' + $d.ToString('yyyyMM') + '.csv'))
}

function Add-CsvLine {
    param([datetime]$d, [string]$line)
    try {
        $p = Get-CsvPath $d
        if (-not (Test-Path -LiteralPath $p)) {
            [System.IO.File]::WriteAllText($p, "Timestamp,RSSI,dBm,BER,RegStatus,Notes`r`n", $Utf8Bom)
        }
        [System.IO.File]::AppendAllText($p, $line + "`r`n", $Utf8Bom)
    } catch {
        Write-Host ('CSV 書き込み失敗 (Excel で開いていませんか?): ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Import-History {
    $p = Get-CsvPath (Get-Date)
    if (-not (Test-Path -LiteralPath $p)) { return }
    $lines = Get-Content -LiteralPath $p -Encoding UTF8 | Select-Object -Last 200
    foreach ($l in $lines) {
        $c = $l -split ','
        $v = 0
        if ($c.Length -ge 4 -and [int]::TryParse($c[1], [ref]$v)) {
            [void]$History.Add(@{ t = $c[0]; r = $v })
        }
    }
    while ($History.Count -gt $HistoryMax) { $History.RemoveAt(0) }
}

# ---------------- data.js (画面用) ----------------
function Write-Data {
    $hist = @()
    foreach ($h in $History) {
        $r = $h.r
        if ($r -eq 99) { $r = 0 }          # 圏外(99)はグラフ上 0 で描く
        $hist += @{ t = $h.t; r = $r }
    }
    $obj = @{
        mock        = [bool]$Mock
        intervalSec = $IntervalSec
        current     = $Current
        history     = $hist
    }
    $json = ConvertTo-Json -InputObject $obj -Depth 5 -Compress
    $tmp  = $DataJs + '.tmp'
    [System.IO.File]::WriteAllText($tmp, ('window.ISAT_DATA = ' + $json + ';'), $Utf8NoBom)
    Move-Item -LiteralPath $tmp -Destination $DataJs -Force -ErrorAction SilentlyContinue
}

# ---------------- 1 回分の取得 ----------------
function Invoke-Poll {
    $now    = Get-Date
    $nowStr = $now.ToString('yyyy-MM-dd HH:mm:ss')
    $rssi = 99; $ber = 99; $dbm = 'N/A'; $reg = '不明'; $note = 'Periodic'

    # 信号強度 AT+CSQ -> +CSQ: <rssi>,<ber>
    $csq = Invoke-At 'AT+CSQ' 3
    $m = [regex]::Match($csq, '\+CSQ:\s*(\d+)\s*,\s*(\d+)')
    if ($m.Success) {
        $rssi = [int]$m.Groups[1].Value
        $ber  = [int]$m.Groups[2].Value
        if ($rssi -eq 99) { $dbm = '圏外' } else { $dbm = [string](-113 + 2 * $rssi) + ' dBm' }
    } else {
        $note = 'CSQ no response'
        if ($csq -match 'IO Error') {
            $reg  = 'ポートエラー'
            $note = ($csq.Trim() -split "`r?`n")[0]
        }
    }

    # 登録状態 AT+CREG? -> +CREG: <n>,<stat>
    $creg = Invoke-At 'AT+CREG?' 3
    $m = [regex]::Match($creg, '\+CREG:\s*\d+\s*,\s*(\d+)')
    if ($m.Success) {
        $code = $m.Groups[1].Value
        if ($RegText.ContainsKey($code)) { $reg = $RegText[$code] } else { $reg = '未登録 (' + $code + ')' }
    }

    # 追加カード (Config.ps1 の $Extras)
    $extraVals = @()
    foreach ($e in $Extras) {
        $r  = Invoke-At $e.Cmd 3
        $mm = [regex]::Match($r, $e.Regex)
        $val = 'N/A'
        if ($mm.Success) { $val = $mm.Groups[1].Value }
        $extraVals += @{ name = $e.Name; value = $val }
    }

    $regCsv  = $reg  -replace ',', ' '
    $noteCsv = $note -replace ',', ' '
    Add-CsvLine $now ($nowStr + ',' + $rssi + ',' + $dbm + ',' + $ber + ',' + $regCsv + ',' + $noteCsv)

    [void]$History.Add(@{ t = $nowStr; r = $rssi })
    while ($History.Count -gt $HistoryMax) { $History.RemoveAt(0) }

    $script:Current = @{ LastUpdate = $nowStr; Rssi = $rssi; Dbm = $dbm; Ber = $ber; RegStatus = $reg; Extras = $extraVals }
    Write-Data
    Write-Host ($nowStr + '  CSQ=' + $rssi + '  ' + $dbm + '  ' + $reg)
}

# ---------------- 定時試験発信 ----------------
function Invoke-TestCall {
    param([datetime]$now)
    Write-Host ($now.ToString('HH:mm') + '  試験発信 ' + $TestNumber + ' (' + $CallDuration + ' 秒)')
    [void](Invoke-At ('ATD' + $TestNumber + ';') $CallDuration 'ATH')
    Add-CsvLine $now ($now.ToString('yyyy-MM-dd HH:mm:ss') + ',,,,,TestCall ' + $TestNumber)
}

# ---------------- メイン ----------------
Import-History
Write-Data
$modeText = $Port + ' @' + $BaudRate
if ($Mock) { $modeText = 'MOCK' }
Write-Host '===================================================='
Write-Host (' IsatPhone 2 Monitor   mode=' + $modeText + '  interval=' + $IntervalSec + 's')
Write-Host (' 画面 : ' + (Join-Path $Dir 'index.html'))
Write-Host ' 終了 : Ctrl+C'
Write-Host '===================================================='

$next = Get-Date
while ($true) {
    $now = Get-Date
    $key = $now.ToString('yyyyMMdd_HHmm')
    if (($CallTimes -contains $now.ToString('HH:mm')) -and ($LastCallKey -ne $key)) {
        $LastCallKey = $key
        Invoke-TestCall $now
        $next = Get-Date                     # 発信の直後に 1 回取得する
    }
    if ($now -ge $next) {
        Invoke-Poll
        $next = (Get-Date).AddSeconds($IntervalSec)
    }
    Start-Sleep -Seconds 1
}

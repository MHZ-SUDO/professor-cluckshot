[CmdletBinding()]
param(
    [ValidateRange(30, 3600)]
    [int]$MinIntervalSeconds = 180,

    [ValidateRange(30, 7200)]
    [int]$MaxIntervalSeconds = 420
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($MaxIntervalSeconds -lt $MinIntervalSeconds) {
    throw 'MaxIntervalSeconds 不能小于 MinIntervalSeconds。'
}

$engine = Join-Path $PSScriptRoot 'PaperCheerOverlay.ps1'
$pidPath = Join-Path $PSScriptRoot 'paper-cheer-overlay.pid'
$powershell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

if (-not (Test-Path -LiteralPath $engine)) {
    throw "找不到气泡运行脚本：$engine"
}

if (Test-Path -LiteralPath $pidPath) {
    $existingId = (Get-Content -LiteralPath $pidPath -Raw -Encoding UTF8).Trim()
    if ($existingId -match '^\d+$') {
        $existing = Get-CimInstance Win32_Process -Filter "ProcessId = $existingId" -ErrorAction SilentlyContinue
        if ($null -ne $existing -and $existing.CommandLine -like "*PaperCheerOverlay.ps1*") {
            [pscustomobject]@{ started = $false; reason = 'already-running'; processId = [int]$existingId } | ConvertTo-Json -Compress
            exit 0
        }
    }
}

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-STA',
    '-File', ('"{0}"' -f $engine),
    '-MinIntervalSeconds', $MinIntervalSeconds,
    '-MaxIntervalSeconds', $MaxIntervalSeconds
)

$process = Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru
[System.IO.File]::WriteAllText($pidPath, [string]$process.Id, (New-Object System.Text.UTF8Encoding($false)))

[pscustomobject]@{
    started = $true
    processId = $process.Id
    minIntervalSeconds = $MinIntervalSeconds
    maxIntervalSeconds = $MaxIntervalSeconds
    anchor = 'Codex 宠物覆盖层上方'
    clickThrough = $true
} | ConvertTo-Json -Compress

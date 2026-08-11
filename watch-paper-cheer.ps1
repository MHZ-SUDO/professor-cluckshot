param(
    [ValidateRange(30, 86400)]
    [int]$IntervalSeconds = 300,

    [ValidateRange(0.0, 1.0)]
    [double]$Probability = 0.24,

    [ValidateRange(0, 86400000)]
    [int]$CooldownMs = 180000,

    [string]$RuntimeUrl = 'http://127.0.0.1:17321',

    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$powershell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$speaker = Join-Path $PSScriptRoot 'say-paper-cheer.ps1'

if (-not (Test-Path -LiteralPath $speaker)) {
    throw "找不到台词脚本：$speaker"
}

do {
    try {
        & $powershell -NoProfile -ExecutionPolicy Bypass -File $speaker `
            -Trigger random `
            -Probability $Probability `
            -CooldownMs $CooldownMs `
            -RuntimeUrl $RuntimeUrl
    }
    catch {
        Write-Warning ("Professor Cluckshot did not speak this round: {0}" -f $_.Exception.Message)
    }

    if ($Once) {
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
} while ($true)

[CmdletBinding()]
param(
    [ValidateSet('random','start','thinking','running','reviewing','waiting','success','failure','idle','click','hover','drag')]
    [string]$Trigger = 'random',

    [ValidateRange(3, 60)]
    [int]$VisibleSeconds = 15,

    [string]$Text
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pidPath = Join-Path $PSScriptRoot 'paper-cheer-overlay.pid'
$commandPath = Join-Path $PSScriptRoot 'paper-cheer-command.json'

if (-not (Test-Path -LiteralPath $pidPath)) {
    throw '台词旁车尚未启动。先运行 Start-PaperCheer.ps1。'
}

$processIdText = (Get-Content -LiteralPath $pidPath -Raw -Encoding UTF8).Trim()
$process = if ($processIdText -match '^\d+$') {
    Get-CimInstance Win32_Process -Filter "ProcessId = $processIdText" -ErrorAction SilentlyContinue
} else {
    $null
}

if ($null -eq $process -or $process.CommandLine -notlike '*PaperCheerOverlay.ps1*') {
    throw '台词旁车未在运行。先运行 Start-PaperCheer.ps1。'
}

$payload = [ordered]@{
    trigger = $Trigger
    visibleSeconds = $VisibleSeconds
    text = $Text
    requestedAt = (Get-Date).ToString('o')
}
$temporaryPath = "$commandPath.$PID.tmp"
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($temporaryPath, ($payload | ConvertTo-Json -Compress), $encoding)
Move-Item -LiteralPath $temporaryPath -Destination $commandPath -Force

[pscustomobject]@{
    queued = $true
    trigger = $Trigger
    visibleSeconds = $VisibleSeconds
    text = $Text
    processId = [int]$processIdText
} | ConvertTo-Json -Compress

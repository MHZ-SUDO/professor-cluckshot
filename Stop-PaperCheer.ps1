[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pidPath = Join-Path $PSScriptRoot 'paper-cheer-overlay.pid'
if (-not (Test-Path -LiteralPath $pidPath)) {
    [pscustomobject]@{ stopped = $false; reason = 'not-running' } | ConvertTo-Json -Compress
    exit 0
}

$processIdText = (Get-Content -LiteralPath $pidPath -Raw -Encoding UTF8).Trim()
$stopped = $false
if ($processIdText -match '^\d+$') {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processIdText" -ErrorAction SilentlyContinue
    if ($null -ne $process -and $process.CommandLine -like "*PaperCheerOverlay.ps1*") {
        Stop-Process -Id ([int]$processIdText) -ErrorAction Stop
        $stopped = $true
    }
}

Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
[pscustomobject]@{ stopped = $stopped; processId = $processIdText } | ConvertTo-Json -Compress

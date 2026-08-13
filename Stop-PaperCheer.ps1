[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sidecars = @(
    [pscustomobject]@{
        name = 'speechOverlay'
        scriptPath = Join-Path $PSScriptRoot 'PaperCheerOverlay.ps1'
        pidPath = Join-Path $PSScriptRoot 'paper-cheer-overlay.pid'
    },
    [pscustomobject]@{
        name = 'inputBridge'
        scriptPath = Join-Path $PSScriptRoot 'CodexPetInputBridge.ps1'
        pidPath = Join-Path $PSScriptRoot 'codex-pet-input-bridge.pid'
    }
)

function Get-SidecarProcessIds {
    param(
        [string]$ScriptPath,
        [string]$PidPath
    )

    $matches = @{}
    if (Test-Path -LiteralPath $PidPath) {
        $processIdText = (Get-Content -LiteralPath $PidPath -Raw -Encoding UTF8).Trim()
        if ($processIdText -match '^\d+$') {
            $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $processIdText" -ErrorAction SilentlyContinue
            if ($null -ne $candidate -and $null -ne $candidate.CommandLine -and
                $candidate.CommandLine.IndexOf($ScriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $matches[[int]$candidate.ProcessId] = $true
            }
        }
    }

    $processes = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue
    foreach ($candidate in $processes) {
        if ($null -ne $candidate.CommandLine -and
            $candidate.CommandLine.IndexOf($ScriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matches[[int]$candidate.ProcessId] = $true
        }
    }

    if ($matches.Count -eq 0) {
        return
    }

    foreach ($processId in $matches.Keys) {
        Write-Output ([int]$processId)
    }
}

$results = [ordered]@{}
foreach ($sidecar in $sidecars) {
    $processIds = @()
    $runningIds = @(Get-SidecarProcessIds -ScriptPath $sidecar.scriptPath -PidPath $sidecar.pidPath |
        Where-Object { $null -ne $_ -and [int]$_ -gt 0 })
    foreach ($processId in $runningIds) {
        Stop-Process -Id $processId -ErrorAction Stop
        $processIds += $processId
    }

    Remove-Item -LiteralPath $sidecar.pidPath -Force -ErrorAction SilentlyContinue
    $results[$sidecar.name] = [pscustomobject]@{
        stopped = $processIds.Count -gt 0
        processIds = @($processIds)
    }
}

[pscustomobject]@{
    stopped = $results.speechOverlay.stopped -or $results.inputBridge.stopped
    speechOverlay = $results.speechOverlay
    inputBridge = $results.inputBridge
} | ConvertTo-Json -Depth 4 -Compress

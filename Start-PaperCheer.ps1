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

$overlayScript = Join-Path $PSScriptRoot 'PaperCheerOverlay.ps1'
$bridgeScript = Join-Path $PSScriptRoot 'CodexPetInputBridge.ps1'
$overlayPidPath = Join-Path $PSScriptRoot 'paper-cheer-overlay.pid'
$bridgePidPath = Join-Path $PSScriptRoot 'codex-pet-input-bridge.pid'
$powershell = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $powershell)) {
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
}

foreach ($requiredScript in @($overlayScript, $bridgeScript)) {
    if (-not (Test-Path -LiteralPath $requiredScript)) {
        throw "找不到运行脚本：$requiredScript"
    }
}

function Get-SidecarProcess {
    param(
        [string]$ScriptPath,
        [string]$PidPath
    )

    $candidates = @()
    if (Test-Path -LiteralPath $PidPath) {
        $processIdText = (Get-Content -LiteralPath $PidPath -Raw -Encoding UTF8).Trim()
        if ($processIdText -match '^\d+$') {
            $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $processIdText" -ErrorAction SilentlyContinue
            if ($null -ne $candidate) {
                $candidates += $candidate
            }
        }
    }

    $candidates += @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue)
    foreach ($candidate in $candidates) {
        if ($null -ne $candidate.CommandLine -and
            $candidate.CommandLine.IndexOf($ScriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $candidate
        }
    }

    return $null
}

function Write-PidFile {
    param(
        [string]$Path,
        [int]$ProcessId
    )

    [System.IO.File]::WriteAllText($Path, [string]$ProcessId, (New-Object System.Text.UTF8Encoding($false)))
}

function Start-Sidecar {
    param(
        [string]$ScriptPath,
        [string]$PidPath,
        [string[]]$ExtraArguments,
        [switch]$Sta
    )

    $existing = Get-SidecarProcess -ScriptPath $ScriptPath -PidPath $PidPath
    if ($null -ne $existing) {
        Write-PidFile -Path $PidPath -ProcessId ([int]$existing.ProcessId)
        return [pscustomobject]@{
            started = $false
            reason = 'already-running'
            processId = [int]$existing.ProcessId
        }
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($Sta) {
        $arguments += '-STA'
    }
    $arguments += @('-File', ('"{0}"' -f $ScriptPath))
    $arguments += $ExtraArguments

    $process = Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 250
    if ($process.HasExited) {
        throw "运行脚本启动后立即退出：$ScriptPath"
    }

    Write-PidFile -Path $PidPath -ProcessId $process.Id
    return [pscustomobject]@{
        started = $true
        reason = 'started'
        processId = $process.Id
    }
}

$bridge = Start-Sidecar -ScriptPath $bridgeScript -PidPath $bridgePidPath -ExtraArguments @()
$pointerEventPath = Join-Path $PSScriptRoot 'paper-cheer-pointer-events.json'
$bridgeReady = $false
$bridgeReadyDeadline = (Get-Date).AddSeconds(5)
do {
    if (Test-Path -LiteralPath $pointerEventPath -PathType Leaf) {
        try {
            $pointerState = Get-Content -LiteralPath $pointerEventPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $bridgeReady = $null -ne $pointerState -and [int]$pointerState.processId -eq [int]$bridge.processId
        }
        catch {
            $bridgeReady = $false
        }
    }
    if (-not $bridgeReady) {
        Start-Sleep -Milliseconds 50
    }
} while (-not $bridgeReady -and (Get-Date) -lt $bridgeReadyDeadline)

if (-not $bridgeReady) {
    throw '输入桥未在限时内完成点击事件通道初始化。'
}

$overlay = Start-Sidecar -ScriptPath $overlayScript -PidPath $overlayPidPath -Sta -ExtraArguments @(
    '-MinIntervalSeconds', [string]$MinIntervalSeconds,
    '-MaxIntervalSeconds', [string]$MaxIntervalSeconds
)

[pscustomobject]@{
    started = $bridge.started -or $overlay.started
    inputBridge = $bridge
    speechOverlay = $overlay
    minIntervalSeconds = $MinIntervalSeconds
    maxIntervalSeconds = $MaxIntervalSeconds
    anchor = 'Codex 宠物旁边（原生像素定位）'
    bubbleClickThrough = $true
} | ConvertTo-Json -Depth 4 -Compress

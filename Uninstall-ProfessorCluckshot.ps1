[CmdletBinding()]
param(
    [string]$CodexHome,

    [string]$StartupFolder,

    [switch]$KeepFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $env:CODEX_HOME
    } else {
        Join-Path $env:USERPROFILE '.codex'
    }
}
if ([string]::IsNullOrWhiteSpace($StartupFolder)) {
    $StartupFolder = [Environment]::GetFolderPath('Startup')
}

$petPath = [IO.Path]::GetFullPath((Join-Path $CodexHome 'pets\professor-cluckshot')).TrimEnd('\')
$petParent = Split-Path -Parent $petPath
if ((Split-Path -Leaf $petPath) -ne 'professor-cluckshot' -or (Split-Path -Leaf $petParent) -ne 'pets') {
    throw "Refusing to remove unexpected path: $petPath"
}

$stopResult = $null
$stopScript = Join-Path $petPath 'Stop-PaperCheer.ps1'
if (Test-Path -LiteralPath $stopScript -PathType Leaf) {
    $stopOutput = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $stopScript
    $stopResult = $stopOutput | ConvertFrom-Json
}

$startupShortcutPath = Join-Path ([IO.Path]::GetFullPath($StartupFolder)) 'Professor Cluckshot.lnk'
if (Test-Path -LiteralPath $startupShortcutPath -PathType Leaf) {
    Remove-Item -LiteralPath $startupShortcutPath -Force
}

if (-not $KeepFiles -and (Test-Path -LiteralPath $petPath -PathType Container)) {
    Remove-Item -LiteralPath $petPath -Recurse -Force
}

[pscustomobject]@{
    uninstalled = -not $KeepFiles
    filesKept = [bool]$KeepFiles
    petPath = $petPath
    packageExists = Test-Path -LiteralPath $petPath -PathType Container
    startupRemoved = -not (Test-Path -LiteralPath $startupShortcutPath)
    stopResult = $stopResult
} | ConvertTo-Json -Depth 5 -Compress

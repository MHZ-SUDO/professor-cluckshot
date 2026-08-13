[CmdletBinding()]
param(
    [string]$CodexHome,

    [string]$StartupFolder,

    [switch]$NoStartup,

    [switch]$SkipStart
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

$sourcePath = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$petPath = [IO.Path]::GetFullPath((Join-Path $CodexHome 'pets\professor-cluckshot')).TrimEnd('\')
$startupPath = [IO.Path]::GetFullPath($StartupFolder).TrimEnd('\')
$startupShortcutPath = Join-Path $startupPath 'Professor Cluckshot.lnk'
$registerStartup = -not $NoStartup
$powershell = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $powershell)) {
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
}

$packageFiles = @(
    'ASSET_NOTICE.md',
    'CodexPetInputBridge.ps1',
    'Get-PaperCheerStatus.ps1',
    'Install-ProfessorCluckshot.ps1',
    'LICENSE',
    'package-version.json',
    'paper-cheer-dialogue.json',
    'PaperCheerOverlay.ps1',
    'pet.json',
    'README.md',
    'say-paper-cheer.ps1',
    'Show-PaperCheer.ps1',
    'spritesheet.webp',
    'Start-PaperCheer.ps1',
    'Stop-PaperCheer.ps1',
    'Uninstall-ProfessorCluckshot.ps1',
    'watch-paper-cheer.ps1'
)

foreach ($name in $packageFiles) {
    $sourceFile = Join-Path $sourcePath $name
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Package file is missing: $sourceFile"
    }
}

$oldStopScript = Join-Path $petPath 'Stop-PaperCheer.ps1'
if (Test-Path -LiteralPath $oldStopScript -PathType Leaf) {
    try {
        & $powershell -NoProfile -ExecutionPolicy Bypass -File $oldStopScript | Out-Null
    } catch {
        Write-Warning "Existing helpers could not be stopped cleanly: $($_.Exception.Message)"
    }
}

[void](New-Item -ItemType Directory -Path $petPath -Force)
if (-not [string]::Equals($sourcePath, $petPath, [StringComparison]::OrdinalIgnoreCase)) {
    foreach ($name in $packageFiles) {
        Copy-Item -LiteralPath (Join-Path $sourcePath $name) -Destination (Join-Path $petPath $name) -Force
    }
}

Get-ChildItem -LiteralPath $petPath -Filter '*.ps1' -File | Unblock-File

if ($registerStartup) {
    [void](New-Item -ItemType Directory -Path $startupPath -Force)
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $null
    try {
        $shortcut = $shell.CreateShortcut($startupShortcutPath)
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $petPath 'Start-PaperCheer.ps1')
        $shortcut.WorkingDirectory = $petPath
        $shortcut.WindowStyle = 7
        $shortcut.Description = 'Start Professor Cluckshot input repair and speech helpers'
        $shortcut.Save()
    } finally {
        if ($null -ne $shortcut) {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        }
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
} elseif (Test-Path -LiteralPath $startupShortcutPath -PathType Leaf) {
    Remove-Item -LiteralPath $startupShortcutPath -Force
}

$startResult = $null
if (-not $SkipStart) {
    $startOutput = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $petPath 'Start-PaperCheer.ps1')
    $startResult = $startOutput | ConvertFrom-Json
}

[pscustomobject]@{
    installed = $true
    version = '1.1.1'
    petPath = $petPath
    startupRegistered = $registerStartup -and (Test-Path -LiteralPath $startupShortcutPath)
    startupShortcut = if ($registerStartup) { $startupShortcutPath } else { $null }
    helpersStarted = -not $SkipStart
    startResult = $startResult
    codexRestartRequired = $false
} | ConvertTo-Json -Depth 6 -Compress

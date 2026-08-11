[CmdletBinding()]
param(
    [ValidateSet('random','start','thinking','running','reviewing','waiting','success','failure','idle')]
    [string]$Trigger = 'random',
    [double]$Probability = 0.24,
    [int]$CooldownMs = 180000,
    [string]$RuntimeUrl = 'http://127.0.0.1:17321',
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dialoguePath = Join-Path $scriptDir 'paper-cheer-dialogue.json'
$dialogue = Get-Content -LiteralPath $dialoguePath -Raw -Encoding UTF8 | ConvertFrom-Json
$stateDir = Join-Path $env:LOCALAPPDATA 'ProfessorCluckshot'
$statePath = Join-Path $stateDir 'state.json'

if (-not $Force -and $Trigger -eq 'random' -and (Get-Random -Minimum 0 -Maximum 10000) -ge [int]($Probability * 10000)) {
    [pscustomobject]@{ sent = $false; reason = 'random-gate'; trigger = $Trigger } | ConvertTo-Json -Compress
    exit 0
}

$state = [pscustomobject]@{ lastSentAt = 0L; recentIds = @() }
if (Test-Path -LiteralPath $statePath) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $state = [pscustomobject]@{ lastSentAt = 0L; recentIds = @() }
    }
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
if (-not $Force -and ($now - [int64]$state.lastSentAt) -lt $CooldownMs) {
    [pscustomobject]@{ sent = $false; reason = 'cooldown'; trigger = $Trigger } | ConvertTo-Json -Compress
    exit 0
}

$eligible = @($dialogue.messages | Where-Object { $_.triggers -contains $Trigger })
if ($eligible.Count -eq 0) { $eligible = @($dialogue.messages | Where-Object { $_.triggers -contains 'random' }) }
$recent = @($state.recentIds)
$fresh = @($eligible | Where-Object { $recent -notcontains $_.id })
if ($fresh.Count -gt 0) { $eligible = $fresh }

if ($Trigger -eq 'random') {
    $availableCategoryNames = @($eligible | ForEach-Object { $_.category } | Sort-Object -Unique)
    $categoryDefinitions = @(
        $dialogue.categories.psobject.Properties |
            Where-Object { $availableCategoryNames -contains $_.Name } |
            ForEach-Object { [pscustomobject]@{ name = $_.Name; weight = [int]$_.Value.weight } }
    )
    if ($categoryDefinitions.Count -gt 0) {
        $totalWeight = [int](($categoryDefinitions | Measure-Object -Property weight -Sum).Sum)
        $roll = Get-Random -Minimum 1 -Maximum ($totalWeight + 1)
        $cursor = 0
        $chosenCategory = $null
        foreach ($category in $categoryDefinitions) {
            $cursor += $category.weight
            if ($roll -le $cursor) { $chosenCategory = $category.name; break }
        }
        if ($chosenCategory) { $eligible = @($eligible | Where-Object { $_.category -eq $chosenCategory }) }
    }
}

$selected = $eligible | Get-Random
$newRecent = @($recent + $selected.id | Select-Object -Last ([int]$dialogue.runtime.recentHistorySize))
$result = [pscustomobject]@{
    sent = $true
    trigger = $Trigger
    messageId = $selected.id
    category = $selected.category
    text = $selected.text
    dryRun = [bool]$DryRun
}

if (-not $DryRun) {
    New-Item -ItemType Directory -Force $stateDir | Out-Null
    $body = @{ message = $selected.text; ttlMs = 6500 } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Method Post -Uri ($RuntimeUrl.TrimEnd('/') + '/api/say') -ContentType 'application/json' -Body $body | Out-Null
    } catch {
        throw "OpenPet 未运行或接口不可达：$RuntimeUrl。先启动 OpenPet，再重试。原台词为：$($selected.text)"
    }
    [pscustomobject]@{ lastSentAt = $now; recentIds = $newRecent } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

$result | ConvertTo-Json -Compress

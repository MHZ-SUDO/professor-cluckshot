[CmdletBinding()]
param(
    [string]$Package,
    [string]$Output
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Package)) { $Package = Split-Path -Parent $testDirectory }
if ([string]::IsNullOrWhiteSpace($Output)) { $Output = Join-Path $testDirectory 'immediate-speech-regression.json' }
$overlayPath = Join-Path $Package 'PaperCheerOverlay.ps1'
$sourceHash = (Get-FileHash -LiteralPath $overlayPath -Algorithm SHA256).Hash
$tokens = $null
$parseErrors = $null
$sourceAst = [Management.Automation.Language.Parser]::ParseFile($overlayPath, [ref]$tokens, [ref]$parseErrors)
$script:checks = [Collections.Generic.List[object]]::new()
$script:timings = [Collections.Generic.List[object]]::new()
$script:shows = [Collections.Generic.List[object]]::new()
$script:writes = [Collections.Generic.List[object]]::new()
$script:callOrder = [Collections.Generic.List[string]]::new()
$script:callInProgress = $false
$script:pointerEventPath = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Output))) ('.immediate-speech-fixture-' + [Guid]::NewGuid().ToString('N') + '.json')
$script:fixtureWriteIndex = 0
$script:fixtureEpoch = [DateTime]::UtcNow
$script:obsoleteReferences = @()

function Check {
    param([string]$Name, [bool]$Condition)
    $script:checks.Add([pscustomobject]@{name=$Name;passed=$Condition})
    if (-not $Condition) { throw "FAILED: $Name" }
}

# Only these two production functions are loaded. The source file is never
# dot-sourced, so no Add-Type, window, timer, input hook or process is started.
foreach ($functionName in @('Register-PetClick', 'Receive-PetPointerEvents')) {
    $definition = @($sourceAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $true) | Where-Object Name -eq $functionName)
    if ($definition.Count -ne 1) { throw "Expected exactly one definition: $functionName" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

function Write-PetInteractionState {
    param([string]$Action, [datetime]$At)
    $script:callOrder.Add('write:' + $Action)
    $script:writes.Add([pscustomobject]@{action=$Action;at=$At;insideCall=$script:callInProgress})
}

function Show-PetInteraction {
    param([string]$Trigger)
    $script:callOrder.Add('show:' + $Trigger)
    $script:shows.Add([pscustomobject]@{trigger=$Trigger;insideCall=$script:callInProgress;timestamp=[Diagnostics.Stopwatch]::GetTimestamp()})
}

function Reset-Harness {
    $script:shows.Clear()
    $script:writes.Clear()
    $script:callOrder.Clear()
    $script:lastPetClickAt = [datetime]::MinValue
    $script:lastPetHoverAt = [datetime]::MinValue
    $script:lastPetDragAt = [datetime]::MinValue
    $script:foregroundBeforePetClick = [IntPtr]::Zero
    $script:petHoverStartedAt = $null
    $script:pointerEventSession = ''
    $script:processedPointerEventIds = @()
    $script:lastPointerFileWriteTicks = 0L
    # Old double-click/ignore variables are intentionally NOT initialized.
}

function Invoke-TestClick {
    param([string]$Case, [datetime]$At, [IntPtr]$Foreground = [IntPtr]::Zero)
    $before = $script:shows.Count
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $script:callInProgress = $true
    try { Register-PetClick -At $At -X -19020 -Y -19100 -ForegroundBefore $Foreground }
    finally { $script:callInProgress = $false; $timer.Stop() }
    $script:timings.Add([pscustomobject]@{case=$Case;elapsedMs=$timer.Elapsed.TotalMilliseconds})
    Check "$Case speaks before Register returns" ($script:shows.Count -eq $before + 1 -and $script:shows[$before].insideCall)
    Check "$Case writes one immediate single" ($script:writes.Count -eq $script:shows.Count -and $script:writes[$before].action -eq 'single' -and $script:writes[$before].insideCall)
    Check "$Case preserves write/show order" ($script:callOrder[$before * 2] -eq 'write:single' -and $script:callOrder[$before * 2 + 1] -eq 'show:click')
}

function New-ClickEvent {
    param([string]$Id, [datetime]$At)
    return [ordered]@{id=$Id;kind='click';at=$At.ToUniversalTime().ToString('o');x=-19020;y=-19100;foregroundBefore=12345}
}

function Write-Fixture {
    param([string]$Session, [object[]]$Events)
    $payload = [ordered]@{sessionId=$Session;events=@($Events)}
    [IO.File]::WriteAllText($script:pointerEventPath, ($payload | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $script:fixtureWriteIndex++
    [IO.File]::SetLastWriteTimeUtc($script:pointerEventPath, $script:fixtureEpoch.AddMilliseconds($script:fixtureWriteIndex * 10))
}

function Invoke-Receive {
    $script:callInProgress = $true
    try { Receive-PetPointerEvents }
    finally { $script:callInProgress = $false }
}

$failure = $null
try {
    Check 'overlay parses without errors' (@($parseErrors).Count -eq 0)
    Reset-Harness
    $startAt = [DateTime]::UtcNow
    Invoke-TestClick -Case 'single click' -At $startAt -Foreground ([IntPtr]::new(12345))
    Check 'foreground metadata is retained' ($script:foregroundBeforePetClick.ToInt64() -eq 12345)
    Check 'single timestamp committed synchronously' ($script:lastPetClickAt -eq $startAt -and $script:lastPetHoverAt -eq $startAt)

    Reset-Harness
    Invoke-TestClick -Case 'double first' -At $startAt
    Invoke-TestClick -Case 'double second at 40ms' -At $startAt.AddMilliseconds(40)
    Check 'double click produces two speech calls' ($script:shows.Count -eq 2)
    foreach ($offset in @(100, 550, 1250, 2500, 2999)) {
        Invoke-TestClick -Case "follow-up at ${offset}ms" -At $startAt.AddMilliseconds($offset)
    }
    Check 'all five clicks within former three-second silence are delivered' ($script:shows.Count -eq 7)

    Reset-Harness
    $one = New-ClickEvent -Id 'event-one' -At $startAt
    $two = New-ClickEvent -Id 'event-two' -At $startAt.AddMilliseconds(40)
    Write-Fixture -Session 'fixture-a' -Events @($one)
    Invoke-Receive
    Check 'Receive dispatches the first event immediately' ($script:shows.Count -eq 1 -and $script:shows[0].insideCall)
    Check 'Receive stores the first id' ($script:processedPointerEventIds.Count -eq 1)
    Invoke-Receive
    Check 'unchanged file is not dispatched twice' ($script:shows.Count -eq 1 -and $script:writes.Count -eq 1)
    Write-Fixture -Session 'fixture-a' -Events @($one)
    Invoke-Receive
    Check 'rewritten repeated event is deduplicated' ($script:shows.Count -eq 1 -and $script:writes.Count -eq 1)
    Write-Fixture -Session 'fixture-a' -Events @($one, $two, $two)
    Invoke-Receive
    Check 'new event is delivered and within-file duplicate skipped' ($script:shows.Count -eq 2 -and $script:writes.Count -eq 2 -and $script:processedPointerEventIds.Count -eq 2)
    Write-Fixture -Session 'fixture-b' -Events @($one)
    Invoke-Receive
    Check 'new bridge session resets id deduplication' ($script:shows.Count -eq 3 -and $script:processedPointerEventIds.Count -eq 1)

    foreach ($scriptFile in @(Get-ChildItem -LiteralPath $Package -Filter '*.ps1' -File)) {
        $fileTokens=$null; $fileErrors=$null
        $fileAst=[Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$fileTokens, [ref]$fileErrors)
        Check "$($scriptFile.Name) parses" (@($fileErrors).Count -eq 0)
        foreach ($variable in @($fileAst.FindAll({param($node) $node -is [Management.Automation.Language.VariableExpressionAst]}, $true))) {
            $name = $variable.VariablePath.UserPath -replace '^(script|global|local|private):', ''
            if ($name -notin @('doubleClickMilliseconds','ignorePetClicksUntil','systemDoubleClickMilliseconds','pendingPetClickAt','pendingPetClickX','pendingPetClickY')) { continue }
            $assignment = $variable.Parent -is [Management.Automation.Language.AssignmentStatementAst] -and $variable.Parent.Left -eq $variable
            $script:obsoleteReferences += [pscustomobject]@{file=$scriptFile.Name;line=$variable.Extent.StartLineNumber;variable=$name;assignmentOnly=$assignment}
        }
    }
    $removedReferences = @($script:obsoleteReferences | Where-Object { $_.variable -in @('doubleClickMilliseconds','ignorePetClicksUntil') })
    $oldReads = @($script:obsoleteReferences | Where-Object { -not $_.assignmentOnly })
    Check 'removed delay and ignore variables have no references' ($removedReferences.Count -eq 0)
    Check 'remaining legacy variables are assignments only, not StrictMode reads' ($oldReads.Count -eq 0)
    Check 'candidate source unchanged' ((Get-FileHash -LiteralPath $overlayPath -Algorithm SHA256).Hash -eq $sourceHash)
} catch {
    $failure = $_.Exception.Message + ' at line ' + $_.InvocationInfo.ScriptLineNumber
} finally {
    if (Test-Path -LiteralPath $script:pointerEventPath) { Remove-Item -LiteralPath $script:pointerEventPath -Force }
}

$report = [ordered]@{
    passed = ($null -eq $failure)
    error = $failure
    packageVersion = (Get-Content -LiteralPath (Join-Path $Package 'package-version.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
    sourceSha256 = $sourceHash
    checks = @($script:checks.ToArray())
    callTimings = @($script:timings.ToArray())
    legacyVariableReferences = @($script:obsoleteReferences)
    scope = 'AST-extracted functions under StrictMode with Show/Write stubs and an isolated event file. No WPF, native input, hooks or helper processes. Timing measures function dispatch, not visible frame latency.'
}
[IO.File]::WriteAllText($Output, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{passed=$report.passed;error=$failure;checks=$script:checks.Count;callsTimed=$script:timings.Count;maxCallMs=($script:timings | Measure-Object -Property elapsedMs -Maximum).Maximum;output=$Output} | ConvertTo-Json -Compress
if (-not $report.passed) { exit 1 }

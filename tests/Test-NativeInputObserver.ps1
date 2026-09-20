param(
    [string]$Package = (Split-Path -Parent $PSScriptRoot),
    [string]$Output = (Join-Path $PSScriptRoot 'native-input-regression.json')
)
$ErrorActionPreference = 'Stop'
$bridgePath = Join-Path $Package 'CodexPetInputBridge.ps1'
$bridgeHashAtStart = (Get-FileHash -LiteralPath $bridgePath -Algorithm SHA256).Hash
$bridgeText = [IO.File]::ReadAllText($bridgePath)
$bridgeMatch = [regex]::Match($bridgeText, "(?s)\`$source = @'\r?\n(.*?)\r?\n'@")
if (-not $bridgeMatch.Success) { throw 'Cannot extract bridge C#' }
$nativeSource = $bridgeMatch.Groups[1].Value.Replace('Local\ProfessorCluckshotInputGesture',('Local\CluckshotObserverFixture_' + $PID))
$fixtureSource = @'

public static class NativeObserverFixture {
    private delegate IntPtr WindowProc(IntPtr h,uint m,IntPtr w,IntPtr l);
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    private struct WNDCLASS {
        public uint style; public WindowProc proc; public int clsExtra,wndExtra;
        public IntPtr instance,icon,cursor,background; public string menuName,className;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MSG { public IntPtr h; public uint m; public UIntPtr w; public IntPtr l; public uint time; public int x,y; public uint extra; }
    private static WindowProc proc=WndProc;
    public static int MouseMessages, StyleChanges;
    public static readonly List<long> OwnedWindows=new List<long>();
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern ushort RegisterClass(ref WNDCLASS c);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int width,int height,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr param);
    [DllImport("user32.dll")] private static extern IntPtr DefWindowProc(IntPtr h,uint m,IntPtr w,IntPtr l);
    [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int show);
    [DllImport("user32.dll")] private static extern bool SetLayeredWindowAttributes(IntPtr h,uint key,byte alpha,uint flags);
    [DllImport("user32.dll")] private static extern bool PeekMessage(out MSG m,IntPtr h,uint min,uint max,uint flags);
    [DllImport("user32.dll")] private static extern IntPtr DispatchMessage(ref MSG m);
    private static IntPtr WndProc(IntPtr h,uint m,IntPtr w,IntPtr l) {
        if (m>=0x200 && m<=0x202) MouseMessages++;
        if (m==0x7d) StyleChanges++;
        return DefWindowProc(h,m,w,l);
    }
    public static void Init() {
        foreach(string name in new[]{"CluckshotObserver_QA","Chrome_RenderWidgetHostHWND"}) {
            var c=new WNDCLASS {proc=proc,className=name};
            if(RegisterClass(ref c)==0) throw new InvalidOperationException("RegisterClass failed");
        }
    }
    public static IntPtr Create(bool blocker) {
        uint ex=blocker ? 0x08080088U : 0x080800A8U;
        IntPtr h=CreateWindowEx(ex,"CluckshotObserver_QA","Offscreen observer fixture",0x90000000U,-20000,-20000,500,500,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
        if(h==IntPtr.Zero) throw new InvalidOperationException("Fixture creation failed");
        OwnedWindows.Add(h.ToInt64());
        SetLayeredWindowAttributes(h,0,0,2);
        if(!blocker) {
            IntPtr child=CreateWindowEx(0,"Chrome_RenderWidgetHostHWND","",0x50000000U,0,0,500,500,h,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
            if(child==IntPtr.Zero) throw new InvalidOperationException("Renderer fixture creation failed");
        }
        Pump(); return h;
    }
    public static void Pump() { MSG m; while(PeekMessage(out m,IntPtr.Zero,0,0,1)) DispatchMessage(ref m); }
    public static bool Route(int message,int x,int y,uint flags) {
        return ProfessorCluckshotInputNative.ProcessPointer(message,new ProfessorCluckshotInputNative.POINT { X=x,Y=y },flags);
    }
    public static long Style(IntPtr h) { return ProfessorCluckshotInputNative.GetWindowLongPtr(h,-20).ToInt64(); }
    public static void ExpireTarget() {
        var f=typeof(ProfessorCluckshotInputNative).GetField("CurrentTarget",System.Reflection.BindingFlags.Static|System.Reflection.BindingFlags.NonPublic);
        object target=f.GetValue(null);
        if(target==null) throw new InvalidOperationException("No configured target to expire");
        target.GetType().GetField("ExpiresAt").SetValue(target,DateTime.UtcNow.AddSeconds(-1).Ticks);
    }
    public static void Cleanup() {
        foreach(long h in OwnedWindows) if(ProfessorCluckshotInputNative.IsWindow(new IntPtr(h))) DestroyWindow(new IntPtr(h));
        OwnedWindows.Clear();
    }
}
'@
Add-Type -TypeDefinition ($nativeSource + [Environment]::NewLine + $fixtureSource)
[void][ProfessorCluckshotInputNative]::EnablePerMonitorV2ForCurrentThread()
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($bridgeText,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Candidate PowerShell does not parse' }
$publishAst = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Publish-PetBodyClick'},$true)
$drainAst = $ast.Find({param($node) $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Condition.Extent.Text -like '*DrainMouseHookEvents*'},$true)
if ($null -eq $publishAst -or $null -eq $drainAst) { throw 'Cannot find production event publication pipeline' }
# Execute the real payload-construction and dispatch classification logic.
# Returning false here prevents any production JSON write or speech-window notice.
function Write-PointerEventFile { return $false }
Invoke-Expression $publishAst.Extent.Text
$drainPipeline = [scriptblock]::Create($drainAst.Extent.Text)
$script:pointerEventSession = 'isolated-observer-fixture'
$script:pointerEventSequence = 0
$script:pointerEvents = @()
$script:petAutomationLayout = $null
$script:lastOverlayPointer = $null
$script:caseResults = [Collections.Generic.List[object]]::new()
$script:checks = [Collections.Generic.List[object]]::new()
$script:fixture = [IntPtr]::Zero
$foregroundBefore = [ProfessorCluckshotInputNative]::GetForegroundWindow().ToInt64()
function Check([string]$Name,[bool]$Condition) {
    $script:checks.Add([pscustomobject]@{name=$Name;passed=$Condition})
    if (-not $Condition) { throw "FAILED: $Name" }
}
function Start-Case([string]$Name) {
    Check "$Name starts without active gesture" (-not [ProfessorCluckshotInputNative]::IsGestureActive())
    [NativeObserverFixture]::Cleanup()
    [Threading.Thread]::Sleep(90)
    [void][ProfessorCluckshotInputNative]::DrainMouseHookEvents()
    $script:pointerEvents = @()
    $script:lastOverlayPointer = $null
    $script:fixture = [NativeObserverFixture]::Create($false)
    [ProfessorCluckshotInputNative]::ConfigurePetTargets($script:fixture,[int[]]@(-19900,-19940,-19820,-19850),[int[]]@(-19780,-19850,-19720,-19810))
    [NativeObserverFixture]::MouseMessages = 0
}
function Route([int]$Message,[int]$X=-19880,[int]$Y=-19920,[uint32]$Flags=0) {
    $consumed = [NativeObserverFixture]::Route($Message,$X,$Y,$Flags)
    Check ('input 0x{0:x} at ({1},{2}) is passed through' -f $Message,$X,$Y) (-not $consumed)
}
function Complete-Case([string]$Name,[string]$ExpectedKind='',[object]$Extra=$null) {
    [NativeObserverFixture]::Pump()
    . $drainPipeline
    Check "$Name leaves gesture inactive" (-not [ProfessorCluckshotInputNative]::IsGestureActive())
    Check "$Name sends no synthetic native mouse messages" ([NativeObserverFixture]::MouseMessages -eq 0)
    if ($ExpectedKind) {
        Check "$Name publishes exactly one $ExpectedKind event" ($script:pointerEvents.Count -eq 1 -and $script:pointerEvents[0].kind -eq $ExpectedKind)
        Check "$Name never reports suppressing or deflecting physical input" (-not $script:pointerEvents[0].nativeClickSuppressed -and -not $script:pointerEvents[0].nativeClickDeflected)
    } else { Check "$Name publishes no speech event" ($script:pointerEvents.Count -eq 0) }
    $script:caseResults.Add([pscustomobject]@{name=$Name;expectedEventKind=$ExpectedKind;publishedEvents=@($script:pointerEvents);nativeMouseMessages=[NativeObserverFixture]::MouseMessages;extra=$Extra})
}
$errorText = $null
try {
    [NativeObserverFixture]::Init()
    Check 'fixture never installs a global mouse hook' (-not [ProfessorCluckshotInputNative]::IsMouseHookActive())

    Start-Case 'body-click'
    Route 0x200
    Check 'idle hover enables native pointer access over body' (([NativeObserverFixture]::Style($script:fixture) -band 0x20) -eq 0)
    Route 0x201; Route 0x202
    Complete-Case 'body-click' 'click'

    Start-Case 'body-drag-out-and-back'
    Route 0x201
    $startStyle=[NativeObserverFixture]::Style($script:fixture)
    $startChanges=[NativeObserverFixture]::StyleChanges
    Route 0x200 -19700 -19700
    Route 0x200 -20100 -20100
    Route 0x200
    [ProfessorCluckshotInputNative]::RefreshNativePointerAccess()
    Check 'physical drag moves leave window style unchanged' ([NativeObserverFixture]::Style($script:fixture) -eq $startStyle -and [NativeObserverFixture]::StyleChanges -eq $startChanges)
    Route 0x202
    Check 'release leaves window style unchanged' ([NativeObserverFixture]::Style($script:fixture) -eq $startStyle -and [NativeObserverFixture]::StyleChanges -eq $startChanges)
    Complete-Case 'body-drag-out-and-back' 'drag' ([pscustomobject]@{styleBefore=$startStyle;styleAfter=[NativeObserverFixture]::Style($script:fixture);styleChangesDuringGesture=([NativeObserverFixture]::StyleChanges-$startChanges)})

    Start-Case 'button-click'
    Route 0x201 -19750 -19830; Route 0x202 -19750 -19830
    Complete-Case 'button-click'

    Start-Case 'screenshot-occlusion'
    $blocker=[NativeObserverFixture]::Create($true)
    Route 0x200
    Check 'covered pet remains click-through' (([NativeObserverFixture]::Style($script:fixture) -band 0x20) -ne 0)
    Route 0x201; Route 0x202
    Complete-Case 'screenshot-occlusion'

    Start-Case 'hidden-overlay'
    [void][NativeObserverFixture]::ShowWindow($script:fixture,0)
    Route 0x201; Route 0x202
    Complete-Case 'hidden-overlay'

    Start-Case 'expired-target'
    [NativeObserverFixture]::ExpireTarget()
    Route 0x200; Route 0x201; Route 0x202
    Complete-Case 'expired-target'

    Start-Case 'outside-target'
    Route 0x200 -19980 -19980; Route 0x201 -19980 -19980; Route 0x202 -19980 -19980
    Complete-Case 'outside-target'

    Start-Case 'idle-target-loss-restores-click-through'
    Route 0x200
    Check 'hover first gives native hit access' (([NativeObserverFixture]::Style($script:fixture) -band 0x20) -eq 0)
    [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
    Route 0x200 -19980 -19980
    Check 'cleared idle target restores previous overlay click-through' (([NativeObserverFixture]::Style($script:fixture) -band 0x20) -ne 0)
    Complete-Case 'idle-target-loss-restores-click-through'

    Start-Case 'injected-input'
    Route 0x201 -19880 -19920 1; Route 0x200 -19700 -19700 1; Route 0x202 -19700 -19700 1
    Complete-Case 'injected-input'

    Start-Case 'target-refresh-loss-during-drag'
    Route 0x201
    [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
    Route 0x200 -19700 -19700; Route 0x202 -20100 -20100
    Complete-Case 'target-refresh-loss-during-drag' 'drag'

    Start-Case 'window-destroyed-during-drag'
    Route 0x201
    [void][NativeObserverFixture]::DestroyWindow($script:fixture)
    Route 0x200 -19700 -19700; Route 0x202 -19700 -19700
    Complete-Case 'window-destroyed-during-drag' 'drag'

    $diagnostics=[ProfessorCluckshotInputNative]::GetRelayDiagnostics()
    Check 'diagnostics report no relayed moves or pending relay work' ($diagnostics.DeliveredMoves -eq 0 -and $diagnostics.PendingGestures -eq 0 -and [string]::IsNullOrEmpty($diagnostics.LastError))
    Check 'no physical button transitions suppressed' ([ProfessorCluckshotInputNative]::GetBodyInputSuppressionCount() -eq 0)
    Check 'global mouse hook remains uninstalled' (-not [ProfessorCluckshotInputNative]::IsMouseHookActive())
    Check 'candidate source unchanged during test' ((Get-FileHash -LiteralPath $bridgePath -Algorithm SHA256).Hash -eq $bridgeHashAtStart)
} catch {
    $errorText=$_.Exception.Message
} finally {
    [NativeObserverFixture]::Cleanup()
}
$foregroundAfter = [ProfessorCluckshotInputNative]::GetForegroundWindow().ToInt64()
$report = [ordered]@{
    generatedAt=[DateTime]::UtcNow.ToString('o')
    bridgePath=$bridgePath
    bridgeSHA256=$bridgeHashAtStart
    packageVersion=(Get-Content -LiteralPath (Join-Path $Package 'package-version.json') -Raw | ConvertFrom-Json).version
    passed=($null -eq $errorText)
    error=$errorText
    scope='Offscreen Win32 fixture invoking the production ProcessPointer and click/drag publication pipeline. Does not install a hook, inject physical input, render speech, or validate live Chromium drag smoothness.'
    eventIsolation='Production named input event replaced with a process-specific fixture name; JSON-write stub returns false and blocks real speech notification.'
    untestedNativeBoundary='Expired bounds are verified to publish no speech. The stale-geometry native WindowFromPoint fallback is not forced by this fully transparent offscreen fixture; real physical hit dispatch and serialized hook-thread refresh require live verification.'
    foregroundBefore=$foregroundBefore;foregroundAfter=$foregroundAfter;foregroundUnchanged=($foregroundBefore -eq $foregroundAfter)
    cursorMovementRequested=$false;productionWindowMoved=$false;productionHelperRestarted=$false
    diagnostics=[ProfessorCluckshotInputNative]::GetRelayDiagnostics()
    checks=$script:checks.ToArray()
    cases=$script:caseResults.ToArray()
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Output -Encoding UTF8
[pscustomobject]@{passed=$report.passed;error=$errorText;checks=$script:checks.Count;cases=$script:caseResults.Count;output=$Output;foregroundUnchanged=$report.foregroundUnchanged} | ConvertTo-Json
if ($errorText) { throw $errorText }

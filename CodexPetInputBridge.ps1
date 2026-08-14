[CmdletBinding()]
param(
    [switch]$ProbeOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class ProfessorCluckshotInputNative
{
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public int Size;
        public RECT Monitor;
        public RECT Work;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT point);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hwnd,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags
    );

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [DllImport("user32.dll")]
    public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    public static bool GetPetHorizontalBand(IntPtr overlay, out double leftFraction, out double rightFraction)
    {
        leftFraction = 0.42;
        rightFraction = 0.58;

        RECT rect;
        if (!GetWindowRect(overlay, out rect)) return false;
        IntPtr monitor = MonitorFromWindow(overlay, 2);
        MONITORINFO info = new MONITORINFO();
        info.Size = Marshal.SizeOf(typeof(MONITORINFO));
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) return false;

        const int edgeTolerance = 24;
        if (rect.Left <= info.Work.Left + edgeTolerance)
        {
            leftFraction = 0.06;
            rightFraction = 0.22;
        }
        else if (rect.Right >= info.Work.Right - edgeTolerance)
        {
            leftFraction = 0.77;
            rightFraction = 0.92;
        }
        return true;
    }

    public static IntPtr FindOverlay()
    {
        IntPtr bestPreferred = IntPtr.Zero;
        IntPtr bestFallback = IntPtr.Zero;
        int bestPreferredScore = Int32.MaxValue;
        int bestFallbackScore = Int32.MaxValue;

        EnumWindows((hwnd, lParam) =>
        {
            var className = new StringBuilder(128);
            var title = new StringBuilder(128);
            GetClassName(hwnd, className, className.Capacity);
            GetWindowText(hwnd, title, title.Capacity);

            RECT rect;
            string windowClass = className.ToString();
            if ((windowClass != "Chrome_WidgetWin_1" && windowClass != "FLUTTERVIEW") ||
                title.ToString() != "Codex" ||
                !IsWindowVisible(hwnd) ||
                !GetWindowRect(hwnd, out rect))
            {
                return true;
            }

            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width < 120 || width > 1200 || height < 120 || height > 1200)
            {
                return true;
            }

            long style = GetWindowLongPtr(hwnd, -20).ToInt64();
            bool preferred = (style & 0x8L) != 0 && (style & 0x80L) != 0;
            int score = (Math.Abs(width - height) * 4) + width + height;
            if (preferred && score < bestPreferredScore)
            {
                bestPreferred = hwnd;
                bestPreferredScore = score;
            }
            if (score < bestFallbackScore)
            {
                bestFallback = hwnd;
                bestFallbackScore = score;
            }

            return true;
        }, IntPtr.Zero);

        return bestPreferred != IntPtr.Zero ? bestPreferred : bestFallback;
    }

    public static IntPtr FindRenderer(IntPtr overlay)
    {
        IntPtr result = IntPtr.Zero;
        EnumChildWindows(overlay, (hwnd, lParam) =>
        {
            var className = new StringBuilder(128);
            GetClassName(hwnd, className, className.Capacity);
            string windowClass = className.ToString();
            if (windowClass == "Chrome_RenderWidgetHostHWND" || windowClass == "FLUTTERVIEW")
            {
                result = hwnd;
                return false;
            }

            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static IntPtr MakeMouseLParam(int x, int y)
    {
        long packed = (ushort)x | ((long)(ushort)y << 16);
        return new IntPtr(packed);
    }
}
'@

Add-Type -TypeDefinition $source

function Get-OverlaySnapshot {
    param([IntPtr]$Overlay)

    if ($Overlay -eq [IntPtr]::Zero -or -not [ProfessorCluckshotInputNative]::IsWindow($Overlay)) {
        return $null
    }

    $rect = New-Object ProfessorCluckshotInputNative+RECT
    $cursor = New-Object ProfessorCluckshotInputNative+POINT
    if (-not [ProfessorCluckshotInputNative]::GetWindowRect($Overlay, [ref]$rect)) {
        return $null
    }

    $hasCursor = [ProfessorCluckshotInputNative]::GetCursorPos([ref]$cursor)
    $inside = $hasCursor -and
        $cursor.X -ge $rect.Left -and $cursor.X -lt $rect.Right -and
        $cursor.Y -ge $rect.Top -and $cursor.Y -lt $rect.Bottom
    $extendedStyle = [ProfessorCluckshotInputNative]::GetWindowLongPtr($Overlay, -20).ToInt64()
    $transparent = ($extendedStyle -band 0x20) -ne 0
    [uint32]$ownerProcessId = 0
    [void][ProfessorCluckshotInputNative]::GetWindowThreadProcessId($Overlay, [ref]$ownerProcessId)
    [double]$petBandLeft = 0.42
    [double]$petBandRight = 0.58
    [void][ProfessorCluckshotInputNative]::GetPetHorizontalBand(
        $Overlay,
        [ref]$petBandLeft,
        [ref]$petBandRight
    )

    [pscustomobject]@{
        overlay = $Overlay
        ownerProcessId = [int]$ownerProcessId
        left = $rect.Left
        top = $rect.Top
        width = $rect.Right - $rect.Left
        height = $rect.Bottom - $rect.Top
        cursorX = if ($hasCursor) { $cursor.X } else { $null }
        cursorY = if ($hasCursor) { $cursor.Y } else { $null }
        cursorInside = [bool]$inside
        extendedStyle = $extendedStyle
        transparent = [bool]$transparent
        layered = [bool](($extendedStyle -band 0x80000) -ne 0)
        noActivate = [bool](($extendedStyle -band 0x8000000) -ne 0)
        petBandLeft = $petBandLeft
        petBandRight = $petBandRight
    }
}

function Send-OverlayMouseMove {
    param($Snapshot)

    if ($null -eq $Snapshot -or -not $Snapshot.cursorInside -or -not $Snapshot.transparent) {
        return $false
    }

    $localX = $Snapshot.cursorX - $Snapshot.left
    $localY = $Snapshot.cursorY - $Snapshot.top
    return [ProfessorCluckshotInputNative]::PostMessage(
        $Snapshot.overlay,
        0x0200,
        [IntPtr]::Zero,
        [ProfessorCluckshotInputNative]::MakeMouseLParam($localX, $localY)
    )
}

function Test-PetControlZone {
    param($Snapshot)

    if ($null -eq $Snapshot -or -not $Snapshot.cursorInside) {
        return $false
    }

    $localX = $Snapshot.cursorX - $Snapshot.left
    $localY = $Snapshot.cursorY - $Snapshot.top
    return $localX -ge [Math]::Round($Snapshot.width * [Math]::Max(0.0, $Snapshot.petBandLeft - 0.06)) -and
        $localX -le [Math]::Round($Snapshot.width * [Math]::Min(1.0, $Snapshot.petBandRight + 0.06)) -and
        $localY -ge [Math]::Round($Snapshot.height * 0.45) -and
        $localY -lt $Snapshot.height
}

function Test-PetButtonZone {
    param($Snapshot)

    if ($null -eq $Snapshot -or -not $Snapshot.cursorInside) {
        return $false
    }

    $localX = $Snapshot.cursorX - $Snapshot.left
    $localY = $Snapshot.cursorY - $Snapshot.top
    return $localX -ge [Math]::Round($Snapshot.width * [Math]::Max(0.0, $Snapshot.petBandLeft - 0.04)) -and
        $localX -le [Math]::Round($Snapshot.width * [Math]::Min(1.0, $Snapshot.petBandRight + 0.04)) -and
        $localY -ge [Math]::Round($Snapshot.height * 0.90) -and
        $localY -lt $Snapshot.height
}

function Test-PetBodyZone {
    param($Snapshot)

    if ($null -eq $Snapshot -or -not $Snapshot.cursorInside) {
        return $false
    }

    $localX = $Snapshot.cursorX - $Snapshot.left
    $localY = $Snapshot.cursorY - $Snapshot.top
    return $localX -ge [Math]::Round($Snapshot.width * [Math]::Max(0.0, $Snapshot.petBandLeft - 0.02)) -and
        $localX -le [Math]::Round($Snapshot.width * [Math]::Min(1.0, $Snapshot.petBandRight + 0.04)) -and
        $localY -ge [Math]::Round($Snapshot.height * 0.62) -and
        $localY -lt [Math]::Round($Snapshot.height * 0.90)
}

function Write-RelayState {
    param(
        $Snapshot,
        [IntPtr]$Renderer,
        [IntPtr]$HitRoot
    )

    $statePath = Join-Path $PSScriptRoot 'codex-pet-input-bridge-state.json'
    $state = [ordered]@{
        relayedAt = (Get-Date).ToString('o')
        localX = $Snapshot.cursorX - $Snapshot.left
        localY = $Snapshot.cursorY - $Snapshot.top
        renderer = $Renderer.ToInt64()
        originalHitRoot = $HitRoot.ToInt64()
        overlay = $Snapshot.overlay.ToInt64()
    }
    [System.IO.File]::WriteAllText(
        $statePath,
        ($state | ConvertTo-Json -Compress),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Write-PointerEventFile {
    $payload = [ordered]@{
        processId = $PID
        sessionId = $script:pointerEventSession
        sequence = $script:pointerEventSequence
        events = @($script:pointerEvents)
    }
    $json = $payload | ConvertTo-Json -Depth 4 -Compress
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            [System.IO.File]::WriteAllText(
                $script:pointerEventPath,
                $json,
                (New-Object System.Text.UTF8Encoding($false))
            )
            return $true
        }
        catch {
            # The speech process may be reading this tiny state file. A brief
            # collision must never terminate the global input bridge.
            [Threading.Thread]::Sleep(5)
        }
    }
    return $false
}

function Publish-PetBodyClick {
    param(
        [datetime]$At,
        [int]$X,
        [int]$Y
    )

    $script:pointerEventSequence++
    $event = [ordered]@{
        id = '{0}:{1}' -f $script:pointerEventSession, $script:pointerEventSequence
        kind = 'click'
        at = $At.ToString('o')
        x = $X
        y = $Y
    }
    $script:pointerEvents = @($script:pointerEvents + $event | Select-Object -Last 8)
    $written = Write-PointerEventFile
    if ($written) {
        try {
            $speechWindow = [ProfessorCluckshotInputNative]::FindWindow(
                [string]$null,
                'Professor Cluckshot Speech Overlay'
            )
            if ($speechWindow -ne [IntPtr]::Zero) {
                [void][ProfessorCluckshotInputNative]::PostMessage(
                    $speechWindow,
                    0x8001,
                    [IntPtr]::Zero,
                    [IntPtr]::Zero
                )
            }
        }
        catch {
            # The 25 ms file poll remains the fallback if notification fails.
        }
    }
}

function Set-OverlayTransparent {
    param(
        [IntPtr]$Overlay,
        [bool]$Enabled,
        [long]$ReferenceStyle = 0,
        [bool]$NoActivate = $false
    )

    if ($Overlay -eq [IntPtr]::Zero -or -not [ProfessorCluckshotInputNative]::IsWindow($Overlay)) {
        return $false
    }

    $style = [ProfessorCluckshotInputNative]::GetWindowLongPtr($Overlay, -20).ToInt64()
    # The pet overlay is both transparent and layered. On this Codex build,
    # removing only WS_EX_TRANSPARENT still leaves layered-pixel hit testing
    # routing the round controls to the window underneath.
    $desired = if (-not $Enabled) {
        $interactive = ($style -band (-bnot 0x20)) -band (-bnot 0x80000)
        if ($NoActivate -or (($ReferenceStyle -band 0x8000000) -ne 0)) {
            $interactive -bor 0x8000000
        } else {
            $interactive -band (-bnot 0x8000000)
        }
    } else {
        $restored = $style
        $restored = if (($ReferenceStyle -band 0x20) -ne 0) {
            $restored -bor 0x20
        } else {
            $restored -band (-bnot 0x20)
        }
        $restored = if (($ReferenceStyle -band 0x80000) -ne 0) {
            $restored -bor 0x80000
        } else {
            $restored -band (-bnot 0x80000)
        }
        $restored = if (($ReferenceStyle -band 0x8000000) -ne 0) {
            $restored -bor 0x8000000
        } else {
            $restored -band (-bnot 0x8000000)
        }
        $restored
    }
    if ($desired -eq $style) {
        return $false
    }

    [void][ProfessorCluckshotInputNative]::SetWindowLongPtr($Overlay, -20, [IntPtr]::new($desired))
    [void][ProfessorCluckshotInputNative]::SetWindowPos(
        $Overlay,
        [IntPtr]::new(-1),
        0,
        0,
        0,
        0,
        0x233
    )
    return $true
}

if ($ProbeOnly) {
    $overlay = [ProfessorCluckshotInputNative]::FindOverlay()
    $snapshot = Get-OverlaySnapshot -Overlay $overlay
    [pscustomobject]@{
        overlayFound = $null -ne $snapshot
        ownerProcessId = if ($null -ne $snapshot) { $snapshot.ownerProcessId } else { $null }
        width = if ($null -ne $snapshot) { $snapshot.width } else { $null }
        height = if ($null -ne $snapshot) { $snapshot.height } else { $null }
        cursorInside = if ($null -ne $snapshot) { $snapshot.cursorInside } else { $false }
        cursorInControlZone = Test-PetControlZone -Snapshot $snapshot
        cursorInButtonZone = Test-PetButtonZone -Snapshot $snapshot
        cursorInBodyZone = Test-PetBodyZone -Snapshot $snapshot
        transparent = if ($null -ne $snapshot) { $snapshot.transparent } else { $null }
        layered = if ($null -ne $snapshot) { $snapshot.layered } else { $null }
        noActivate = if ($null -ne $snapshot) { $snapshot.noActivate } else { $null }
        petBandLeft = if ($null -ne $snapshot) { $snapshot.petBandLeft } else { $null }
        petBandRight = if ($null -ne $snapshot) { $snapshot.petBandRight } else { $null }
        wouldPostWakeMessage = $null -ne $snapshot -and $snapshot.cursorInside -and $snapshot.transparent
    } | ConvertTo-Json -Compress
    exit 0
}

$mutex = New-Object Threading.Mutex($false, 'Local\ProfessorCluckshotCodexPetInputBridge')
$ownsMutex = $false
try {
    try {
        $ownsMutex = $mutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        $ownsMutex = $true
    }

    if (-not $ownsMutex) {
        exit 0
    }

    $overlay = [IntPtr]::Zero
    $lastLookup = [DateTime]::MinValue
    $forcedInteractive = $false
    $forcedOverlay = [IntPtr]::Zero
    $forcedOriginalStyle = 0
    $baselineNormalized = $false
    $mouseWasDown = $false
    $dragCaptureActive = $false
    $dragReleaseCandidateAt = $null
    $dragLastCursorX = 0
    $dragLastCursorY = 0
    $dragLastMotionAt = [DateTime]::MinValue
    $syntheticClickPending = $false
    $syntheticDownX = 0
    $syntheticDownY = 0
    $bodyClickArmed = $false
    $bodyDownX = 0
    $bodyDownY = 0
    $bodyMaxDistance = 0.0
    $bodyReleaseCandidateAt = $null
    $bodyReleaseX = 0
    $bodyReleaseY = 0
    $script:pointerEventPath = Join-Path $PSScriptRoot 'paper-cheer-pointer-events.json'
    $script:pointerEventSession = [Guid]::NewGuid().ToString('N')
    $script:pointerEventSequence = 0
    $script:pointerEvents = @()
    [void](Write-PointerEventFile)

    while ($true) {
        if ($overlay -eq [IntPtr]::Zero -or -not [ProfessorCluckshotInputNative]::IsWindow($overlay)) {
            if (([DateTime]::UtcNow - $lastLookup).TotalMilliseconds -ge 500) {
                $overlay = [ProfessorCluckshotInputNative]::FindOverlay()
                $lastLookup = [DateTime]::UtcNow
            }
        }

        $snapshot = Get-OverlaySnapshot -Overlay $overlay
        if ($null -eq $snapshot) {
            $forcedInteractive = $false
            $forcedOverlay = [IntPtr]::Zero
            $forcedOriginalStyle = 0
            $baselineNormalized = $false
            $dragCaptureActive = $false
            $dragReleaseCandidateAt = $null
            $dragLastMotionAt = [DateTime]::MinValue
            $bodyClickArmed = $false
            $bodyReleaseCandidateAt = $null
            $overlay = [IntPtr]::Zero
            Start-Sleep -Milliseconds 100
            continue
        }

        $leftButtonDown = (([int][ProfessorCluckshotInputNative]::GetAsyncKeyState(1) -band 0x8000) -ne 0)
        $inControlZone = Test-PetControlZone -Snapshot $snapshot
        $inPetBody = Test-PetBodyZone -Snapshot $snapshot
        $resumeBodyClick = $false

        if ($null -ne $bodyReleaseCandidateAt) {
            $releaseAge = ([DateTime]::UtcNow - $bodyReleaseCandidateAt).TotalMilliseconds
            if ($leftButtonDown) {
                # Ignore a sub-20 ms up/down glitch during a held drag. A real
                # second click arrives later, so first publish the completed
                # click before arming the next one.
                if ($releaseAge -ge 20) {
                    Publish-PetBodyClick -At $bodyReleaseCandidateAt -X $bodyReleaseX -Y $bodyReleaseY
                } else {
                    $resumeBodyClick = $true
                }
                $bodyReleaseCandidateAt = $null
            } elseif ($releaseAge -ge 25) {
                Publish-PetBodyClick -At $bodyReleaseCandidateAt -X $bodyReleaseX -Y $bodyReleaseY
                $bodyReleaseCandidateAt = $null
            }
        }

        if ($leftButtonDown -and -not $mouseWasDown -and ($inPetBody -or $resumeBodyClick)) {
            # Once a body drag starts, keep the overlay interactive until the
            # physical mouse button is released. Otherwise crossing the
            # narrow pet hit band restores click-through mid-drag and the
            # native Codex window loses its drag capture.
            $dragCaptureActive = $true
            $dragReleaseCandidateAt = $null
            $dragLastCursorX = $snapshot.cursorX
            $dragLastCursorY = $snapshot.cursorY
            $dragLastMotionAt = [DateTime]::UtcNow
            $bodyClickArmed = $true
            if (-not $resumeBodyClick) {
                $bodyDownX = $snapshot.cursorX
                $bodyDownY = $snapshot.cursorY
                $bodyMaxDistance = 0.0
            }
        }

        if ($bodyClickArmed) {
            $bodyCurrentDistance = [Math]::Sqrt(
                [Math]::Pow($snapshot.cursorX - $bodyDownX, 2) +
                [Math]::Pow($snapshot.cursorY - $bodyDownY, 2)
            )
            $bodyMaxDistance = [Math]::Max($bodyMaxDistance, $bodyCurrentDistance)
        }

        if (-not $leftButtonDown -and $mouseWasDown -and $bodyClickArmed) {
            $bodyDistance = [Math]::Sqrt(
                [Math]::Pow($snapshot.cursorX - $bodyDownX, 2) +
                [Math]::Pow($snapshot.cursorY - $bodyDownY, 2)
            )
            if ($bodyDistance -lt 16 -and $bodyMaxDistance -lt 16) {
                $bodyReleaseCandidateAt = [DateTime]::UtcNow
                $bodyReleaseX = $snapshot.cursorX
                $bodyReleaseY = $snapshot.cursorY
            }
            $bodyClickArmed = $false
        }
        if ($dragCaptureActive) {
            $dragNow = [DateTime]::UtcNow
            if ($snapshot.cursorX -ne $dragLastCursorX -or $snapshot.cursorY -ne $dragLastCursorY) {
                $dragLastCursorX = $snapshot.cursorX
                $dragLastCursorY = $snapshot.cursorY
                $dragLastMotionAt = $dragNow
            }
            $recentDragMotion = ($dragNow - $dragLastMotionAt).TotalMilliseconds -lt 80
            if ($leftButtonDown -or $recentDragMotion) {
                $dragReleaseCandidateAt = $null
            } elseif ($null -eq $dragReleaseCandidateAt) {
                $dragReleaseCandidateAt = $dragNow
            } elseif (($dragNow - $dragReleaseCandidateAt).TotalMilliseconds -ge 250) {
                $dragCaptureActive = $false
                $dragReleaseCandidateAt = $null
            }
        }
        $keepInteractive = $inControlZone -or $dragCaptureActive
        $baselineStyle = (($snapshot.extendedStyle -bor 0x20) -bor 0x80000) -band (-bnot 0x8000000)
        if (-not $baselineNormalized -and -not $keepInteractive) {
            [void](Set-OverlayTransparent -Overlay $overlay -Enabled $true -ReferenceStyle $baselineStyle)
            $snapshot = Get-OverlaySnapshot -Overlay $overlay
            $baselineNormalized = $true
        }
        if ($keepInteractive) {
            if (-not $forcedInteractive -or $forcedOverlay -ne $overlay) {
                $forcedOriginalStyle = $baselineStyle
                $baselineNormalized = $true
                $forcedInteractive = $true
                $forcedOverlay = $overlay
            }
            [void](Set-OverlayTransparent -Overlay $overlay -Enabled $false -ReferenceStyle $forcedOriginalStyle -NoActivate ($inPetBody -or $dragCaptureActive))
        } elseif ($forcedInteractive -and $forcedOverlay -eq $overlay) {
            [void](Set-OverlayTransparent -Overlay $overlay -Enabled $true -ReferenceStyle $forcedOriginalStyle)
            $forcedInteractive = $false
            $forcedOverlay = [IntPtr]::Zero
            $forcedOriginalStyle = 0
        }

        [void](Send-OverlayMouseMove -Snapshot $snapshot)

        if ($leftButtonDown -and -not $mouseWasDown -and (Test-PetButtonZone -Snapshot $snapshot)) {
            $renderer = [ProfessorCluckshotInputNative]::FindRenderer($overlay)
            $hit = [ProfessorCluckshotInputNative]::WindowFromPoint(
                [ProfessorCluckshotInputNative+POINT]@{ X = $snapshot.cursorX; Y = $snapshot.cursorY }
            )
            $hitRoot = if ($hit -ne [IntPtr]::Zero) {
                [ProfessorCluckshotInputNative]::GetAncestor($hit, 2)
            } else {
                [IntPtr]::Zero
            }

            if ($hitRoot -ne $overlay) {
                [void](Set-OverlayTransparent -Overlay $overlay -Enabled $false -ReferenceStyle $forcedOriginalStyle)
                $syntheticClickPending = $true
                $syntheticDownX = $snapshot.cursorX
                $syntheticDownY = $snapshot.cursorY
                Write-RelayState -Snapshot $snapshot -Renderer $renderer -HitRoot $hitRoot
            }
        }

        if (-not $leftButtonDown -and $mouseWasDown -and $syntheticClickPending) {
            $distance = [Math]::Sqrt(
                [Math]::Pow($snapshot.cursorX - $syntheticDownX, 2) +
                [Math]::Pow($snapshot.cursorY - $syntheticDownY, 2)
            )
            if ($distance -lt 16 -and (Test-PetButtonZone -Snapshot $snapshot)) {
                [void](Set-OverlayTransparent -Overlay $overlay -Enabled $false -ReferenceStyle $forcedOriginalStyle)
                [ProfessorCluckshotInputNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                Start-Sleep -Milliseconds 60
                [ProfessorCluckshotInputNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
            }
            $syntheticClickPending = $false
        }

        $mouseWasDown = $leftButtonDown
        $pollDelayMilliseconds = if ($dragCaptureActive) { 1 } elseif ($keepInteractive) { 2 } else { 15 }
        [Threading.Thread]::Sleep($pollDelayMilliseconds)
    }
}
finally {
    if ($forcedInteractive -and $forcedOverlay -ne [IntPtr]::Zero) {
        [void](Set-OverlayTransparent -Overlay $forcedOverlay -Enabled $true -ReferenceStyle $forcedOriginalStyle)
    }
    if ($ownsMutex) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}

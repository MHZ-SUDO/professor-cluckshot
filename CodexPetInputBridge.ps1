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

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    public static IntPtr FindOverlay()
    {
        IntPtr best = IntPtr.Zero;
        int bestScore = Int32.MaxValue;

        EnumWindows((hwnd, lParam) =>
        {
            var className = new StringBuilder(128);
            var title = new StringBuilder(128);
            GetClassName(hwnd, className, className.Capacity);
            GetWindowText(hwnd, title, title.Capacity);

            RECT rect;
            if (className.ToString() != "Chrome_WidgetWin_1" ||
                title.ToString() != "Codex" ||
                !IsWindowVisible(hwnd) ||
                !GetWindowRect(hwnd, out rect))
            {
                return true;
            }

            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width < 180 || width > 700 || height < 180 || height > 700)
            {
                return true;
            }

            int score = Math.Abs(width - 408) + Math.Abs(height - 400);
            if (score < bestScore)
            {
                best = hwnd;
                bestScore = score;
            }

            return true;
        }, IntPtr.Zero);

        return best;
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
        transparent = [bool]$transparent
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

if ($ProbeOnly) {
    $overlay = [ProfessorCluckshotInputNative]::FindOverlay()
    $snapshot = Get-OverlaySnapshot -Overlay $overlay
    [pscustomobject]@{
        overlayFound = $null -ne $snapshot
        ownerProcessId = if ($null -ne $snapshot) { $snapshot.ownerProcessId } else { $null }
        width = if ($null -ne $snapshot) { $snapshot.width } else { $null }
        height = if ($null -ne $snapshot) { $snapshot.height } else { $null }
        cursorInside = if ($null -ne $snapshot) { $snapshot.cursorInside } else { $false }
        transparent = if ($null -ne $snapshot) { $snapshot.transparent } else { $null }
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

    while ($true) {
        if ($overlay -eq [IntPtr]::Zero -or -not [ProfessorCluckshotInputNative]::IsWindow($overlay)) {
            if (([DateTime]::UtcNow - $lastLookup).TotalMilliseconds -ge 500) {
                $overlay = [ProfessorCluckshotInputNative]::FindOverlay()
                $lastLookup = [DateTime]::UtcNow
            }
        }

        $snapshot = Get-OverlaySnapshot -Overlay $overlay
        if ($null -eq $snapshot) {
            $overlay = [IntPtr]::Zero
            Start-Sleep -Milliseconds 100
            continue
        }

        [void](Send-OverlayMouseMove -Snapshot $snapshot)
        Start-Sleep -Milliseconds 25
    }
}
finally {
    if ($ownsMutex) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}

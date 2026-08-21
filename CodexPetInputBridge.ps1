[CmdletBinding()]
param(
    [switch]$ProbeOnly,

    [switch]$HookProbe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$source = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

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
    public struct MSLLHOOKSTRUCT
    {
        public POINT Point;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr Window;
        public uint Message;
        public UIntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public POINT Point;
        public uint Private;
    }

    public sealed class MouseHookEventRecord
    {
        public int Message { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
        public long UtcTicks { get; set; }
        public long ForegroundBefore { get; set; }
        public long ForegroundAtEvent { get; set; }
        public int ForegroundShowStateBefore { get; set; }
        public bool NativeClickSuppressed { get; set; }
        public bool NativeClickDeflected { get; set; }
        public bool BodyGestureOwned { get; set; }
        public bool BodyDragStarted { get; set; }
    }

    private delegate IntPtr LowLevelMouseProc(int code, IntPtr wParam, IntPtr lParam);

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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int hookId,
        LowLevelMouseProc callback,
        IntPtr module,
        uint threadId
    );

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int code,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetMessage(out MSG message, IntPtr window, uint minimum, uint maximum);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TranslateMessage(ref MSG message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG message);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostThreadMessage(uint threadId, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string moduleName);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hwnd);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint attach, uint attachTo, bool enabled);

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

    private const int WH_MOUSE_LL = 14;
    private const int WM_MOUSEMOVE = 0x0200;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP = 0x0202;
    private const uint WM_QUIT = 0x0012;
    private const long BODY_DRAG_THRESHOLD_SQUARED = 64L;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_ASYNCWINDOWPOS = 0x4000;

    private static readonly object MouseHookSync = new object();
    private static readonly ConcurrentQueue<MouseHookEventRecord> MouseHookEvents =
        new ConcurrentQueue<MouseHookEventRecord>();
    private static readonly LowLevelMouseProc MouseHookProcedure = MouseHookCallback;
    private static readonly ManualResetEvent MouseHookReady = new ManualResetEvent(false);
    private static Thread MouseHookThread;
    private static IntPtr MouseHookHandle = IntPtr.Zero;
    private static uint MouseHookThreadId;
    private static int MouseHookLastError;
    private static string MouseHookException = String.Empty;
    private static volatile bool MouseLeftButtonHeld;
    private static long MouseGuardOverlayHandle;
    private static int MouseGuardLeft;
    private static int MouseGuardTop;
    private static int MouseGuardRight;
    private static int MouseGuardBottom;
    private static bool MouseBodyGestureActive;
    private static int MouseBodyStartX;
    private static int MouseBodyStartY;
    private static long MouseBodyMaxDistanceSquared;
    private static long MouseBodyForegroundBefore;
    private static int MouseBodyForegroundShowStateBefore;
    private static int MouseBodyOverlayStartLeft;
    private static int MouseBodyOverlayStartTop;
    private static int MouseBodyGuardStartLeft;
    private static int MouseBodyGuardStartTop;
    private static int MouseBodyGuardStartRight;
    private static int MouseBodyGuardStartBottom;
    private static bool MouseBodyOverlayPositionValid;
    private static bool MouseBodyDragStarted;
    private static int MouseBodyInputSuppressionCount;

    public static bool StartMouseHook()
    {
        lock (MouseHookSync)
        {
            if (MouseHookHandle != IntPtr.Zero && MouseHookThread != null && MouseHookThread.IsAlive)
            {
                return true;
            }

            MouseHookReady.Reset();
            MouseHookLastError = 0;
            MouseHookException = String.Empty;
            MouseHookThreadId = 0;
            MouseLeftButtonHeld = false;
            MouseBodyGestureActive = false;
            MouseHookThread = new Thread(MouseHookThreadMain);
            MouseHookThread.IsBackground = true;
            MouseHookThread.Name = "Professor Cluckshot mouse capture";
            MouseHookThread.Start();
        }

        if (!MouseHookReady.WaitOne(2000))
        {
            MouseHookLastError = 1460;
            return false;
        }
        return MouseHookHandle != IntPtr.Zero;
    }

    public static bool IsMouseHookActive()
    {
        Thread thread = MouseHookThread;
        return MouseHookHandle != IntPtr.Zero && thread != null && thread.IsAlive;
    }

    public static int GetMouseHookLastError()
    {
        return MouseHookLastError;
    }

    public static string GetMouseHookException()
    {
        return MouseHookException;
    }

    public static MouseHookEventRecord[] DrainMouseHookEvents()
    {
        var drained = new List<MouseHookEventRecord>();
        MouseHookEventRecord item;
        while (MouseHookEvents.TryDequeue(out item))
        {
            drained.Add(item);
        }
        return drained.ToArray();
    }

    public static void ConfigurePetBodyClickGuard(
        IntPtr overlay,
        int left,
        int top,
        int right,
        int bottom)
    {
        Volatile.Write(ref MouseGuardLeft, left);
        Volatile.Write(ref MouseGuardTop, top);
        Volatile.Write(ref MouseGuardRight, right);
        Volatile.Write(ref MouseGuardBottom, bottom);
        Interlocked.Exchange(ref MouseGuardOverlayHandle, overlay.ToInt64());
    }

    public static void ClearPetBodyClickGuard()
    {
        Interlocked.Exchange(ref MouseGuardOverlayHandle, 0L);
        MouseBodyGestureActive = false;
    }

    public static int GetBodyInputSuppressionCount()
    {
        return Volatile.Read(ref MouseBodyInputSuppressionCount);
    }

    public static void StopMouseHook()
    {
        Thread thread;
        uint threadId;
        lock (MouseHookSync)
        {
            thread = MouseHookThread;
            threadId = MouseHookThreadId;
        }

        if (threadId != 0)
        {
            PostThreadMessage(threadId, WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
        }
        if (thread != null && thread != Thread.CurrentThread && thread.IsAlive)
        {
            thread.Join(1000);
        }
    }

    private static void MouseHookThreadMain()
    {
        try
        {
            MouseHookThreadId = GetCurrentThreadId();
            MouseHookHandle = SetWindowsHookEx(
                WH_MOUSE_LL,
                MouseHookProcedure,
                GetModuleHandle(null),
                0
            );
            if (MouseHookHandle == IntPtr.Zero)
            {
                MouseHookLastError = Marshal.GetLastWin32Error();
                MouseHookReady.Set();
                return;
            }

            MouseHookReady.Set();
            MSG message;
            while (GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
        }
        catch (Exception exception)
        {
            MouseHookLastError = -1;
            MouseHookException = exception.ToString();
            MouseHookReady.Set();
        }
        finally
        {
            IntPtr hook = MouseHookHandle;
            MouseHookHandle = IntPtr.Zero;
            if (hook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(hook);
            }
            MouseHookThreadId = 0;
            MouseLeftButtonHeld = false;
            MouseBodyGestureActive = false;
        }
    }

    private static bool PointInsideBodyGuard(POINT point, out IntPtr overlay)
    {
        overlay = new IntPtr(Interlocked.Read(ref MouseGuardOverlayHandle));
        if (overlay == IntPtr.Zero || !IsWindow(overlay)) return false;
        return point.X >= Volatile.Read(ref MouseGuardLeft) &&
            point.X <= Volatile.Read(ref MouseGuardRight) &&
            point.Y >= Volatile.Read(ref MouseGuardTop) &&
            point.Y <= Volatile.Read(ref MouseGuardBottom);
    }

    private static int GetWindowShowState(IntPtr window)
    {
        if (window == IntPtr.Zero || !IsWindow(window)) return 0;
        if (IsIconic(window)) return 2;
        if (IsZoomed(window)) return 3;
        return 1;
    }

    private static void UpdateOwnedBodyGesturePosition(IntPtr overlay, POINT point)
    {
        long deltaX = point.X - MouseBodyStartX;
        long deltaY = point.Y - MouseBodyStartY;
        long distanceSquared = (deltaX * deltaX) + (deltaY * deltaY);
        if (distanceSquared > MouseBodyMaxDistanceSquared)
        {
            MouseBodyMaxDistanceSquared = distanceSquared;
        }

        if (MouseBodyMaxDistanceSquared < BODY_DRAG_THRESHOLD_SQUARED)
        {
            return;
        }

        MouseBodyDragStarted = true;
        if (!MouseBodyOverlayPositionValid || overlay == IntPtr.Zero || !IsWindow(overlay))
        {
            return;
        }

        int translatedX = (int)deltaX;
        int translatedY = (int)deltaY;
        Volatile.Write(ref MouseGuardLeft, MouseBodyGuardStartLeft + translatedX);
        Volatile.Write(ref MouseGuardTop, MouseBodyGuardStartTop + translatedY);
        Volatile.Write(ref MouseGuardRight, MouseBodyGuardStartRight + translatedX);
        Volatile.Write(ref MouseGuardBottom, MouseBodyGuardStartBottom + translatedY);
        SetWindowPos(
            overlay,
            IntPtr.Zero,
            MouseBodyOverlayStartLeft + translatedX,
            MouseBodyOverlayStartTop + translatedY,
            0,
            0,
            SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS
        );
    }

    private static IntPtr MouseHookCallback(int code, IntPtr wParam, IntPtr lParam)
    {
        bool suppressNativeTransition = false;
        if (code >= 0)
        {
            int message = wParam.ToInt32();
            bool capture = message == WM_LBUTTONDOWN || message == WM_LBUTTONUP ||
                (message == WM_MOUSEMOVE && MouseLeftButtonHeld);
            if (capture)
            {
                MSLLHOOKSTRUCT data = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(
                    lParam,
                    typeof(MSLLHOOKSTRUCT)
                );
                IntPtr guardedOverlay = IntPtr.Zero;
                bool bodyGestureOwned = MouseBodyGestureActive;
                if (message == WM_LBUTTONDOWN)
                {
                    MouseLeftButtonHeld = true;
                    MouseBodyGestureActive = PointInsideBodyGuard(data.Point, out guardedOverlay);
                    bodyGestureOwned = MouseBodyGestureActive;
                    if (MouseBodyGestureActive)
                    {
                        MouseBodyStartX = data.Point.X;
                        MouseBodyStartY = data.Point.Y;
                        MouseBodyMaxDistanceSquared = 0L;
                        MouseBodyDragStarted = false;
                        MouseBodyForegroundBefore = GetForegroundWindow().ToInt64();
                        MouseBodyForegroundShowStateBefore = GetWindowShowState(
                            new IntPtr(MouseBodyForegroundBefore)
                        );
                        MouseBodyGuardStartLeft = Volatile.Read(ref MouseGuardLeft);
                        MouseBodyGuardStartTop = Volatile.Read(ref MouseGuardTop);
                        MouseBodyGuardStartRight = Volatile.Read(ref MouseGuardRight);
                        MouseBodyGuardStartBottom = Volatile.Read(ref MouseGuardBottom);
                        RECT overlayRect;
                        MouseBodyOverlayPositionValid = GetWindowRect(guardedOverlay, out overlayRect);
                        if (MouseBodyOverlayPositionValid)
                        {
                            MouseBodyOverlayStartLeft = overlayRect.Left;
                            MouseBodyOverlayStartTop = overlayRect.Top;
                        }
                    }
                }
                else if (message == WM_MOUSEMOVE && MouseBodyGestureActive)
                {
                    guardedOverlay = new IntPtr(Interlocked.Read(ref MouseGuardOverlayHandle));
                    UpdateOwnedBodyGesturePosition(guardedOverlay, data.Point);
                }
                else if (message == WM_LBUTTONUP && MouseBodyGestureActive)
                {
                    guardedOverlay = new IntPtr(Interlocked.Read(ref MouseGuardOverlayHandle));
                    UpdateOwnedBodyGesturePosition(guardedOverlay, data.Point);
                }
                suppressNativeTransition = bodyGestureOwned &&
                    (message == WM_LBUTTONDOWN || message == WM_LBUTTONUP);
                MouseHookEvents.Enqueue(new MouseHookEventRecord
                {
                    Message = message,
                    X = data.Point.X,
                    Y = data.Point.Y,
                    UtcTicks = DateTime.UtcNow.Ticks,
                    ForegroundBefore = MouseBodyGestureActive ? MouseBodyForegroundBefore : 0L,
                    ForegroundAtEvent = GetForegroundWindow().ToInt64(),
                    ForegroundShowStateBefore = MouseBodyGestureActive
                        ? MouseBodyForegroundShowStateBefore
                        : 0,
                    NativeClickSuppressed = suppressNativeTransition,
                    NativeClickDeflected = false,
                    BodyGestureOwned = bodyGestureOwned,
                    BodyDragStarted = bodyGestureOwned && MouseBodyDragStarted
                });
                if (suppressNativeTransition)
                {
                    Interlocked.Increment(ref MouseBodyInputSuppressionCount);
                }
                if (message == WM_LBUTTONUP)
                {
                    MouseLeftButtonHeld = false;
                    MouseBodyGestureActive = false;
                    MouseBodyOverlayPositionValid = false;
                }
            }
        }
        // Own both ends of a mascot-body gesture. The native Codex pet never
        // receives an unmatched mouse-down, while ordinary mouse moves keep
        // flowing so the pointer remains under the user's control.
        if (suppressNativeTransition)
        {
            return new IntPtr(1);
        }
        return CallNextHookEx(MouseHookHandle, code, wParam, lParam);
    }

    public static bool RestoreForegroundWithoutChangingWindowState(IntPtr window)
    {
        if (window == IntPtr.Zero || !IsWindow(window)) return false;
        if (GetForegroundWindow() == window) return true;
        uint ignoredProcessId;
        IntPtr foreground = GetForegroundWindow();
        uint foregroundThread = foreground == IntPtr.Zero
            ? 0
            : GetWindowThreadProcessId(foreground, out ignoredProcessId);
        uint targetThread = GetWindowThreadProcessId(window, out ignoredProcessId);
        uint currentThread = GetCurrentThreadId();
        bool attachedForeground = foregroundThread != 0 && foregroundThread != currentThread &&
            AttachThreadInput(currentThread, foregroundThread, true);
        bool attachedTarget = targetThread != 0 && targetThread != currentThread &&
            targetThread != foregroundThread && AttachThreadInput(currentThread, targetThread, true);
        try
        {
            bool activated = SetForegroundWindow(window);
            return activated || GetForegroundWindow() == window;
        }
        finally
        {
            if (attachedTarget) AttachThreadInput(currentThread, targetThread, false);
            if (attachedForeground) AttachThreadInput(currentThread, foregroundThread, false);
        }
    }

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
$script:petAutomationLayout = $null

if ($HookProbe) {
    $started = [ProfessorCluckshotInputNative]::StartMouseHook()
    Start-Sleep -Milliseconds 100
    $active = [ProfessorCluckshotInputNative]::IsMouseHookActive()
    $errorCode = [ProfessorCluckshotInputNative]::GetMouseHookLastError()
    $exception = [ProfessorCluckshotInputNative]::GetMouseHookException()
    [ProfessorCluckshotInputNative]::StopMouseHook()
    [pscustomobject]@{
        started = $started
        active = $active
        errorCode = $errorCode
        exception = $exception
    } | ConvertTo-Json -Compress
    exit 0
}

function Get-PetAutomationLayout {
    param([IntPtr]$Overlay)

    if ($Overlay -eq [IntPtr]::Zero -or -not [ProfessorCluckshotInputNative]::IsWindow($Overlay)) {
        return $null
    }

    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Overlay)
        if ($null -eq $root) {
            return $null
        }

        $elements = $root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        $preferredMascots = @()
        $fallbackMascots = @()
        $buttons = @()
        for ($index = 0; $index -lt $elements.Count; $index++) {
            try {
                $current = $elements.Item($index).Current
                if ($current.IsOffscreen) {
                    continue
                }
                $bounds = $current.BoundingRectangle
                if ([double]::IsNaN($bounds.Left) -or [double]::IsInfinity($bounds.Left) -or
                    [double]::IsNaN($bounds.Top) -or [double]::IsInfinity($bounds.Top) -or
                    $bounds.Width -le 0 -or $bounds.Height -le 0) {
                    continue
                }

                $candidate = [pscustomobject]@{
                    left = [int][Math]::Floor($bounds.Left)
                    top = [int][Math]::Floor($bounds.Top)
                    right = [int][Math]::Ceiling($bounds.Right)
                    bottom = [int][Math]::Ceiling($bounds.Bottom)
                    width = [int][Math]::Ceiling($bounds.Width)
                    height = [int][Math]::Ceiling($bounds.Height)
                    name = [string]$current.Name
                    className = [string]$current.ClassName
                }

                if ($current.ControlType -eq [System.Windows.Automation.ControlType]::Image -and
                    $candidate.width -ge 40 -and $candidate.height -ge 40) {
                    $fallbackMascots += $candidate
                    if ($candidate.className.IndexOf('codex-avatar-button', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $preferredMascots += $candidate
                    }
                } elseif ($current.ControlType -eq [System.Windows.Automation.ControlType]::Button) {
                    $buttons += $candidate
                }
            }
            catch {
                # A Chromium accessibility node can disappear during animation.
            }
        }

        $mascotCandidates = if ($preferredMascots.Count -gt 0) {
            @($preferredMascots)
        } else {
            @($fallbackMascots)
        }
        $mascot = @($mascotCandidates | Sort-Object { $_.width * $_.height } -Descending | Select-Object -First 1)
        if ($mascot.Count -eq 0) {
            return $null
        }

        return [pscustomobject]@{
            overlay = $Overlay
            mascot = $mascot[0]
            buttons = @($buttons)
            measuredAt = [DateTime]::UtcNow
            source = 'windows-ui-automation'
        }
    }
    catch {
        return $null
    }
}

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
    $petBoundsSource = 'edge-fallback'
    $automationMascot = $null
    if ($null -ne $script:petAutomationLayout -and
        $script:petAutomationLayout.overlay -eq $Overlay -and
        $null -ne $script:petAutomationLayout.mascot -and
        ($rect.Right - $rect.Left) -gt 0) {
        $automationMascot = $script:petAutomationLayout.mascot
        $petBandLeft = [Math]::Max(0.0, [Math]::Min(1.0,
            ($automationMascot.left - $rect.Left) / [double]($rect.Right - $rect.Left)))
        $petBandRight = [Math]::Max(0.0, [Math]::Min(1.0,
            ($automationMascot.right - $rect.Left) / [double]($rect.Right - $rect.Left)))
        $petBoundsSource = $script:petAutomationLayout.source
    }

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
        petBoundsSource = $petBoundsSource
        mascotBounds = $automationMascot
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

function Test-OverlayPoint {
    param(
        $Snapshot,
        [int]$X,
        [int]$Y
    )

    return $null -ne $Snapshot -and
        $X -ge $Snapshot.left -and $X -lt ($Snapshot.left + $Snapshot.width) -and
        $Y -ge $Snapshot.top -and $Y -lt ($Snapshot.top + $Snapshot.height)
}

function Test-PetControlPoint {
    param(
        $Snapshot,
        [int]$X,
        [int]$Y
    )

    if (-not (Test-OverlayPoint -Snapshot $Snapshot -X $X -Y $Y)) {
        return $false
    }

    if ($null -ne $script:petAutomationLayout -and
        $script:petAutomationLayout.overlay -eq $Snapshot.overlay) {
        $mascot = $script:petAutomationLayout.mascot
        if ($X -ge ($mascot.left - 6) -and $X -le ($mascot.right + 6) -and
            $Y -ge ($mascot.top - 6) -and $Y -le ($mascot.bottom + 6)) {
            return $true
        }
        foreach ($button in @($script:petAutomationLayout.buttons)) {
            if ($X -ge ($button.left - 8) -and $X -le ($button.right + 8) -and
                $Y -ge ($button.top - 8) -and $Y -le ($button.bottom + 8)) {
                return $true
            }
        }
        return $false
    }

    $localX = $X - $Snapshot.left
    $localY = $Y - $Snapshot.top
    return $localX -ge [Math]::Round($Snapshot.width * [Math]::Max(0.0, $Snapshot.petBandLeft - 0.06)) -and
        $localX -le [Math]::Round($Snapshot.width * [Math]::Min(1.0, $Snapshot.petBandRight + 0.06)) -and
        $localY -ge [Math]::Round($Snapshot.height * 0.45) -and
        $localY -lt $Snapshot.height
}

function Test-PetControlZone {
    param($Snapshot)

    if ($null -eq $Snapshot -or -not $Snapshot.cursorInside) {
        return $false
    }
    return Test-PetControlPoint -Snapshot $Snapshot -X $Snapshot.cursorX -Y $Snapshot.cursorY
}

function Test-PetButtonPoint {
    param(
        $Snapshot,
        [int]$X,
        [int]$Y
    )

    if (-not (Test-OverlayPoint -Snapshot $Snapshot -X $X -Y $Y)) {
        return $false
    }

    if ($null -ne $script:petAutomationLayout -and
        $script:petAutomationLayout.overlay -eq $Snapshot.overlay) {
        foreach ($button in @($script:petAutomationLayout.buttons)) {
            if ($X -ge ($button.left - 8) -and $X -le ($button.right + 8) -and
                $Y -ge ($button.top - 8) -and $Y -le ($button.bottom + 8)) {
                return $true
            }
        }
        $mascot = $script:petAutomationLayout.mascot
        return $X -ge ($mascot.left - 18) -and $X -le ($mascot.right + 18) -and
            $Y -ge ($mascot.bottom - 8) -and
            $Y -lt ($Snapshot.top + $Snapshot.height)
    }

    $localX = $X - $Snapshot.left
    $localY = $Y - $Snapshot.top
    return $localX -ge [Math]::Round($Snapshot.width * [Math]::Max(0.0, $Snapshot.petBandLeft - 0.04)) -and
        $localX -le [Math]::Round($Snapshot.width * [Math]::Min(1.0, $Snapshot.petBandRight + 0.04)) -and
        $localY -ge [Math]::Round($Snapshot.height * 0.90) -and
        $localY -lt $Snapshot.height
}

function Test-PetButtonZone {
    param($Snapshot)

    if ($null -eq $Snapshot -or -not $Snapshot.cursorInside) {
        return $false
    }
    return Test-PetButtonPoint -Snapshot $Snapshot -X $Snapshot.cursorX -Y $Snapshot.cursorY
}

function Test-PetBodyPoint {
    param(
        $Snapshot,
        [int]$X,
        [int]$Y
    )

    if (-not (Test-OverlayPoint -Snapshot $Snapshot -X $X -Y $Y)) {
        return $false
    }

    if ($null -ne $script:petAutomationLayout -and
        $script:petAutomationLayout.overlay -eq $Snapshot.overlay) {
        $mascot = $script:petAutomationLayout.mascot
        return $X -ge ($mascot.left - 6) -and $X -le ($mascot.right + 6) -and
            $Y -ge ($mascot.top - 6) -and $Y -le ($mascot.bottom + 6)
    }

    $localX = $X - $Snapshot.left
    $localY = $Y - $Snapshot.top
    # The visible character includes its head and hat well above the old
    # lower-body-only band. Keep the body hit zone aligned with the complete
    # interactive pet column so a head click cannot fall through to Codex's
    # native single-click activation.
    return $localX -ge [Math]::Round($Snapshot.width * [Math]::Max(0.0, $Snapshot.petBandLeft - 0.06)) -and
        $localX -le [Math]::Round($Snapshot.width * [Math]::Min(1.0, $Snapshot.petBandRight + 0.06)) -and
        $localY -ge [Math]::Round($Snapshot.height * 0.45) -and
        $localY -lt [Math]::Round($Snapshot.height * 0.90)
}

function Test-PetBodyZone {
    param($Snapshot)

    if ($null -eq $Snapshot -or -not $Snapshot.cursorInside) {
        return $false
    }
    return Test-PetBodyPoint -Snapshot $Snapshot -X $Snapshot.cursorX -Y $Snapshot.cursorY
}

function Update-PetBodyClickGuard {
    param($Snapshot)

    if ($null -eq $Snapshot -or $Snapshot.overlay -eq [IntPtr]::Zero) {
        [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
        return
    }

    if ($null -ne $script:petAutomationLayout -and
        $script:petAutomationLayout.overlay -eq $Snapshot.overlay -and
        $null -ne $script:petAutomationLayout.mascot) {
        $mascot = $script:petAutomationLayout.mascot
        $guardLeft = [int]($mascot.left - 6)
        $guardTop = [int]($mascot.top - 6)
        $guardRight = [int]($mascot.right + 6)
        $guardBottom = [int]($mascot.bottom + 6)
    } else {
        $guardLeft = [int]($Snapshot.left + [Math]::Round(
            $Snapshot.width * [Math]::Max(0.0, $Snapshot.petBandLeft - 0.06)))
        $guardRight = [int]($Snapshot.left + [Math]::Round(
            $Snapshot.width * [Math]::Min(1.0, $Snapshot.petBandRight + 0.06)))
        $guardTop = [int]($Snapshot.top + [Math]::Round($Snapshot.height * 0.45))
        $guardBottom = [int]($Snapshot.top + [Math]::Round($Snapshot.height * 0.90))
    }

    [ProfessorCluckshotInputNative]::ConfigurePetBodyClickGuard(
        $Snapshot.overlay,
        $guardLeft,
        $guardTop,
        $guardRight,
        $guardBottom
    )
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
        captureMode = $script:pointerCaptureMode
        hookError = $script:pointerHookError
        nativeBodyInputSuppressionCount = [ProfessorCluckshotInputNative]::GetBodyInputSuppressionCount()
        sequence = $script:pointerEventSequence
        events = @($script:pointerEvents)
        lastOverlayPointer = $script:lastOverlayPointer
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
        [int]$Y,
        [IntPtr]$ForegroundBefore,
        [IntPtr]$ForegroundAtRelease = [IntPtr]::Zero,
        [int]$ForegroundShowStateBefore = 0,
        [bool]$NativeClickSuppressed = $false,
        [bool]$NativeClickDeflected = $false
    )

    $script:pointerEventSequence++
    $event = [ordered]@{
        id = '{0}:{1}' -f $script:pointerEventSession, $script:pointerEventSequence
        kind = 'click'
        at = $At.ToString('o')
        x = $X
        y = $Y
        foregroundBefore = $ForegroundBefore.ToInt64()
        foregroundAtRelease = $ForegroundAtRelease.ToInt64()
        foregroundShowStateBefore = $ForegroundShowStateBefore
        nativeClickSuppressed = $NativeClickSuppressed
        nativeClickDeflected = $NativeClickDeflected
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

    # This is only a state-preserving safety net. It never calls ShowWindow,
    # changes maximize/minimize state, resizes a window, or emulates Alt-Tab.
    if ($ForegroundBefore -ne [IntPtr]::Zero -and
        [ProfessorCluckshotInputNative]::GetForegroundWindow() -ne $ForegroundBefore) {
        try {
            [void][ProfessorCluckshotInputNative]::RestoreForegroundWithoutChangingWindowState($ForegroundBefore)
        }
        catch {
            # Speech delivery must survive a focus-policy restriction.
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
    $script:petAutomationLayout = Get-PetAutomationLayout -Overlay $overlay
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
        petBoundsSource = if ($null -ne $snapshot) { $snapshot.petBoundsSource } else { $null }
        mascotBounds = if ($null -ne $snapshot) { $snapshot.mascotBounds } else { $null }
        wouldPostWakeMessage = $null -ne $snapshot -and $snapshot.cursorInside -and $snapshot.transparent
    } | ConvertTo-Json -Compress
    exit 0
}

$mutex = New-Object Threading.Mutex($false, 'Local\ProfessorCluckshotCodexPetInputBridge')
$ownsMutex = $false
$mouseHookStarted = $false
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
    $bodyDragStarted = $false
    $bodyReleaseCandidateAt = $null
    $bodyReleaseX = 0
    $bodyReleaseY = 0
    $bodyForegroundBefore = [IntPtr]::Zero
    $bodyReleaseForegroundBefore = [IntPtr]::Zero
    $hookReleaseGraceStartedAt = $null
    $hookReleaseX = 0
    $hookReleaseY = 0
    $lastFallbackFastClickAt = [DateTime]::MinValue
    $lastHookHealthAt = [DateTime]::MinValue
    $lastAutomationLookup = [DateTime]::MinValue
    # Keep the foreground from the last idle polling tick. The native Codex
    # pet can activate its main window before the mouse-down tick is observed,
    # so GetForegroundWindow() on that tick may already be too late.
    $foregroundBeforeMouseDown = [ProfessorCluckshotInputNative]::GetForegroundWindow()
    $script:pointerEventPath = Join-Path $PSScriptRoot 'paper-cheer-pointer-events.json'
    $bridgeErrorPath = Join-Path $PSScriptRoot 'codex-pet-input-bridge-error.json'
    Remove-Item -LiteralPath $bridgeErrorPath -Force -ErrorAction SilentlyContinue
    $script:pointerEventSession = [Guid]::NewGuid().ToString('N')
    $script:pointerEventSequence = 0
    $script:pointerEvents = @()
    $script:lastOverlayPointer = $null
    $mouseHookStarted = [ProfessorCluckshotInputNative]::StartMouseHook()
    $script:pointerCaptureMode = if ($mouseHookStarted) { 'low-level-hook' } else { 'poll-fallback' }
    $script:pointerHookError = [ProfessorCluckshotInputNative]::GetMouseHookLastError()
    [void](Write-PointerEventFile)

    while ($true) {
        $hookNow = [DateTime]::UtcNow
        if (($hookNow - $lastHookHealthAt).TotalSeconds -ge 3) {
            $lastHookHealthAt = $hookNow
            if (-not [ProfessorCluckshotInputNative]::IsMouseHookActive()) {
                $mouseHookStarted = [ProfessorCluckshotInputNative]::StartMouseHook()
                $script:pointerCaptureMode = if ($mouseHookStarted) { 'low-level-hook' } else { 'poll-fallback' }
                $script:pointerHookError = [ProfessorCluckshotInputNative]::GetMouseHookLastError()
                [void](Write-PointerEventFile)
            }
        }
        $hookEvents = @()
        if ($mouseHookStarted) {
            $hookEvents = @([ProfessorCluckshotInputNative]::DrainMouseHookEvents())
        }

        if ($overlay -eq [IntPtr]::Zero -or -not [ProfessorCluckshotInputNative]::IsWindow($overlay)) {
            if (([DateTime]::UtcNow - $lastLookup).TotalMilliseconds -ge 500) {
                $overlay = [ProfessorCluckshotInputNative]::FindOverlay()
                $lastLookup = [DateTime]::UtcNow
            }
        }

        if ($overlay -ne [IntPtr]::Zero -and
            ($null -eq $script:petAutomationLayout -or
             $script:petAutomationLayout.overlay -ne $overlay -or
             ([DateTime]::UtcNow - $lastAutomationLookup).TotalMilliseconds -ge 100)) {
            $lastAutomationLookup = [DateTime]::UtcNow
            $freshAutomationLayout = Get-PetAutomationLayout -Overlay $overlay
            if ($null -ne $freshAutomationLayout) {
                $script:petAutomationLayout = $freshAutomationLayout
            } elseif ($null -ne $script:petAutomationLayout -and
                $script:petAutomationLayout.overlay -ne $overlay) {
                $script:petAutomationLayout = $null
            }
        }

        $snapshot = Get-OverlaySnapshot -Overlay $overlay
        if ($null -eq $snapshot) {
            [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
            $forcedInteractive = $false
            $forcedOverlay = [IntPtr]::Zero
            $forcedOriginalStyle = 0
            $baselineNormalized = $false
            $dragCaptureActive = $false
            $dragReleaseCandidateAt = $null
            $dragLastMotionAt = [DateTime]::MinValue
            $bodyClickArmed = $false
            $bodyDragStarted = $false
            $bodyReleaseCandidateAt = $null
            $hookReleaseGraceStartedAt = $null
            $script:petAutomationLayout = $null
            $overlay = [IntPtr]::Zero
            Start-Sleep -Milliseconds 100
            continue
        }
        Update-PetBodyClickGuard -Snapshot $snapshot

        $leftButtonState = [int][ProfessorCluckshotInputNative]::GetAsyncKeyState(1)
        $leftButtonDown = (($leftButtonState -band 0x8000) -ne 0)
        $leftButtonPressedSinceLastPoll = (($leftButtonState -band 0x0001) -ne 0)
        $inControlZone = Test-PetControlZone -Snapshot $snapshot
        $inButtonZone = Test-PetButtonZone -Snapshot $snapshot
        $inPetBody = Test-PetBodyZone -Snapshot $snapshot
        $resumeBodyClick = $false

        $overlayPointerDiagnosticChanged = $false
        if ($mouseHookStarted -and $hookEvents.Count -gt 0) {
            foreach ($hookEvent in $hookEvents) {
                $hookMessage = [int]$hookEvent.Message
                $hookX = [int]$hookEvent.X
                $hookY = [int]$hookEvent.Y
                $hookInOverlay = Test-OverlayPoint -Snapshot $snapshot -X $hookX -Y $hookY
                $hookInBody = Test-PetBodyPoint -Snapshot $snapshot -X $hookX -Y $hookY
                $hookInButton = Test-PetButtonPoint -Snapshot $snapshot -X $hookX -Y $hookY
                $hookEventAt = [DateTime]::new([long]$hookEvent.UtcTicks, [DateTimeKind]::Utc)
                $hookForegroundBefore = [IntPtr]::Zero
                if ([long]$hookEvent.ForegroundBefore -ne 0) {
                    $hookForegroundBefore = [IntPtr]::new([long]$hookEvent.ForegroundBefore)
                }
                $hookForegroundAtEvent = [IntPtr]::Zero
                if ([long]$hookEvent.ForegroundAtEvent -ne 0) {
                    $hookForegroundAtEvent = [IntPtr]::new([long]$hookEvent.ForegroundAtEvent)
                }
                $hookBodyGestureOwned = [bool]$hookEvent.BodyGestureOwned
                $hookBodyDragStarted = [bool]$hookEvent.BodyDragStarted

                if (($hookInOverlay -or $hookBodyGestureOwned) -and
                    ($hookMessage -eq 0x0201 -or $hookMessage -eq 0x0202)) {
                    $script:lastOverlayPointer = [ordered]@{
                        at = $hookEventAt.ToString('o')
                        message = if ($hookMessage -eq 0x0201) { 'left-down' } else { 'left-up' }
                        x = $hookX
                        y = $hookY
                        localX = $hookX - $snapshot.left
                        localY = $hookY - $snapshot.top
                        inBody = [bool]$hookInBody
                        inButton = [bool]$hookInButton
                        nativeClickSuppressed = [bool]$hookEvent.NativeClickSuppressed
                        nativeClickDeflected = [bool]$hookEvent.NativeClickDeflected
                        bodyGestureOwned = $hookBodyGestureOwned
                        bodyDragStarted = $hookBodyDragStarted
                        foregroundBefore = $hookForegroundBefore.ToInt64()
                        foregroundAtEvent = $hookForegroundAtEvent.ToInt64()
                        foregroundShowStateBefore = [int]$hookEvent.ForegroundShowStateBefore
                        petBoundsSource = $snapshot.petBoundsSource
                        mascotBounds = $snapshot.mascotBounds
                    }
                    $overlayPointerDiagnosticChanged = $true
                }

                if ($hookMessage -eq 0x0201 -and $hookBodyGestureOwned) {
                    # The helper owns both physical transitions for the mascot
                    # body. Native Codex receives neither end, so it cannot
                    # retain a drag after a single click.
                    $dragCaptureActive = $true
                    $dragReleaseCandidateAt = $null
                    $dragLastCursorX = $hookX
                    $dragLastCursorY = $hookY
                    $dragLastMotionAt = $hookEventAt
                    $bodyClickArmed = $true
                    $bodyDownX = $hookX
                    $bodyDownY = $hookY
                    $bodyMaxDistance = 0.0
                    $bodyDragStarted = $false
                    $hookReleaseGraceStartedAt = $null
                    $bodyForegroundBefore = $hookForegroundBefore
                    if ($bodyForegroundBefore -eq [IntPtr]::Zero) {
                        $bodyForegroundBefore = $foregroundBeforeMouseDown
                    }
                    if ($bodyForegroundBefore -eq $overlay) {
                        $bodyForegroundBefore = [IntPtr]::Zero
                    }
                    if ($bodyForegroundBefore -eq [IntPtr]::Zero) {
                        $bodyForegroundBefore = [ProfessorCluckshotInputNative]::GetForegroundWindow()
                    }
                } elseif ($hookMessage -eq 0x0200 -and $bodyClickArmed -and $hookBodyGestureOwned) {
                    $hookDistance = [Math]::Sqrt(
                        [Math]::Pow($hookX - $bodyDownX, 2) +
                        [Math]::Pow($hookY - $bodyDownY, 2)
                    )
                    $bodyMaxDistance = [Math]::Max($bodyMaxDistance, $hookDistance)
                    $bodyDragStarted = $bodyDragStarted -or $hookBodyDragStarted
                    $dragLastCursorX = $hookX
                    $dragLastCursorY = $hookY
                    $dragLastMotionAt = $hookEventAt
                } elseif ($hookMessage -eq 0x0202 -and $bodyClickArmed -and $hookBodyGestureOwned) {
                    $hookDistance = [Math]::Sqrt(
                        [Math]::Pow($hookX - $bodyDownX, 2) +
                        [Math]::Pow($hookY - $bodyDownY, 2)
                    )
                    $bodyMaxDistance = [Math]::Max($bodyMaxDistance, $hookDistance)
                    $bodyDragStarted = $bodyDragStarted -or $hookBodyDragStarted
                    if (-not $bodyDragStarted -and $hookDistance -lt 8 -and $bodyMaxDistance -lt 8) {
                        Publish-PetBodyClick `
                            -At $hookEventAt `
                            -X $hookX `
                            -Y $hookY `
                            -ForegroundBefore $bodyForegroundBefore `
                            -ForegroundAtRelease $hookForegroundAtEvent `
                            -ForegroundShowStateBefore ([int]$hookEvent.ForegroundShowStateBefore) `
                            -NativeClickSuppressed ([bool]$hookEvent.NativeClickSuppressed) `
                            -NativeClickDeflected ([bool]$hookEvent.NativeClickDeflected)
                    }
                    $bodyClickArmed = $false
                    $hookReleaseGraceStartedAt = $null
                    $dragCaptureActive = $false
                    $dragReleaseCandidateAt = $null
                    if ($bodyDragStarted) {
                        # UI Automation bounds are absolute screen coordinates;
                        # invalidate them after an externally moved pet window.
                        $script:petAutomationLayout = $null
                        $lastAutomationLookup = [DateTime]::MinValue
                    }
                    $bodyDragStarted = $false
                }
            }
            if ($overlayPointerDiagnosticChanged) {
                [void](Write-PointerEventFile)
            }
        }

        if ($mouseHookStarted -and $bodyClickArmed) {
            if ($leftButtonDown) {
                $hookReleaseGraceStartedAt = $null
            } elseif ($null -eq $hookReleaseGraceStartedAt) {
                # A very fast click can release after DrainMouseHookEvents() but
                # before GetAsyncKeyState() in this iteration. Give the queued
                # WM_LBUTTONUP one short turn to arrive instead of disarming the
                # click before its matching release record can be processed.
                $hookReleaseGraceStartedAt = [DateTime]::UtcNow
                $hookReleaseX = $snapshot.cursorX
                $hookReleaseY = $snapshot.cursorY
            } elseif (([DateTime]::UtcNow - $hookReleaseGraceStartedAt).TotalMilliseconds -ge 75) {
                # If Windows really dropped the queued release, complete a
                # stationary click once. Movement still fails closed as a drag,
                # so a missing release can neither stick nor become a false click.
                $releaseDistance = [Math]::Sqrt(
                    [Math]::Pow($hookReleaseX - $bodyDownX, 2) +
                    [Math]::Pow($hookReleaseY - $bodyDownY, 2)
                )
                $bodyMaxDistance = [Math]::Max($bodyMaxDistance, $releaseDistance)
                if (-not $bodyDragStarted -and $releaseDistance -lt 8 -and $bodyMaxDistance -lt 8) {
                    Publish-PetBodyClick `
                        -At $hookReleaseGraceStartedAt `
                        -X $hookReleaseX `
                        -Y $hookReleaseY `
                        -ForegroundBefore $bodyForegroundBefore `
                        -ForegroundAtRelease ([ProfessorCluckshotInputNative]::GetForegroundWindow())
                }
                $bodyClickArmed = $false
                $bodyDragStarted = $false
                $hookReleaseGraceStartedAt = $null
                $dragCaptureActive = $false
                $dragReleaseCandidateAt = $null
                $script:petAutomationLayout = $null
                $lastAutomationLookup = [DateTime]::MinValue
            }
        }

        if (-not $mouseHookStarted -and $null -ne $bodyReleaseCandidateAt) {
            $releaseAge = ([DateTime]::UtcNow - $bodyReleaseCandidateAt).TotalMilliseconds
            if ($leftButtonDown) {
                # Ignore a sub-20 ms up/down glitch during a held drag. A real
                # second click arrives later, so first publish the completed
                # click before arming the next one.
                if ($releaseAge -ge 20) {
                    Publish-PetBodyClick -At $bodyReleaseCandidateAt -X $bodyReleaseX -Y $bodyReleaseY -ForegroundBefore $bodyReleaseForegroundBefore
                } else {
                    $resumeBodyClick = $true
                }
                $bodyReleaseCandidateAt = $null
            } elseif ($releaseAge -ge 25) {
                Publish-PetBodyClick -At $bodyReleaseCandidateAt -X $bodyReleaseX -Y $bodyReleaseY -ForegroundBefore $bodyReleaseForegroundBefore
                $bodyReleaseCandidateAt = $null
            }
        }

        if (-not $mouseHookStarted -and $leftButtonDown -and -not $mouseWasDown -and ($inPetBody -or $resumeBodyClick)) {
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
                $bodyForegroundBefore = $foregroundBeforeMouseDown
                if ($bodyForegroundBefore -eq $overlay) {
                    $bodyForegroundBefore = [IntPtr]::Zero
                }
                if ($bodyForegroundBefore -eq [IntPtr]::Zero) {
                    $bodyForegroundBefore = [ProfessorCluckshotInputNative]::GetForegroundWindow()
                }
            }
        }

        if ($bodyClickArmed) {
            $bodyCurrentDistance = [Math]::Sqrt(
                [Math]::Pow($snapshot.cursorX - $bodyDownX, 2) +
                [Math]::Pow($snapshot.cursorY - $bodyDownY, 2)
            )
            $bodyMaxDistance = [Math]::Max($bodyMaxDistance, $bodyCurrentDistance)
        }

        if (-not $mouseHookStarted -and -not $leftButtonDown -and $mouseWasDown -and $bodyClickArmed) {
            $bodyDistance = [Math]::Sqrt(
                [Math]::Pow($snapshot.cursorX - $bodyDownX, 2) +
                [Math]::Pow($snapshot.cursorY - $bodyDownY, 2)
            )
            if ($bodyDistance -lt 16 -and $bodyMaxDistance -lt 16) {
                $bodyReleaseCandidateAt = [DateTime]::UtcNow
                $bodyReleaseX = $snapshot.cursorX
                $bodyReleaseY = $snapshot.cursorY
                $bodyReleaseForegroundBefore = $bodyForegroundBefore
            }
            $bodyClickArmed = $false
        }

        if (-not $mouseHookStarted -and $leftButtonPressedSinceLastPoll -and
            -not $leftButtonDown -and -not $mouseWasDown -and
            -not $bodyClickArmed -and $inPetBody -and
            ([DateTime]::UtcNow - $lastFallbackFastClickAt).TotalMilliseconds -ge 80) {
            # GetAsyncKeyState's transition bit is a last-resort fallback when
            # policy software prevents installing the low-level mouse hook.
            $lastFallbackFastClickAt = [DateTime]::UtcNow
            $fallbackForeground = $foregroundBeforeMouseDown
            if ($fallbackForeground -eq $overlay) {
                $fallbackForeground = [IntPtr]::Zero
            }
            Publish-PetBodyClick -At $lastFallbackFastClickAt -X $snapshot.cursorX -Y $snapshot.cursorY -ForegroundBefore $fallbackForeground
        }
        if ($dragCaptureActive -and -not $mouseHookStarted) {
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
        $keepInteractive = if ($mouseHookStarted) {
            # The hook owns mascot-body gestures; only the two round controls
            # need native hit testing while the hook is healthy.
            $inButtonZone
        } else {
            $inControlZone -or $dragCaptureActive
        }
        # Keep WS_EX_NOACTIVATE in both transparent and interactive states.
        # A fast click can otherwise land before the hover poll changes styles
        # and let the native pet raise the Codex main window.
        $baselineStyle = (($snapshot.extendedStyle -bor 0x20) -bor 0x80000) -bor 0x8000000
        $baselineNeedsRepair = -not $snapshot.transparent -or
            -not $snapshot.layered -or -not $snapshot.noActivate
        if (-not $keepInteractive -and (-not $baselineNormalized -or $baselineNeedsRepair)) {
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
            # Every pet/control hit remains non-activating. Single-click speech
            # never needs foreground activation; only the confirmed double-
            # click path explicitly raises the Codex main window.
            [void](Set-OverlayTransparent -Overlay $overlay -Enabled $false -ReferenceStyle $forcedOriginalStyle -NoActivate $true)
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

        if (-not $leftButtonDown -and -not $mouseWasDown) {
            $idleForeground = [ProfessorCluckshotInputNative]::GetForegroundWindow()
            if ($idleForeground -ne [IntPtr]::Zero -and $idleForeground -ne $overlay) {
                $foregroundBeforeMouseDown = $idleForeground
            }
        }
        $mouseWasDown = $leftButtonDown
        $pollDelayMilliseconds = if ($dragCaptureActive) { 1 } elseif ($keepInteractive) { 2 } else { 15 }
        [Threading.Thread]::Sleep($pollDelayMilliseconds)
    }
}
catch {
    try {
        $errorPath = Join-Path $PSScriptRoot 'codex-pet-input-bridge-error.json'
        $errorState = [ordered]@{
            at = (Get-Date).ToString('o')
            message = [string]$_.Exception.Message
            position = [string]$_.InvocationInfo.PositionMessage
            processId = $PID
        }
        [System.IO.File]::WriteAllText(
            $errorPath,
            ($errorState | ConvertTo-Json -Depth 4),
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
    catch {
        # Do not hide the original shutdown behind diagnostic I/O failure.
    }
}
finally {
    [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
    if ($mouseHookStarted -or [ProfessorCluckshotInputNative]::IsMouseHookActive()) {
        [ProfessorCluckshotInputNative]::StopMouseHook()
    }
    if ($forcedInteractive -and $forcedOverlay -ne [IntPtr]::Zero) {
        [void](Set-OverlayTransparent -Overlay $forcedOverlay -Enabled $true -ReferenceStyle $forcedOriginalStyle)
    }
    if ($ownsMutex) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}

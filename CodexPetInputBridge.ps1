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
        public bool NativeDragHandoff { get; set; }
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
    public static extern bool ScreenToClient(IntPtr hwnd, ref POINT point);

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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

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
    public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);


    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [DllImport("user32.dll")]
    public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);


    [StructLayout(LayoutKind.Sequential)]
    private struct GUITHREADINFO {
        public int Size;
        public uint Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public RECT CaretRect;
    }
    [DllImport("user32.dll")]
    private static extern bool GetGUIThreadInfo(uint threadId, ref GUITHREADINFO info);
    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr window, uint attribute, out int value, int size);

    private const int WH_MOUSE_LL = 14;
    private const int WM_MOUSEMOVE = 0x0200;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP = 0x0202;
    private const uint WM_QUIT = 0x0012;
    private const long BODY_DRAG_THRESHOLD_SQUARED = 64L;
    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);
    private static readonly object MouseHookSync = new object();
    private static readonly ConcurrentQueue<MouseHookEventRecord> MouseHookEvents = new ConcurrentQueue<MouseHookEventRecord>();
    private static readonly LowLevelMouseProc MouseHookProcedure = MouseHookCallback;
    private static readonly ManualResetEvent MouseHookReady = new ManualResetEvent(false);
    private static Thread MouseHookThread;
    private static IntPtr MouseHookHandle;
    private static uint MouseHookThreadId;
    private static int MouseHookLastError;
    private static string MouseHookException = String.Empty;
    private static int MouseBodyInputSuppressionCount;

    // One immutable publication prevents mixed X/Y bounds during a display change.
    private sealed class PetTarget {
        public IntPtr Overlay, Renderer;
        public RECT Body;
        public RECT[] Buttons;
        public long ExpiresAt;
    }
    private static PetTarget CurrentTarget;
    private static bool GestureIsButton;
    private static bool GestureDragging;
    private static POINT GestureStart;
    private static long GestureForeground;
    private static int GestureShowState;
    private static int GestureActive;



    private static readonly EventWaitHandle GestureSignal = new EventWaitHandle(false,
        EventResetMode.ManualReset, @"Local\ProfessorCluckshotInputGesture");
    private static long SettleUntil, InputMoveCount, CompletedGestureCount;
    private const uint WM_REFRESH_POINTER_ACCESS = 0x8030;
    private static int PointerRefreshQueued;
    private static IntPtr LastAccessWindow;
    private static bool LastAccessEnabled;
    public sealed class RelayDiagnostics {
        public long InputMoves { get; set; }
        public long DeliveredMoves { get; set; }
        public long CompletedGestures { get; set; }
        public int PendingGestures { get; set; }
        public string LastError { get; set; }
    }
    public static RelayDiagnostics GetRelayDiagnostics() {
        return new RelayDiagnostics { InputMoves = Interlocked.Read(ref InputMoveCount),
            DeliveredMoves = 0, CompletedGestures = Interlocked.Read(ref CompletedGestureCount),
            PendingGestures = 0, LastError = String.Empty };
    }
    public static bool IsInteractionBusy() {
        return IsGestureActive() || DateTime.UtcNow.Ticks < Interlocked.Read(ref SettleUntil);
    }
    private static void SetGestureActive(bool active) {
        Volatile.Write(ref GestureActive, active ? 1 : 0);
        if (active) GestureSignal.Set(); else GestureSignal.Reset();
    }
    private static void SetNativePointerAccess(IntPtr window, bool enabled, bool force) {
        if (window == IntPtr.Zero || !IsWindow(window)) return;
        if (!force && window == LastAccessWindow && enabled == LastAccessEnabled) return;
        long style = GetWindowLongPtr(window, -20).ToInt64();
        long desired = enabled ? style & ~0x20L : style | 0x20L;
        desired |= 0x08000000L;
        if (desired != style) SetWindowLongPtr(window, -20, new IntPtr(desired));
        LastAccessWindow = window;
        LastAccessEnabled = enabled;
    }
    public static void RefreshNativePointerAccess() {
        uint thread = MouseHookThreadId;
        if (thread == 0 || Interlocked.Exchange(ref PointerRefreshQueued, 1) != 0) return;
        if (!PostThreadMessage(thread, WM_REFRESH_POINTER_ACCESS, UIntPtr.Zero, IntPtr.Zero))
            Interlocked.Exchange(ref PointerRefreshQueued, 0);
    }
    private static void UpdateNativePointerAccess(POINT point, bool force) {
        if (IsInteractionBusy()) return;
        PetTarget target = Volatile.Read(ref CurrentTarget);
        if (target == null) { SetNativePointerAccess(LastAccessWindow, false, force); return; }
        bool inside = DateTime.UtcNow.Ticks <= target.ExpiresAt && Contains(target.Body, point);
        if (!inside && DateTime.UtcNow.Ticks <= target.ExpiresAt)
            foreach (RECT button in target.Buttons) if (Contains(button, point)) { inside = true; break; }
        SetNativePointerAccess(target.Overlay, inside && IsPetPointUnobscured(target.Overlay, point), force);
    }

    public static bool EnablePerMonitorV2ForCurrentThread() {
        try { return SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) != IntPtr.Zero; }
        catch (EntryPointNotFoundException) { return false; }
    }

    public static void ConfigurePetTargets(IntPtr overlay, int[] body, int[] buttons) {
        if (overlay == IntPtr.Zero || body == null || body.Length != 4 || !IsWindowVisible(overlay)) {
            ClearPetBodyClickGuard();
            return;
        }
        var controls = new List<RECT>();
        if (buttons != null) {
            for (int i = 0; i + 3 < buttons.Length; i += 4)
                controls.Add(new RECT { Left = buttons[i], Top = buttons[i+1], Right = buttons[i+2], Bottom = buttons[i+3] });
        }
        Volatile.Write(ref CurrentTarget, new PetTarget {
            Overlay = overlay, Renderer = FindRenderer(overlay),
            Body = new RECT { Left = body[0], Top = body[1], Right = body[2], Bottom = body[3] },
            Buttons = controls.ToArray(), ExpiresAt = DateTime.UtcNow.AddMilliseconds(600).Ticks
        });
    }

    public static void ClearPetBodyClickGuard() {
        // A transient accessibility refresh must not cancel an already owned drag.
        Volatile.Write(ref CurrentTarget, null);
    }
    public static bool IsGestureActive() { return Volatile.Read(ref GestureActive) != 0; }
    public static int GetBodyInputSuppressionCount() { return Volatile.Read(ref MouseBodyInputSuppressionCount); }
    private static bool Contains(RECT rect, POINT point) {
        return point.X >= rect.Left && point.X < rect.Right && point.Y >= rect.Top && point.Y < rect.Bottom;
    }

    public static bool IsPetPointUnobscured(IntPtr overlay, POINT point) {
        if (overlay == IntPtr.Zero || !IsWindow(overlay) || !IsWindowVisible(overlay)) return false;
        GUITHREADINFO info = new GUITHREADINFO();
        info.Size = Marshal.SizeOf(typeof(GUITHREADINFO));
        if (GetGUIThreadInfo(0, ref info) && info.Capture != IntPtr.Zero && GetAncestor(info.Capture, 2) != overlay)
            return false;
        // Respect screenshot selection surfaces and any other covering window.
        // WindowFromPoint alone cannot distinguish an occluder from the window
        // below our deliberately click-through pet.
        IntPtr above = GetWindow(overlay, 3); // GW_HWNDPREV, toward top of Z order
        for (int count = 0; above != IntPtr.Zero && count < 512; count++, above = GetWindow(above, 3)) {
            if (!IsWindowVisible(above) || (GetWindowLongPtr(above, -20).ToInt64() & 0x20L) != 0) continue;
            RECT rect;
            if (!GetWindowRect(above, out rect) || !Contains(rect, point)) continue;
            int cloaked;
            if (DwmGetWindowAttribute(above, 14, out cloaked, sizeof(int)) == 0 && cloaked != 0) continue;
            return false;
        }
        return true;
    }


    // Observe actual input. Never swallow or synthesize DOWN, MOVE, or UP.
    // Chromium and Windows retain a single consistent button/capture state.
    public static bool ProcessPointer(int message, POINT point, uint flags) {
        if ((flags & 1U) != 0) return false;
        if (message != WM_LBUTTONDOWN && message != WM_LBUTTONUP && message != WM_MOUSEMOVE) return false;
        if (message == WM_MOUSEMOVE && !IsGestureActive()) {
            UpdateNativePointerAccess(point, false);
            return false;
        }
        if (message == WM_LBUTTONDOWN) {
            PetTarget target = Volatile.Read(ref CurrentTarget);
            bool button = false;
            bool fresh = target != null && DateTime.UtcNow.Ticks <= target.ExpiresAt;
            if (fresh) foreach (RECT bounds in target.Buttons) if (Contains(bounds, point)) { button = true; break; }
            bool known = fresh && (button || Contains(target.Body, point));
            IntPtr overlay = target != null ? target.Overlay : LastAccessWindow;
            // A quick second drag can precede fresh UIA bounds. Track the real
            // native hit without inventing a speech click from stale geometry.
            if (!known) {
                IntPtr hit = WindowFromPoint(point);
                if (overlay == IntPtr.Zero || hit == IntPtr.Zero || GetAncestor(hit, 2) != overlay) return false;
                button = true;
            }
            if (!IsPetPointUnobscured(overlay, point)) return false;
            SetNativePointerAccess(overlay, true, true);
            GestureIsButton = button;
            GestureDragging = false;
            GestureStart = point;
            GestureForeground = GetForegroundWindow().ToInt64();
            GestureShowState = GestureForeground == 0 ? 0 : IsIconic(new IntPtr(GestureForeground)) ? 2 : IsZoomed(new IntPtr(GestureForeground)) ? 3 : 1;
            SetGestureActive(true);
        } else if (!IsGestureActive()) {
            return false;
        }
        bool justStarted = false;
        if (message == WM_MOUSEMOVE) Interlocked.Increment(ref InputMoveCount);
        if (message != WM_LBUTTONDOWN) {
            long dx = (long)point.X - GestureStart.X, dy = (long)point.Y - GestureStart.Y;
            if (!GestureIsButton && !GestureDragging && dx * dx + dy * dy >= BODY_DRAG_THRESHOLD_SQUARED) {
                GestureDragging = true;
                justStarted = true;
            }
        }
        if (!GestureIsButton && (message != WM_MOUSEMOVE || justStarted)) {
            MouseHookEvents.Enqueue(new MouseHookEventRecord {
                Message = message, X = point.X, Y = point.Y, UtcTicks = DateTime.UtcNow.Ticks,
                ForegroundBefore = GestureForeground, ForegroundAtEvent = GetForegroundWindow().ToInt64(),
                ForegroundShowStateBefore = GestureShowState, NativeClickSuppressed = false,
                NativeClickDeflected = false, BodyGestureOwned = false,
                BodyDragStarted = GestureDragging, NativeDragHandoff = false
            });
        }
        if (message == WM_LBUTTONUP) {
            Interlocked.Increment(ref CompletedGestureCount);
            Interlocked.Exchange(ref SettleUntil, DateTime.UtcNow.AddMilliseconds(80).Ticks);
            SetGestureActive(false);
        }
        return false;
    }

    private static IntPtr MouseHookCallback(int code, IntPtr wParam, IntPtr lParam) {
        if (code >= 0) {
            try {
                var data = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                if (ProcessPointer(wParam.ToInt32(), data.Point, data.Flags)) return new IntPtr(1);
            } catch (Exception error) { MouseHookException = error.Message; }
        }
        return CallNextHookEx(MouseHookHandle, code, wParam, lParam);
    }

    public static bool StartMouseHook() {
        lock (MouseHookSync) {
            if (IsMouseHookActive()) return true;
            GestureSignal.Reset();
            MouseHookReady.Reset();
            MouseHookLastError = 0;
            MouseHookException = String.Empty;
            MouseHookThread = new Thread(MouseHookThreadMain);
            MouseHookThread.IsBackground = true;
            MouseHookThread.Name = "Professor Cluckshot input relay";
            MouseHookThread.Start();
        }
        if (!MouseHookReady.WaitOne(2000)) { MouseHookLastError = 1460; return false; }
        return MouseHookHandle != IntPtr.Zero;
    }
    public static bool IsMouseHookActive() { return MouseHookHandle != IntPtr.Zero && MouseHookThread != null && MouseHookThread.IsAlive; }
    public static int GetMouseHookLastError() { return MouseHookLastError; }
    public static string GetMouseHookException() { return MouseHookException; }
    public static MouseHookEventRecord[] DrainMouseHookEvents() {
        var items = new List<MouseHookEventRecord>();
        MouseHookEventRecord item;
        while (MouseHookEvents.TryDequeue(out item)) items.Add(item);
        return items.ToArray();
    }
    public static void StopMouseHook() {
        uint threadId = MouseHookThreadId;
        Thread thread = MouseHookThread;
        if (threadId != 0) PostThreadMessage(threadId, WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
        if (thread != null && thread != Thread.CurrentThread && thread.IsAlive) thread.Join(1000);
    }
    private static void MouseHookThreadMain() {
        try {
            EnablePerMonitorV2ForCurrentThread();
            MouseHookThreadId = GetCurrentThreadId();
            MouseHookHandle = SetWindowsHookEx(WH_MOUSE_LL, MouseHookProcedure, GetModuleHandle(null), 0);
            if (MouseHookHandle == IntPtr.Zero) { MouseHookLastError = Marshal.GetLastWin32Error(); MouseHookReady.Set(); return; }
            MouseHookReady.Set();
            MSG message;
            while (GetMessage(out message, IntPtr.Zero, 0, 0) > 0) {
                if (message.Message == WM_REFRESH_POINTER_ACCESS) {
                    Interlocked.Exchange(ref PointerRefreshQueued, 0);
                    POINT cursor;
                    if (GetCursorPos(out cursor)) UpdateNativePointerAccess(cursor, true);
                    continue;
                }
                TranslateMessage(ref message); DispatchMessage(ref message);
            }
        } catch (Exception error) { MouseHookException = error.ToString(); MouseHookLastError = -1; MouseHookReady.Set(); }
        finally {
            SetGestureActive(false);
            IntPtr hook = MouseHookHandle;
            MouseHookHandle = IntPtr.Zero;
            if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
            MouseHookThreadId = 0;
        }
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
        int bestPreferredScore = Int32.MaxValue;

        EnumWindows((hwnd, lParam) =>
        {
            var className = new StringBuilder(128);
            var title = new StringBuilder(128);
            GetClassName(hwnd, className, className.Capacity);
            GetWindowText(hwnd, title, title.Capacity);

            RECT rect;
            string windowClass = className.ToString();
            string windowTitle = title.ToString();
            bool supportedTitle = windowTitle == "Codex" || windowTitle == "ChatGPT";
            if ((windowClass != "Chrome_WidgetWin_1" && windowClass != "FLUTTERVIEW") ||
                !supportedTitle ||
                !IsWindowVisible(hwnd) ||
                !GetWindowRect(hwnd, out rect))
            {
                return true;
            }

            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width < 40 || height < 40)
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

            return true;
        }, IntPtr.Zero);

        // A normal Codex main window must never become the pet input target.
        return bestPreferred;
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
[void][ProfessorCluckshotInputNative]::EnablePerMonitorV2ForCurrentThread()
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

    if ($Overlay -eq [IntPtr]::Zero -or
        -not [ProfessorCluckshotInputNative]::IsWindow($Overlay) -or
        -not [ProfessorCluckshotInputNative]::IsWindowVisible($Overlay)) {
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

    if ($Overlay -eq [IntPtr]::Zero -or
        -not [ProfessorCluckshotInputNative]::IsWindow($Overlay) -or
        -not [ProfessorCluckshotInputNative]::IsWindowVisible($Overlay)) {
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
    $layout = $script:petAutomationLayout
    if ($null -eq $Snapshot -or $null -eq $layout -or $layout.overlay -ne $Snapshot.overlay -or
        ([DateTime]::UtcNow - $layout.measuredAt).TotalMilliseconds -gt 500) {
        [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
        return
    }
    $mascot = $layout.mascot
    $buttons = [Collections.Generic.List[int]]::new()
    foreach ($button in @($layout.buttons)) {
        $buttons.Add([int]$button.left); $buttons.Add([int]$button.top)
        $buttons.Add([int]$button.right); $buttons.Add([int]$button.bottom)
    }
    [ProfessorCluckshotInputNative]::ConfigurePetTargets($Snapshot.overlay,
        [int[]]@($mascot.left, $mascot.top, $mascot.right, $mascot.bottom), $buttons.ToArray())
}

function Write-PointerEventFile {
    $payload = [ordered]@{
        processId = $PID
        sessionId = $script:pointerEventSession
        captureMode = $script:pointerCaptureMode
        updatedAt = [DateTime]::UtcNow.ToString('o')
        gestureActive = [ProfessorCluckshotInputNative]::IsInteractionBusy()
        relayDiagnostics = [ProfessorCluckshotInputNative]::GetRelayDiagnostics()
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
        [bool]$NativeClickDeflected = $false,
        [ValidateSet('click','drag')][string]$Kind = 'click'
    )

    $script:pointerEventSequence++
    $event = [ordered]@{
        id = '{0}:{1}' -f $script:pointerEventSession, $script:pointerEventSequence
        kind = $Kind
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
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { exit 0 }
    $overlay = [IntPtr]::Zero
    $lastLookup = [DateTime]::MinValue
    $lastAutomationLookup = [DateTime]::MinValue
    $lastHeartbeat = [DateTime]::MinValue
    $lastCursorKey = ''
    $targetsNeedRefresh = $true
    $script:pointerEventPath = Join-Path $PSScriptRoot 'paper-cheer-pointer-events.json'
    $bridgeErrorPath = Join-Path $PSScriptRoot 'codex-pet-input-bridge-error.json'
    Remove-Item -LiteralPath $bridgeErrorPath -Force -ErrorAction SilentlyContinue
    $script:pointerEventSession = [Guid]::NewGuid().ToString('N')
    $script:pointerEventSequence = 0
    $script:pointerEvents = @()
    $script:lastOverlayPointer = $null
    $mouseHookStarted = [ProfessorCluckshotInputNative]::StartMouseHook()
    $script:pointerCaptureMode = if ($mouseHookStarted) { 'native-physical-input' } else { 'unavailable' }
    $script:pointerHookError = [ProfessorCluckshotInputNative]::GetMouseHookLastError()
    [void](Write-PointerEventFile)
    if (-not $mouseHookStarted) { throw "Input hook unavailable: $script:pointerHookError" }

    while ($true) {
        $now = [DateTime]::UtcNow
        # Drain complete gestures before refreshing a possibly replaced native HWND.
        foreach ($event in @([ProfessorCluckshotInputNative]::DrainMouseHookEvents())) {
            $eventAt = [DateTime]::new([long]$event.UtcTicks, [DateTimeKind]::Utc)
            $script:lastOverlayPointer = [ordered]@{
                at = $eventAt.ToString('o'); x = $event.X; y = $event.Y
                message = if ($event.Message -eq 0x0201) { 'left-down' } elseif ($event.Message -eq 0x0202) { 'left-up' } else { 'drag-start' }
                bodyGestureOwned = $event.BodyGestureOwned; bodyDragStarted = $event.BodyDragStarted
                nativeDragHandoff = $event.NativeDragHandoff; nativeClickSuppressed = $event.NativeClickSuppressed
                foregroundBefore = $event.ForegroundBefore; foregroundAtEvent = $event.ForegroundAtEvent
            }
            if ($event.Message -eq 0x0202) {
                $kind = if ($event.BodyDragStarted) { 'drag' } else { 'click' }
                Publish-PetBodyClick -At $eventAt -X $event.X -Y $event.Y -Kind $kind `
                    -ForegroundBefore ([IntPtr]::new($event.ForegroundBefore)) `
                    -ForegroundAtRelease ([IntPtr]::new($event.ForegroundAtEvent)) `
                    -ForegroundShowStateBefore $event.ForegroundShowStateBefore -NativeClickSuppressed $event.NativeClickSuppressed
                if ($event.BodyDragStarted) { $script:petAutomationLayout = $null; $lastAutomationLookup = [DateTime]::MinValue }
            } else { [void](Write-PointerEventFile) }
        }

        if ([ProfessorCluckshotInputNative]::IsInteractionBusy()) {
            [Threading.Thread]::Sleep(10)
            continue
        }

        if ($overlay -eq [IntPtr]::Zero -or -not [ProfessorCluckshotInputNative]::IsWindow($overlay) -or
            -not [ProfessorCluckshotInputNative]::IsWindowVisible($overlay)) {
            [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
            $script:petAutomationLayout = $null
            if (($now - $lastLookup).TotalMilliseconds -ge 150) {
                $overlay = [ProfessorCluckshotInputNative]::FindOverlay()
                $lastLookup = $now
                $lastAutomationLookup = [DateTime]::MinValue
                $lastCursorKey = ''
            }
        }
        if ($overlay -ne [IntPtr]::Zero -and ($now - $lastAutomationLookup).TotalMilliseconds -ge 100) {
            $script:petAutomationLayout = Get-PetAutomationLayout -Overlay $overlay
            $lastAutomationLookup = $now
            $targetsNeedRefresh = $true
        }
        $snapshot = Get-OverlaySnapshot -Overlay $overlay
        if ($targetsNeedRefresh -or $null -eq $snapshot) {
            Update-PetBodyClickGuard -Snapshot $snapshot
            $targetsNeedRefresh = $false
        }
        if ([ProfessorCluckshotInputNative]::IsInteractionBusy()) {
            [Threading.Thread]::Sleep(10)
            continue
        }
        if ($null -ne $snapshot) {
            # Restore hit access only while idle. Actual native drag/capture owns
            # the entire gesture; never replay hover coordinates into a moving HWND.
            [ProfessorCluckshotInputNative]::RefreshNativePointerAccess()
        }
        if (($now - $lastHeartbeat).TotalSeconds -ge 1) {
            if (-not [ProfessorCluckshotInputNative]::IsMouseHookActive()) { throw 'Input hook stopped' }
            [void](Write-PointerEventFile)
            $lastHeartbeat = $now
        }
        [Threading.Thread]::Sleep(15)
    }
} catch {
    $errorState = [ordered]@{ at = (Get-Date).ToString('o'); message = $_.Exception.Message; position = $_.InvocationInfo.PositionMessage; processId = $PID }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'codex-pet-input-bridge-error.json'),
        ($errorState | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    throw
} finally {
    [ProfessorCluckshotInputNative]::ClearPetBodyClickGuard()
    if ($mouseHookStarted) { [ProfessorCluckshotInputNative]::StopMouseHook() }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

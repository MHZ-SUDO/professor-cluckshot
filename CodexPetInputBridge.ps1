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
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    public static extern bool ScreenToClient(IntPtr hwnd, ref POINT point);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClass(ref WNDCLASS windowClass);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(uint exStyle, string className, string title,
        uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu,
        IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll", EntryPoint = "DefWindowProcW", CharSet = CharSet.Unicode)]
    private static extern IntPtr DefWindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll")]
    private static extern void PostQuitMessage(int exitCode);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetLayeredWindowAttributes(IntPtr window, uint key, byte alpha, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y,
        int width, int height, uint flags);
    [DllImport("user32.dll")]
    private static extern IntPtr SetCapture(IntPtr window);
    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();
    [DllImport("user32.dll")]
    private static extern IntPtr GetCapture();
    [DllImport("user32.dll")]
    private static extern UIntPtr SetTimer(IntPtr window, UIntPtr timerId, uint milliseconds, IntPtr callback);
    [DllImport("user32.dll")]
    private static extern bool KillTimer(IntPtr window, UIntPtr timerId);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message,
        IntPtr wParam, IntPtr lParam, uint flags, uint timeoutMs, out UIntPtr result);
    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
    [DllImport("gdi32.dll")]
    private static extern int CombineRgn(IntPtr destination, IntPtr first, IntPtr second, int mode);
    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr objectHandle);
    [DllImport("user32.dll")]
    private static extern int SetWindowRgn(IntPtr window, IntPtr region, bool redraw);

    private delegate IntPtr ShieldWindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)]
    private struct TRACKMOUSEEVENT {
        public int Size;
        public uint Flags;
        public IntPtr Window;
        public uint HoverTime;
    }
    [DllImport("user32.dll")]
    private static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT request);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASS {
        public uint Style;
        public ShieldWindowProc Callback;
        public int ClassExtra, WindowExtra;
        public IntPtr Instance, Icon, Cursor, Background;
        public string Menu, Name;
    }

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
    private static extern IntPtr MonitorFromPoint(POINT point, uint flags);

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
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_RBUTTONUP = 0x0205;
    private const int WM_CONTEXTMENU = 0x007b;
    private const int WM_TIMER = 0x0113;
    private const int WM_MOUSEACTIVATE = 0x0021;
    private const int WM_NCHITTEST = 0x0084;
    private const int WM_CLOSE = 0x0010;
    private const int WM_DESTROY = 0x0002;
    private const int WM_CAPTURECHANGED = 0x0215;
    private const int WM_MOUSELEAVE = 0x02a3;
    private const int WM_SHIELD_REFRESH = 0x8031;
    private const int WM_SHIELD_STOP = 0x8032;
    private const int WM_SHIELD_FINISH_UP = 0x8033;
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

    // The almost invisible input window owns only stationary body clicks. Its
    // window thread receives real hardware messages in their original order.
    private static readonly ManualResetEvent ShieldReady = new ManualResetEvent(false);
    private static readonly ShieldWindowProc ShieldProcedure = ShieldCallback;
    private static Thread ShieldThread;
    private static uint ShieldThreadId;
    private static IntPtr ShieldWindow;
    private static string ShieldError = String.Empty;
    private static bool ShieldVisible;
    private static RECT ShieldBounds;
    private static int ShieldState; // 0 idle, 1 shield capture, 2 handoff, 3 canceled, 4 physical UP pending delivery
    private static bool ShieldSendingHandoff;
    private static POINT ShieldStart;
    private static int ShieldDragThresholdPhysical = 5;
    private static IntPtr ShieldOverlay, ShieldRenderer;
    private static RECT ShieldOverlayBoundsAtDown;
    private static RECT ShieldBodyBoundsAtDown;
    private static IntPtr ShieldPlacedOverlay;
    private static POINT ShieldLastUp;
    private static long ShieldReleaseDeadline;
    private static long ShieldRequireTargetAfter;
    private static long ShieldForeground;
    private static int ShieldShowState;
    private static long ShieldClicks, ShieldNativeDrags, ShieldHandoffFailures, DeliveredMoveCount;
    private static long LatestDragPointPacked, LastRelayedDragPointPacked;
    private static int ShieldLastSendError;
    private static string ShieldLastResult = String.Empty;
    private static bool ShieldTrackingMouse;
    private static IntPtr ShieldHoverRenderer;

    // One immutable publication prevents mixed X/Y bounds during a display change.
    private sealed class PetTarget {
        public IntPtr Overlay, Renderer;
        public RECT Body;
        public RECT[] Buttons;
        public long PublishedAt, ExpiresAt;
    }
    private static PetTarget CurrentTarget;
    private static PetTarget ShieldRegionTarget;
    private static IntPtr ShieldRegionWindow;
    private static long ShieldRegionUpdates;
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
        public long ShieldClicks { get; set; }
        public long ShieldNativeDrags { get; set; }
        public long ShieldHandoffFailures { get; set; }
        public int ShieldLastSendError { get; set; }
        public string ShieldLastResult { get; set; }
        public bool ShieldVisible { get; set; }
        public long ShieldRegionUpdates { get; set; }
    }
    public static RelayDiagnostics GetRelayDiagnostics() {
        return new RelayDiagnostics { InputMoves = Interlocked.Read(ref InputMoveCount),
            DeliveredMoves = Interlocked.Read(ref DeliveredMoveCount), CompletedGestures = Interlocked.Read(ref CompletedGestureCount),
            PendingGestures = 0, LastError = ShieldError,
            ShieldClicks = Interlocked.Read(ref ShieldClicks),
            ShieldNativeDrags = Interlocked.Read(ref ShieldNativeDrags),
            ShieldHandoffFailures = Interlocked.Read(ref ShieldHandoffFailures),
            ShieldLastSendError = Volatile.Read(ref ShieldLastSendError),
            ShieldLastResult = ShieldLastResult,
            ShieldVisible = ShieldVisible, ShieldRegionUpdates = Interlocked.Read(ref ShieldRegionUpdates) };
    }
    public static bool IsInteractionBusy() {
        return IsGestureActive() || Volatile.Read(ref ShieldState) == 4 ||
            DateTime.UtcNow.Ticks < Interlocked.Read(ref SettleUntil);
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
        long publishedAt = DateTime.UtcNow.Ticks;
        Volatile.Write(ref CurrentTarget, new PetTarget {
            Overlay = overlay, Renderer = FindRenderer(overlay),
            Body = new RECT { Left = body[0], Top = body[1], Right = body[2], Bottom = body[3] },
            Buttons = controls.ToArray(), PublishedAt = publishedAt,
            ExpiresAt = publishedAt + TimeSpan.FromMilliseconds(600).Ticks
        });
        RefreshShield();
    }

    public static void ClearPetBodyClickGuard() {
        // A transient accessibility refresh must not cancel an already owned drag.
        Volatile.Write(ref CurrentTarget, null);
        RefreshShield();
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
        if (GetGUIThreadInfo(0, ref info) && info.Capture != IntPtr.Zero &&
            info.Capture != ShieldWindow && GetAncestor(info.Capture, 2) != overlay)
            return false;
        // Respect screenshot selection surfaces and any other covering window.
        // WindowFromPoint alone cannot distinguish an occluder from the window
        // below our deliberately click-through pet.
        IntPtr above = GetWindow(overlay, 3); // GW_HWNDPREV, toward top of Z order
        for (int count = 0; above != IntPtr.Zero && count < 512; count++, above = GetWindow(above, 3)) {
            if (above == ShieldWindow) continue;
            if (!IsWindowVisible(above) || (GetWindowLongPtr(above, -20).ToInt64() & 0x20L) != 0) continue;
            RECT rect;
            if (!GetWindowRect(above, out rect) || !Contains(rect, point)) continue;
            int cloaked;
            if (DwmGetWindowAttribute(above, 14, out cloaked, sizeof(int)) == 0 && cloaked != 0) continue;
            return false;
        }
        return true;
    }

    private static void RefreshShield() {
        uint thread = ShieldThreadId;
        if (thread != 0) PostThreadMessage(thread, WM_SHIELD_REFRESH, UIntPtr.Zero, IntPtr.Zero);
    }
    public static bool StartClickShield() {
        if (ShieldThread != null && ShieldThread.IsAlive && ShieldWindow != IntPtr.Zero) return true;
        ShieldReady.Reset(); ShieldError = String.Empty;
        ShieldThread = new Thread(ShieldThreadMain);
        ShieldThread.IsBackground = true;
        ShieldThread.Name = "Professor Cluckshot click shield";
        ShieldThread.Start();
        return ShieldReady.WaitOne(2000) && ShieldWindow != IntPtr.Zero;
    }
    public static void StopClickShield() {
        uint threadId = ShieldThreadId;
        Thread thread = ShieldThread;
        if (threadId != 0) PostThreadMessage(threadId, WM_SHIELD_STOP, UIntPtr.Zero, IntPtr.Zero);
        if (thread != null && thread != Thread.CurrentThread && thread.IsAlive) thread.Join(1500);
    }
    public static string GetClickShieldError() { return ShieldError; }
    public static bool IsClickShieldActive() { return ShieldWindow != IntPtr.Zero && ShieldThread != null && ShieldThread.IsAlive; }
    private static void ShieldThreadMain() {
        try {
            EnablePerMonitorV2ForCurrentThread();
            ShieldThreadId = GetCurrentThreadId();
            string className = "ProfessorCluckshotClickShield_" + Guid.NewGuid().ToString("N");
            var windowClass = new WNDCLASS { Callback = ShieldProcedure, Name = className };
            if (RegisterClass(ref windowClass) == 0)
                throw new InvalidOperationException("RegisterClass: " + Marshal.GetLastWin32Error());
            IntPtr window = CreateWindowEx(0x00080000U | 0x00000080U | 0x08000000U | 0x00000008U,
                className, "Professor Cluckshot Click Shield", 0x80000000U,
                0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (window == IntPtr.Zero)
                throw new InvalidOperationException("CreateWindowEx: " + Marshal.GetLastWin32Error());
            ShieldWindow = window;
            if (!SetLayeredWindowAttributes(window, 0, 1, 2))
                throw new InvalidOperationException("SetLayeredWindowAttributes: " + Marshal.GetLastWin32Error());
            ShieldReady.Set();
            MSG message;
            while (GetMessage(out message, IntPtr.Zero, 0, 0) > 0) {
                if (message.Message == WM_SHIELD_REFRESH) { RefreshShieldOnThread(); continue; }
                if (message.Message == WM_SHIELD_FINISH_UP) { FinishNativeUpOnShieldThread(); continue; }
                if (message.Message == WM_SHIELD_STOP) break;
                TranslateMessage(ref message); DispatchMessage(ref message);
            }
            if (GetCapture() == window) ReleaseCapture();
            DestroyWindow(window);
        } catch (Exception error) {
            ShieldError = error.ToString(); ShieldReady.Set();
        } finally {
            ShieldRegionTarget = null;
            ShieldRegionWindow = IntPtr.Zero;
            ShieldWindow = IntPtr.Zero;
            ShieldVisible = false;
            ShieldThreadId = 0;
            Volatile.Write(ref ShieldState, 0);
            SetGestureActive(false);
        }
    }
    private static bool SameRect(RECT first, RECT second) {
        return first.Left == second.Left && first.Top == second.Top &&
            first.Right == second.Right && first.Bottom == second.Bottom;
    }
    private static bool ShieldAboveOverlay(IntPtr overlay) {
        for (IntPtr above = GetWindow(overlay, 3); above != IntPtr.Zero; above = GetWindow(above, 3))
            if (above == ShieldWindow) return true;
        return false;
    }
    private static void ApplyShieldRegion(PetTarget target) {
        int width = target.Body.Right - target.Body.Left;
        int height = target.Body.Bottom - target.Body.Top;
        PetTarget previous = ShieldRegionTarget;
        bool same = previous != null && ShieldRegionWindow == ShieldWindow &&
            width == previous.Body.Right - previous.Body.Left &&
            height == previous.Body.Bottom - previous.Body.Top &&
            target.Buttons.Length == previous.Buttons.Length;
        if (same) {
            for (int i = 0; i < target.Buttons.Length; i++) {
                RECT a = target.Buttons[i], b = previous.Buttons[i];
                if (a.Left - target.Body.Left != b.Left - previous.Body.Left ||
                    a.Right - target.Body.Left != b.Right - previous.Body.Left ||
                    a.Top - target.Body.Top != b.Top - previous.Body.Top ||
                    a.Bottom - target.Body.Top != b.Bottom - previous.Body.Top) {
                    same = false;
                    break;
                }
            }
        }
        // The region is local to the window. Moving the same shape needs no
        // new HRGN or layered-window invalidation on every accessibility poll.
        if (same) return;
        IntPtr region = CreateRectRgn(0, 0, width, height);
        if (region == IntPtr.Zero) return;
        foreach (RECT button in target.Buttons) {
            IntPtr exclusion = CreateRectRgn(button.Left - target.Body.Left,
                button.Top - target.Body.Top, button.Right - target.Body.Left,
                button.Bottom - target.Body.Top);
            if (exclusion != IntPtr.Zero) {
                CombineRgn(region, region, exclusion, 4); // RGN_DIFF
                DeleteObject(exclusion);
            }
        }
        if (SetWindowRgn(ShieldWindow, region, false) == 0) {
            DeleteObject(region);
        } else {
            // Ownership of the successful region has transferred to Windows.
            ShieldRegionTarget = target;
            ShieldRegionWindow = ShieldWindow;
            Interlocked.Increment(ref ShieldRegionUpdates);
        }
    }
    private static void RefreshShieldOnThread() {
        if (ShieldWindow == IntPtr.Zero || Volatile.Read(ref ShieldState) != 0) return;
        PetTarget target = Volatile.Read(ref CurrentTarget);
        bool fresh = target != null && DateTime.UtcNow.Ticks <= target.ExpiresAt &&
            target.PublishedAt > Interlocked.Read(ref ShieldRequireTargetAfter);
        int width = fresh ? target.Body.Right - target.Body.Left : 0;
        int height = fresh ? target.Body.Bottom - target.Body.Top : 0;
        POINT center = fresh ? new POINT {
            X = target.Body.Left + width / 2, Y = target.Body.Top + height / 2
        } : new POINT();
        bool usable = fresh && width > 0 && height > 0 && width <= 500 && height <= 500 &&
            target.Renderer != IntPtr.Zero && IsWindow(target.Renderer) &&
            GetAncestor(target.Renderer, 2) == target.Overlay &&
            IsPetPointUnobscured(target.Overlay, center);
        if (!usable) {
            if (ShieldVisible) {
                EndShieldHover();
                SetWindowPos(ShieldWindow, IntPtr.Zero, 0, 0, 0, 0, 0x0080U | 0x0001U | 0x0002U | 0x0010U);
            }
            ShieldVisible = false;
            return;
        }
        bool needsPlacement = !ShieldVisible || !SameRect(ShieldBounds, target.Body) ||
            !ShieldAboveOverlay(target.Overlay);
        if (needsPlacement) {
            EndShieldHover();
            // Insert directly above the pet. Other already-visible selection
            // surfaces keep their place above this input window.
            IntPtr abovePet = GetWindow(target.Overlay, 3);
            IntPtr after = abovePet == ShieldWindow ? GetWindow(ShieldWindow, 3) : abovePet;
            if (after == IntPtr.Zero) after = new IntPtr(-1);
            if (SetWindowPos(ShieldWindow, after, target.Body.Left, target.Body.Top,
                width, height, 0x0010U | 0x0040U | 0x0200U)) {
                ShieldBounds = target.Body;
                ShieldPlacedOverlay = target.Overlay;
                ShieldVisible = true;
            } else {
                ShieldError = "SetWindowPos shield: " + Marshal.GetLastWin32Error();
                ShieldVisible = false;
            }
        }
        if (ShieldVisible) ShieldPlacedOverlay = target.Overlay;
        if (ShieldVisible) ApplyShieldRegion(target);
    }
    private static bool SendToPetRaw(uint message, int x, int y, IntPtr flags) {
        if (ShieldRenderer == IntPtr.Zero || !IsWindow(ShieldRenderer) ||
            GetAncestor(ShieldRenderer, 2) != ShieldOverlay) return false;
        POINT client = new POINT { X = x, Y = y };
        if (!ScreenToClient(ShieldRenderer, ref client) ||
            client.X < Int16.MinValue || client.X > Int16.MaxValue ||
            client.Y < Int16.MinValue || client.Y > Int16.MaxValue) return false;
        UIntPtr ignored;
        bool sent = SendMessageTimeout(ShieldRenderer, message, flags,
            MakeMouseLParam(client.X, client.Y), 0x23U, 100, out ignored) != IntPtr.Zero;
        Volatile.Write(ref ShieldLastSendError, sent ? 0 : Marshal.GetLastWin32Error());
        return sent;
    }
    private static bool SendToPet(uint message, int x, int y, bool pressed) {
        return SendToPetRaw(message, x, y, pressed ? new IntPtr(1) : IntPtr.Zero);
    }
    private static long PackPoint(POINT point) {
        return unchecked(((long)(uint)point.X << 32) | (uint)point.Y);
    }
    private static POINT UnpackPoint(long packed) {
        return new POINT { X = unchecked((int)(packed >> 32)), Y = unchecked((int)packed) };
    }
    private static void ForwardLatestDragMove() {
        long latest = Interlocked.Read(ref LatestDragPointPacked);
        if (latest == Interlocked.Read(ref LastRelayedDragPointPacked)) return;
        POINT point = UnpackPoint(latest);
        if (SendToPet(WM_MOUSEMOVE, point.X, point.Y, true)) {
            Interlocked.Exchange(ref LastRelayedDragPointPacked, latest);
            Interlocked.Increment(ref DeliveredMoveCount);
        }
    }
    private static void QueueFinalDragMove(POINT position) {
        IntPtr renderer = ShieldRenderer;
        if (renderer == IntPtr.Zero || !IsWindow(renderer) ||
            GetAncestor(renderer, 2) != ShieldOverlay) return;
        POINT client = position;
        if (!ScreenToClient(renderer, ref client) ||
            client.X < Int16.MinValue || client.X > Int16.MaxValue ||
            client.Y < Int16.MinValue || client.Y > Int16.MaxValue) return;
        if (PostMessage(renderer, WM_MOUSEMOVE, new IntPtr(1),
            MakeMouseLParam(client.X, client.Y)))
            Interlocked.Increment(ref DeliveredMoveCount);
        else Volatile.Write(ref ShieldLastSendError, Marshal.GetLastWin32Error());
    }
    private static bool PhysicalLeftHeld() { return GetAsyncKeyState(1) < 0; }
    private static int PhysicalDragThreshold(IntPtr overlay) {
        uint dpi = 96;
        try { dpi = GetDpiForWindow(overlay); }
        catch (EntryPointNotFoundException) { dpi = 96; }
        if (dpi < 96) dpi = 96;
        // The pet's JavaScript checks >=4 CSS pixels per axis. Add one
        // physical pixel so rounding at 125%, 150%, etc. cannot turn a
        // handed-off drag back into a native click.
        return Math.Max(5, (int)Math.Ceiling(4.0 * dpi / 96.0) + 1);
    }
    private static void PositionShieldAfterNativeDrag() {
        IntPtr overlay = ShieldOverlay;
        RECT currentOverlay;
        if (ShieldWindow == IntPtr.Zero || overlay == IntPtr.Zero ||
            !IsWindowVisible(overlay) || !GetWindowRect(overlay, out currentOverlay) ||
            ShieldOverlayBoundsAtDown.Right <= ShieldOverlayBoundsAtDown.Left) {
            HideShieldOnThread();
            return;
        }
        int dx = currentOverlay.Left - ShieldOverlayBoundsAtDown.Left;
        int dy = currentOverlay.Top - ShieldOverlayBoundsAtDown.Top;
        if (dx == 0) dx = ShieldLastUp.X - ShieldStart.X;
        if (dy == 0) dy = ShieldLastUp.Y - ShieldStart.Y;
        int width = ShieldBodyBoundsAtDown.Right - ShieldBodyBoundsAtDown.Left;
        int height = ShieldBodyBoundsAtDown.Bottom - ShieldBodyBoundsAtDown.Top;
        RECT predicted = new RECT {
            Left = ShieldBodyBoundsAtDown.Left + dx, Top = ShieldBodyBoundsAtDown.Top + dy,
            Right = ShieldBodyBoundsAtDown.Right + dx, Bottom = ShieldBodyBoundsAtDown.Bottom + dy
        };
        IntPtr monitor = MonitorFromPoint(ShieldLastUp, 2);
        MONITORINFO monitorInfo = new MONITORINFO { Size = Marshal.SizeOf(typeof(MONITORINFO)) };
        if (monitor != IntPtr.Zero && GetMonitorInfo(monitor, ref monitorInfo) &&
            width <= monitorInfo.Work.Right - monitorInfo.Work.Left &&
            height <= monitorInfo.Work.Bottom - monitorInfo.Work.Top) {
            predicted.Left = Math.Max(monitorInfo.Work.Left,
                Math.Min(predicted.Left, monitorInfo.Work.Right - width));
            predicted.Top = Math.Max(monitorInfo.Work.Top,
                Math.Min(predicted.Top, monitorInfo.Work.Bottom - height));
            predicted.Right = predicted.Left + width;
            predicted.Bottom = predicted.Top + height;
        }
        POINT center = new POINT { X = predicted.Left + (predicted.Right - predicted.Left) / 2,
            Y = predicted.Top + (predicted.Bottom - predicted.Top) / 2 };
        if (!IsPetPointUnobscured(overlay, center)) { HideShieldOnThread(); return; }
        IntPtr abovePet = GetWindow(overlay, 3);
        IntPtr after = abovePet == ShieldWindow ? GetWindow(ShieldWindow, 3) : abovePet;
        if (after == IntPtr.Zero) after = new IntPtr(-1);
        if (!SetWindowPos(ShieldWindow, after, predicted.Left, predicted.Top,
            predicted.Right - predicted.Left, predicted.Bottom - predicted.Top,
            0x0010U | 0x0040U | 0x0200U)) {
            ShieldError = "SetWindowPos after drag: " + Marshal.GetLastWin32Error();
            HideShieldOnThread();
            return;
        }
        ShieldBounds = predicted;
        ShieldPlacedOverlay = overlay;
        ShieldVisible = true;
        PetTarget oldTarget = Volatile.Read(ref CurrentTarget);
        if (oldTarget != null && oldTarget.Overlay == overlay) ApplyShieldRegion(oldTarget);
    }
    private static void HideShieldOnThread() {
        if (ShieldVisible && ShieldWindow != IntPtr.Zero) {
            EndShieldHover();
            SetWindowPos(ShieldWindow, IntPtr.Zero, 0, 0, 0, 0,
                0x0080U | 0x0001U | 0x0002U | 0x0010U);
        }
        ShieldVisible = false;
    }
    private static void FinishNativeUpOnShieldThread() {
        if (Volatile.Read(ref ShieldState) != 4) return;
        KillTimer(ShieldWindow, new UIntPtr(2));
        // Give the actual hardware UP an opportunity to reach Chromium in
        // order. The final queued MOVE must precede the fallback UP.
        if (SetTimer(ShieldWindow, new UIntPtr(1), 20, IntPtr.Zero) == UIntPtr.Zero)
            FinishNativeUpAfterTimer();
    }
    private static void FinishNativeUpAfterTimer() {
        if (Interlocked.CompareExchange(ref ShieldState, 0, 4) != 4) return;
        if (ShieldRenderer != IntPtr.Zero && IsWindow(ShieldRenderer))
            PostMessage(ShieldRenderer, WM_LBUTTONUP, IntPtr.Zero,
                NativePosition(ShieldRenderer, ShieldLastUp.X, ShieldLastUp.Y));
        PositionShieldAfterNativeDrag();
    }
    public static void ReconcileShieldRelease() {
        if (Volatile.Read(ref ShieldState) != 4 ||
            DateTime.UtcNow.Ticks < Interlocked.Read(ref ShieldReleaseDeadline)) return;
        if (Interlocked.CompareExchange(ref ShieldState, 0, 4) != 4) return;
        // A physical UP normally goes to Chromium after capture handoff. A
        // second UP is inert there; it also balances a rare UP lost during a
        // concurrent window/capture transition.
        if (ShieldRenderer != IntPtr.Zero && IsWindow(ShieldRenderer))
            PostMessage(ShieldRenderer, WM_LBUTTONUP, IntPtr.Zero,
                NativePosition(ShieldRenderer, ShieldLastUp.X, ShieldLastUp.Y));
        RefreshShield();
    }
    private static void EndShieldHover() {
        IntPtr renderer = ShieldHoverRenderer;
        ShieldHoverRenderer = IntPtr.Zero;
        if (ShieldTrackingMouse && ShieldWindow != IntPtr.Zero) {
            var cancel = new TRACKMOUSEEVENT { Size = Marshal.SizeOf(typeof(TRACKMOUSEEVENT)),
                Flags = 0x80000002U, Window = ShieldWindow, HoverTime = 0 };
            TrackMouseEvent(ref cancel);
        }
        ShieldTrackingMouse = false;
        if (renderer != IntPtr.Zero && IsWindow(renderer))
            PostMessage(renderer, WM_MOUSELEAVE, IntPtr.Zero, IntPtr.Zero);
    }
    private static void ForwardShieldHover(IntPtr window, POINT position) {
        PetTarget target = Volatile.Read(ref CurrentTarget);
        if (target == null || target.Renderer == IntPtr.Zero ||
            !IsWindow(target.Renderer) || GetAncestor(target.Renderer, 2) != target.Overlay) return;
        if (ShieldHoverRenderer != IntPtr.Zero && ShieldHoverRenderer != target.Renderer) EndShieldHover();
        if (!ShieldTrackingMouse) {
            var request = new TRACKMOUSEEVENT { Size = Marshal.SizeOf(typeof(TRACKMOUSEEVENT)),
                Flags = 2, Window = window, HoverTime = 0 };
            ShieldTrackingMouse = TrackMouseEvent(ref request);
        }
        POINT client = position;
        if (ScreenToClient(target.Renderer, ref client) &&
            client.X >= Int16.MinValue && client.X <= Int16.MaxValue &&
            client.Y >= Int16.MinValue && client.Y <= Int16.MaxValue) {
            ShieldHoverRenderer = target.Renderer;
            PostMessage(target.Renderer, WM_MOUSEMOVE, IntPtr.Zero,
                MakeMouseLParam(client.X, client.Y));
        }
    }
    private static bool PetHasCapture() {
        if (ShieldRenderer == IntPtr.Zero || !IsWindow(ShieldRenderer)) return false;
        uint processId;
        uint targetThread = GetWindowThreadProcessId(ShieldRenderer, out processId);
        GUITHREADINFO info = new GUITHREADINFO { Size = Marshal.SizeOf(typeof(GUITHREADINFO)) };
        return targetThread != 0 && GetGUIThreadInfo(targetThread, ref info) &&
            info.Capture != IntPtr.Zero && GetAncestor(info.Capture, 2) == ShieldOverlay;
    }
    private static void FinishShieldGesture(int message, POINT end, bool wasDrag) {
        if (wasDrag) Interlocked.Exchange(ref ShieldRequireTargetAfter, DateTime.UtcNow.Ticks);
        MouseHookEvents.Enqueue(new MouseHookEventRecord {
            Message = message, X = end.X, Y = end.Y, UtcTicks = DateTime.UtcNow.Ticks,
            ForegroundBefore = ShieldForeground, ForegroundAtEvent = GetForegroundWindow().ToInt64(),
            ForegroundShowStateBefore = ShieldShowState,
            NativeClickSuppressed = !wasDrag, NativeClickDeflected = !wasDrag,
            BodyGestureOwned = !wasDrag, BodyDragStarted = wasDrag, NativeDragHandoff = wasDrag
        });
        Interlocked.Increment(ref CompletedGestureCount);
        Interlocked.Exchange(ref SettleUntil, DateTime.UtcNow.AddMilliseconds(80).Ticks);
        Volatile.Write(ref ShieldState, 0);
        SetGestureActive(false);
        if (wasDrag) PositionShieldAfterNativeDrag(); else RefreshShield();
    }
    private static IntPtr ShieldCallback(IntPtr window, uint message, IntPtr wParam, IntPtr lParam) {
        if (message == WM_MOUSEACTIVATE) return new IntPtr(3); // MA_NOACTIVATE
        if (message == WM_NCHITTEST) return new IntPtr(1); // HTCLIENT
        if (message == WM_LBUTTONDOWN) {
            if (Volatile.Read(ref ShieldState) == 4) {
                SendToPet(WM_LBUTTONUP, ShieldLastUp.X, ShieldLastUp.Y, false);
                Volatile.Write(ref ShieldState, 0);
            }
            PetTarget target = Volatile.Read(ref CurrentTarget);
            POINT start = new POINT {
                X = ShieldBounds.Left + unchecked((short)(lParam.ToInt64() & 0xffff)),
                Y = ShieldBounds.Top + unchecked((short)((lParam.ToInt64() >> 16) & 0xffff))
            };
            if (!ShieldVisible || !Contains(ShieldBounds, start)) return IntPtr.Zero;
            if (target != null)
                foreach (RECT button in target.Buttons) if (Contains(button, start)) return IntPtr.Zero;
            IntPtr overlay = target != null ? target.Overlay : ShieldPlacedOverlay;
            if (overlay == IntPtr.Zero || !IsWindowVisible(overlay)) return IntPtr.Zero;
            bool nativeTargetReady = target != null && DateTime.UtcNow.Ticks <= target.ExpiresAt &&
                SameRect(target.Body, ShieldBounds) && target.Renderer != IntPtr.Zero &&
                IsWindow(target.Renderer) && GetAncestor(target.Renderer, 2) == target.Overlay;
            EndShieldHover();
            ShieldStart = start;
            ShieldDragThresholdPhysical = PhysicalDragThreshold(overlay);
            ShieldBodyBoundsAtDown = ShieldBounds;
            ShieldOverlay = overlay;
            ShieldRenderer = nativeTargetReady ? target.Renderer : IntPtr.Zero;
            if (!GetWindowRect(overlay, out ShieldOverlayBoundsAtDown))
                ShieldOverlayBoundsAtDown = new RECT();
            ShieldForeground = GetForegroundWindow().ToInt64();
            ShieldShowState = ShieldForeground == 0 ? 0 : IsIconic(new IntPtr(ShieldForeground)) ? 2 : IsZoomed(new IntPtr(ShieldForeground)) ? 3 : 1;
            SetCapture(window);
            Volatile.Write(ref ShieldState, 1);
            SetGestureActive(true);
            return IntPtr.Zero;
        }
        if (message == WM_RBUTTONDOWN || message == WM_RBUTTONUP) {
            PetTarget target = Volatile.Read(ref CurrentTarget);
            if (target != null && target.Renderer != IntPtr.Zero && IsWindow(target.Renderer) &&
                GetAncestor(target.Renderer, 2) == target.Overlay) {
                ShieldOverlay = target.Overlay;
                ShieldRenderer = target.Renderer;
                int x = ShieldBounds.Left + unchecked((short)(lParam.ToInt64() & 0xffff));
                int y = ShieldBounds.Top + unchecked((short)((lParam.ToInt64() >> 16) & 0xffff));
                SendToPetRaw(message, x, y,
                    message == WM_RBUTTONDOWN ? new IntPtr(2) : IntPtr.Zero);
            }
            return IntPtr.Zero;
        }
        if (message == WM_CONTEXTMENU) return IntPtr.Zero;
        if (message == WM_MOUSEMOVE && Volatile.Read(ref ShieldState) == 1) {
            POINT current = new POINT {
                X = ShieldBounds.Left + unchecked((short)(lParam.ToInt64() & 0xffff)),
                Y = ShieldBounds.Top + unchecked((short)((lParam.ToInt64() >> 16) & 0xffff))
            };
            if (Math.Abs(current.X - ShieldStart.X) >= ShieldDragThresholdPhysical ||
                Math.Abs(current.Y - ShieldStart.Y) >= ShieldDragThresholdPhysical) {
                if (!PhysicalLeftHeld() || !IsWindow(ShieldOverlay) || !IsWindow(ShieldRenderer)) {
                    ShieldLastResult = "released-before-handoff";
                    Volatile.Write(ref ShieldState, 3);
                    return IntPtr.Zero;
                }
                ShieldSendingHandoff = true;
                bool downSent = SendToPet(WM_LBUTTONDOWN, ShieldStart.X, ShieldStart.Y, true);
                bool moveSent = downSent && SendToPet(WM_MOUSEMOVE, current.X, current.Y, true);
                bool captured = downSent && moveSent && PetHasCapture();
                ShieldSendingHandoff = false;
                if (captured) {
                    GestureStart = ShieldStart;
                    GestureForeground = ShieldForeground;
                    GestureShowState = ShieldShowState;
                    GestureIsButton = false;
                    GestureDragging = true;
                    long initialPoint = PackPoint(current);
                    Interlocked.Exchange(ref LatestDragPointPacked, initialPoint);
                    Interlocked.Exchange(ref LastRelayedDragPointPacked, initialPoint);
                    Volatile.Write(ref ShieldState, 2);
                    Interlocked.Increment(ref ShieldNativeDrags);
                    ShieldLastResult = "native-capture";
                    SetNativePointerAccess(ShieldOverlay, true, true);
                    if (GetCapture() == window) ReleaseCapture();
                    HideShieldOnThread();
                    if (SetTimer(window, new UIntPtr(2), 16, IntPtr.Zero) == UIntPtr.Zero)
                        ShieldError = "SetTimer drag relay: " + Marshal.GetLastWin32Error();
                } else {
                    Interlocked.Increment(ref ShieldHandoffFailures);
                    ShieldLastResult = downSent ? "native-handoff-cleanup" : "native-down-failed";
                    if (downSent) {
                        // Keep the cleanup MOVE and UP at one displaced point.
                        // Returning to origin can coalesce away the move and
                        // turn this exceptional path into a native click.
                        int cleanupX = ShieldStart.X + ShieldDragThresholdPhysical + 1;
                        int cleanupY = ShieldStart.Y + ShieldDragThresholdPhysical + 1;
                        if (!SendToPet(WM_MOUSEMOVE, cleanupX, cleanupY, true))
                            PostMessage(ShieldRenderer, WM_MOUSEMOVE, new IntPtr(1), NativePosition(ShieldRenderer, cleanupX, cleanupY));
                        if (!SendToPet(WM_LBUTTONUP, cleanupX, cleanupY, false))
                            PostMessage(ShieldRenderer, WM_LBUTTONUP, IntPtr.Zero, NativePosition(ShieldRenderer, cleanupX, cleanupY));
                    }
                    Volatile.Write(ref ShieldState, 3); // wait for real shield UP
                }
            }
            return IntPtr.Zero;
        }
        if (message == WM_MOUSEMOVE && Volatile.Read(ref ShieldState) == 0) {
            POINT current = new POINT {
                X = ShieldBounds.Left + unchecked((short)(lParam.ToInt64() & 0xffff)),
                Y = ShieldBounds.Top + unchecked((short)((lParam.ToInt64() >> 16) & 0xffff))
            };
            ForwardShieldHover(window, current);
            return IntPtr.Zero;
        }
        if (message == WM_MOUSELEAVE) { EndShieldHover(); return IntPtr.Zero; }
        if (message == WM_TIMER && wParam == new IntPtr(1)) {
            KillTimer(window, new UIntPtr(1));
            FinishNativeUpAfterTimer();
            return IntPtr.Zero;
        }
        if (message == WM_TIMER && wParam == new IntPtr(2)) {
            if (Volatile.Read(ref ShieldState) == 2) ForwardLatestDragMove();
            else KillTimer(window, new UIntPtr(2));
            return IntPtr.Zero;
        }
        if (message == WM_LBUTTONUP) {
            int state = Volatile.Read(ref ShieldState);
            POINT end = new POINT {
                X = ShieldBounds.Left + unchecked((short)(lParam.ToInt64() & 0xffff)),
                Y = ShieldBounds.Top + unchecked((short)((lParam.ToInt64() >> 16) & 0xffff))
            };
            if (state == 2 || state == 4) {
                if (state == 2) ShieldLastUp = end;
                else end = ShieldLastUp; // actual screen point from the low-level physical UP
                if (!SendToPet(WM_LBUTTONUP, end.X, end.Y, false) &&
                    ShieldRenderer != IntPtr.Zero && IsWindow(ShieldRenderer))
                    PostMessage(ShieldRenderer, WM_LBUTTONUP, IntPtr.Zero,
                        NativePosition(ShieldRenderer, end.X, end.Y));
                if (state == 2) FinishShieldGesture(WM_LBUTTONUP, end, true);
                else { Volatile.Write(ref ShieldState, 0); PositionShieldAfterNativeDrag(); }
            } else if (state == 1) {
                Interlocked.Increment(ref ShieldClicks);
                FinishShieldGesture(WM_LBUTTONUP, end, false);
            } else if (state == 3) {
                Volatile.Write(ref ShieldState, 0); SetGestureActive(false); RefreshShield();
            }
            if (GetCapture() == window) ReleaseCapture();
            return IntPtr.Zero;
        }
        if (message == WM_CAPTURECHANGED) {
            if (Volatile.Read(ref ShieldState) == 1 && !ShieldSendingHandoff) {
                ShieldLastResult = "shield-capture-lost";
                Volatile.Write(ref ShieldState, 0);
                SetGestureActive(false);
                RefreshShield();
            }
            return IntPtr.Zero;
        }
        if (message == WM_CLOSE) { DestroyWindow(window); return IntPtr.Zero; }
        if (message == WM_DESTROY) { PostQuitMessage(0); return IntPtr.Zero; }
        return DefWindowProc(window, message, wParam, lParam);
    }
    private static IntPtr NativePosition(IntPtr renderer, int x, int y) {
        POINT client = new POINT { X = x, Y = y };
        if (!ScreenToClient(renderer, ref client)) return IntPtr.Zero;
        return MakeMouseLParam(client.X, client.Y);
    }


    // Observe physical input without consuming it. A body click is owned by
    // the separate shield window; after a verified drag handoff the native
    // renderer receives the rest of the physical gesture directly.
    public static bool ProcessPointer(int message, POINT point, uint flags) {
        if ((flags & 1U) != 0) return false;
        if (message != WM_LBUTTONDOWN && message != WM_LBUTTONUP && message != WM_MOUSEMOVE) return false;
        int shieldState = Volatile.Read(ref ShieldState);
        if (shieldState == 1 || shieldState == 3) return false;
        if ((shieldState == 0 || shieldState == 4) && message == WM_LBUTTONDOWN && ShieldWindow != IntPtr.Zero &&
            WindowFromPoint(point) == ShieldWindow) return false;
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
        if (message == WM_MOUSEMOVE) {
            Interlocked.Increment(ref InputMoveCount);
            if (shieldState == 2)
                Interlocked.Exchange(ref LatestDragPointPacked, PackPoint(point));
        }
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
            if (shieldState == 2) {
                Interlocked.Exchange(ref LatestDragPointPacked, PackPoint(point));
                QueueFinalDragMove(point);
                ShieldLastUp = point;
                Interlocked.Exchange(ref ShieldRequireTargetAfter, DateTime.UtcNow.Ticks);
                Interlocked.Exchange(ref ShieldReleaseDeadline, DateTime.UtcNow.AddMilliseconds(250).Ticks);
                Volatile.Write(ref ShieldState, 4);
                uint shieldThread = ShieldThreadId;
                if (shieldThread != 0)
                    PostThreadMessage(shieldThread, WM_SHIELD_FINISH_UP, UIntPtr.Zero, IntPtr.Zero);
            }
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
$script:petAutomationRoot = $null
$script:petAutomationRootOverlay = [IntPtr]::Zero
$script:petAutomationCache = [System.Windows.Automation.CacheRequest]::new()
$script:petAutomationCache.AutomationElementMode = [System.Windows.Automation.AutomationElementMode]::None
$script:petAutomationCache.TreeScope = [System.Windows.Automation.TreeScope]::Element
foreach ($property in @(
    [System.Windows.Automation.AutomationElement]::IsOffscreenProperty,
    [System.Windows.Automation.AutomationElement]::BoundingRectangleProperty,
    [System.Windows.Automation.AutomationElement]::NameProperty,
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty
)) { $script:petAutomationCache.Add($property) }
$script:petAutomationCondition = [System.Windows.Automation.OrCondition]::new(
    [System.Windows.Automation.Condition[]]@(
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Image),
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button)
    ))
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
        if ($null -eq $script:petAutomationRoot -or $script:petAutomationRootOverlay -ne $Overlay) {
            $script:petAutomationRoot = [System.Windows.Automation.AutomationElement]::FromHandle($Overlay)
            $script:petAutomationRootOverlay = $Overlay
        }
        $root = $script:petAutomationRoot
        if ($null -eq $root) {
            return $null
        }

        # Fetch only the two control types and five properties we need, in one
        # cache request. Returned nodes are snapshots, not live UIA references.
        $cacheScope = $script:petAutomationCache.Activate()
        try {
            $elements = $root.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                $script:petAutomationCondition
            )
        } finally { $cacheScope.Dispose() }
        $preferredMascots = @()
        $fallbackMascots = @()
        $buttons = @()
        for ($index = 0; $index -lt $elements.Count; $index++) {
            try {
                $current = $elements.Item($index).Cached
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
        $script:petAutomationRoot = $null
        $script:petAutomationRootOverlay = [IntPtr]::Zero
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
        apartmentState = [Threading.Thread]::CurrentThread.GetApartmentState().ToString()
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

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::MTA) {
    throw 'The input bridge requires PowerShell -MTA. Run Start-PaperCheer.ps1.'
}
$mutex = New-Object Threading.Mutex($false, 'Local\ProfessorCluckshotCodexPetInputBridge')
$ownsMutex = $false
$mouseHookStarted = $false
$shieldStarted = $false
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
    if ($mouseHookStarted) { $shieldStarted = [ProfessorCluckshotInputNative]::StartClickShield() }
    $script:pointerCaptureMode = if ($mouseHookStarted -and $shieldStarted) { 'click-shield-native-drag' } else { 'unavailable' }
    $script:pointerHookError = [ProfessorCluckshotInputNative]::GetMouseHookLastError()
    [void](Write-PointerEventFile)
    if (-not $mouseHookStarted) { throw "Input hook unavailable: $script:pointerHookError" }
    if (-not $shieldStarted) { throw "Click shield unavailable: $([ProfessorCluckshotInputNative]::GetClickShieldError())" }

    while ($true) {
        $now = [DateTime]::UtcNow
        [ProfessorCluckshotInputNative]::ReconcileShieldRelease()
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
            if (-not [ProfessorCluckshotInputNative]::IsClickShieldActive()) { throw "Click shield stopped: $([ProfessorCluckshotInputNative]::GetClickShieldError())" }
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
    if ($shieldStarted) { [ProfessorCluckshotInputNative]::StopClickShield() }
    if ($mouseHookStarted) { [ProfessorCluckshotInputNative]::StopMouseHook() }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

[CmdletBinding()]
param(
    [ValidateSet('random','start','thinking','running','reviewing','waiting','success','failure','idle')]
    [string]$InitialTrigger = 'random',

    [ValidateRange(30, 3600)]
    [int]$MinIntervalSeconds = 180,

    [ValidateRange(30, 7200)]
    [int]$MaxIntervalSeconds = 420,

    [ValidateRange(3, 30)]
    [int]$VisibleSeconds = 13,

    [ValidateRange(1, 30)]
    [int]$RecentHistorySize = 32,

    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
    throw 'PaperCheerOverlay 必须通过 PowerShell -STA 启动。请运行 Start-PaperCheer.ps1。'
}

if ($MaxIntervalSeconds -lt $MinIntervalSeconds) {
    throw 'MaxIntervalSeconds 不能小于 MinIntervalSeconds。'
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if (-not ('PaperCheer.NativeWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace PaperCheer {
    public static class NativeWindow {
        private const int GWL_EXSTYLE = -20;
        private const long WS_EX_TRANSPARENT = 0x00000020L;
        private const long WS_EX_TOOLWINDOW = 0x00000080L;
        private const long WS_EX_NOACTIVATE = 0x08000000L;

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MONITORINFO {
            public int Size;
            public RECT Monitor;
            public RECT Work;
            public uint Flags;
        }

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromRect(ref RECT rect, uint flags);

        [DllImport("user32.dll")]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(
            IntPtr hWnd,
            IntPtr insertAfter,
            int x,
            int y,
            int width,
            int height,
            uint flags
        );

        [DllImport("user32.dll")]
        private static extern bool ShowWindowAsync(IntPtr hWnd, int command);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool AttachThreadInput(uint sourceThread, uint targetThread, bool attach);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern void SwitchToThisWindow(IntPtr hWnd, bool altTab);

        [DllImport("user32.dll")]
        public static extern uint GetDoubleClickTime();

        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out POINT point);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int virtualKey);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
        private static extern int GetWindowLong32(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
        private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int index, IntPtr value);

        [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
        private static extern int SetWindowLong32(IntPtr hWnd, int index, int value);

        private static IntPtr GetWindowLongPtr(IntPtr hWnd, int index) {
            return IntPtr.Size == 8
                ? GetWindowLongPtr64(hWnd, index)
                : new IntPtr(GetWindowLong32(hWnd, index));
        }

        private static void SetWindowLongPtr(IntPtr hWnd, int index, IntPtr value) {
            if (IntPtr.Size == 8) {
                SetWindowLongPtr64(hWnd, index, value);
            } else {
                SetWindowLong32(hWnd, index, value.ToInt32());
            }
        }

        public static void MakeClickThrough(IntPtr hWnd) {
            long style = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
            style |= WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
            SetWindowLongPtr(hWnd, GWL_EXSTYLE, new IntPtr(style));
        }

        public static bool TryGetCodexPetWindow(out IntPtr resultWindow, out RECT result) {
            IntPtr bestPreferredWindow = IntPtr.Zero;
            IntPtr bestFallbackWindow = IntPtr.Zero;
            RECT bestPreferredRect = new RECT();
            RECT bestFallbackRect = new RECT();
            int bestPreferredScore = Int32.MaxValue;
            int bestFallbackScore = Int32.MaxValue;

            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                if (!IsWindowVisible(hWnd)) return true;

                StringBuilder title = new StringBuilder(256);
                StringBuilder className = new StringBuilder(128);
                GetWindowText(hWnd, title, title.Capacity);
                GetClassName(hWnd, className, className.Capacity);
                if (!String.Equals(title.ToString(), "Codex", StringComparison.Ordinal)) return true;
                string windowClass = className.ToString();
                if (windowClass != "Chrome_WidgetWin_1" && windowClass != "FLUTTERVIEW") return true;

                RECT rect;
                if (!GetWindowRect(hWnd, out rect)) return true;

                int width = rect.Right - rect.Left;
                int height = rect.Bottom - rect.Top;
                if (width < 120 || width > 1200 || height < 120 || height > 1200) return true;

                long style = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
                bool preferred = (style & 0x8L) != 0 && (style & WS_EX_TOOLWINDOW) != 0;
                int score = (Math.Abs(width - height) * 4) + width + height;
                if (preferred && score < bestPreferredScore) {
                    bestPreferredScore = score;
                    bestPreferredWindow = hWnd;
                    bestPreferredRect = rect;
                }
                if (score < bestFallbackScore) {
                    bestFallbackScore = score;
                    bestFallbackWindow = hWnd;
                    bestFallbackRect = rect;
                }
                return true;
            }, IntPtr.Zero);

            if (bestPreferredScore != Int32.MaxValue) {
                resultWindow = bestPreferredWindow;
                result = bestPreferredRect;
                return true;
            }
            resultWindow = bestFallbackWindow;
            result = bestFallbackRect;
            return bestFallbackScore != Int32.MaxValue;
        }

        public static bool TryGetCodexPetRect(out RECT result) {
            IntPtr ignored;
            return TryGetCodexPetWindow(out ignored, out result);
        }

        public static bool GetPetHorizontalBand(RECT target, out double leftFraction, out double rightFraction) {
            leftFraction = 0.42;
            rightFraction = 0.58;

            IntPtr monitor = MonitorFromRect(ref target, 2);
            MONITORINFO info = new MONITORINFO();
            info.Size = Marshal.SizeOf(typeof(MONITORINFO));
            if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) return false;

            // Codex mirrors the rendered pet inside its transparent overlay
            // when the overlay is docked against a monitor edge.
            const int edgeTolerance = 24;
            if (target.Left <= info.Work.Left + edgeTolerance) {
                leftFraction = 0.06;
                rightFraction = 0.22;
            } else if (target.Right >= info.Work.Right - edgeTolerance) {
                leftFraction = 0.77;
                rightFraction = 0.92;
            }
            return true;
        }

        public static bool ActivateCodexMainWindow() {
            IntPtr petWindow;
            RECT petRect;
            if (!TryGetCodexPetWindow(out petWindow, out petRect)) return false;

            uint petProcessId;
            GetWindowThreadProcessId(petWindow, out petProcessId);
            IntPtr best = IntPtr.Zero;
            long bestArea = -1;
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                if (hWnd == petWindow) return true;
                uint processId;
                GetWindowThreadProcessId(hWnd, out processId);
                if (processId != petProcessId) return true;

                StringBuilder className = new StringBuilder(128);
                GetClassName(hWnd, className, className.Capacity);
                string windowClass = className.ToString();
                if (windowClass != "Chrome_WidgetWin_1" && windowClass != "FLUTTERVIEW") return true;
                long style = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
                if ((style & WS_EX_TOOLWINDOW) != 0) return true;

                RECT rect;
                if (!GetWindowRect(hWnd, out rect)) return true;
                long area = Math.Max(0, rect.Right - rect.Left) * (long)Math.Max(0, rect.Bottom - rect.Top);
                if (area > bestArea) {
                    bestArea = area;
                    best = hWnd;
                }
                return true;
            }, IntPtr.Zero);

            if (best == IntPtr.Zero) return false;
            return ActivateWindow(best);
        }

        private static bool ActivateWindow(IntPtr window) {
            if (window == IntPtr.Zero) return false;
            uint processId;
            IntPtr foreground = GetForegroundWindow();
            uint foregroundThread = foreground == IntPtr.Zero
                ? 0
                : GetWindowThreadProcessId(foreground, out processId);
            uint currentThread = GetCurrentThreadId();
            bool attached = foregroundThread != 0 && foregroundThread != currentThread &&
                AttachThreadInput(currentThread, foregroundThread, true);
            ShowWindowAsync(window, 9);
            BringWindowToTop(window);
            SetForegroundWindow(window);
            SwitchToThisWindow(window, true);
            if (attached) AttachThreadInput(currentThread, foregroundThread, false);
            return true;
        }

        public static bool PositionBubbleNearPet(IntPtr bubble, IntPtr petWindow, RECT target) {
            RECT bubbleRect;
            if (bubble == IntPtr.Zero || petWindow == IntPtr.Zero || !GetWindowRect(bubble, out bubbleRect)) return false;

            int bubbleWidth = bubbleRect.Right - bubbleRect.Left;
            int bubbleHeight = bubbleRect.Bottom - bubbleRect.Top;
            int targetWidth = target.Right - target.Left;
            int targetHeight = target.Bottom - target.Top;
            if (bubbleWidth <= 0 || bubbleHeight <= 0 || targetWidth <= 0 || targetHeight <= 0) return false;

            IntPtr monitor = MonitorFromRect(ref target, 2);
            MONITORINFO info = new MONITORINFO();
            info.Size = Marshal.SizeOf(typeof(MONITORINFO));
            if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) return false;

            double petLeftFraction;
            double petRightFraction;
            GetPetHorizontalBand(target, out petLeftFraction, out petRightFraction);
            int petLeft = target.Left + (int)Math.Round(targetWidth * petLeftFraction);
            int petRight = target.Left + (int)Math.Round(targetWidth * petRightFraction);
            int petTop = target.Top + (int)Math.Round(targetHeight * 0.62);
            int petBottom = target.Top + (int)Math.Round(targetHeight * 0.90);
            int petCenterX = (petLeft + petRight) / 2;
            int petCenterY = (petTop + petBottom) / 2;
            const int gap = 2;
            const int margin = 8;

            int[,] candidates = new int[,] {
                { petRight + gap, petCenterY - (bubbleHeight / 2) },
                { petLeft - gap - bubbleWidth, petCenterY - (bubbleHeight / 2) },
                { petCenterX - (bubbleWidth / 2), petTop - gap - bubbleHeight },
                { petCenterX - (bubbleWidth / 2), petBottom + gap }
            };

            int minX = info.Work.Left + margin;
            int maxX = info.Work.Right - margin - bubbleWidth;
            int minY = info.Work.Top + margin;
            int maxY = info.Work.Bottom - margin - bubbleHeight;
            int left = candidates[0, 0];
            int top = candidates[0, 1];
            bool found = false;
            for (int i = 0; i < candidates.GetLength(0); i++) {
                int x = candidates[i, 0];
                int y = candidates[i, 1];
                if (x >= minX && x <= maxX && y >= minY && y <= maxY) {
                    left = x;
                    top = y;
                    found = true;
                    break;
                }
            }

            if (!found) {
                left = Math.Max(minX, Math.Min(left, maxX));
                top = Math.Max(minY, Math.Min(top, maxY));
            }

            // Win32 rectangles and SetWindowPos both use physical screen
            // pixels, avoiding WPF DIP drift at 125%/150% scaling and on
            // mixed-DPI multi-monitor desktops.
            // Keep the bubble in the topmost band but directly behind the pet,
            // so wide text or an animated pose can never cover the character.
            return SetWindowPos(bubble, petWindow, left, top, 0, 0, 0x0011);
        }

        public static int GetWindowDpiValue(IntPtr window) {
            uint dpi = window == IntPtr.Zero ? 0 : GetDpiForWindow(window);
            return dpi == 0 ? 96 : (int)dpi;
        }

        public static bool PositionBubbleNearBounds(IntPtr bubble, IntPtr petWindow, RECT petBounds) {
            // UI Automation reports physical screen pixels. Temporarily make
            // this thread per-monitor-aware so the Win32 bubble rectangle and
            // SetWindowPos use the same coordinate space on a scaled laptop.
            IntPtr previousContext = SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                RECT bubbleRect;
                if (bubble == IntPtr.Zero || petWindow == IntPtr.Zero ||
                    !GetWindowRect(bubble, out bubbleRect)) return false;

                int bubbleWidth = bubbleRect.Right - bubbleRect.Left;
                int bubbleHeight = bubbleRect.Bottom - bubbleRect.Top;
                int petWidth = petBounds.Right - petBounds.Left;
                int petHeight = petBounds.Bottom - petBounds.Top;
                if (bubbleWidth <= 0 || bubbleHeight <= 0 || petWidth <= 0 || petHeight <= 0) return false;

                IntPtr monitor = MonitorFromRect(ref petBounds, 2);
                MONITORINFO info = new MONITORINFO();
                info.Size = Marshal.SizeOf(typeof(MONITORINFO));
                if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) return false;

                int dpi = GetWindowDpiValue(petWindow);
                int gap = Math.Max(4, (int)Math.Round(4.0 * dpi / 96.0));
                int margin = Math.Max(8, (int)Math.Round(8.0 * dpi / 96.0));
                int petCenterX = (petBounds.Left + petBounds.Right) / 2;
                int petCenterY = (petBounds.Top + petBounds.Bottom) / 2;
                int[,] candidates = new int[,] {
                    { petBounds.Right + gap, petCenterY - (bubbleHeight / 2) },
                    { petBounds.Left - gap - bubbleWidth, petCenterY - (bubbleHeight / 2) },
                    { petCenterX - (bubbleWidth / 2), petBounds.Top - gap - bubbleHeight },
                    { petCenterX - (bubbleWidth / 2), petBounds.Bottom + gap }
                };

                int minX = info.Work.Left + margin;
                int maxX = info.Work.Right - margin - bubbleWidth;
                int minY = info.Work.Top + margin;
                int maxY = info.Work.Bottom - margin - bubbleHeight;
                int left = candidates[0, 0];
                int top = candidates[0, 1];
                bool found = false;
                for (int i = 0; i < candidates.GetLength(0); i++) {
                    int x = candidates[i, 0];
                    int y = candidates[i, 1];
                    if (x >= minX && x <= maxX && y >= minY && y <= maxY) {
                        left = x;
                        top = y;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    left = Math.Max(minX, Math.Min(left, maxX));
                    top = Math.Max(minY, Math.Min(top, maxY));
                }
                return SetWindowPos(bubble, petWindow, left, top, 0, 0, 0x0011);
            } finally {
                if (previousContext != IntPtr.Zero) {
                    SetThreadDpiAwarenessContext(previousContext);
                }
            }
        }
    }
}
'@
}

$packageRoot = $PSScriptRoot
$dialoguePath = Join-Path $packageRoot 'paper-cheer-dialogue.json'
$statePath = Join-Path $packageRoot 'paper-cheer-overlay-state.json'
$lastMessagePath = Join-Path $packageRoot 'paper-cheer-last-message.json'
$commandPath = Join-Path $packageRoot 'paper-cheer-command.json'
$pointerEventPath = Join-Path $packageRoot 'paper-cheer-pointer-events.json'
$inputBridgeScript = Join-Path $packageRoot 'CodexPetInputBridge.ps1'
$inputBridgePidPath = Join-Path $packageRoot 'codex-pet-input-bridge.pid'
$powershellExecutable = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $powershellExecutable -PathType Leaf)) {
    $powershellExecutable = (Get-Command powershell.exe -ErrorAction Stop).Source
}

if (-not (Test-Path -LiteralPath $dialoguePath)) {
    throw "找不到台词库：$dialoguePath"
}

$dialogue = Get-Content -LiteralPath $dialoguePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($dialogue.messages).Count -lt 2) {
    throw '台词库为空或数量不足。'
}

function Get-SavedState {
    if (Test-Path -LiteralPath $statePath) {
        try {
            $saved = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $saved -and $null -ne $saved.recentIds) {
                return @($saved.recentIds)
            }
        } catch {
            # 状态文件损坏时直接开始一轮新的去重记录，不影响桌宠运行。
        }
    }
    return @()
}

function Save-Json {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 5), $encoding)
}

$script:recentIds = @((Get-SavedState) | Select-Object -Last $RecentHistorySize)
$script:lastCategory = $null
$script:recentGeneratedTexts = @()

function Get-GeneratedPart {
    param([Parameter(Mandatory = $true)][object]$Parts)

    $items = @($Parts | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) {
        return $null
    }

    return $items[(Get-Random -Minimum 0 -Maximum $items.Count)]
}

function New-GeneratedMessage {
    param([Parameter(Mandatory = $true)][string]$Trigger)

    if (@('click','hover','drag') -contains $Trigger -or
        $script:lastCategory -eq 'generated' -or
        $null -eq $dialogue.PSObject.Properties['generated']) {
        return $null
    }

    $config = $dialogue.generated
    try {
        $chance = [double]$config.chance
    } catch {
        return $null
    }

    if ($chance -le 0 -or (Get-Random -Minimum 0 -Maximum 10000) -ge [Math]::Round($chance * 10000)) {
        return $null
    }

    $templates = @($config.templates)
    $openers = @($config.openers)
    $actions = @($config.actions)
    $endings = @($config.endings)
    if ($templates.Count -eq 0 -or $openers.Count -eq 0 -or $actions.Count -eq 0 -or $endings.Count -eq 0) {
        return $null
    }

    $maxCharacters = 34
    try { $maxCharacters = [Math]::Max(18, [int]$config.maxCharacters) } catch {}

    $text = $null
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $template = [string](Get-GeneratedPart -Parts $templates)
        $candidate = $template.Replace('{opening}', [string](Get-GeneratedPart -Parts $openers))
        $candidate = $candidate.Replace('{action}', [string](Get-GeneratedPart -Parts $actions))
        $candidate = $candidate.Replace('{ending}', [string](Get-GeneratedPart -Parts $endings))
        if ($candidate.Length -le $maxCharacters -and $script:recentGeneratedTexts -notcontains $candidate) {
            $text = $candidate
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $script:recentGeneratedTexts = @((@($script:recentGeneratedTexts) + @($text)) | Select-Object -Last 10)
    $script:lastCategory = 'generated'
    return [pscustomobject]@{
        id = 'generated-' + [guid]::NewGuid().ToString('N')
        category = 'generated'
        triggers = @($Trigger)
        text = $text
    }
}

function Get-CategoryWeight {
    param([Parameter(Mandatory = $true)][string]$Category)

    $property = @($dialogue.categories.PSObject.Properties | Where-Object { $_.Name -eq $Category } | Select-Object -First 1)
    if ($property.Count -eq 0) {
        return 1
    }

    try {
        return [Math]::Max(1, [int]$property[0].Value.weight)
    } catch {
        return 1
    }
}

function Select-Message {
    param([Parameter(Mandatory = $true)][string]$Trigger)

    $generated = New-GeneratedMessage -Trigger $Trigger
    if ($null -ne $generated) {
        return $generated
    }

    $candidates = @($dialogue.messages | Where-Object { @($_.triggers) -contains $Trigger })
    if ($Trigger -eq 'random') {
        $nonInteraction = @($candidates | Where-Object { $_.category -ne 'interaction' })
        if ($nonInteraction.Count -gt 0) {
            $candidates = $nonInteraction
        }
    }

    if ($candidates.Count -eq 0) {
        $candidates = @($dialogue.messages)
    }

    $fresh = @($candidates | Where-Object { $script:recentIds -notcontains $_.id })
    if ($fresh.Count -gt 0) {
        $candidates = $fresh
    }

    $categoryGroups = @($candidates | Group-Object -Property category)
    if ($categoryGroups.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($script:lastCategory)) {
        $differentGroups = @($categoryGroups | Where-Object { $_.Name -ne $script:lastCategory })
        if ($differentGroups.Count -gt 0) {
            $categoryGroups = $differentGroups
        }
    }

    $categoryWheel = New-Object System.Collections.Generic.List[string]
    foreach ($group in $categoryGroups) {
        $weight = Get-CategoryWeight -Category ([string]$group.Name)
        for ($index = 0; $index -lt $weight; $index++) {
            [void]$categoryWheel.Add([string]$group.Name)
        }
    }

    $selectedCategory = $categoryWheel[(Get-Random -Minimum 0 -Maximum $categoryWheel.Count)]
    $categoryCandidates = @($candidates | Where-Object { $_.category -eq $selectedCategory })
    $selected = $categoryCandidates[(Get-Random -Minimum 0 -Maximum $categoryCandidates.Count)]
    $script:lastCategory = [string]$selected.category
    return $selected
}

function Take-ManualCommand {
    if (-not (Test-Path -LiteralPath $commandPath)) {
        return $null
    }

    try {
        $command = Get-Content -LiteralPath $commandPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Remove-Item -LiteralPath $commandPath -Force -ErrorAction Stop
        return $command
    } catch {
        Remove-Item -LiteralPath $commandPath -Force -ErrorAction SilentlyContinue
        return $null
    }
}

$window = New-Object System.Windows.Window
$window.Title = 'Professor Cluckshot Speech Overlay'
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.Focusable = $false
$window.Topmost = $true
$window.IsHitTestVisible = $false
$window.Width = 272
$window.Height = 82
$window.Opacity = 0
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual

$border = New-Object System.Windows.Controls.Border
$border.CornerRadius = New-Object System.Windows.CornerRadius(16)
$border.BorderThickness = New-Object System.Windows.Thickness(1)
$border.Padding = New-Object System.Windows.Thickness(14, 9, 14, 9)
$border.Background = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFFEFCF8'))
$border.BorderBrush = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFE8DCCA'))

$panel = New-Object System.Windows.Controls.StackPanel
$panel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

$ball = New-Object System.Windows.Controls.TextBlock
$ball.Text = '🏀'
$ball.FontSize = 17
$ball.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Emoji')
$ball.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$ball.Margin = New-Object System.Windows.Thickness(0, 1, 8, 0)

$messageText = New-Object System.Windows.Controls.TextBlock
$messageText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
$messageText.FontSize = 13
$messageText.FontWeight = [System.Windows.FontWeights]::SemiBold
$messageText.Foreground = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF242B38'))
$messageText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$messageText.MaxWidth = 220
$messageText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

$panel.Children.Add($ball) | Out-Null
$panel.Children.Add($messageText) | Out-Null
$border.Child = $panel
$window.Content = $border
$script:bubbleHandle = [IntPtr]::Zero
$script:bubbleSource = $null
$script:pointerMessageHook = $null
$script:petVisualBounds = $null
$script:lastBubbleMetricKey = ''

function Set-ResponsiveBubbleMetrics {
    param(
        [IntPtr]$BubbleHandle,
        [IntPtr]$PetWindow = [IntPtr]::Zero,
        $PetBounds = $null
    )

    $dpiWindow = if ($PetWindow -ne [IntPtr]::Zero) { $PetWindow } else { $BubbleHandle }
    $dpi = [PaperCheer.NativeWindow]::GetWindowDpiValue($dpiWindow)
    $dpiScale = [Math]::Max(1.0, $dpi / 96.0)

    # Scale continuously from the pet's apparent logical width. A 160 px pet
    # on a 200% laptop is about 80 DIPs and gets the compact end of the range;
    # the same pet on a 100% desktop gets the roomier end. Moving between
    # monitors recalculates the ratio on the next position tick.
    $petLogicalWidth = 80.0
    if ($null -ne $PetBounds -and ($PetBounds.Right - $PetBounds.Left) -gt 0) {
        $petLogicalWidth = ($PetBounds.Right - $PetBounds.Left) / $dpiScale
    }
    $sizeRatio = [Math]::Max(0.0, [Math]::Min(1.0, ($petLogicalWidth - 80.0) / 90.0))
    $metricKey = '{0}:{1}' -f $dpi, [Math]::Round($petLogicalWidth)
    if ($script:lastBubbleMetricKey -eq $metricKey) {
        return
    }
    $script:lastBubbleMetricKey = $metricKey

    $bubbleWidth = [Math]::Round(204.0 + (68.0 * $sizeRatio))
    $bubbleHeight = [Math]::Round(66.0 + (16.0 * $sizeRatio))
    $paddingX = 10.0 + (4.0 * $sizeRatio)
    $paddingY = 7.0 + (2.0 * $sizeRatio)
    $cornerRadius = 14.0 + (2.0 * $sizeRatio)
    $iconSize = 14.0 + (3.0 * $sizeRatio)
    $iconGap = 6.0 + (2.0 * $sizeRatio)
    $textSize = 11.5 + (1.5 * $sizeRatio)

    $window.Width = $bubbleWidth
    $window.Height = $bubbleHeight
    $border.CornerRadius = New-Object System.Windows.CornerRadius($cornerRadius)
    $border.Padding = New-Object System.Windows.Thickness($paddingX, $paddingY, $paddingX, $paddingY)
    $ball.FontSize = $iconSize
    $ball.Margin = New-Object System.Windows.Thickness(0, 1, $iconGap, 0)
    $messageText.FontSize = $textSize
    $messageText.MaxWidth = [Math]::Max(150, $bubbleWidth - 48)
    $window.UpdateLayout()
}

function Get-PetVisualBounds {
    param([IntPtr]$PetWindow)

    if ($PetWindow -eq [IntPtr]::Zero) {
        return $null
    }
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($PetWindow)
        if ($null -eq $root) {
            return $null
        }
        $imageCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Image
        )
        $images = $root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            $imageCondition
        )
        $preferred = @()
        $fallback = @()
        for ($index = 0; $index -lt $images.Count; $index++) {
            try {
                $current = $images.Item($index).Current
                if ($current.IsOffscreen) {
                    continue
                }
                $bounds = $current.BoundingRectangle
                if ([double]::IsNaN($bounds.Left) -or [double]::IsInfinity($bounds.Left) -or
                    [double]::IsNaN($bounds.Top) -or [double]::IsInfinity($bounds.Top) -or
                    $bounds.Width -lt 40 -or $bounds.Height -lt 40) {
                    continue
                }
                $candidate = [pscustomobject]@{
                    left = [int][Math]::Floor($bounds.Left)
                    top = [int][Math]::Floor($bounds.Top)
                    right = [int][Math]::Ceiling($bounds.Right)
                    bottom = [int][Math]::Ceiling($bounds.Bottom)
                    width = [int][Math]::Ceiling($bounds.Width)
                    height = [int][Math]::Ceiling($bounds.Height)
                    className = [string]$current.ClassName
                }
                $fallback += $candidate
                if ($candidate.className.IndexOf('codex-avatar-button', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $preferred += $candidate
                }
            } catch {
                # Chromium accessibility nodes can change during animation.
            }
        }
        $candidates = if ($preferred.Count -gt 0) { @($preferred) } else { @($fallback) }
        $mascot = @($candidates | Sort-Object { $_.width * $_.height } -Descending | Select-Object -First 1)
        if ($mascot.Count -eq 0) {
            return $null
        }
        $rect = New-Object PaperCheer.NativeWindow+RECT
        $rect.Left = $mascot[0].left
        $rect.Top = $mascot[0].top
        $rect.Right = $mascot[0].right
        $rect.Bottom = $mascot[0].bottom
        return $rect
    } catch {
        return $null
    }
}

function Update-BubblePosition {
    $virtualLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
    $virtualTop = [System.Windows.SystemParameters]::VirtualScreenTop
    $virtualRight = $virtualLeft + [System.Windows.SystemParameters]::VirtualScreenWidth
    $virtualBottom = $virtualTop + [System.Windows.SystemParameters]::VirtualScreenHeight

    $target = New-Object PaperCheer.NativeWindow+RECT
    $petWindow = [IntPtr]::Zero
    if ([PaperCheer.NativeWindow]::TryGetCodexPetWindow([ref]$petWindow, [ref]$target)) {
        if ($null -eq $script:petVisualBounds) {
            $script:petVisualBounds = Get-PetVisualBounds -PetWindow $petWindow
        }
        Set-ResponsiveBubbleMetrics `
            -BubbleHandle $script:bubbleHandle `
            -PetWindow $petWindow `
            -PetBounds $script:petVisualBounds
        if ($null -ne $script:petVisualBounds -and
            $script:bubbleHandle -ne [IntPtr]::Zero -and
            [PaperCheer.NativeWindow]::PositionBubbleNearBounds(
                $script:bubbleHandle,
                $petWindow,
                $script:petVisualBounds
            )) {
            return
        }
        if ($script:bubbleHandle -ne [IntPtr]::Zero -and
            [PaperCheer.NativeWindow]::PositionBubbleNearPet($script:bubbleHandle, $petWindow, $target)) {
            return
        }

        # Startup-only fallback before the WPF handle is available.
        $targetHeight = $target.Bottom - $target.Top
        $rightSideLeft = $target.Right - 150
        $leftSideLeft = $target.Left - $window.Width + 150
        $top = $target.Top + [Math]::Round($targetHeight * 0.66)

        if ($rightSideLeft + $window.Width -le $virtualRight - 8) {
            $left = $rightSideLeft
        } elseif ($leftSideLeft -ge $virtualLeft + 8) {
            $left = $leftSideLeft
        } else {
            $left = $target.Left + [Math]::Round((($target.Right - $target.Left) - $window.Width) / 2)
            $top = $target.Top - $window.Height - 10
        }
    } else {
        $left = [System.Windows.SystemParameters]::WorkArea.Right - $window.Width - 28
        $top = [System.Windows.SystemParameters]::WorkArea.Bottom - $window.Height - 240
    }

    $window.Left = [Math]::Max($virtualLeft + 8, [Math]::Min($left, $virtualRight - $window.Width - 8))
    $window.Top = [Math]::Max($virtualTop + 8, [Math]::Min($top, $virtualBottom - $window.Height - 8))
}

function Get-PetHitBounds {
    $target = New-Object PaperCheer.NativeWindow+RECT
    $petWindow = [IntPtr]::Zero
    if (-not [PaperCheer.NativeWindow]::TryGetCodexPetWindow([ref]$petWindow, [ref]$target)) {
        $script:petVisualBounds = $null
        return $null
    }

    $script:petVisualBounds = Get-PetVisualBounds -PetWindow $petWindow
    if ($null -ne $script:petVisualBounds) {
        return [pscustomobject]@{
            Left = $script:petVisualBounds.Left - 6
            Right = $script:petVisualBounds.Right + 6
            Top = $script:petVisualBounds.Top - 6
            Bottom = $script:petVisualBounds.Bottom + 6
        }
    }

    $width = $target.Right - $target.Left
    $height = $target.Bottom - $target.Top
    [double]$petLeftFraction = 0.42
    [double]$petRightFraction = 0.58
    [void][PaperCheer.NativeWindow]::GetPetHorizontalBand(
        $target,
        [ref]$petLeftFraction,
        [ref]$petRightFraction
    )
    return [pscustomobject]@{
        Left = $target.Left + [Math]::Round($width * [Math]::Max(0.0, $petLeftFraction - 0.06))
        Right = $target.Left + [Math]::Round($width * [Math]::Min(1.0, $petRightFraction + 0.06))
        Top = $target.Top + [Math]::Round($height * 0.45)
        Bottom = $target.Top + [Math]::Round($height * 0.90)
    }
}

function Show-PetInteraction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('click','hover','drag')]
        [string]$Trigger
    )

    $interactionSeconds = Get-Random -Minimum 12 -Maximum 18
    Show-Message -Message (Select-Message -Trigger $Trigger) -DisplaySeconds $interactionSeconds
    $script:nextAt = (Get-Date).AddSeconds((Get-Random -Minimum $MinIntervalSeconds -Maximum ($MaxIntervalSeconds + 1)))
}

function Write-PetInteractionState {
    param([string]$Action, [datetime]$At)

    $script:interactionRegisterCount++
    $event = [pscustomobject]@{
        action = $Action
        at = $At.ToString('o')
        recordedAt = (Get-Date).ToString('o')
    }
    $script:interactionHistory = @($script:interactionHistory + $event | Select-Object -Last 12)
    $payload = [ordered]@{
        action = $Action
        at = $At.ToString('o')
        registerCount = $script:interactionRegisterCount
        foregroundBeforeClick = $script:foregroundBeforePetClick.ToInt64()
        restoreWindow = 0
        focusPolicy = 'single-click-no-window-mutation'
        doubleClickMilliseconds = $script:doubleClickMilliseconds
        history = $script:interactionHistory
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $packageRoot 'paper-cheer-interaction-state.json'),
        ($payload | ConvertTo-Json -Compress),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Register-PetClick {
    param(
        [datetime]$At,
        [int]$X,
        [int]$Y,
        [IntPtr]$ForegroundBefore = [IntPtr]::Zero
    )

    if ($At -lt $script:ignorePetClicksUntil) {
        return
    }

    if ($null -ne $script:pendingPetClickAt) {
        $elapsed = ($At - $script:pendingPetClickAt).TotalMilliseconds
        $distance = [Math]::Sqrt(
            [Math]::Pow($X - $script:pendingPetClickX, 2) +
            [Math]::Pow($Y - $script:pendingPetClickY, 2)
        )
        if ($elapsed -le $script:doubleClickMilliseconds -and $distance -lt 16) {
            $script:pendingPetClickAt = $null
            # The native pet may emit one delayed relay more than two seconds
            # after a completed double-click. Ignore that tail event so it
            # cannot turn the successful double-click back into a single.
            $script:ignorePetClicksUntil = $At.AddSeconds(3)
            $script:lastPetClickAt = $At
            Write-PetInteractionState -Action 'double' -At $At
            [void][PaperCheer.NativeWindow]::ActivateCodexMainWindow()
            return
        }
    }

    $script:pendingPetClickAt = $At
    $script:pendingPetClickX = $X
    $script:pendingPetClickY = $Y
    if ($ForegroundBefore -ne [IntPtr]::Zero) {
        $script:foregroundBeforePetClick = $ForegroundBefore
    }
    Write-PetInteractionState -Action 'pending-single' -At $At
}

function Receive-PetPointerEvents {
    if (-not (Test-Path -LiteralPath $pointerEventPath -PathType Leaf)) {
        return
    }

    try {
        $state = Get-Content -LiteralPath $pointerEventPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $state -or [string]::IsNullOrWhiteSpace([string]$state.sessionId)) {
            return
        }

        if ($script:pointerEventSession -ne [string]$state.sessionId) {
            $script:pointerEventSession = [string]$state.sessionId
            $script:processedPointerEventIds = @()
        }

        foreach ($event in @($state.events)) {
            $eventId = [string]$event.id
            if ([string]::IsNullOrWhiteSpace($eventId) -or
                $script:processedPointerEventIds -contains $eventId) {
                continue
            }

            $script:processedPointerEventIds = @(
                @($script:processedPointerEventIds) + $eventId | Select-Object -Last 24
            )
            if ([string]$event.kind -eq 'click') {
                $eventAt = [datetime]::Parse(
                    [string]$event.at,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::RoundtripKind
                ).ToLocalTime()
                $foregroundBefore = [IntPtr]::Zero
                if ($null -ne $event.PSObject.Properties['foregroundBefore']) {
                    $foregroundBefore = [IntPtr]::new([long]$event.foregroundBefore)
                }
                Register-PetClick -At $eventAt -X ([int]$event.x) -Y ([int]$event.y) -ForegroundBefore $foregroundBefore
            }
        }
    }
    catch {
        # The bridge replaces this tiny file atomically. If antivirus or file
        # indexing briefly holds it, retry naturally on the next 25 ms tick.
    }
}

$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

$hideTimer = New-Object System.Windows.Threading.DispatcherTimer
$hideTimer.Interval = [TimeSpan]::FromSeconds($VisibleSeconds)

$positionTimer = New-Object System.Windows.Threading.DispatcherTimer
$positionTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$positionTimer.Add_Tick({
    $script:petHitBounds = Get-PetHitBounds
    if ($window.Opacity -gt 0.01) {
        Update-BubblePosition
    }
})

$script:mouseWasDown = $false
$script:mouseDownOnPet = $false
$script:mouseDownX = 0
$script:mouseDownY = 0
$script:petHoverStartedAt = $null
$script:lastPetClickAt = [datetime]::MinValue
$script:lastPetDragAt = [datetime]::MinValue
$script:lastPetHoverAt = [datetime]::MinValue
$script:pendingPetClickAt = $null
$script:pendingPetClickX = 0
$script:pendingPetClickY = 0
$script:foregroundBeforePetClick = [IntPtr]::Zero
$script:ignorePetClicksUntil = [datetime]::MinValue
$script:interactionRegisterCount = 0
$script:interactionHistory = @()
$script:pointerEventSession = ''
$script:processedPointerEventIds = @()
$script:systemDoubleClickMilliseconds = [Math]::Max(200, [int][PaperCheer.NativeWindow]::GetDoubleClickTime())
# Windows double-click timing can be unusually high on a machine. Cap the pet's
# own pairing window so a single speaks promptly without changing system input.
$script:doubleClickMilliseconds = [Math]::Max(250, [Math]::Min(550, $script:systemDoubleClickMilliseconds))
$script:petHitBounds = Get-PetHitBounds

$interactionTimer = New-Object System.Windows.Threading.DispatcherTimer
$interactionTimer.Interval = [TimeSpan]::FromMilliseconds(25)
$interactionTimer.Add_Tick({
    $cursor = New-Object PaperCheer.NativeWindow+POINT
    if (-not [PaperCheer.NativeWindow]::GetCursorPos([ref]$cursor)) {
        return
    }

    $bounds = $script:petHitBounds
    $overPet = $null -ne $bounds -and
        $cursor.X -ge $bounds.Left -and $cursor.X -le $bounds.Right -and
        $cursor.Y -ge $bounds.Top -and $cursor.Y -le $bounds.Bottom
    $now = Get-Date
    $leftButtonState = [int][PaperCheer.NativeWindow]::GetAsyncKeyState(1)
    $leftButtonDown = (($leftButtonState -band 0x8000) -ne 0)

    Receive-PetPointerEvents

    if ($null -ne $script:pendingPetClickAt -and
        ($now - $script:pendingPetClickAt).TotalMilliseconds -gt $script:doubleClickMilliseconds) {
        $script:pendingPetClickAt = $null
        Write-PetInteractionState -Action 'single' -At $now
        Show-PetInteraction -Trigger 'click'
        $script:lastPetClickAt = $now
        $script:lastPetHoverAt = $now
    }

    if ($overPet -and -not $leftButtonDown) {
        # Capture the window that was active while the pointer was merely
        # hovering. The native pet handles a click before our polling tick can
        # observe mouse-down, so sampling only on mouse-down is too late.
        if (-not $script:mouseWasDown) {
            $script:foregroundBeforePetClick = [PaperCheer.NativeWindow]::GetForegroundWindow()
        }
        if ($null -eq $script:petHoverStartedAt) {
            $script:petHoverStartedAt = $now
        } elseif (($now - $script:petHoverStartedAt).TotalMilliseconds -ge 900 -and
                  ($now - $script:lastPetHoverAt).TotalSeconds -ge 45) {
            Show-PetInteraction -Trigger 'hover'
            $script:lastPetHoverAt = $now
            $script:petHoverStartedAt = $now
        }
    } elseif (-not $overPet) {
        $script:petHoverStartedAt = $null
    }

    if ($leftButtonDown -and -not $script:mouseWasDown) {
        $script:mouseDownOnPet = $overPet
        $script:mouseDownX = $cursor.X
        $script:mouseDownY = $cursor.Y
    }

    if (-not $leftButtonDown -and $script:mouseWasDown) {
        if ($script:mouseDownOnPet) {
            $distance = [Math]::Sqrt([Math]::Pow($cursor.X - $script:mouseDownX, 2) + [Math]::Pow($cursor.Y - $script:mouseDownY, 2))
            if ($distance -ge 16 -and ($now - $script:lastPetDragAt).TotalSeconds -ge 5) {
                Show-PetInteraction -Trigger 'drag'
                $script:lastPetDragAt = $now
                $script:lastPetHoverAt = $now
            }
        }
        $script:mouseDownOnPet = $false
    }

    $script:mouseWasDown = $leftButtonDown
})

$autoTimer = New-Object System.Windows.Threading.DispatcherTimer
$autoTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:lastInputBridgeHealthAt = [DateTime]::MinValue

function Ensure-InputBridgeRunning {
    $now = Get-Date
    if (($now - $script:lastInputBridgeHealthAt).TotalSeconds -lt 3) {
        return
    }
    $script:lastInputBridgeHealthAt = $now

    $bridgeProcessId = 0
    if (Test-Path -LiteralPath $inputBridgePidPath -PathType Leaf) {
        try {
            $bridgeProcessIdText = (Get-Content -LiteralPath $inputBridgePidPath -Raw -Encoding UTF8).Trim()
            if ($bridgeProcessIdText -match '^\d+$') {
                $bridgeProcessId = [int]$bridgeProcessIdText
            }
        }
        catch {
            $bridgeProcessId = 0
        }
    }

    if ($bridgeProcessId -gt 0) {
        $bridgeProcess = Get-Process -Id $bridgeProcessId -ErrorAction SilentlyContinue
        if ($null -ne $bridgeProcess -and @('powershell','pwsh') -contains $bridgeProcess.ProcessName) {
            return
        }
    }

    try {
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $inputBridgeScript)
        )
        $bridgeProcess = Start-Process -FilePath $powershellExecutable -ArgumentList $arguments -WindowStyle Hidden -PassThru
        [System.IO.File]::WriteAllText(
            $inputBridgePidPath,
            [string]$bridgeProcess.Id,
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
    catch {
        # Retry on the next health tick without interrupting speech.
    }
}

function Show-Message {
    param(
        [Parameter(Mandatory = $true)][object]$Message,
        [ValidateRange(3, 60)][int]$DisplaySeconds = $VisibleSeconds
    )

    $messageText.Text = [string]$Message.text
    Update-BubblePosition
    $window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $window.Opacity = 1
    $window.Show()
    $window.Topmost = $true
    Update-BubblePosition

    $script:recentIds = @((@($script:recentIds) + @([string]$Message.id)) | Select-Object -Last $RecentHistorySize)
    Save-Json -Path $statePath -Value ([ordered]@{
        recentIds = @($script:recentIds)
        updatedAt = (Get-Date).ToString('o')
    })
    Save-Json -Path $lastMessagePath -Value ([ordered]@{
        id = [string]$Message.id
        category = [string]$Message.category
        text = [string]$Message.text
        shownAt = (Get-Date).ToString('o')
    })

    $hideTimer.Stop()
    $hideTimer.Interval = [TimeSpan]::FromSeconds($DisplaySeconds)
    $hideTimer.Start()
}

$hideTimer.Add_Tick({
    $hideTimer.Stop()
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.To = 0
    $fade.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(260))
    $window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)

    if ($Once) {
        $script:shutdownTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:shutdownTimer.Interval = [TimeSpan]::FromMilliseconds(320)
        $script:shutdownTimer.Add_Tick({
            $script:shutdownTimer.Stop()
            $app.Shutdown()
        })
        $script:shutdownTimer.Start()
    }
})

$script:nextAt = (Get-Date).AddSeconds((Get-Random -Minimum $MinIntervalSeconds -Maximum ($MaxIntervalSeconds + 1)))
$autoTimer.Add_Tick({
    Ensure-InputBridgeRunning
    $manualCommand = Take-ManualCommand
    if ($null -ne $manualCommand) {
        $manualTrigger = [string]$manualCommand.trigger
        if (@('random','start','thinking','running','reviewing','waiting','success','failure','idle','click','hover','drag') -notcontains $manualTrigger) {
            $manualTrigger = 'random'
        }

        $manualSeconds = $VisibleSeconds
        if ($null -ne $manualCommand.PSObject.Properties['visibleSeconds']) {
            try { $manualSeconds = [int]$manualCommand.visibleSeconds } catch {}
        }
        $manualSeconds = [Math]::Max(3, [Math]::Min($manualSeconds, 60))

        if ($null -ne $manualCommand.PSObject.Properties['text'] -and -not [string]::IsNullOrWhiteSpace([string]$manualCommand.text)) {
            $manualMessage = [pscustomobject]@{
                id = 'manual-' + [guid]::NewGuid().ToString('N')
                category = 'manual'
                text = [string]$manualCommand.text
            }
        } else {
            $manualMessage = Select-Message -Trigger $manualTrigger
        }

        Show-Message -Message $manualMessage -DisplaySeconds $manualSeconds
        $script:nextAt = (Get-Date).AddSeconds((Get-Random -Minimum $MinIntervalSeconds -Maximum ($MaxIntervalSeconds + 1)))
        return
    }

    if (-not $Once -and (Get-Date) -ge $script:nextAt) {
        $autoSeconds = Get-Random -Minimum 12 -Maximum 18
        Show-Message -Message (Select-Message -Trigger 'random') -DisplaySeconds $autoSeconds
        $script:nextAt = (Get-Date).AddSeconds((Get-Random -Minimum $MinIntervalSeconds -Maximum ($MaxIntervalSeconds + 1)))
    }
})

$window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    $script:bubbleHandle = $helper.Handle
    Set-ResponsiveBubbleMetrics -BubbleHandle $script:bubbleHandle
    [PaperCheer.NativeWindow]::MakeClickThrough($script:bubbleHandle)
    $script:bubbleSource = [System.Windows.Interop.HwndSource]::FromHwnd($script:bubbleHandle)
    $script:pointerMessageHook = [System.Windows.Interop.HwndSourceHook]{
        param(
            [IntPtr]$Hwnd,
            [int]$Message,
            [IntPtr]$WParam,
            [IntPtr]$LParam,
            [ref]$Handled
        )
        if ($Message -eq 0x8001) {
            Receive-PetPointerEvents
            $Handled.Value = $true
        }
        return [IntPtr]::Zero
    }
    $script:bubbleSource.AddHook($script:pointerMessageHook)
})

$window.Add_Closed({
    $positionTimer.Stop()
    $interactionTimer.Stop()
    $autoTimer.Stop()
    $hideTimer.Stop()
    if ($null -ne $script:bubbleSource -and $null -ne $script:pointerMessageHook) {
        $script:bubbleSource.RemoveHook($script:pointerMessageHook)
    }
    $app.Shutdown()
})

$window.Show()
$positionTimer.Start()
$interactionTimer.Start()
$autoTimer.Start()
$initialSeconds = Get-Random -Minimum 12 -Maximum 18
Show-Message -Message (Select-Message -Trigger $InitialTrigger) -DisplaySeconds $initialSeconds

[void]$app.Run()

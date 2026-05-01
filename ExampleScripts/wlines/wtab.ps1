[CmdletBinding()]
param(
    [switch]$List,
    [string]$Hide,
    [switch]$HideMode,
    [switch]$Help,
    [switch]$fzf
)

$ErrorActionPreference = 'Stop'

if ($Help)
{
    Write-Host @"
Wlines Window Tab - Window management intergration for wlines

USAGE:
    wtab.ps1 [OPTIONS]

OPTIONS:
    -List           List all available windows (regular and hidden)
    -Hide <title>   Hide a window by title
                    Examples:
                    -Hide "Discord"
                    -Hide "Zen Browser"
                    -Hide "Steam"
    -HideMode       Interactive mode with Hide as the default action
    -Help           Show this help message

INTERACTIVE MODE:
    When run without arguments, shows a popup to select a window, then 
    executes the default action (Focus by default).
    
    Use -HideMode to change the default action to Hide instead.

EXAMPLES:
    # Interactive mode - Focus selected window (default)
    .\wtab.ps1

    # Interactive mode - Hide selected window
    .\wtab.ps1 -HideMode

    # List all windows
    .\wtab.ps1 -List

    # Hide a window directly
    .\wtab.ps1 -Hide "Discord"
"@
    return
}

$WlinesWrapper = if ($fzf)
{
    Join-Path $PSScriptRoot 'wfzf.ps1'
} else
{
    Join-Path $PSScriptRoot 'wrofi.ps1'
}

# Auto-detect SSH session
$IsRemoteSession = -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)

if (-not ([Ref].Assembly.GetType('WinEnum'))) {
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class WinEnum {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const int SW_HIDE = 0;
    public const int SW_SHOWNORMAL = 1;
    public const int SW_SHOW = 5;
    public const int SW_RESTORE = 9;

    public static List<WindowInfo> GetAllWindowsStatic()
    {
        var windows = new List<WindowInfo>();
        EnumWindowsProc callback = (hWnd, lParam) =>
        {
            int length = GetWindowTextLength(hWnd);
            if (length > 0)
            {
                StringBuilder sb = new StringBuilder(length + 1);
                GetWindowText(hWnd, sb, sb.Capacity);
                string title = sb.ToString();

                if (!string.IsNullOrWhiteSpace(title))
                {
                    RECT rect;
                    GetWindowRect(hWnd, out rect);

                    windows.Add(new WindowInfo
                    {
                        Handle = hWnd,
                        Title = title,
                        IsVisible = IsWindowVisible(hWnd),
                        IsMinimized = IsIconic(hWnd),
                        X = rect.left,
                        Y = rect.top
                    });
                }
            }
            return true;
        };

        EnumWindows(callback, IntPtr.Zero);
        return windows;
    }
}

public class WindowInfo
{
    public IntPtr Handle { get; set; }
    public string Title { get; set; }
    public bool IsVisible { get; set; }
    public bool IsMinimized { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
}
"@
}

function Get-TabItems
{
    $allWindows = [WinEnum]::GetAllWindowsStatic()
    $results = [System.Collections.Generic.List[object]]::new()

    # System window patterns to exclude (case-insensitive)
    $systemPatterns = [regex]::new('^(System tray overflow window\.|MediaPlayer SMTC window.*|Realtek Audio Console|WingetMessageOnlyWindow|RemoteApp|PopupHost|Task Switching|Default IME|MSCTFIME UI|CiceroUIWndFrame|GDI\+ Window|DesktopWindowXamlSource|Hidden Window|MessageWindow|DDE Server Window|BroadcastListenerWindow|SystemResourceNotifyWindow|MediaContextNotificationWindow|NvContainerWindowClass|DWM Notification|Program Manager|WISPTIS|Windows Input Experience|Input.*|MS_WebcheckMonitor|BluetoothNotificationAreaIconWindowClass|MiracastConnectionWindow|Quick Settings|Settings|Start|Search|New notification|Battery|Menu|Shell.*|Task Host|OmApSvcBroker|Windows.*Experience|NvSvc|UxdService|RealtekAudioBackgroundProcessClass|SecurityHealthSystray|QTrayIconMessageWindow|GlobalHiddenWindow|Windows Push Notifications|Discord Overlay Input Trap|_q_titlebar$|\.NET-BroadcastEventWindow|Progress|Firefox Media Keys|WinEventWindow|EXPLORER)', 'IgnoreCase')
    # Ignored windows list
    $ignoredPatterns = [regex]::new('(Untitled|CrossDeviceResumeWindow|Windows Default Lock Screen|\.ahk - AutoHotkey|^yasb$|^YasbBar$|Buttery Taskbar)', 'IgnoreCase')

    # $systemPatterns = [regex]::new('^(Default IME|MSCTFIME UI|CiceroUIWndFrame|GDI\+ Window|DesktopWindowXamlSource|Hidden Window|MessageWindow|DDE Server Window|BroadcastListenerWindow|SystemResourceNotifyWindow|MediaContextNotificationWindow|NvContainerWindowClass|DWM Notification|Program Manager|WISPTIS|Windows Input Experience|Input.*|MS_WebcheckMonitor|BluetoothNotificationAreaIconWindowClass|MiracastConnectionWindow|Quick Settings|Start|Search|New notification|Battery|Menu|Shell.*|Task Host|OmApSvcBroker|Windows.*Experience|NvSvc|UxdService|RealtekAudioBackgroundProcessClass|SecurityHealthSystray|QTrayIconMessageWindow|GlobalHiddenWindow|Windows Push Notifications|Discord Overlay Input Trap|_q_titlebar$|\.NET-BroadcastEventWindow|Progress|Firefox Media Keys|WinEventWindow|EXPLORER)', 'IgnoreCase')
    # $ignoredPatterns = [regex]::new('(^yasb$|^YasbBar$|\.ahk - AutoHotkey|Buttery Taskbar|CrossDeviceResume|Untitled|Windows Default Lock Screen)', 'IgnoreCase')

    $index = 1
    foreach ($window in $allWindows)
    {
        # Skip system windows
        if ($systemPatterns.IsMatch($window.Title)) { continue }

        # Skip ignored windows
        if ($ignoredPatterns.IsMatch($window.Title)) { continue }

        $statusParts = [System.Collections.Generic.List[string]]::new()
        if ($window.IsMinimized) { $statusParts.Add('󰲏') }
        if (-not $window.IsVisible) { $statusParts.Add('󰈉') }
        
        $statusStr = if ($statusParts.Count -gt 0) { " [$($statusParts -join ' | ')]" } else { '' }
        $itemId = '{0:D4}' -f $index
        
        $results.Add([PSCustomObject]@{
            ItemId          = $itemId
            Label           = "$($window.Title)$statusStr | [$itemId]"
            WindowHandle    = $window.Handle
            IsHidden        = (-not $window.IsVisible) -or $window.IsMinimized
            IsMinimized     = $window.IsMinimized
            IsVisible       = $window.IsVisible
            Title           = $window.Title
        })
        $index++
    }

    return $results
}

function Hide-SelectedWindow
{
    param(
        [Parameter(Mandatory)]$WindowTitle,
        [Parameter(Mandatory)]$AllItems
    )

    # Find the window by title
    $window = $AllItems | Where-Object { $_.Title -eq $WindowTitle } | Select-Object -First 1
    
    if (-not $window)
    {
        Write-Warning "Window '$WindowTitle' not found."
        return $false
    }

    try
    {
        # Hide window using WinAPI
        Write-Host "Hiding unmanaged window: $($window.Title)"
        [WinEnum]::ShowWindow($window.WindowHandle, [WinEnum]::SW_HIDE) | Out-Null

        Write-Host "Window hidden successfully." -ForegroundColor Green
        return $true
    } catch
    {
        Write-Warning "Failed to hide window: $($_.Exception.Message)"
        return $false
    }
}

function Show-HiddenWindow
{
    param(
        [IntPtr]$WindowHandle
    )

    try
    {
        # Show the window
        [WinEnum]::ShowWindow($WindowHandle, [WinEnum]::SW_RESTORE) | Out-Null
        
        # Small delay to allow window to restore
        Start-Sleep -Milliseconds 100
        
        # Set it to foreground
        [WinEnum]::SetForegroundWindow($WindowHandle) | Out-Null
    } catch
    {
        Write-Warning "Failed to show window: $($_.Exception.Message)"
    }
}

$items = Get-TabItems

# SSH warning
if ($IsRemoteSession)
{
    Write-Warning "SSH session detected: Window enumeration returns windows from the remote machine, not your local workstation. This script does not work correctly over SSH."
}

if ($items.Count -eq 0)
{
    Write-Warning 'No windows were found.'
    return
}

if ($List)
{
    Write-Host "=== Windows ===" -ForegroundColor Green
    $items |
        Select-Object Title, IsHidden, IsMinimized, IsVisible |
        Format-Table -AutoSize
    return
}

# Handle -Hide parameter
if (-not [string]::IsNullOrWhiteSpace($Hide))
{
    Hide-SelectedWindow -WindowTitle $Hide -AllItems $items
    return
}

# Determine default action based on flag
$defaultAction = if ($HideMode)
{ '2' 
} else
{ '1' 
}
$actionLabel = if ($HideMode)
{ 'Hide' 
} else
{ 'Focus' 
}

$selection = & $WlinesWrapper -InputContent ($items.Label -join "`n") -p "Select Window ($actionLabel Mode)"
if ([string]::IsNullOrWhiteSpace($selection))
{
    return
}

$selectionId = ''
if ($selection -match '\[(\d{4})\]\s*$')
{
    $selectionId = $Matches[1]
}

if ([string]::IsNullOrWhiteSpace($selectionId))
{
    Write-Warning 'The selected window item could not be identified.'
    return
}

$selectedItem = $items | Where-Object { $_.ItemId -eq $selectionId } | Select-Object -First 1
if ($null -eq $selectedItem)
{
    Write-Warning 'The selected window item no longer exists.'
    return
}

try
{
    if ($defaultAction -eq '2')
    {
        # Hide action
        if ($selectedItem.Title -in @('Wlines Glaze Tab', 'Wlines Start Menu'))
        {
            Write-Warning "Cannot hide: This is a protected window."
            return
        }
        
        if ($IsRemoteSession)
        {
            $cmd = "[WinEnum]::ShowWindow([IntPtr]::Zero, [WinEnum]::SW_HIDE)"
            & (Join-Path $PSScriptRoot '..\..\pwsh-msg.ps1') -Command $cmd -Name "Windows Tabs"
        } else
        {
            Hide-SelectedWindow -WindowTitle $selectedItem.Title -AllItems $items
        }
    } else
    {
        # Unmanaged window - use WinAPI to handle it
        if ($IsRemoteSession)
        {
            $cmd = "[WinEnum]::SetForegroundWindow([IntPtr]::Zero)"
            & (Join-Path $PSScriptRoot '..\..\pwsh-msg.ps1') -Command $cmd -Name "Windows Tabs"
        } else
        {
            if ($selectedItem.IsHidden)
            {
                Show-HiddenWindow -WindowHandle $selectedItem.WindowHandle
            } else
            {
                [WinEnum]::SetForegroundWindow($selectedItem.WindowHandle) | Out-Null
            }
        }
    }
} catch
{
    Write-Warning $_.Exception.Message
}

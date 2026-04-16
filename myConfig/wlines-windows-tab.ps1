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
    wlines-windows-tab.ps1 [OPTIONS]

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
    .\wlines-windows-tab.ps1

    # Interactive mode - Hide selected window
    .\wlines-windows-tab.ps1 -HideMode

    # List all windows
    .\wlines-windows-tab.ps1 -List

    # Hide a window directly
    .\wlines-windows-tab.ps1 -Hide "Discord"
"@
    return
}

$WlinesWrapper = if ($fzf)
{
    Join-Path $PSScriptRoot 'wlines-fzf.ps1'
} else
{
    Join-Path $PSScriptRoot 'wlines-rofi.ps1'
}

# Auto-detect SSH session
$IsRemoteSession = -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)
if ($IsRemoteSession)
{
    Write-Host "SSH session detected - window management will execute on local machine via pwsh-daemon"
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class WinEnum {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);

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

    public static List<WindowInfo> GetAllWindowsStatic()
    {
        var windows = new List<WindowInfo>();
        EnumWindowsProc callback = (hWnd, lParam) =>
        {
            StringBuilder sb = new StringBuilder(256);
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

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Win32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class FocusHelper {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

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

    // ShowWindow constants
    public const int SW_HIDE = 0;
    public const int SW_SHOWNORMAL = 1;
    public const int SW_SHOW = 5;
    public const int SW_RESTORE = 9;
}
"@

function Get-AllWindows
{
    $allWindows = [WinEnum]::GetAllWindowsStatic()
    
    $results = @()
    foreach ($window in $allWindows)
    {
        $results += [PSCustomObject]@{
            Handle      = $window.Handle
            Title       = $window.Title
            IsVisible   = $window.IsVisible
            IsMinimized = $window.IsMinimized
            IsHidden    = (-not $window.IsVisible) -or $window.IsMinimized
            X           = $window.X
            Y           = $window.Y
        }
    }

    return $results
}

function Get-Windows
{
    $allWindows = Get-AllWindows
    $results = @()

    # System window patterns to exclude (case-insensitive)
    $systemPatterns = @(
        'Default IME', 'MSCTFIME UI', 'CiceroUIWndFrame',
        'GDI\+ Window', 'DesktopWindowXamlSource',
        'Hidden Window', 'MessageWindow',
        'DDE Server Window', 'BroadcastListenerWindow',
        'SystemResourceNotifyWindow', 'MediaContextNotificationWindow',
        'NvContainerWindowClass', 'DWM Notification',
        'Program Manager', 'WISPTIS',
        'Windows Input Experience', 'Input.*',
        'MS_WebcheckMonitor', 'BluetoothNotificationAreaIconWindowClass',
        'MiracastConnectionWindow', 'Quick Settings',
        'Start', 'Search', 'New notification', 'Battery',
        'Menu', 'Shell.*', 'Task Host', 'OmApSvcBroker',
        'Windows.*Experience', 'NvSvc', 'UxdService', 'RealtekAudioBackgroundProcessClass',
        'SecurityHealthSystray', 'QTrayIconMessageWindow', 'GlobalHiddenWindow',
        'Windows Push Notifications', 'Discord Overlay Input Trap',
        '^_q_titlebar$', '\.NET-BroadcastEventWindow', 'Progress',
        'Firefox Media Keys', 'WinEventWindow', 'EXPLORER'
    )

    # Ignored windows list
    $ignoredPatterns = @(
        '^yasb$', '^YasbBar$',
        '\.ahk - AutoHotkey',
        'Buttery Taskbar',
        'CrossDeviceResume',
        'Untitled',
        'Windows Default Lock Screen'
    )

    foreach ($window in $allWindows)
    {
        # Skip if already managed by Glaze
        if ($window.Title -in $glazeTitles)
        {
            continue
        }

        # Skip system windows
        $isSystemWindow = $false
        foreach ($pattern in $systemPatterns)
        {
            if ($window.Title -match "^$pattern")
            {
                $isSystemWindow = $true
                break
            }
        }

        if ($isSystemWindow)
        {
            continue
        }

        # Skip ignored windows
        $isIgnored = $false
        foreach ($pattern in $ignoredPatterns)
        {
            if ($window.Title -match $pattern)
            {
                $isIgnored = $true
                break
            }
        }

        if ($isIgnored)
        {
            continue
        }

        $statusParts = @()
        if ($window.IsMinimized)
        { $statusParts += 'MINIMIZED' 
        }
        if (-not $window.IsVisible)
        { $statusParts += 'HIDDEN' 
        }
        $statusStr = if ($statusParts.Count -gt 0)
        { " [$($statusParts -join ' | ')]" 
        } else
        { '' 
        }

        $results += [PSCustomObject]@{
            ItemId          = ''
            Label           = "$($window.Title)$statusStr"
            WindowHandle    = $window.Handle
            IsHidden        = (-not $window.IsVisible) -or $window.IsMinimized
            IsMinimized     = $window.IsMinimized
            IsVisible       = $window.IsVisible
            Title           = $window.Title
        }
    }

    return $results
}

function Resolve-WorkspaceForWindow
{
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)]$Workspaces,
        [Parameter(Mandatory)]$Windows
    )

    $workspaceMap = @{}
    foreach ($ws in $Workspaces)
    {
        $workspaceMap[$ws.id] = $ws
    }

    $windowMap = @{}
    foreach ($w in $Windows)
    {
        $windowMap[$w.id] = $w
    }

    $currentParentId = $Window.parentId

    while ($true)
    {
        if ($workspaceMap.ContainsKey($currentParentId))
        {
            return $workspaceMap[$currentParentId]
        }

        if (-not $windowMap.ContainsKey($currentParentId))
        {
            return $null
        }

        $currentParentId = $windowMap[$currentParentId].parentId
    }
}

function Get-WorkspaceForUnmanagedWindow
{
    param(
        [Parameter(Mandatory)]$WindowPosition,
        [Parameter(Mandatory)]$Workspaces
    )

    # Simple heuristic: return the first workspace (GlazeWM typically manages workspaces per monitor)
    # In most cases, returning the first displayed workspace is a good default
    if ($Workspaces.Count -gt 0)
    {
        $displayedWorkspace = $Workspaces | Where-Object { $_.isDisplayed } | Select-Object -First 1
        if ($displayedWorkspace)
        {
            return $displayedWorkspace
        }
        return $Workspaces[0]
    }

    return $null
}

function Get-TabItems
{
    $items = Get-Windows -GlazeWindows $state.Windows -GlazeWorkspaces $state.Workspaces
    # Add item IDs for unmanaged windows
    for ($index = 0; $index -lt $items.Count; $index++)
    {
        $itemId = '{0:D4}' -f ($index + 1)
        $items[$index].ItemId = $itemId
        $items[$index].Label = "$($items[$index].Label) | [${itemId}]"
    }

    return $items
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
        [FocusHelper]::ShowWindow($window.WindowHandle, [FocusHelper]::SW_HIDE) | Out-Null

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
        [FocusHelper]::ShowWindow($WindowHandle, [FocusHelper]::SW_RESTORE) | Out-Null
        
        # Small delay to allow window to restore
        Start-Sleep -Milliseconds 100
        
        # Set it to foreground
        [FocusHelper]::SetForegroundWindow($WindowHandle) | Out-Null
    } catch
    {
        Write-Warning "Failed to show window: $($_.Exception.Message)"
    }
}

$items = @(Get-TabItems)

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
            $cmd = "[FocusHelper]::ShowWindow([IntPtr]::Zero, [FocusHelper]::SW_HIDE)"
            & (Join-Path $PSScriptRoot 'pwsh-msg.ps1') -Command $cmd -Name "Windows Tabs"
        } else
        {
            Hide-SelectedWindow -WindowTitle $selectedItem.Title -AllItems $items
        }
    } else
    {
        # Unmanaged window - use WinAPI to handle it
        if ($IsRemoteSession)
        {
            $cmd = "[Win32]::SetForegroundWindow([IntPtr]::Zero)"
            & (Join-Path $PSScriptRoot 'pwsh-msg.ps1') -Command $cmd -Name "Windows Tabs"
        } else
        {
            if ($selectedItem.IsHidden)
            {
                Show-HiddenWindow -WindowHandle $selectedItem.WindowHandle
            } else
            {
                [Win32]::SetForegroundWindow($selectedItem.WindowHandle) | Out-Null
            }
        }
    }
} catch
{
    Write-Warning $_.Exception.Message
}

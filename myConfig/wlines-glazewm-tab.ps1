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
Wlines Glaze Tab - Window manager integration for GlazeWM

USAGE:
    wlines-glazewm-tab.ps1 [OPTIONS]

OPTIONS:
    -List           List all available windows (managed and unmanaged)
    -Hide <title>   Hide a window by title (removes from GlazeWM if managed)
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
    .\wlines-glazewm-tab.ps1

    # Interactive mode - Hide selected window
    .\wlines-glazewm-tab.ps1 -HideMode

    # List all windows
    .\wlines-glazewm-tab.ps1 -List

    # Hide a window directly
    .\wlines-glazewm-tab.ps1 -Hide "Discord"

SAFETY FEATURES:
    - Cannot hide the Wlines Glaze Tab script itself
    - Cannot hide the Wlines Start Menu
    - Managed windows are properly closed via GlazeWM
    - Unmanaged windows are hidden using Windows APIs
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
    Write-Host "SSH session detected - GlazeWM management will execute on local machine via pwsh-daemon"
}

function Get-SSHSourceName
{
    # Extract SSH connection source and format it
    if ($env:SSH_CONNECTION)
    {
        # Format: "client_ip client_port server_ip server_port"
        $parts = $env:SSH_CONNECTION -split ' '
        if ($parts.Count -ge 1)
        {
            return "ssh:$($parts[0])"
        }
    } elseif ($env:SSH_CLIENT)
    {
        # Format: "client_ip client_port"
        $parts = $env:SSH_CLIENT -split ' '
        if ($parts.Count -ge 1)
        {
            return "ssh:$($parts[0])"
        }
    }
    return $null
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

function Get-UnmanagedWindows
{
    param($GlazeWindows, $GlazeWorkspaces)

    $glazeTitles = $GlazeWindows | ForEach-Object { $_.title }
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
        'Untitled',
        'CrossDeviceResumeWindow',
        'Windows Default Lock Screen',
        '\.ahk - AutoHotkey',
        '^yasb$', '^YasbBar$',
        'Buttery Taskbar'
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
            Label           = "Unmanaged | $($window.Title)$statusStr"
            WindowHandle    = $window.Handle
            Managed         = $false
            IsHidden        = (-not $window.IsVisible) -or $window.IsMinimized
            IsMinimized     = $window.IsMinimized
            IsVisible       = $window.IsVisible
            Title           = $window.Title
            Workspaces     = $GlazeWorkspaces
        }
    }

    return $results
}

function Get-GlazeState
{
    $workspaceResponse = glazewm query workspaces | ConvertFrom-Json
    $windowResponse = glazewm query windows | ConvertFrom-Json

    if (-not $workspaceResponse.success)
    {
        throw 'Failed to query GlazeWM workspaces.'
    }

    if (-not $windowResponse.success)
    {
        throw 'Failed to query GlazeWM windows.'
    }

    return [PSCustomObject]@{
        Workspaces = @($workspaceResponse.data.workspaces)
        Windows    = @($windowResponse.data.windows)
    }
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
    $state = Get-GlazeState
    $workspaceMap = @{}
    foreach ($workspace in $state.Workspaces)
    {
        $workspaceMap[$workspace.id] = $workspace
    }

    $items = foreach ($window in $state.Windows)
    {
        $workspace = Resolve-WorkspaceForWindow `
            -Window $window `
            -Workspaces $state.Workspaces `
            -Windows $state.Windows

        if ($null -eq $workspace)
        {
            continue
        }
        $workspaceLabel = if ([string]::IsNullOrWhiteSpace($workspace.displayName))
        {
            $workspace.name
        } else
        {
            $workspace.displayName
        }

        $parts = @($window.processName)
        if (-not [string]::IsNullOrWhiteSpace($window.title))
        {
            $parts += $window.title
        }
        $parts += "Workspace $workspaceLabel"

        if (-not $workspace.isDisplayed)
        {
            $parts += 'Hidden Workspace'
        }

        if ($window.hasFocus)
        {
            $parts += 'Focused'
        }

        if ($window.state.type -eq 'minimized')
        {
            $parts += 'Minimized'
        }

        [PSCustomObject]@{
            ItemId          = ''
            Label           = ($parts -join ' | ')
            WindowId        = $window.id
            Title           = $window.title
            ProcessName     = $window.processName
            WorkspaceId     = $workspace.id
            WorkspaceName   = $workspace.name
            WorkspaceLabel  = $workspaceLabel
            WorkspaceShown  = [bool]$workspace.isDisplayed
            WindowFocused   = [bool]$window.hasFocus
            WindowMinimized = ($window.state.type -eq 'minimized')
            Managed         = $true
            WindowHandle    = $null
            IsHidden        = $false
        }
    }

    $items = @($items | Sort-Object ProcessName, Title, WorkspaceName)
    for ($index = 0; $index -lt $items.Count; $index++)
    {
        $itemId = '{0:D4}' -f ($index + 1)
        $items[$index].ItemId = $itemId
        $items[$index].Label = "$($items[$index].Label) | [${itemId}]"
    }

    # Add unmanaged windows (including hidden ones)
    $unmanaged = Get-UnmanagedWindows -GlazeWindows $state.Windows -GlazeWorkspaces $state.Workspaces
    $items += $unmanaged

    # Add item IDs for unmanaged windows
    $managedCount = ($items | Where-Object { $_.Managed }).Count
    $unmanagedItems = $items | Where-Object { -not $_.Managed }
    for ($index = 0; $index -lt $unmanagedItems.Count; $index++)
    {
        $itemId = '{0:D4}' -f ($managedCount + $index + 1)
        $unmanagedItems[$index].ItemId = $itemId
        $unmanagedItems[$index].Label = "$($unmanagedItems[$index].Label) | [${itemId}]"
    }

    return $items
}

function Hide-SelectedWindow
{
    param(
        [Parameter(Mandatory)]$WindowTitle,
        [Parameter(Mandatory)]$AllItems,
        [Parameter(Mandatory)]$State
    )

    # Safety check: don't hide ourselves
    $selfTitles = @('Wlines Glaze Tab', 'Wlines Start Menu')
    foreach ($selfTitle in $selfTitles)
    {
        if ($WindowTitle -eq $selfTitle)
        {
            Write-Warning "Cannot hide: This is the current script window."
            return $false
        }
    }

    # Find the window by title
    $window = $AllItems | Where-Object { $_.Title -eq $WindowTitle } | Select-Object -First 1
    
    if (-not $window)
    {
        Write-Warning "Window '$WindowTitle' not found."
        return $false
    }

    try
    {
        if ($window.Managed)
        {
            # For managed windows, focus it then close it via GlazeWM
            Write-Host "Closing managed window from GlazeWM: $($window.Title)"
            glazewm command focus --container-id $window.WindowId | Out-Null
            Start-Sleep -Milliseconds 300
            glazewm command close | Out-Null
            Start-Sleep -Milliseconds 500
        } else
        {
            # Hide unmanaged window using WinAPI
            Write-Host "Hiding unmanaged window: $($window.Title)"
            [FocusHelper]::ShowWindow($window.WindowHandle, [FocusHelper]::SW_HIDE) | Out-Null
        }

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
        [IntPtr]$WindowHandle,
        $Workspaces
    )

    try
    {
        # Determine which workspace the window belongs to and focus it if needed
        if ($Workspaces -and $Workspaces.Count -gt 0)
        {
            $displayedWorkspace = $Workspaces | Where-Object { $_.isDisplayed } | Select-Object -First 1
            if ($displayedWorkspace)
            {
                # Focus the workspace if it's not already displayed
                if (-not $displayedWorkspace.isDisplayed)
                {
                    glazewm command focus --workspace $displayedWorkspace.name | Out-Null
                }
            } else
            {
                # Fallback: focus the first workspace
                glazewm command focus --workspace $Workspaces[0].name | Out-Null
            }
        }

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
    $managedCount = ($items | Where-Object { $_.Managed }).Count
    Write-Warning "SSH session detected: Can only show $managedCount GlazeWM managed windows (unmanaged windows are enumerated from remote machine)."
}

if ($items.Count -eq 0)
{
    Write-Warning 'No windows were found.'
    return
}

if ($List)
{
    $managedItems = $items | Where-Object { $_.Managed }
    $unmanagedItems = $items | Where-Object { -not $_.Managed }
    
    if ($managedItems)
    {
        Write-Host "=== GlazeWM Managed Windows ===" -ForegroundColor Green
        $managedItems |
            Select-Object ProcessName, Title, WorkspaceLabel, WorkspaceShown, WindowFocused, IsHidden |
            Format-Table -AutoSize
    }
    
    if ($unmanagedItems)
    {
        Write-Host "`n=== Unmanaged Windows ===" -ForegroundColor Yellow
        $unmanagedItems |
            Select-Object Title, IsHidden |
            Format-Table -AutoSize
    }
    return
}

# Handle -Hide parameter
if (-not [string]::IsNullOrWhiteSpace($Hide))
{
    $state = Get-GlazeState
    Hide-SelectedWindow -WindowTitle $Hide -AllItems $items -State $state
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
        Hide-SelectedWindow -WindowTitle $selectedItem.Title -AllItems $items -State (Get-GlazeState)
    } else
    {
        # Focus action (default)
        if ($selectedItem.Managed)
        {
            if (-not $selectedItem.WorkspaceShown)
            {
                glazewm command focus --workspace $selectedItem.WorkspaceName | Out-Null
            }

            if ($selectedItem.WindowMinimized)
            {
                glazewm command --id $selectedItem.WindowId toggle-minimized | Out-Null
            }

            glazewm command focus --container-id $selectedItem.WindowId | Out-Null
        } else
        {
            # Unmanaged window - use WinAPI to handle it
            if ($selectedItem.IsHidden)
            {
                Show-HiddenWindow -WindowHandle $selectedItem.WindowHandle -Workspaces $selectedItem.Workspaces
            } else
            {
                # Focus the workspace first, then set window to foreground
                if ($selectedItem.Workspaces -and $selectedItem.Workspaces.Count -gt 0)
                {
                    $displayedWorkspace = $selectedItem.Workspaces | Where-Object { $_.isDisplayed } | Select-Object -First 1
                    if ($displayedWorkspace -and -not $displayedWorkspace.isDisplayed)
                    {
                        glazewm command focus --workspace $displayedWorkspace.name | Out-Null
                    }
                }
                [Win32]::SetForegroundWindow($selectedItem.WindowHandle) | Out-Null
            }
        }
    }
} catch
{
    Write-Warning $_.Exception.Message
}

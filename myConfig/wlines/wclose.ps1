[CmdletBinding()]
param(
    [switch]$List,
    [Alias('f')]
    [switch]$Force,
    [switch]$fzf,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WlinesWrapper = if ($fzf)
{
    Join-Path $PSScriptRoot 'wfzf.ps1'
} else
{
    Join-Path $PSScriptRoot 'wrofi.ps1'
}
$CurrentSessionId = (Get-Process -Id $PID).SessionId
$DisplayLimit = 240
$LogDir = Join-Path $env:LOCALAPPDATA 'wlines'
$LogPath = Join-Path $LogDir 'wclose.log'

# Auto-detect remote session (SSH, etc.)
$IsRemoteSession = -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)
$SkipSessionIdCheck = $IsRemoteSession

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

$ExcludedProcessIds = [System.Collections.Generic.HashSet[int]]::new()
[string[]]$IgnoredProcessNames = @(
    'ApplicationFrameHost',
    'explorer',
    'OmApSvcBroker',
    'RtkUWP',
    'TextInputHost'
)
[string[]]$IgnoredCloseOnlyProcessNames = @(
    'Taskmgr'
)
[void]$ExcludedProcessIds.Add($PID)
$parentProcessId = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty ParentProcessId -ErrorAction SilentlyContinue
if ($parentProcessId -is [int])
{
    [void]$ExcludedProcessIds.Add($parentProcessId)
}
if ($ExtraArgs -contains '--force')
{
    $Force = $true
}

if (-not ('WlinesKill.NativeMethods' -as [type]))
{
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace WlinesKill {
    public static class NativeMethods {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowTextLengthW(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PostMessageW(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    }
}
'@
}

function Write-LauncherLog
{
    param([Parameter(Mandatory)][string]$Message)

    if (-not (Test-Path $LogDir))
    {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $LogPath -Value "[$timestamp] $Message"
}

function Get-ProcessCommandLineMap
{
    param([int[]]$ProcessIds)

    $map = @{}
    if ($null -eq $ProcessIds -or $ProcessIds.Count -eq 0)
    {
        return $map
    }

    $filter = ($ProcessIds | Sort-Object -Unique | ForEach-Object { "ProcessId = $_" }) -join ' OR '
    if ([string]::IsNullOrWhiteSpace($filter))
    {
        return $map
    }

    try
    {
        $processInfos = Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction Stop
        foreach ($processInfo in $processInfos)
        {
            $map[[int]$processInfo.ProcessId] = [string]$processInfo.CommandLine
        }
    } catch
    {
        Write-LauncherLog ("Bulk command line lookup failed: {0}" -f $_.Exception.Message)
    }

    return $map
}

function Format-SearchField
{
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value))
    {
        return ''
    }

    $singleLine = ($Value -replace '\s+', ' ').Trim()
    if ($singleLine.Length -le $DisplayLimit)
    {
        return $singleLine
    }

    return $singleLine.Substring(0, $DisplayLimit) + '...'
}

function Get-VisibleWindowCandidates
{
    $windows = [System.Collections.Generic.List[object]]::new()
    $callback = [WlinesKill.NativeMethods+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [WlinesKill.NativeMethods]::IsWindowVisible($hWnd))
        {
            return $true
        }

        $titleLength = [WlinesKill.NativeMethods]::GetWindowTextLengthW($hWnd)
        if ($titleLength -le 0)
        {
            return $true
        }

        $builder = [System.Text.StringBuilder]::new($titleLength + 1)
        [void][WlinesKill.NativeMethods]::GetWindowTextW($hWnd, $builder, $builder.Capacity)
        $windowTitle = Format-SearchField $builder.ToString()
        if ([string]::IsNullOrWhiteSpace($windowTitle))
        {
            return $true
        }

        [uint32]$processId = 0
        [void][WlinesKill.NativeMethods]::GetWindowThreadProcessId($hWnd, [ref]$processId)
        if ($processId -le 0)
        {
            return $true
        }

        $windows.Add([PSCustomObject]@{
                Hwnd        = $hWnd
                HwndHex     = ('0x{0:X}' -f $hWnd.ToInt64())
                ProcessId   = [int]$processId
                WindowTitle = $windowTitle
            })

        return $true
    }

    [void][WlinesKill.NativeMethods]::EnumWindows($callback, [IntPtr]::Zero)
    return @($windows)
}

function Get-ProcessStateLabel
{
    param($Process)

    try
    {
        if ($null -ne $Process.Responding -and -not $Process.Responding)
        {
            return 'Not Responding'
        }
    } catch
    {
        return ''
    }

    return ''
}

function Get-RunningApplicationItems
{
    Write-LauncherLog "Enumerating visible windows for session $CurrentSessionId"
    $processes = @(Get-Process -ErrorAction SilentlyContinue)
    $processMap = @{}
    foreach ($process in $processes)
    {
        try
        {
            $processId = $process.Id
            if (-not $processMap.ContainsKey($processId))
            {
                $processMap[$processId] = $process
            }
        } catch
        {
            Write-LauncherLog ("Skipping process while building map: {0}" -f $_.Exception.Message)
        }
    }

    Write-LauncherLog "Get-Process returned $($processes.Count) processes"
    $visibleWindows = @(Get-VisibleWindowCandidates)
    Write-LauncherLog "EnumWindows returned $($visibleWindows.Count) visible titled windows"

    $candidates = foreach ($window in $visibleWindows)
    {
        try
        {
            $processId = $window.ProcessId
            if ($ExcludedProcessIds.Contains($processId))
            {
                continue
            }

            if (-not $processMap.ContainsKey($processId))
            {
                continue
            }

            $process = $processMap[$processId]
            if (-not $SkipSessionIdCheck -and $process.SessionId -ne $CurrentSessionId)
            {
                continue
            }

            if ($process.ProcessName -in $IgnoredProcessNames)
            {
                continue
            }

            if ((-not $Force) -and $process.ProcessName -in $IgnoredCloseOnlyProcessNames)
            {
                continue
            }

            [PSCustomObject]@{
                Hwnd        = $window.Hwnd
                HwndHex     = $window.HwndHex
                ProcessId   = $processId
                Name        = $process.ProcessName
                State       = Get-ProcessStateLabel $process
                WindowTitle = $window.WindowTitle
            }
        } catch
        {
            Write-LauncherLog ("Skipping window during candidate scan: {0}" -f $_.Exception.Message)
            continue
        }
    }

    $candidates = @($candidates | Sort-Object Name, ProcessId, HwndHex)
    Write-LauncherLog "Visible application candidates: $($candidates.Count)"
    $candidateProcessIds = @()
    if ($candidates.Count -gt 0)
    {
        $candidateProcessIds = @($candidates | Select-Object -ExpandProperty ProcessId -Unique)
    }
    $commandLineMap = Get-ProcessCommandLineMap -ProcessIds $candidateProcessIds

    $items = foreach ($candidate in $candidates)
    {
        try
        {
            $processId = $candidate.ProcessId
            $processName = $candidate.Name
            $processState = $candidate.State
            $windowTitle = $candidate.WindowTitle
            $hwndHex = $candidate.HwndHex
            $commandLine = ''
            if ($commandLineMap.ContainsKey($processId))
            {
                $commandLine = Format-SearchField $commandLineMap[$processId]
            }

            $parts = @($processName)

            if (-not [string]::IsNullOrWhiteSpace($processState))
            {
                $parts += $processState
            }

            if (-not [string]::IsNullOrWhiteSpace($windowTitle))
            {
                $parts += $windowTitle
            }

            if (-not [string]::IsNullOrWhiteSpace($commandLine))
            {
                $parts += $commandLine
            }

            $parts += $hwndHex

            [PSCustomObject]@{
                ItemId      = ''
                Label       = ($parts -join ' | ')
                Hwnd        = $candidate.Hwnd
                HwndHex     = $hwndHex
                ProcessId   = $processId
                Name        = $processName
                State       = $processState
                WindowTitle = $windowTitle
                CommandLine = $commandLine
            }
        } catch
        {
            Write-LauncherLog ("Skipping process due to enumeration failure: {0}" -f $_.Exception.Message)
            continue
        }
    }

    $sortedItems = @($items | Sort-Object Name, ProcessId, HwndHex)
    for ($index = 0; $index -lt $sortedItems.Count; $index++)
    {
        $itemId = '{0:D4}' -f ($index + 1)
        $sortedItems[$index].ItemId = $itemId
        $sortedItems[$index].Label = "$($sortedItems[$index].Label) | [${itemId}]"
    }
    Write-LauncherLog "Collected $($sortedItems.Count) processes for display"
    return $sortedItems
}

function Get-RunningProcessItems
{
    Write-LauncherLog "Enumerating session processes for force mode in session $CurrentSessionId"
    $processes = @(Get-Process -ErrorAction SilentlyContinue)
    Write-LauncherLog "Get-Process returned $($processes.Count) processes for force mode"

    $candidates = foreach ($process in $processes)
    {
        try
        {
            $processId = $process.Id
            if ($ExcludedProcessIds.Contains($processId))
            {
                continue
            }

            if (-not $SkipSessionIdCheck -and $process.SessionId -ne $CurrentSessionId)
            {
                continue
            }

            if ($process.ProcessName -in $IgnoredProcessNames)
            {
                continue
            }

            [PSCustomObject]@{
                ProcessId = $processId
                Name      = $process.ProcessName
                State     = Get-ProcessStateLabel $process
            }
        } catch
        {
            Write-LauncherLog ("Skipping process during force enumeration: {0}" -f $_.Exception.Message)
            continue
        }
    }

    $candidates = @($candidates | Sort-Object Name, ProcessId)
    Write-LauncherLog "Force mode candidates: $($candidates.Count)"

    $candidateProcessIds = @()
    if ($candidates.Count -gt 0)
    {
        $candidateProcessIds = @($candidates | Select-Object -ExpandProperty ProcessId -Unique)
    }
    $commandLineMap = Get-ProcessCommandLineMap -ProcessIds $candidateProcessIds

    $processItems = foreach ($candidate in $candidates)
    {
        try
        {
            $processId = $candidate.ProcessId
            $processName = $candidate.Name
            $processState = $candidate.State
            $commandLine = ''
            if ($commandLineMap.ContainsKey($processId))
            {
                $commandLine = Format-SearchField $commandLineMap[$processId]
            }

            $parts = @($processName)

            if (-not [string]::IsNullOrWhiteSpace($processState))
            {
                $parts += $processState
            }

            if (-not [string]::IsNullOrWhiteSpace($commandLine))
            {
                $parts += $commandLine
            }

            [PSCustomObject]@{
                ItemId      = ''
                Label       = ($parts -join ' | ')
                Hwnd        = [IntPtr]::Zero
                HwndHex     = ''
                ProcessId   = $processId
                Name        = $processName
                State       = $processState
                WindowTitle = ''
                CommandLine = $commandLine
            }
        } catch
        {
            Write-LauncherLog ("Skipping process group due to enumeration failure: {0}" -f $_.Exception.Message)
            continue
        }
    }

    $sortedItems = @($processItems | Sort-Object Name, ProcessId)
    for ($index = 0; $index -lt $sortedItems.Count; $index++)
    {
        $itemId = '{0:D4}' -f ($index + 1)
        $sortedItems[$index].ItemId = $itemId
        $sortedItems[$index].Label = "$($sortedItems[$index].Label) | [${itemId}]"
    }

    Write-LauncherLog "Collected $($sortedItems.Count) visible processes for display"
    return $sortedItems
}

Write-LauncherLog "Starting wclose (force=$Force, remote=$IsRemoteSession)"

# SSH sessions can't enumerate GUI windows, force process mode
if ($IsRemoteSession -and -not $Force)
{
    Write-LauncherLog 'Remote session detected, switching to force mode (process-based)'
    $Force = $true
}

$items = if ($Force)
{ @(Get-RunningProcessItems) 
} else
{ @(Get-RunningApplicationItems) 
}
$itemCount = @($items).Count
if ($itemCount -eq 0)
{
    Write-LauncherLog 'No running applications were found in the current session'
    Write-Warning 'No running applications were found in the current session.'
    return
}

if ($List)
{
    Write-LauncherLog 'List mode requested'
    $items |
        Select-Object ProcessId, HwndHex, Name, WindowTitle, CommandLine |
        Format-Table -AutoSize
    return
}

$pickerInput = $items.Label -join "`n"
Write-LauncherLog "Launching wlines with $itemCount entries"
$prompt = if ($Force)
{ 'Kill process' 
} else
{ 'Close window' 
}
$selection = & $WlinesWrapper -InputContent $pickerInput -p $prompt
Write-LauncherLog "wlines returned: '$selection'"
if ([string]::IsNullOrWhiteSpace($selection))
{
    Write-LauncherLog 'No selection was returned from wlines'
    return
}

$selectionId = ''
if ($selection -match '\[(\d{4})\]\s*$')
{
    $selectionId = $Matches[1]
}
if ([string]::IsNullOrWhiteSpace($selectionId))
{
    Write-LauncherLog "Selection did not contain a valid item ID: '$selection'"
    Write-Warning 'The selected window could not be identified.'
    return
}

$selectedItem = $items | Where-Object { $_.ItemId -eq $selectionId } | Select-Object -First 1
if ($null -eq $selectedItem)
{
    Write-LauncherLog "Selection ID could not be matched to a window: '$selectionId'"
    Write-Warning 'The selected window no longer exists in the current list.'
    return
}

if ($Force)
{
    Write-LauncherLog "Attempting to force kill PID $($selectedItem.ProcessId) ($($selectedItem.Name))"
    try
    {
        Stop-Process -Id $selectedItem.ProcessId -Force -ErrorAction Stop
        Write-LauncherLog "Successfully force killed PID $($selectedItem.ProcessId)"
    } catch
    {
        Write-LauncherLog "Failed to force kill PID $($selectedItem.ProcessId): $($_.Exception.Message)"
        Write-Warning "Failed to force kill PID $($selectedItem.ProcessId)."
        return
    }
} else
{
    Write-LauncherLog "Attempting to close HWND $($selectedItem.HwndHex) for PID $($selectedItem.ProcessId) ($($selectedItem.Name))"
    try
    {
        $WM_CLOSE = 0x0010
        $posted = [WlinesKill.NativeMethods]::PostMessageW($selectedItem.Hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
        if (-not $posted)
        {
            Write-LauncherLog "PostMessageW(WM_CLOSE) failed for $($selectedItem.HwndHex)"
            Write-Warning "Failed to close window $($selectedItem.HwndHex)."
            return
        }
        Write-LauncherLog "Successfully posted WM_CLOSE to $($selectedItem.HwndHex)"
    } catch
    {
        Write-LauncherLog "Failed to close window $($selectedItem.HwndHex): $($_.Exception.Message)"
        Write-Warning "Failed to close window $($selectedItem.HwndHex)."
        return
    }
}

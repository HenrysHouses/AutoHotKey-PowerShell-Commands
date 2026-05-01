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
try {
    $parentProcessId = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Parent.Id
    if ($null -ne $parentProcessId) { [void]$ExcludedProcessIds.Add($parentProcessId) }
} catch {}

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

# Optimized logging (lazy initialization and batching could be better, but just minimizing calls for now)
$EnableLogging = $false # Set to true for debugging
function Write-LauncherLog
{
    param([Parameter(Mandatory)][string]$Message)
    if (-not $EnableLogging) { return }
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $LogPath -Value "[$timestamp] $Message"
}

function Get-ProcessCommandLineMap
{
    param([int[]]$ProcessIds)

    $map = @{}
    if ($null -eq $ProcessIds -or $ProcessIds.Count -eq 0) { return $map }

    $uniqueIds = $ProcessIds | Sort-Object -Unique
    $filter = ($uniqueIds | ForEach-Object { "ProcessId = $_" }) -join ' OR '
    
    try {
        $processInfos = Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction SilentlyContinue
        if ($processInfos) {
            foreach ($processInfo in $processInfos) {
                $map[[int]$processInfo.ProcessId] = [string]$processInfo.CommandLine
            }
        }
    } catch {}

    return $map
}

function Format-SearchField
{
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $singleLine = ($Value -replace '\s+', ' ').Trim()
    if ($singleLine.Length -le $DisplayLimit) { return $singleLine }
    return $singleLine.Substring(0, $DisplayLimit) + '...'
}

function Get-VisibleWindowCandidates
{
    $windows = [System.Collections.Generic.List[object]]::new()
    $callback = [WlinesKill.NativeMethods+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [WlinesKill.NativeMethods]::IsWindowVisible($hWnd)) { return $true }

        $titleLength = [WlinesKill.NativeMethods]::GetWindowTextLengthW($hWnd)
        if ($titleLength -le 0) { return $true }

        $builder = [System.Text.StringBuilder]::new($titleLength + 1)
        [void][WlinesKill.NativeMethods]::GetWindowTextW($hWnd, $builder, $builder.Capacity)
        $windowTitle = $builder.ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($windowTitle)) { return $true }

        [uint32]$processId = 0
        [void][WlinesKill.NativeMethods]::GetWindowThreadProcessId($hWnd, [ref]$processId)
        if ($processId -gt 0) {
            $windows.Add([PSCustomObject]@{
                Hwnd        = $hWnd
                HwndHex     = ('0x{0:X}' -f $hWnd.ToInt64())
                ProcessId   = [int]$processId
                WindowTitle = $windowTitle
            })
        }
        return $true
    }

    [void][WlinesKill.NativeMethods]::EnumWindows($callback, [IntPtr]::Zero)
    return $windows
}

function Get-RunningApplicationItems
{
    $processes = Get-Process | Where-Object { 
        ($SkipSessionIdCheck -or $_.SessionId -eq $CurrentSessionId) -and 
        $_.ProcessName -notin $IgnoredProcessNames -and
        ($Force -or $_.ProcessName -notin $IgnoredCloseOnlyProcessNames) -and
        -not $ExcludedProcessIds.Contains($_.Id)
    }
    
    $processMap = @{}
    foreach ($p in $processes) { $processMap[$p.Id] = $p }

    $visibleWindows = Get-VisibleWindowCandidates
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($window in $visibleWindows) {
        if ($processMap.ContainsKey($window.ProcessId)) {
            $process = $processMap[$window.ProcessId]
            $state = try { if ($process.Responding -eq $false) { 'Not Responding' } else { '' } } catch { '' }
            
            $candidates.Add([PSCustomObject]@{
                Hwnd        = $window.Hwnd
                HwndHex     = $window.HwndHex
                ProcessId   = $window.ProcessId
                Name        = $process.ProcessName
                State       = $state
                WindowTitle = Format-SearchField $window.WindowTitle
            })
        }
    }

    if ($candidates.Count -eq 0) { return @() }

    $candidateProcessIds = $candidates | Select-Object -ExpandProperty ProcessId -Unique
    $commandLineMap = Get-ProcessCommandLineMap -ProcessIds $candidateProcessIds

    $items = [System.Collections.Generic.List[object]]::new()
    $index = 1
    foreach ($candidate in ($candidates | Sort-Object Name, ProcessId, HwndHex)) {
        $cmdLine = if ($commandLineMap.ContainsKey($candidate.ProcessId)) { Format-SearchField $commandLineMap[$candidate.ProcessId] } else { '' }
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add($candidate.Name)
        if ($candidate.State) { $parts.Add($candidate.State) }
        if ($candidate.WindowTitle) { $parts.Add($candidate.WindowTitle) }
        if ($cmdLine) { $parts.Add($cmdLine) }
        $parts.Add($candidate.HwndHex)
        
        $itemId = '{0:D4}' -f $index
        $items.Add([PSCustomObject]@{
            ItemId      = $itemId
            Label       = ($parts -join ' | ') + " | [$itemId]"
            Hwnd        = $candidate.Hwnd
            HwndHex     = $candidate.HwndHex
            ProcessId   = $candidate.ProcessId
            Name        = $candidate.Name
        })
        $index++
    }
    return $items
}

function Get-RunningProcessItems
{
    $processes = Get-Process | Where-Object { 
        ($SkipSessionIdCheck -or $_.SessionId -eq $CurrentSessionId) -and 
        $_.ProcessName -notin $IgnoredProcessNames -and
        -not $ExcludedProcessIds.Contains($_.Id)
    }

    if ($processes.Count -eq 0) { return @() }

    $candidateProcessIds = $processes | Select-Object -ExpandProperty Id -Unique
    $commandLineMap = Get-ProcessCommandLineMap -ProcessIds $candidateProcessIds

    $items = [System.Collections.Generic.List[object]]::new()
    $index = 1
    foreach ($process in ($processes | Sort-Object ProcessName, Id)) {
        $state = try { if ($process.Responding -eq $false) { 'Not Responding' } else { '' } } catch { '' }
        $cmdLine = if ($commandLineMap.ContainsKey($process.Id)) { Format-SearchField $commandLineMap[$process.Id] } else { '' }
        
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add($process.ProcessName)
        if ($state) { $parts.Add($state) }
        if ($cmdLine) { $parts.Add($cmdLine) }
        
        $itemId = '{0:D4}' -f $index
        $items.Add([PSCustomObject]@{
            ItemId      = $itemId
            Label       = ($parts -join ' | ') + " | [$itemId]"
            Hwnd        = [IntPtr]::Zero
            HwndHex     = ''
            ProcessId   = $process.Id
            Name        = $process.ProcessName
        })
        $index++
    }
    return $items
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

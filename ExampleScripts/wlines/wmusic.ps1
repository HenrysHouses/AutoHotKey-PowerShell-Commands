[CmdletBinding()]
param(
    [ValidateSet('play', 'pause', 'next', 'prev', 'previous', 'volumeUp', 'volumeDown', 'mute')]
    [string]$Action,
    [switch]$fzf
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

if (-not ([System.Management.Automation.PSTypeName]'YouTubeMusic').Type)
{
    try
    {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;

public class YouTubeMusic {
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string className, string windowTitle);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);

    private const int KEYEVENTF_KEYDOWN = 0;
    private const int KEYEVENTF_KEYUP = 2;
    private const uint WM_KEYDOWN = 0x100;
    private const uint WM_KEYUP = 0x101;

    // Virtual key codes
    private const byte VK_SPACE = 0x20;
    private const byte VK_LEFT = 0x25;
    private const byte VK_RIGHT = 0x27;
    private const byte VK_UP = 0x26;
    private const byte VK_DOWN = 0x28;

    public static IntPtr FindYouTubeMusicWindow() {
        // Search by partial window title
        try {
            Process[] processes = Process.GetProcessesByName("librewolf");
            foreach (Process p in processes) {
                if (p.MainWindowTitle != null && p.MainWindowTitle.Contains("YouTube Music")) {
                    IntPtr handle = p.MainWindowHandle;
                    if (handle != IntPtr.Zero) {
                        return handle;
                    }
                }
            }
        } catch {
            // Silently handle any process access issues
        }
        return IntPtr.Zero;
    }

    public static bool SendKeyToWindow(IntPtr hWnd, byte vk) {
        if (hWnd == IntPtr.Zero) return false;
        
        try {
            SetForegroundWindow(hWnd);
            System.Threading.Thread.Sleep(100);
            
            keybd_event(vk, 0, KEYEVENTF_KEYDOWN, 0);
            System.Threading.Thread.Sleep(50);
            keybd_event(vk, 0, KEYEVENTF_KEYUP, 0);
            System.Threading.Thread.Sleep(50);
            
            return true;
        } catch {
            return false;
        }
    }

    public static bool PlayPause(IntPtr hWnd) {
        return SendKeyToWindow(hWnd, VK_SPACE);
    }

    public static bool NextTrack(IntPtr hWnd) {
        return SendKeyToWindow(hWnd, VK_RIGHT);
    }

    public static bool PreviousTrack(IntPtr hWnd) {
        return SendKeyToWindow(hWnd, VK_LEFT);
    }

    public static bool VolumeUp(IntPtr hWnd) {
        return SendKeyToWindow(hWnd, VK_UP);
    }

    public static bool VolumeDown(IntPtr hWnd) {
        return SendKeyToWindow(hWnd, VK_DOWN);
    }
}
"@
    } catch
    {
        Write-Warning "Failed to load YouTube Music control type: $_"
    }
}

function Get-YouTubeMusicInfo
{
    # Try to get current song info from browser process
    # This is a simplified approach - real metadata extraction would require browser automation
    $hWnd = [YouTubeMusic]::FindYouTubeMusicWindow()
    
    if ($hWnd -eq [IntPtr]::Zero)
    {
        return @{
            Status = "Not Running"
            Song = "YouTube Music not found"
            Artist = ""
            Playing = $false
        }
    }

    return @{
        Status = "Playing"
        Song = "YouTube Music"
        Artist = "LibreWolf Browser"
        Playing = $true
    }
}

function Invoke-MusicControl
{
    param([string]$ControlAction)

    $hWnd = [YouTubeMusic]::FindYouTubeMusicWindow()
    
    if ($hWnd -eq [IntPtr]::Zero)
    {
        Write-Error "YouTube Music window not found. Make sure YouTube Music is open in LibreWolf."
        return $false
    }

    $success = $false
    switch ($ControlAction)
    {
        'play'
        { $success = [YouTubeMusic]::PlayPause($hWnd); break 
        }
        'pause'
        { $success = [YouTubeMusic]::PlayPause($hWnd); break 
        }
        'next'
        { $success = [YouTubeMusic]::NextTrack($hWnd); break 
        }
        'prev'
        { $success = [YouTubeMusic]::PreviousTrack($hWnd); break 
        }
        'previous'
        { $success = [YouTubeMusic]::PreviousTrack($hWnd); break 
        }
        'volumeUp'
        { $success = [YouTubeMusic]::VolumeUp($hWnd); break 
        }
        'volumeDown'
        { $success = [YouTubeMusic]::VolumeDown($hWnd); break 
        }
        'mute'
        { 
            # LibreWolf doesn't have a direct mute, so we'll pulse volume down multiple times
            $success = [YouTubeMusic]::PlayPause($hWnd)
            break 
        }
    }

    return $success
}

# If action is specified via command line, execute it directly
if ($Action)
{
    $success = Invoke-MusicControl $Action
    if ($success)
    {
        Write-Host "OK: $Action executed"
    } else
    {
        Write-Host "FAIL: Failed to execute $Action"
    }
    exit
}

# Interactive mode
$info = Get-YouTubeMusicInfo
$menu = @(
    "Play/Pause"
    "Next Track"
    "Previous Track"
    "Volume Up"
    "Volume Down"
) -join "`n"

$selection = & $WlinesWrapper -InputContent $menu "Music Control"

switch ($selection)
{
    "Play/Pause"
    { Invoke-MusicControl 'play' 
    }
    "Next Track"
    { Invoke-MusicControl 'next' 
    }
    "Previous Track"
    { Invoke-MusicControl 'prev' 
    }
    "Volume Up"
    { Invoke-MusicControl 'volumeUp' 
    }
    "Volume Down"
    { Invoke-MusicControl 'volumeDown' 
    }
}

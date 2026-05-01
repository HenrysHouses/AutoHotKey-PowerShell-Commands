[CmdletBinding()]
param(
    [ValidateSet('play', 'pause', 'next', 'prev', 'previous', 'volumeUp', 'volumeDown', 'mute', 'toggle')]
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

# Load WinRT types for SMTC
if (-not ([System.Management.Automation.PSTypeName]'Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager').Type)
{
    try
    {
        [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
        [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSession, Windows.Media.Control, ContentType=WindowsRuntime]
    } catch
    {
        Write-Warning "Failed to load SMTC types. This script requires Windows 10 1809 or later."
    }
}

# Load Global Volume Control via user32.dll
if (-not ([System.Management.Automation.PSTypeName]'GlobalVolume').Type)
{
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class GlobalVolume {
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);

    private const byte VK_VOLUME_MUTE = 0xAD;
    private const byte VK_VOLUME_DOWN = 0xAE;
    private const byte VK_VOLUME_UP = 0xAF;
    private const int KEYEVENTF_KEYDOWN = 0;
    private const int KEYEVENTF_KEYUP = 2;

    public static void VolumeUp() {
        keybd_event(VK_VOLUME_UP, 0, KEYEVENTF_KEYDOWN, 0);
        keybd_event(VK_VOLUME_UP, 0, KEYEVENTF_KEYUP, 0);
    }

    public static void VolumeDown() {
        keybd_event(VK_VOLUME_DOWN, 0, KEYEVENTF_KEYDOWN, 0);
        keybd_event(VK_VOLUME_DOWN, 0, KEYEVENTF_KEYUP, 0);
    }

    public static void Mute() {
        keybd_event(VK_VOLUME_MUTE, 0, KEYEVENTF_KEYDOWN, 0);
        keybd_event(VK_VOLUME_MUTE, 0, KEYEVENTF_KEYUP, 0);
    }
}
"@
    } catch {
        Write-Warning "Failed to load GlobalVolume type: $_"
    }
}

function Wait-WinRT
{
    param($AsyncOp)
    if ($null -eq $AsyncOp) { return $null }

    $timeout = 20 # 2 seconds max
    while ($timeout -gt 0)
    {
        try {
            $status = $AsyncOp.Status
            if ($status -eq 1 -or $status -eq 'Completed')
            {
                return $AsyncOp.GetResults()
            }
            if ($status -eq 2 -or $status -eq 3 -or $status -eq 'Canceled' -or $status -eq 'Error')
            {
                return $null
            }
        } catch {
            # Fallback for objects that don't expose Status property well
            try { return $AsyncOp.GetResults() } catch {}
        }
        Start-Sleep -Milliseconds 100
        $timeout--
    }
    try { return $AsyncOp.GetResults() } catch { return $null }
}

function Get-SmtcSession
{
    try {
        $asyncOp = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
        $manager = Wait-WinRT $asyncOp
        if ($null -eq $manager) { return $null }
        return $manager.GetCurrentSession()
    } catch {
        return $null
    }
}

function Get-MediaInfo
{
    $session = Get-SmtcSession
    
    if ($null -eq $session)
    {
        return @{
            Status = "Not Running"
            Song = "No active media"
            Artist = ""
            Playing = $false
        }
    }

    $propsAsync = $session.TryGetMediaPropertiesAsync()
    $props = Wait-WinRT $propsAsync
    $playback = $session.GetPlaybackInfo()
    
    return @{
        Status = if ($playback) { $playback.PlaybackStatus.ToString() } else { "Unknown" }
        Song = if ($props -and $props.Title) { $props.Title } else { "Unknown Track" }
        Artist = if ($props -and $props.Artist) { $props.Artist } else { "Unknown Artist" }
        Playing = if ($playback) { $playback.PlaybackStatus -eq 4 } else { $false }
        App = $session.SourceAppUserModelId
    }
}

function Invoke-MusicControl
{
    param([string]$ControlAction)

    if ($ControlAction -match 'volume|mute')
    {
        switch ($ControlAction)
        {
            'volumeUp'   { [GlobalVolume]::VolumeUp(); return $true }
            'volumeDown' { [GlobalVolume]::VolumeDown(); return $true }
            'mute'       { [GlobalVolume]::Mute(); return $true }
        }
    }

    $session = Get-SmtcSession
    if ($null -eq $session)
    {
        Write-Error "No active SMTC media session found."
        return $false
    }

    $async = $null
    switch ($ControlAction)
    {
        'play'      { $async = $session.TryPlayAsync() }
        'pause'     { $async = $session.TryPauseAsync() }
        'toggle'    { $async = $session.TryTogglePlayPauseAsync() }
        'next'      { $async = $session.TrySkipNextAsync() }
        'prev'      { $async = $session.TrySkipPreviousAsync() }
        'previous'  { $async = $session.TrySkipPreviousAsync() }
    }

    if ($async)
    {
        $null = Wait-WinRT $async
        return $true
    }

    return $false
}

# CLI Mode
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

# Interactive Mode
$info = Get-MediaInfo
$displayStatus = if ($info.Playing) { "Playing" } else { "Paused" }
$header = if ($info.Status -eq "Not Running") { "Music Control (No Session)" } else { "Music: $($info.Song) - $($info.Artist) [$displayStatus]" }

$menu = @(
    "Play/Pause"
    "Next Track"
    "Previous Track"
    "Volume Up"
    "Volume Down"
    "Mute"
) -join "`n"

$selection = & $WlinesWrapper -InputContent $menu -p $header

switch ($selection)
{
    "Play/Pause"     { Invoke-MusicControl 'toggle' }
    "Next Track"     { Invoke-MusicControl 'next' }
    "Previous Track" { Invoke-MusicControl 'prev' }
    "Volume Up"      { Invoke-MusicControl 'volumeUp' }
    "Volume Down"    { Invoke-MusicControl 'volumeDown' }
    "Mute"           { Invoke-MusicControl 'mute' }
}

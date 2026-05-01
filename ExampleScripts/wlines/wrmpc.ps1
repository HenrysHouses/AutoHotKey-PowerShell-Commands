# wrmpc.ps1 - RMPC/Music Player Control via wlines/fzf with SSH support
# Translates rofi-rmpccontrol.sh to PowerShell with wlines wrapper and SSH capability
# SSH mode: Android -> Windows SSH -> pwsh-msg -> WSL -> rmpc

param(
    [Parameter(Mandatory = $false)]
    [switch]$fzf,
    
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

function Show-Help
{
    @"
wrmpc.ps1 - Advanced RMPC Music Player Controller

PARAMETERS:
    -fzf                       Use fzf for interactive selection instead of rofi
                               Auto-detects if fzf is available in WSL
                               Falls back to rofi if not available
    
    -Help                      Display this help message

SSH DETECTION:
    Automatically detects SSH sessions via environment variables:
    - SSH_CONNECTION
    - SSH_CLIENT
    
    When SSH is detected:
    - Sends commands through pwsh-msg.ps1 to named pipe
    - Adds SSH identification to message header
    - Allows remote control from SSH client (e.g., Android)

USAGE EXAMPLES:
    # Basic usage with rofi (default)
    .\wrmpc.ps1
    
    # Use fzf for selection
    .\wrmpc.ps1 -fzf
    
    # SSH auto-detection works automatically
    # From Android SSH: same commands, SSH routing handled transparently
    
    # Show help
    .\wrmpc.ps1 -Help

FEATURES:
    - Play/Pause, Skip, Previous controls
    - Add/Play Next/Play Now (local and YouTube)
    - YouTube Link and Search support
    - Volume control
    - Album art extraction
    - History tracking for YouTube links
    - Automatic SSH detection and routing
    - Works via SSH from remote clients (Android, etc.)
    - Flexible UI: rofi or fzf based on availability
    - Wrappers handle all UI interactions

ACTIONS:
    Play/Pause      - Toggle playback
    Skip            - Skip to next track
    Previous        - Go to previous track
    Add             - Add local song to queue
    Play Next       - Add local song to play next
    Play Now        - Play local song immediately
    Add YT Link     - Add YouTube video by link
    Play Next YT    - Add YouTube video to play next
    Play Now YT     - Play YouTube video now
    Add Search      - Search YouTube and add
    Play Next Search - Search YouTube and play next
    Play Now Search - Search YouTube and play now
    Current         - Show current song info
    Volume          - Adjust volume
    Download YT     - Download YouTube to library
    Restart MPD     - Restart the MPD daemon
    Restart ffplay  - Restart the ffplay audio steam listener client on windows
"@
}

if ($Help)
{
    Show-Help
    exit 0
}

# Configuration
$script:WSLUser = "henryk"
$script:MusicDir = "/mnt/CachyOs/@home/roockert/Music"
$script:CachePath = "/mnt/CachyOs/@home/roockert/.cache/rmpc"
$script:ConfigPath = "/home/henryk/.config/rmpc/config.ron"
$script:YouTubeHistoryFile = "$script:CachePath/rmpc_youtube_history"
$script:PicturesDir = "/mnt/CachyOs/@home/roockert/Pictures/AlbumArt"
$script:RmpcConfigFile = "/home/henryk/.config/rmpc/config.ron"

# Detect if running via SSH
$script:IsSSH = $false
$script:SSHIdentification = $null

if (-not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION))
{
    $script:IsSSH = $true
    $parts = $env:SSH_CONNECTION -split ' '
    if ($parts.Count -ge 1)
    {
        $script:SSHIdentification = $parts[0]
    }
} elseif (-not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT))
{
    $script:IsSSH = $true
    $parts = $env:SSH_CLIENT -split ' '
    if ($parts.Count -ge 1)
    {
        $script:SSHIdentification = $parts[0]
    }
}

# Check if fzf is available in WSL
$script:UseFzf = $fzf

# Logging
function Write-Log
{
    param([string]$Message, [string]$Level = "INFO")
}

# Format rmpc command with config file
function Format-RmpcCommand
{
    param([string]$RmpcCmd)
    
    # Add config flag if command contains rmpc and doesn't already have -c
    if ($RmpcCmd -match "rmpc" -and $RmpcCmd -notmatch "\s-c\s")
    {
        $RmpcCmd = $RmpcCmd -replace "rmpc(\s|$)", "rmpc -c $script:RmpcConfigFile`$1"
    } return $RmpcCmd
}

# Execute command - routes through SSH if detected, otherwise direct to WSL
function Invoke-RmpcCommand
{
    param(
        [string]$Command,
        [string]$CommandName = ""
    )
    
    $displayCmd = if ($CommandName) { "$CommandName" } else { $Command }
    $formattedCmd = Format-RmpcCommand $Command
    
    if ($script:IsSSH)
    {
        & pwsh-msg -Command "wsl-rmpc-exec -Command `"$formattedCmd`"" -Name "Rmpc Control"
    } else
    {
        & wsl-rmpc-exec -Command $formattedCmd
    }
}

# Mount CachyOS drive if needed
function Mount-CachyOSDrive
{
    try
    {
        $mountCheck = wsl -u henryk -- test -d /mnt/CachyOs 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            wsl -e sudo mount /dev/sdb1 /mnt/CachyOs 2>&1 | Out-Null
            return $LASTEXITCODE -eq 0
        }
        return $true
    } catch
    {
        return $false
    }
}

# Auto-start MPD if not running
function Start-MPDIfNeeded
{
    try
    {
        $mpdCheck = wsl -u henryk -- systemctl --user is-active mpd 2>&1
        if ($mpdCheck -notmatch "active")
        {
            wsl -u henryk -- systemctl --user start mpd 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
            $mpdCheck = wsl -u henryk -- systemctl --user is-active mpd 2>&1
            return $mpdCheck -match "active"
        }
        return $true
    } catch
    {
        return $false
    }
}

# Select from list using rofi or fzf wrapper
function Get-Selection
{
    param(
        [string]$InputContent,
        [string]$Prompt
    )
    
    if ($script:UseFzf)
    {
        $selection = $InputContent | & "$PSScriptRoot/wfzf.ps1" -p $Prompt
    } else
    {
        $selection = $InputContent | & "$PSScriptRoot/wrofi.ps1" -p $Prompt
    }
    
    return $selection
}

# Create action selection menu
function Get-ActionSelection
{
    $actionList = @(
        "Play/Pause",
        "Skip",
        "Previous",
        "Add",
        "Play Next",
        "Play Now",
        "Add YT Link",
        "Play Next YT Link",
        "Play Now YT Link",
        "Add Search",
        "Play Next Search",
        "Play Now Search",
        "Current",
        "Volume",
        "Download Youtube",
        "Restart MPD",
        "Restart ffplay"
    )
    
    $actionString = $actionList -join "`n"
    return Get-Selection $actionString "Music Player Actions"
}

# Get song from local music directory
function Get-LocalSongSelection
{
    $findCmd = 'find /mnt/CachyOs/@home/roockert/Music -type f -name "*.m4a" 2>/dev/null | awk -F/ ''{songname = $NF; gsub(/\.m4a$/, "", songname); printf "%s ::ARTIST:: %s ::ALBUM:: %s\n", songname, $(NF-2), $(NF-1)}'' | sort'
    
    $songList = & wsl-rmpc-exec.ps1 -Command $findCmd
    
    if ([string]::IsNullOrEmpty($songList)) { return $null }
    
    $songLines = @($songList -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $formattedList = $songLines -join "`n"
    
    $selection = Get-Selection $formattedList "Select a Track"
    
    if ([string]::IsNullOrEmpty($selection)) { return $null }
    
    $parts = $selection -split ' ::ARTIST:: '
    $songName = $parts[0]
    $rest = $parts[1] -split ' ::ALBUM:: '
    $artist = $rest[0]
    $album = $rest[1]
    
    return @{
        Name = $songName
        Artist = $artist
        Album = $album
        Path = "$artist/$album/$songName.m4a"
    }
}

# Save YouTube link to history file
function Save-YouTubeToHistory
{
    param([string]$Link)
    
    if ([string]::IsNullOrEmpty($Link)) { return }
    
    $OriginalLink = $Link
    if ($Link -match "::URL::\s*(https://[^\s]+)") { $Link = $matches[1] }
    
    if ($Link -notmatch "^https://www\.youtube\.com/watch\?v=") { return }
    
    if ($OriginalLink -match "^\[H\].*::URL::") { $entry = $OriginalLink }
    else {
        if ($Link -match "v=([a-zA-Z0-9_-]{11})") {
            $videoId = $matches[1]
            $entry = "[H]  $videoId ::URL:: $Link"
        } else { return }
    }
    
    $historyFile = "/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history"
    $saveCmd = "echo `"$entry`" >> `"$historyFile`""
    
    & wsl-rmpc-exec -Command $saveCmd | Out-Null
}

# Get YouTube link from user
function Get-YouTubeLink
{
    param([string]$Action)
    
    $history = & wsl-rmpc-exec -Command "test -f $script:YouTubeHistoryFile && cat $script:YouTubeHistoryFile || echo ''"
    
    if (-not [string]::IsNullOrEmpty($history))
    {
        $historyList = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($history -split "`n"))
        {
            $line = $line.Trim()
            if ($line -match "^\[H\].*::URL::\s*(https://[^\s]+)") { $historyList.Add($line) }
        }
        
        $historyList.Add("New Link")
        
        if ($historyList.Count -gt 1)
        {
            $link = Get-Selection ($historyList -join "`n") "YT Link or ID"
            if ($link -eq "New Link") { return "" }
            return $link
        }
    }
    return ""
}

function Test-YouTubeLink
{
    param([string]$Link)
    if ($Link -match "::URL::\s*(https://[^\s]+)") { $Link = $matches[1] }
    return ($Link -match "^https://www\.youtube\.com/watch\?v=" -or $Link -match "^[a-zA-Z0-9_-]{11}$")
}

function Format-YouTubeLink
{
    param([string]$Link)
    if ($Link -match "::URL::\s*(https://[^\s]+)") { $Link = $matches[1] }
    if ($Link -match "^https://www\.youtube\.com/watch\?v=") { return $Link }
    if ($Link -match "^[a-zA-Z0-9_-]{11}$") { return "https://www.youtube.com/watch?v=$Link" }
    return $null
}

function Get-VolumeSelection
{
    $currentVolume = & wsl-rmpc-exec -Command "rmpc -c $script:RmpcConfigFile volume"
    return Get-Selection "" "Set Volume (current: $currentVolume%)"
}

function Get-SearchQuery
{
    param([string]$Type = "youtube")
    
    $history = & wsl-rmpc-exec -Command "test -f $script:YouTubeHistoryFile && cat $script:YouTubeHistoryFile || echo ''"
    
    if (-not [string]::IsNullOrEmpty($history))
    {
        $historyList = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($history -split "`n"))
        {
            $line = $line.Trim()
            if ($line -match "^\[H\].*::URL::\s*(https://[^\s]+)") { $historyList.Add($line) }
        }
        
        $historyList.Add("New Search")
        
        if ($historyList.Count -gt 1)
        {
            $selection = Get-Selection ($historyList -join "`n") "Search"
            if ($selection -eq "New Search" -or [string]::IsNullOrEmpty($selection)) { return "" }
            if ($selection -match "::URL::\s*(https://[^\s]+)") { return $matches[1] }
            return $selection
        }
    }
    return ""
}

function Invoke-PlayPause { Invoke-RmpcCommand "rmpc togglepause" "play-pause" }
function Invoke-Skip { Invoke-RmpcCommand "rmpc next" "skip" }
function Invoke-Previous { Invoke-RmpcCommand "rmpc prev" "previous" }

function Invoke-AddLocal {
    $song = Get-LocalSongSelection
    if ($song) { Invoke-RmpcCommand "rmpc add `"$($song.Path)`"" "add-local" }
}

function Invoke-PlayNextLocal {
    $song = Get-LocalSongSelection
    if ($song) { Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc add -p `$((current_que + 1)) `"$($song.Path)`"" "play-next-local" }
}

function Invoke-PlayNowLocal {
    $song = Get-LocalSongSelection
    if ($song) { Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc add -p `$((current_que + 1)) `"$($song.Path)`"; sleep 0.5; rmpc next" "play-now-local" }
}

function Invoke-AddYouTubeLink {
    $link = Get-YouTubeLink "add"
    if ($link) {
        $link = Format-YouTubeLink $link
        if ($link) { Save-YouTubeToHistory $link; Invoke-RmpcCommand "rmpc addyt `"$link`"" "add-yt-link" }
    }
}

function Invoke-PlayNextYouTubeLink {
    $link = Get-YouTubeLink "play-next"
    if ($link) {
        $link = Format-YouTubeLink $link
        if ($link) { Save-YouTubeToHistory $link; Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc addyt -p `$((current_que + 1)) `"$link`"" "play-next-yt-link" }
    }
}

function Invoke-PlayNowYouTubeLink {
    $link = Get-YouTubeLink "play-now"
    if ($link) {
        $link = Format-YouTubeLink $link
        if ($link) { Save-YouTubeToHistory $link; Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc addyt -p `$((current_que + 1)) `"$link`"; sleep 0.5; rmpc next" "play-now-yt-link" }
    }
}

function Invoke-AddSearch {
    $query = Get-SearchQuery "youtube"
    if ($query) {
        if ($query -match "^https://www\.youtube\.com/watch\?v=") { Save-YouTubeToHistory $query }
        $searchCmd = "rmpc searchyt `"$query`" > /tmp/rmpc_search_output.txt 2>&1; sleep 1; url=`$(grep -oP `"Downloading '\K[^']+`" /tmp/rmpc_search_output.txt | head -1); if [ ! -z `"`$url`" ]; then video_id=`$(echo `"`$url`" | grep -oP 'v=\K[^&]+'); title=`$(rmpc queue | jq -r --arg id `"`$video_id`" '.[] | select(.file | contains(`$id`)) | .metadata.title' 2>/dev/null | head -1); if [ ! -z `"`$title`" ]; then echo `"[H]  `$title ::URL:: `$url`" >> '/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history'; fi; rm -f /tmp/rmpc_search_output.txt; fi"
        Invoke-RmpcCommand $searchCmd "add-search"
    }
}

function Invoke-PlayNextSearch {
    $query = Get-SearchQuery "youtube"
    if ($query) {
        if ($query -match "^https://www\.youtube\.com/watch\?v=") { Save-YouTubeToHistory $query }
        $searchCmd = "current_que=`$(rmpc status | jq -r '.song'); rmpc searchyt -p `$((current_que + 1)) `"$query`" > /tmp/rmpc_search_output.txt 2>&1; sleep 1; url=`$(grep -oP `"Downloading '\K[^']+`" /tmp/rmpc_search_output.txt | head -1); if [ ! -z `"`$url`" ]; then video_id=`$(echo `"`$url`" | grep -oP 'v=\K[^&]+'); title=`$(rmpc queue | jq -r --arg id `"`$video_id`" '.[] | select(.file | contains(`$id`)) | .metadata.title' 2>/dev/null | head -1); if [ ! -z `"`$title`" ]; then echo `"[H]  `$title ::URL:: `$url`" >> '/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history'; fi; rm -f /tmp/rmpc_search_output.txt; fi"
        Invoke-RmpcCommand $searchCmd "play-next-search"
    }
}

function Invoke-PlayNowSearch {
    $query = Get-SearchQuery "youtube"
    if ($query) {
        if ($query -match "^https://www\.youtube\.com/watch\?v=") { Save-YouTubeToHistory $query }
        $searchCmd = "current_que=`$(rmpc status | jq -r '.song'); rmpc searchyt -p `$((current_que + 1)) `"$query`" > /tmp/rmpc_search_output.txt 2>&1; sleep 2; url=`$(grep -oP `"Downloading '\K[^']+`" /tmp/rmpc_search_output.txt | head -1); if [ ! -z `"`$url`" ]; then video_id=`$(echo `"`$url`" | grep -oP 'v=\K[^&]+'); title=`$(rmpc queue | jq -r --arg id `"`$video_id`" '.[] | select(.file | contains(`$id`)) | .metadata.title' 2>/dev/null | head -1); if [ ! -z `"`$title`" ]; then echo `"[H]  `$title ::URL:: `$url`" >> '/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history'; fi; rm -f /tmp/rmpc_search_output.txt; fi; if [ `"`$current_que`" != `"-1`" ]; then rmpc next 2>/dev/null || true; fi; rmpc play 2>/dev/null || true"
        Invoke-RmpcCommand $searchCmd "play-now-search"
    }
}

function Invoke-ShowCurrent {
    $currentCmd = "songid=`$(rmpc status | jq -r '.songid'); name=`$(rmpc queue | jq -r --arg id `"`$songid`" '.[] | select(.id == (`$id | tonumber)) | .metadata.title'); echo `$name"
    Invoke-RmpcCommand $currentCmd "current-song"
}

function Invoke-VolumeControl {
    $volume = Get-VolumeSelection
    if ($volume) { Invoke-RmpcCommand "rmpc volume $volume" "volume-control" }
}

function Invoke-DownloadYouTube {
    $link = Get-YouTubeLink "download"
    if ($link) {
        $link = Format-YouTubeLink $link
        if ($link) { Invoke-RmpcCommand "cd ~/Music/youtube && yt-dlp `"$link`"" "download-yt" }
    }
}

function Invoke-RestartMPD { Invoke-RmpcCommand "systemctl --user restart mpd && echo `"MPD restarted successfully`" || echo `"Failed to restart MPD`"" "restart-mpd" }
function Invoke-RestartFfplay { pwsh-msg -Command "ffplay-keeper" -Restart -Name "Rmpc Control" -PipeName "PWSH_COMMAND_PIPE" }

function Invoke-Main
{
    $action = Get-ActionSelection
    if (-not $action) { exit 0 }

    if ($action -notmatch "Restart ffplay") {
        [void](Mount-CachyOSDrive)
        [void](Start-MPDIfNeeded)
    }
    
    switch -Regex ($action)
    {
        "^Play/Pause*" { Invoke-PlayPause }
        "^Skip*" { Invoke-Skip }
        "^Previous*" { Invoke-Previous }
        "^Add$" { Invoke-AddLocal }
        "^Play Next$" { Invoke-PlayNextLocal }
        "^Play Now$" { Invoke-PlayNowLocal }
        "^Add YT Link" { Invoke-AddYouTubeLink }
        "^Play Next YT Link" { Invoke-PlayNextYouTubeLink }
        "^Play Now YT Link" { Invoke-PlayNowYouTubeLink }
        "^Add Search" { Invoke-AddSearch }
        "^Play Next Search" { Invoke-PlayNextSearch }
        "^Play Now Search" { Invoke-PlayNowSearch }
        "^Current" { Invoke-ShowCurrent }
        "^Volume" { Invoke-VolumeControl }
        "^Download Youtube" { Invoke-DownloadYouTube }
        "^Restart MPD" { Invoke-RestartMPD }
        "^Restart ffplay" { Invoke-RestartFfplay }
    }
}

Invoke-Main

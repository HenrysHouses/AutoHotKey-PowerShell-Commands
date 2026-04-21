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
if ($fzf)
{
    try
    {
        $result = wsl -u $script:WSLUser -- bash -c "which fzf 2>/dev/null" 2>&1
        if ([string]::IsNullOrEmpty($result))
        {
            Write-Host "⚠ fzf not found in WSL, falling back to rofi" -ForegroundColor Yellow
            $script:UseFzf = $false
        }
    } catch
    {
        Write-Host "⚠ Cannot check fzf availability, falling back to rofi" -ForegroundColor Yellow
        $script:UseFzf = $false
    }
}

# Logging
function Write-Log
{
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch ($Level)
        {
            "ERROR"
            { "Red" 
            }
            "WARN"
            { "Yellow" 
            }
            "SUCCESS"
            { "Green" 
            }
            default
            { "Gray" 
            }
        }
    )
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
    
    $displayCmd = if ($CommandName)
    { "$CommandName" 
    } else
    { $Command 
    }
    $formattedCmd = Format-RmpcCommand $Command
    
    if ($script:IsSSH)
    {
        Write-Log "Routing via SSH message queue: $displayCmd" "INFO"
        & pwsh-msg -Command "wsl-rmpc-exec -Command `"$formattedCmd`"" -Name "Rmpc Control"
    } else
    {
        & wsl-rmpc-exec -Command $formattedCmd
    }
}

# Test WSL connection
# function Test-WSLConnection
# {
#     try
#     {
#         $result = wsl -u henryk -- echo "WSL_OK" 2>&1
#         return $result -eq "WSL_OK"
#     } catch
#     {
#         return $false
#     }
# }

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

# # Test RMPC availability and config
# function Test-RmpcAvailable
# {
#     try
#     {
#         $which_result = & "$PSScriptRoot/../../wsl-rmpc-exec.ps1" -Command "which rmpc" 2>&1
#         if ([string]::IsNullOrEmpty($which_result))
#         {
#             return $false
#         }
#
#         # Also verify config file exists
#         $config_check = & "$PSScriptRoot/../../wsl-rmpc-exec.ps1" -Command "test -f $script:RmpcConfigFile && echo 'OK'" 2>&1
#         if ($config_check -ne "OK")
#         {
#             Write-Log "Warning: rmpc config file not found at $script:RmpcConfigFile" "WARN"
#         }
#
#         return $true
#     } catch
#     {
#         return $false
#     }
# }

# Select from list using rofi or fzf wrapper
function Get-Selection
{
    param(
        [string]$InputContent,
        [string]$Prompt
    )
    
    # Write-Log "[WLINES INPUT] Prompt: $Prompt" "INFO"
    # Write-Log "[WLINES INPUT] Content: $($InputContent -replace "`n", '\n')" "INFO"
    
    if ($script:UseFzf)
    {
        $selection = $InputContent | & "$PSScriptRoot/wfzf.ps1" -p $Prompt
    } else
    {
        $selection = $InputContent | & "$PSScriptRoot/wrofi.ps1" -p $Prompt
    }
    
    # Write-Log "[WLINES OUTPUT] Selected: $selection" "INFO"
    return $selection
}

# Create action selection menu
function Get-ActionSelection
{
    $actionList = @(
        # "Play/Pause                                                                                                                           plpa toggle tg"
        # "Skip                                                                                                                                 sp"
        # "Prev                                                                                                                                 previous"
        # "Add"
        # "Play Next                                                                                                                            pn pnext plnext playnext"
        # "Play Now                                                                                                                             pow pnow plow plnow playnow"
        # "Add YT Link                                                                                                                          alnk addlnk adlnk addytlnk ytadd lnkadd linkadd"
        # "Play Next YT Link                                                                                                                    plyt plnk pnlnk pnytlnk lnk playnextlink ytnext lnknext linknext"
        # "Play Now YT Link                                                                                                                     pyn pnlink powyt pnowyt plonk pnlonk pnoytlnk playnowlink ytnow lnknow linknow"
        # "Add Search                                                                                                                           as adsrch addsrch srchnow sradd"
        # "Play Next Search                                                                                                                     ps pnlsrch plsrch playnextsearch playnextsrch searchnext srchnext srnext"
        # "Play Now Search                                                                                                                      psn pnowsrch powsrch srchnow playnowsearch playnowsrch searchnow srchnow srnow"
        # "Current"
        # "Volume"
        # "Download Youtube                                                                                                                     dyt dyoutube"

        "Play/Pause"
        "Skip"
        "Previous"
        "Add"
        "Play Next"
        "Play Now"
        "Add YT Link"
        "Play Next YT Link"
        "Play Now YT Link"
        "Add Search"
        "Play Next Search"
        "Play Now Search"
        "Current"
        "Volume"
        "Download Youtube"
        "Restart MPD"
        "Restart ffplay"
    )
    
    $actionString = $actionList -join "`n"
    $uiMethod = if ($script:UseFzf)
    { "fzf" 
    } else
    { "rofi" 
    }
    # Write-Log "Action selection via $uiMethod" "INFO"
    
    return Get-Selection $actionString "Music Player Actions"
}

# Get song from local music directory
function Get-LocalSongSelection
{
    # Write-Log "Selecting from local music library" "INFO"
    
    # Use a here-string to avoid complex escaping, passed as literal string
    $findCmd = 'find /mnt/CachyOs/@home/roockert/Music -type f -name "*.m4a" 2>/dev/null | awk -F/ ''{songname = $NF; gsub(/\.m4a$/, "", songname); printf "%s ::ARTIST:: %s ::ALBUM:: %s\n", songname, $(NF-2), $(NF-1)}'' | sort'
    
    $songList = & wsl-rmpc-exec.ps1 -Command $findCmd
    
    if ([string]::IsNullOrEmpty($songList))
    {
        # Write-Log "No songs found in local library" "WARN"
        return $null
    }
    
    # Ensure proper newline handling - split by `n and filter empty lines
    $songLines = @($songList -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    # Write-Log "[LOCAL SONG LIST] Total songs found: $($songLines.Count)" "INFO"
    # Write-Log "[LOCAL SONG LIST] First song: $($songLines[0])" "INFO"
    
    # Rejoin with proper newlines for wlines input
    $formattedList = $songLines -join "`n"
    
    $selection = Get-Selection $formattedList "Select a Track"
    
    if ([string]::IsNullOrEmpty($selection))
    {
        # Write-Log "Song selection cancelled" "WARN"
        return $null
    }
    
    # Parse the selection
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
    
    if ([string]::IsNullOrEmpty($Link))
    {
        return
    }
    
    $OriginalLink = $Link
    
    # Extract just the URL if it has the ::URL:: format
    if ($Link -match "::URL::\s*(https://[^\s]+)")
    {
        $Link = $matches[1]
    }
    
    # Only save valid YouTube URLs
    if ($Link -notmatch "^https://www\.youtube\.com/watch\?v=")
    {
        return
    }
    
    # If original had [H] format with title, preserve it
    if ($OriginalLink -match "^\[H\].*::URL::")
    {
        $entry = $OriginalLink
    } else
    {
        # Otherwise just save the URL (search functions will save with title)
        # Extract video ID for display
        if ($Link -match "v=([a-zA-Z0-9_-]{11})")
        {
            $videoId = $matches[1]
            $entry = "[H]  $videoId ::URL:: $Link"
        } else
        {
            return
        }
    }
    
    # Use hardcoded path to avoid variable expansion issues
    $historyFile = "/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history"
    $saveCmd = "echo `"$entry`" >> `"$historyFile`""
    
    & wsl-rmpc-exec -Command $saveCmd | Out-Null
}

# Get YouTube link from user
function Get-YouTubeLink
{
    param([string]$Action)
    
    # Write-Log "Requesting YouTube link" "INFO"
    
    # Check for history
    $history = & wsl-rmpc-exec -Command "test -f $script:YouTubeHistoryFile && cat $script:YouTubeHistoryFile || echo ''"
    
    if (-not [string]::IsNullOrEmpty($history))
    {
        $historyList = @()
        foreach ($line in ($history -split "`n"))
        {
            $line = $line.Trim()
            if ([string]::IsNullOrEmpty($line))
            {
                continue
            }
            
            # Handle formatted entries: [H] Title ::URL:: URL
            if ($line -match "^\[H\].*::URL::\s*(https://[^\s]+)")
            {
                $historyList += $line
            }
        }
        
        $historyList += "New Link"
        
        if ($historyList.Count -gt 1)
        {
            $link = Get-Selection ($historyList -join "`n") "YT Link or ID"
            
            if ($link -eq "New Link")
            {
                return ""
            }
            
            return $link
        }
    }
    
    return ""
}

# Validate YouTube link
function Test-YouTubeLink
{
    param([string]$Link)
    
    # Extract URL from format like "[H]  Title ::URL:: https://..."
    if ($Link -match "::URL::\s*(https://[^\s]+)")
    {
        $Link = $matches[1]
    }
    
    if ($Link -match "^https://www\.youtube\.com/watch\?v=")
    {
        return $true
    }
    
    if ($Link -match "^[a-zA-Z0-9_-]{11}$")
    {
        return $true
    }
    
    return $false
}

# Normalize YouTube link to full URL
function Format-YouTubeLink
{
    param([string]$Link)
    
    # Extract URL from format like "[H]  Title ::URL:: https://..."
    if ($Link -match "::URL::\s*(https://[^\s]+)")
    {
        $Link = $matches[1]
    }
    
    if ($Link -match "^https://www\.youtube\.com/watch\?v=")
    {
        return $Link
    }
    
    if ($Link -match "^[a-zA-Z0-9_-]{11}$")
    {
        return "https://www.youtube.com/watch?v=$Link"
    }
    
    return $null
}

# Get volume level
function Get-VolumeSelection
{
    # Write-Log "Requesting volume level" "INFO"
    
    $currentVolume = & wsl-rmpc-exec -Command "rmpc -c $script:RmpcConfigFile volume"
    
    $volume = Get-Selection "" "Set Volume (current: $currentVolume%)"
    
    return $volume
}

# Get search query from user
function Get-SearchQuery
{
    param([string]$Type = "youtube")
    
    # Write-Log "Requesting search query for $Type" "INFO"
    
    # Check for history
    $history = & wsl-rmpc-exec -Command "test -f $script:YouTubeHistoryFile && cat $script:YouTubeHistoryFile || echo ''"
    
    if (-not [string]::IsNullOrEmpty($history))
    {
        $historyList = @()
        foreach ($line in ($history -split "`n"))
        {
            $line = $line.Trim()
            if ([string]::IsNullOrEmpty($line))
            {
                continue
            }
            
            # Handle formatted entries: [H] Title ::URL:: URL
            if ($line -match "^\[H\].*::URL::\s*(https://[^\s]+)")
            {
                $historyList += $line
            }
        }
        
        $historyList += "New Search"
        
        if ($historyList.Count -gt 1)
        {
            $selection = Get-Selection ($historyList -join "`n") "Search"
            
            if ($selection -eq "New Search" -or [string]::IsNullOrEmpty($selection))
            {
                return ""
            }
            
            # Extract URL from the selection
            if ($selection -match "::URL::\s*(https://[^\s]+)")
            {
                return $matches[1]
            }
            
            return $selection
        }
    }
    
    return ""
}

# Handle Play/Pause
function Invoke-PlayPause
{
    # Write-Log "Toggling play/pause" "INFO"
    Invoke-RmpcCommand "rmpc togglepause" "play-pause"
}

# Handle Skip
function Invoke-Skip
{
    # Write-Log "Skipping to next track" "INFO"
    Invoke-RmpcCommand "rmpc next" "skip"
}

# Handle Previous
function Invoke-Previous
{
    # Write-Log "Playing previous track" "INFO"
    Invoke-RmpcCommand "rmpc prev" "previous"
}

# Handle Add local song
function Invoke-AddLocal
{
    $song = Get-LocalSongSelection
    if ($null -eq $song)
    {
        return
    }
    
    # Write-Log "Adding to queue: $($song.Name)" "INFO"
    Invoke-RmpcCommand "rmpc add `"$($song.Path)`"" "add-local"
}

# Handle Play Next local song
function Invoke-PlayNextLocal
{
    $song = Get-LocalSongSelection
    if ($null -eq $song)
    {
        return
    }
    
    # Write-Log "Adding to play next: $($song.Name)" "INFO"
    Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc add -p `$((current_que + 1)) `"$($song.Path)`"" "play-next-local"
}

# Handle Play Now local song
function Invoke-PlayNowLocal
{
    $song = Get-LocalSongSelection
    if ($null -eq $song)
    {
        return
    }
    
    # Write-Log "Playing now: $($song.Name)" "INFO"
    Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc add -p `$((current_que + 1)) `"$($song.Path)`"; sleep 0.5; rmpc next" "play-now-local"
}

# Handle Add YouTube link
function Invoke-AddYouTubeLink
{
    $link = Get-YouTubeLink "add"
    if ([string]::IsNullOrEmpty($link))
    {
        # Write-Log "YouTube link cancelled" "WARN"
        return
    }
    
    $link = Format-YouTubeLink $link
    if ([string]::IsNullOrEmpty($link))
    {
        # Write-Log "Invalid YouTube link format" "ERROR"
        return
    }
    
    Save-YouTubeToHistory $link
    # Write-Log "Adding YouTube link to queue: $link" "INFO"
    Invoke-RmpcCommand "rmpc addyt `"$link`"" "add-yt-link"
}

# Handle Play Next YouTube link
function Invoke-PlayNextYouTubeLink
{
    $link = Get-YouTubeLink "play-next"
    if ([string]::IsNullOrEmpty($link))
    {
        # Write-Log "YouTube link cancelled" "WARN"
        return
    }
    
    $link = Format-YouTubeLink $link
    if ([string]::IsNullOrEmpty($link))
    {
        # Write-Log "Invalid YouTube link format" "ERROR"
        return
    }
    
    Save-YouTubeToHistory $link
    # Write-Log "Playing next YouTube link: $link" "INFO"
    Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc addyt -p `$((current_que + 1)) `"$link`"" "play-next-yt-link"
}

# Handle Play Now YouTube link
function Invoke-PlayNowYouTubeLink
{
    $link = Get-YouTubeLink "play-now"
    if ([string]::IsNullOrEmpty($link))
    {
        # Write-Log "YouTube link cancelled" "WARN"
        return
    }
    
    $link = Format-YouTubeLink $link
    if ([string]::IsNullOrEmpty($link))
    {
        # Write-Log "Invalid YouTube link format" "ERROR"
        return
    }
    
    Save-YouTubeToHistory $link
    # Write-Log "Playing now YouTube link: $link" "INFO"
    # Add at current position + 1 and skip to it immediately
    Invoke-RmpcCommand "current_que=`$(rmpc status | jq -r '.song'); rmpc addyt -p `$((current_que + 1)) `"$link`"; sleep 0.5; rmpc next" "play-now-yt-link"
}

# Handle Add search
function Invoke-AddSearch
{
    $query = Get-SearchQuery "youtube"
    if ([string]::IsNullOrEmpty($query))
    {
        # Write-Log "Search cancelled" "WARN"
        return
    }
    
    # If it's a URL from history, save it (consistency)
    if ($query -match "^https://www\.youtube\.com/watch\?v=")
    {
        Save-YouTubeToHistory $query
    }
    
    # Write-Log "Searching YouTube for: $query" "INFO"
    $searchCmd = @"
rmpc searchyt `"$query`" > /tmp/rmpc_search_output.txt 2>&1
sleep 1
# Extract the URL from the download output
url=`$(grep -oP "Downloading '\K[^']+" /tmp/rmpc_search_output.txt | head -1)
if [ ! -z "`$url" ]; then
    # Extract video ID from URL
    video_id=`$(echo "`$url" | grep -oP 'v=\K[^&]+')
    # Get title from rmpc queue by searching for the file with this video ID
    title=`$(rmpc queue | jq -r '.[] | select(.file | contains("'`$video_id`'")) | .metadata.title' 2>/dev/null | head -1)
    if [ ! -z "`$title" ]; then
        echo "[H]  `$title ::URL:: `$url" >> '/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history'
    fi
    rm -f /tmp/rmpc_search_output.txt
fi
"@
    Invoke-RmpcCommand $searchCmd "add-search"
}

# Handle Play Next search
function Invoke-PlayNextSearch
{
    $query = Get-SearchQuery "youtube"
    if ([string]::IsNullOrEmpty($query))
    {
        # Write-Log "Search cancelled" "WARN"
        return
    }
    
    # If it's a URL from history, save it (consistency)
    if ($query -match "^https://www\.youtube\.com/watch\?v=")
    {
        Save-YouTubeToHistory $query
    }
    
    # Write-Log "Play next from search: $query" "INFO"
    $searchCmd = @"
current_que=`$(rmpc status | jq -r '.song')
rmpc searchyt -p `$((current_que + 1)) `"$query`" > /tmp/rmpc_search_output.txt 2>&1
sleep 1
# Extract the URL from the download output
url=`$(grep -oP "Downloading '\K[^']+" /tmp/rmpc_search_output.txt | head -1)
if [ ! -z "`$url" ]; then
    # Extract video ID from URL
    video_id=`$(echo "`$url" | grep -oP 'v=\K[^&]+')
    # Get title from rmpc queue by searching for the file with this video ID
    title=`$(rmpc queue | jq -r '.[] | select(.file | contains("'`$video_id`'")) | .metadata.title' 2>/dev/null | head -1)
    if [ ! -z "`$title" ]; then
        echo "[H]  `$title ::URL:: `$url" >> '/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history'
    fi
    rm -f /tmp/rmpc_search_output.txt
fi
"@
    Invoke-RmpcCommand $searchCmd "play-next-search"
}

# Handle Play Now search
function Invoke-PlayNowSearch
{
    $query = Get-SearchQuery "youtube"
    if ([string]::IsNullOrEmpty($query))
    {
        # Write-Log "Search cancelled" "WARN"
        return
    }
    
    # If it's a URL from history, save it (it's already in history but this ensures consistency)
    if ($query -match "^https://www\.youtube\.com/watch\?v=")
    {
        Save-YouTubeToHistory $query
    }
    
    # Write-Log "Play now from search: $query" "INFO"
    # Add search result, extract URL from output, then play
    $searchCmd = @"
current_que=`$(rmpc status | jq -r '.song')
rmpc searchyt -p `$((current_que + 1)) `"$query`" > /tmp/rmpc_search_output.txt 2>&1
sleep 2
# Extract the URL from the download output
url=`$(grep -oP "Downloading '\K[^']+" /tmp/rmpc_search_output.txt | head -1)
if [ ! -z "`$url" ]; then
    # Extract video ID from URL
    video_id=`$(echo "`$url" | grep -oP 'v=\K[^&]+')
    # Get title from rmpc queue by searching for the file with this video ID
    title=`$(rmpc queue | jq -r '.[] | select(.file | contains("'`$video_id`'")) | .metadata.title' 2>/dev/null | head -1)
    if [ ! -z "`$title" ]; then
        echo "[H]  `$title ::URL:: `$url" >> '/mnt/CachyOs/@home/roockert/.cache/rmpc/rmpc_youtube_history'
    fi
    rm -f /tmp/rmpc_search_output.txt
fi
# Try to skip to newly added song, with error handling
if [ "`$current_que" != "-1" ]; then
    rmpc next 2>/dev/null || true
fi
# Ensure playback starts
rmpc play 2>/dev/null || true
"@
    Invoke-RmpcCommand $searchCmd "play-now-search"
}

# Handle Current song display
function Invoke-ShowCurrent
{
    # Write-Log "Getting current song" "INFO"
    
    $currentCmd = @"
songid=`$(rmpc status | jq -r '.songid')
name=`$(rmpc queue | jq -r --arg id "`$songid" '.[] | select(.id == (`$id | tonumber)) | .metadata.title')
echo `$name
"@
    
    Invoke-RmpcCommand $currentCmd "current-song"
}

# Handle Volume
function Invoke-VolumeControl
{
    $volume = Get-VolumeSelection
    if ([string]::IsNullOrEmpty($volume))
    {
        # Write-Log "Volume control cancelled" "WARN"
        return
    }
    
    # Write-Log "Setting volume to: $volume" "INFO"
    Invoke-RmpcCommand "rmpc volume $volume" "volume-control"
}

# Handle Download YouTube
function Invoke-DownloadYouTube
{
    $link = Get-YouTubeLink "download"
    if ([string]::IsNullOrEmpty($link))
    {
        Write-Log "Download cancelled" "WARN"
        return
    }
    
    $link = Format-YouTubeLink $link
    if ([string]::IsNullOrEmpty($link))
    {
        Write-Log "Invalid YouTube link format" "ERROR"
        return
    }
    
    Write-Log "Downloading YouTube video: $link" "INFO"
    Invoke-RmpcCommand "cd ~/Music/youtube && yt-dlp `"$link`"" "download-yt"
}

# Handle Restart MPD
function Invoke-RestartMPD
{
    Write-Log "Attempting to restart MPD" "INFO"
    
    $restartCmd = @"
systemctl --user restart mpd && echo "MPD restarted successfully" || echo "Failed to restart MPD"
"@
    
    Invoke-RmpcCommand $restartCmd "restart-mpd"
}

function Invoke-RestartFfplay
{
    pwsh-msg -Command ". ffplay-keeper" -Restart -Name "Rmpc Control" -PipeName "PWSH_COMMAND_PIPE"
}

# Main execution
function Invoke-Main
{
    $uiMethod = if ($script:UseFzf)
    { "fzf" 
    } else
    { "rofi" 
    }
    # Write-Log "RMPC Music Player Control Started" "INFO"
    # Write-Log "UI Method: $uiMethod" "INFO"
    
    if ($script:IsSSH)
    {
        Write-Log "SSH Detected: $($script:SSHIdentification)" "INFO"
        Write-Log "Commands will be routed via pwsh-msg -> wsl-rmpc-exec" "INFO"
    } else
    {
        # Write-Log "Local mode" "INFO"
    }
    
    # Check WSL
    # if (-not (Test-WSLConnection))
    # {
    #     Write-Log "Cannot connect to WSL" "ERROR"
    #     exit 1
    # }
    # Write-Log "WSL connection OK" "SUCCESS"
    
    # Mount CachyOS drive if needed
    # Write-Log "Checking CachyOS drive mount..." "INFO"
    if (-not (Mount-CachyOSDrive))
    {
        Write-Log "Warning: Could not mount CachyOS drive - music may not be accessible" "WARN"
    } else
    {
        # Write-Log "CachyOS drive mounted/verified" "SUCCESS"
    }
    
    # Check RMPC
    # if (-not (Test-RmpcAvailable))
    # {
    #     Write-Log "rmpc not found in WSL" "ERROR"
    #     exit 1
    # }
    # Write-Log "rmpc available" "SUCCESS"
    
    # Auto-start MPD if not running
    # Write-Log "Checking MPD daemon..." "INFO"
    if (-not (Start-MPDIfNeeded))
    {
        Write-Log "Warning: MPD may not have started correctly" "WARN"
    } else
    {
        # Write-Log "MPD daemon running" "SUCCESS"
    }
    
    # Show action menu
    $action = Get-ActionSelection
    
    if ([string]::IsNullOrEmpty($action))
    {
        # Write-Log "No action selected - exiting" "INFO"
        exit 0
    }
    
    # Write-Log "Selected action: $action" "INFO"
    
    switch -Regex ($action)
    {
        "^Play/Pause*"
        { Invoke-PlayPause 
        }
        "^Skip*"
        { Invoke-Skip 
        }
        "^Previous*"
        { Invoke-Previous 
        }
        "^Add$"
        { Invoke-AddLocal 
        }
        "^Play Next$"
        { Invoke-PlayNextLocal 
        }
        "^Play Now$"
        { Invoke-PlayNowLocal 
        }
        "^Add YT Link"
        { Invoke-AddYouTubeLink 
        }
        "^Play Next YT Link"
        { Invoke-PlayNextYouTubeLink 
        }
        "^Play Now YT Link"
        { Invoke-PlayNowYouTubeLink 
        }
        "^Add Search"
        { Invoke-AddSearch 
        }
        "^Play Next Search"
        { Invoke-PlayNextSearch 
        }
        "^Play Now Search"
        { Invoke-PlayNowSearch 
        }
        "^Current"
        { Invoke-ShowCurrent 
        }
        "^Volume"
        { Invoke-VolumeControl 
        }
        "^Download Youtube"
        { Invoke-DownloadYouTube 
        }
        "^Restart MPD"
        { Invoke-RestartMPD 
        }
        "^Restart ffplay"
        { Invoke-RestartFfplay
        }
    }
}

# Run main
Invoke-Main

# wsl-rmpc-exec.ps1 - Windows to WSL RMPC Bridge with Auto-ffplay Launch
# Intermediary between pwsh-msg-daemon and WSL
# Executes rmpc commands in WSL (Arch Linux)
# Automatically launches ffplay when music playback starts

param(
    [Parameter(Mandatory = $true)]
    [string]$Command,
    
    [Parameter(Mandatory = $false)]
    [string]$Source = "unknown"
)

# Configuration
$WSLUser = "henryk"
$StreamURL = "http://127.0.0.1:8000"

# Function to test WSL connection
function Test-WSLConnection
{
    try
    {
        $result = wsl -u $WSLUser -- echo "WSL_OK" 2>&1
        return $result -eq "WSL_OK"
    } catch
    {
        return $false
    }
}

# Function to launch ffplay with stream URL via keeper watchdog
function Start-ffplayStream
{
    pwsh-msg -Command "ffplay-keeper" -Restart -Name "Rmpc WSL" -PipeName "PWSH_COMMAND_PIPE"
}

# Function to stop ffplay stream
function Stop-ffplayStream
{
    pwsh-msg -Command "ffplay-keeper" -Cancel -Name "Rmpc WSL" -PipeName "PWSH_COMMAND_PIPE"
}

# Detect playback commands
$Command = $Command.Trim()
$isPlay = $Command -match "^(play|next|prev|addyt|searchyt)"
$isStop = $Command -match "^stop"
$isPause = $Command -match "^pause"
$isToggle = $Command -match "^togglepause"

if ($isPlay)
{
    Start-ffplayStream | Out-Null
} elseif ($isStop -or $isPause)
{
    Stop-ffplayStream | Out-Null
} elseif ($isToggle)
{
    # Check current MPD state to decide whether to start or stop stream
    try
    {
        $mpdStatus = wsl -u $WSLUser -e rmpc status 2>&1
        if ($mpdStatus -match "playing")
        {
            # About to pause
            Stop-ffplayStream | Out-Null
        } else
        {
            # About to play
            Start-ffplayStream | Out-Null
        }
    } catch
    {
        # Fallback to restart if status check fails
        Start-ffplayStream | Out-Null
    }
}

# Execute command in WSL
try
{
    # -d sets distribution, -u sets user, -e runs command directly
    # Pass command as argument array to avoid shell interpretation
    wsl -u $WSLUser -e bash -c "$Command" 2>&1
    exit $LASTEXITCODE
} catch
{
    Write-Error "Failed to execute in WSL: $_"
    exit 1
}

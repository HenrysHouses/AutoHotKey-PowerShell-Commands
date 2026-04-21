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

# Function to mount CachyOS drive if needed
function Mount-CachyOSDrive
{
    try
    {
        $mountCheck = wsl -u $WSLUser -- test -d /mnt/CachyOs 2>&1
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

# Function to ensure MPD is running
function Start-MPDIfNeeded
{
    try
    {
        $mpdCheck = wsl -u $WSLUser -- systemctl --user is-active mpd 2>&1
        if ($mpdCheck -notmatch "active")
        {
            wsl -u $WSLUser -- systemctl --user start mpd 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
            $mpdCheck = wsl -u $WSLUser -- systemctl --user is-active mpd 2>&1
            return $mpdCheck -match "active"
        }
        return $true
    } catch
    {
        return $false
    }
}

# Function to launch ffplay with stream URL via keeper watchdog
function Start-ffplayStream
{
    pwsh-msg -Command ". 'C:\Users\Henri\bin\ffplay-keeper.ps1'" -Restart -Name "Rmpc WSL" -PipeName "PWSH_COMMAND_PIPE"
}

# Detect if this is a play command and launch ffplay
$Command = $Command.Trim()
$isPlayCommand = ($Command -match "togglepause|next|prev|play|addyt|searchyt") -and ($Command -notmatch "status|queue|current")

# Write-Host "[DEBUG] Command received: '$Command'" -ForegroundColor Cyan
# Write-Host "[DEBUG] Is play command: $isPlayCommand" -ForegroundColor Cyan

if ($isPlayCommand)
{
    # Write-Host "[DEBUG] Attempting to start ffplay..." -ForegroundColor Green
    Start-ffplayStream | Out-Null
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

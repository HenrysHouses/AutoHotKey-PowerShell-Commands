# ffplay-keeper.ps1 - Robust watchdog for ffplay audio stream
# Designed to be run via pwsh-pipe-daemon

[CmdletBinding()]
param()

$StreamURL = "http://127.0.0.1:8000"
$MaxRetries = 10
$BaseDelay = 2
$MaxDelay = 30

Write-Verbose "[KEEPER] Initializing ffplay watchdog..."

# Helper to kill orphaned ffplay instances
function Stop-ExistingFfplay
{
    $killed = $false
    Get-Process ffplay -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" } | ForEach-Object {
        Write-Verbose "[KEEPER] Terminating orphaned ffplay (PID: $($_.Id))"
        Stop-Process $_ -Force -ErrorAction SilentlyContinue
        wsl --exec pkill dbus-daemon
        $killed = $true
    }
    if ($killed)
    {
        New-BurntToastNotification -Text "ffplay keeper", "Process killed" -Silent
    }
}

Stop-ExistingFfplay

$RetryCount = 0

try
{
    wsl --exec dbus-launch true
    New-BurntToastNotification -Text "ffplay keeper", "Listening to url $StreamURL" -Silent
    while ($true)
    {
        # Check if ffplay is already running (defensive check)
        $ffproc = Get-Process ffplay -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" }

        if (-not $ffproc)
        {
            Write-Verbose "[KEEPER] Starting ffplay stream ($StreamURL)..."

            # Use Start-Process so we can monitor exit codes and avoid blocking the loop too hard
            # -nodisp: no video window
            # -autoexit: exit on stream end (allows keeper to restart) 
            # -loglevel quiet: suppress ffplay output
            $p = Start-Process ffplay -ArgumentList "-nodisp", "-autoexit", "-loglevel", "quiet", "$StreamURL" -NoNewWindow -PassThru -ErrorAction SilentlyContinue 

            if ($p)
            {
                Write-Verbose "[KEEPER] ffplay started (PID: $($p.Id))"
                $p.WaitForExit()

                $exitCode = $p.ExitCode
                Write-Verbose "[KEEPER] ffplay exited with code: $exitCode"

                if ($exitCode -ne 0)
                {
                    $RetryCount++
                    $delay = [Math]::Min($MaxDelay, $BaseDelay * [Math]::Pow(2, [Math]::Min($RetryCount - 1, 5)))
                    Write-Verbose "[KEEPER] Stream error detected. Retry $RetryCount/$MaxRetries in $delay seconds..."
                    New-BurntToastNotification -Text "ffplay keeper", "Stream error detected. Retry $RetryCount/$MaxRetries in $delay seconds..." -Silent
                } else
                {
                    $RetryCount = 0 # Reset on clean exit
                    $delay = $BaseDelay
                    Write-Verbose "[KEEPER] Stream ended normally. Restarting in $delay seconds..."
                }
            } else
            {
                Write-Verbose "[KEEPER] Failed to start ffplay process!"
                New-BurntToastNotification -Text "ffplay keeper", "Failed to start ffplay process!"
                $delay = $MaxDelay
            }
        } else
        {
            # Already running, just wait
            $delay = $BaseDelay
        }

        if ($RetryCount -ge $MaxRetries)
        {
            Write-Verbose "[KEEPER] Max retries reached. Waiting 60s before resetting..."
            New-BurntToastNotification -Text "ffplay keeper", "Max retries reached. Waiting 60s before resetting..."
            Start-Sleep -Seconds 60
            $RetryCount = 0
            continue
        }

        Start-Sleep -Seconds $delay
    }
} catch
{
    New-BurntToastNotification -Text "ffplay keeper", "Fatal error: $($_.Exception.Message)"
    Write-Verbose "[KEEPER] Fatal error in watchdog loop: $($_.Exception.Message)"
} finally
{
    Write-Verbose "[KEEPER] Shutting down watchdog. Cleaning up ffplay..."
    Stop-ExistingFfplay
}

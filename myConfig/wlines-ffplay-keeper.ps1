# wlines-ffplay-keeper.ps1 - Persistent watchdog for ffplay stream
$StreamURL = "http://127.0.0.1:8000"

Write-Host "[KEEPER] Initializing ffplay watchdog..."
# Kill any existing ffplay to ensure a clean start
# (Specifically looking for console-less instances)
Get-Process ffplay -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" } | Stop-Process -Force -ErrorAction SilentlyContinue

while ($true) {
    # Check if ffplay is already running
    $ffproc = Get-Process ffplay -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" }
    
    if (-not $ffproc) {
        Write-Host "[KEEPER] ffplay not detected. Launching..." -ForegroundColor Yellow
        # Launch ffplay. This will block until ffplay exits or the runspace is stopped.
        ffplay -nodisp $StreamURL
        Write-Host "[KEEPER] ffplay exited. Restarting in 2 seconds..." -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 2
}

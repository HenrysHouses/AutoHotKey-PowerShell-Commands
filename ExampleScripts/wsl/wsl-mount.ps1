$drivePath = "\\.\PHYSICALDRIVE0"

$alive = Get-Process wsl -ErrorAction SilentlyContinue

if ($null -ne $alive)
{
    Write-Host "WSL is running, can not mount drive."
    exit 1
}

# Start-Process pwsh -WindowStyle hidden -ArgumentList "-NoProfile", "-Command", "sudo wsl.exe --mount $drivePath"
wsl.exe --mount $drivePath

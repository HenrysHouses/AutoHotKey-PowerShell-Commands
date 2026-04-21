Param(
    [string]$PhysicalDrive = "\\.\PHYSICALDRIVE0",
    [string]$MountPoint = "/mnt/CachyOs"
)

# Write-Host "Mounting $PhysicalDrive... (requires admin)"
try
{
    wsl -- test -d "$MountPoint/@home"
} catch
{
    Write-Host "Mounting drive to WSL..."
    try
    {
        & sudo wsl.exe --mount $PhysicalDrive 2>&1
    } catch
    {
        Write-Error "Failed to run wsl --mount: $_"
        exit 1
    }
}


Write-Host "Starting rmpc inside WSL..."
if ($Distro -ne "")
{
    & wsl -- rmpc
} else
{
    try
    {
        wsl -- rmpc
    } catch 
    {
        & $(wsl -- sudo pkill -p $(pidof "mpd"); mpd)
    } 
}

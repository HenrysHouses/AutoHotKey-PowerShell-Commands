$distroName = "archlinux"
$mountPath = "/mnt/CachyOs/@home"
$drivePath = "\\.\PHYSICALDRIVE0"

$probe = Start-Process wsl.exe `
    -ArgumentList "-d", $distroName, "-u", "root", "--", "test", "-d", $mountPath `
    -NoNewWindow `
    -Wait `
    -PassThru

if ($probe.ExitCode -eq 0) {
    return
}

Write-Host "Mount path '$mountPath' is not available in $distroName. Mounting $drivePath..."

sudo wsl.exe --mount $drivePath

if ($LASTEXITCODE -ne 0) {
    throw "Failed to mount $drivePath with 'wsl.exe --mount'."
}

$retryProbe = Start-Process wsl.exe `
    -ArgumentList "-d", $distroName, "-u", "root", "--", "test", "-d", $mountPath `
    -NoNewWindow `
    -Wait `
    -PassThru

if ($retryProbe.ExitCode -ne 0) {
    throw "Mounted $drivePath, but '$mountPath' is still not visible in $distroName."
}

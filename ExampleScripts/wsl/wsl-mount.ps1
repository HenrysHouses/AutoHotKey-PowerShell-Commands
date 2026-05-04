$drivePath = "\\.\PHYSICALDRIVE0"

$alive = Get-Process wsl -ErrorAction SilentlyContinue

if ($null -ne $alive)
{
    Write-Host "WSL is running, can not mount drive."
    exit 1
}

Start-Process -FilePath "sudo" -ArgumentList "-s", "wsl.exe", "--mount", $drivePath -WindowStyle Hidden

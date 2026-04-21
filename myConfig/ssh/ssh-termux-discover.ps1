param(
    [string]$ConfigPath = "",
    [int]$Port = 8022,
    [int]$TimeoutMs = 1000,
    [switch]$FullScan,
    [switch]$UpdateConfig
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "ssh-termux-common.ps1")

$ConfigPath = Get-SshTermuxConfigPath -ConfigPath $ConfigPath -ScriptRoot $PSScriptRoot
$config = Get-SshTermuxConfig -ConfigPath $ConfigPath -RequiredFields @("host", "port", "user")

$configuredHost = [string]$config.host
if (Test-ValidIpv4 -IpAddress $configuredHost) {
    Write-Host "Testing configured host ${configuredHost}:$Port ..."
    if (Test-TcpPort -HostName $configuredHost -Port $Port -TimeoutMs $TimeoutMs) {
        Write-Host "Configured host is reachable."
        $config.host = $configuredHost
        $config.port = $Port
        Save-SshTermuxConfig -Config $config -ConfigPath $ConfigPath
        Write-Host "Updated $ConfigPath with host $configuredHost and port $Port"
        exit 0
    }

    Write-Host "Configured host did not respond within ${TimeoutMs}ms."
}

$candidates = @(Find-SshTermuxHosts -Port $Port -TimeoutMs $TimeoutMs -FullScan:$FullScan -PreferredHost ([string]$config.host))

if (-not $candidates -or $candidates.Count -eq 0) {
    if (-not $FullScan) {
        Fail "No host responded on port $Port. Re-run with -FullScan for a full subnet scan."
    }

    Fail "No host responded on port $Port."
}

Write-Host "Found:"
$candidates | ForEach-Object { Write-Host "  $_" }

if ($candidates.Count -eq 1 -or $UpdateConfig) {
    $resolvedHost = Get-FirstCandidateHost -Candidates $candidates
    if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
        Fail "Could not resolve a host value from discovery results."
    }

    $config.host = $resolvedHost
    $config.port = $Port
    Save-SshTermuxConfig -Config $config -ConfigPath $ConfigPath
    Write-Host "Updated $ConfigPath with host $resolvedHost and port $Port"
} else {
    Write-Host "Multiple hosts responded. Re-run with -UpdateConfig after narrowing it down."
}

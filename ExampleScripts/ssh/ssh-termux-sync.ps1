param(
    [Parameter(Position = 0)]
    [string]$Source = "",

    [Parameter(Position = 1)]
    [string]$RemotePath = "",

    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "ssh-termux-common.ps1")

$ConfigPath = Get-SshTermuxConfigPath -ConfigPath $ConfigPath -ScriptRoot $PSScriptRoot
$config = Get-SshTermuxConfig -ConfigPath $ConfigPath -RequiredFields @("host", "port", "user", "remoteBase")
$config = Resolve-SshTermuxHost -Config $config -ConfigPath $ConfigPath -Port ([int]$config.port)

$wslExe = "C:\Windows\System32\wsl.exe"
if (-not (Test-Path -LiteralPath $wslExe)) {
    Fail "wsl.exe not found at $wslExe."
}

function Convert-ToWslPath([string]$WindowsPath) {
    $drive = $WindowsPath.Substring(0, 1).ToLowerInvariant()
    $rest = $WindowsPath.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
}

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Select-LocalPath -IncludeDirectories -IncludeCurrentDirectory
}

$resolvedSource = (Resolve-Path -LiteralPath $Source).Path

$sourceForRsync = $resolvedSource
if ((Get-Item -LiteralPath $resolvedSource).PSIsContainer -and -not $sourceForRsync.EndsWith('\')) {
    $sourceForRsync += '\'
}

$wslSource = Convert-ToWslPath $sourceForRsync

$remoteBase = [string]$config.remoteBase
$destination = if ([string]::IsNullOrWhiteSpace($RemotePath)) {
    $remoteBase.TrimEnd("/")
} elseif ($RemotePath.StartsWith("/")) {
    $RemotePath
} else {
    ($remoteBase.TrimEnd("/") + "/" + $RemotePath.TrimStart("/"))
}

$remoteTarget = "$($config.user)@$($config.host):$destination"
$wslSshExe = Convert-ToWslPath "C:\Windows\System32\OpenSSH\ssh.exe"
$sshCommand = "$wslSshExe -p $($config.port) -o StrictHostKeyChecking=accept-new"
$wslCommand = @(
    "rsync",
    "-av",
    "--progress",
    "-e", $sshCommand,
    "--",
    $wslSource,
    $remoteTarget
)

Write-Host "Syncing $resolvedSource"
Write-Host "Target  $remoteTarget"
Write-Host "Using   WSL rsync"

& $wslExe @wslCommand

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

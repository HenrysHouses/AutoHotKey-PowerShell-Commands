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

$scpExe = "C:\Windows\System32\OpenSSH\scp.exe"

if (-not (Test-Path -LiteralPath $scpExe)) {
    Fail "scp.exe not found at $scpExe."
}

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Select-LocalPath -IncludeFiles -IncludeDirectories -IncludeCurrentDirectory
}

$resolvedSource = (Resolve-Path -LiteralPath $Source).Path
$item = Get-Item -LiteralPath $resolvedSource

$remoteBase = [string]$config.remoteBase
$destination = if ([string]::IsNullOrWhiteSpace($RemotePath)) {
    $remoteBase.TrimEnd("/")
} elseif ($RemotePath.StartsWith("/")) {
    $RemotePath
} else {
    ($remoteBase.TrimEnd("/") + "/" + $RemotePath.TrimStart("/"))
}

$target = "$($config.user)@$($config.host):$destination"

$arguments = @(
    "-P", [string]$config.port,
    "-o", "StrictHostKeyChecking=accept-new"
)

if ($item.PSIsContainer) {
    $arguments += "-r"
}

$arguments += @(
    "--",
    $resolvedSource,
    $target
)

Write-Host "Pushing $resolvedSource"
Write-Host "Target  $target"

& $scpExe @arguments

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

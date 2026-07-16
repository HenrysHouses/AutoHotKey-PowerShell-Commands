param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$RemoteHost,

    [Parameter(Position = 1)]
    [string]$Source = "",

    [Parameter(Position = 2)]
    [string]$RemotePath = ""
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

$scpExe = "C:\Windows\System32\OpenSSH\scp.exe"

if (-not (Test-Path -LiteralPath $scpExe)) {
    Fail "scp.exe not found at $scpExe."
}

if ([string]::IsNullOrWhiteSpace($Source)) {
    Fail "Source path required as second parameter."
}

$expandedSource = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
$resolvedSource = (Resolve-Path -LiteralPath $expandedSource).Path
$item = Get-Item -LiteralPath $resolvedSource

if ([string]::IsNullOrWhiteSpace($RemotePath)) {
    $RemotePath = "."
}

$RemotePath = $RemotePath.Replace('\', '/')

$target = "$RemoteHost`:$RemotePath"

$arguments = @(
    "-o", "StrictHostKeyChecking=accept-new",
    "-F", "nul"
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

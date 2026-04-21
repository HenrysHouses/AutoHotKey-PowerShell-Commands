param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Command,

    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "ssh-termux-common.ps1")

$ConfigPath = Get-SshTermuxConfigPath -ConfigPath $ConfigPath -ScriptRoot $PSScriptRoot
$config = Get-SshTermuxConfig -ConfigPath $ConfigPath -RequiredFields @("host", "port", "user")
$config = Resolve-SshTermuxHost -Config $config -ConfigPath $ConfigPath -Port ([int]$config.port)

$sshExe = "C:\Windows\System32\OpenSSH\ssh.exe"
if (-not (Test-Path -LiteralPath $sshExe)) {
    Fail "ssh.exe not found at $sshExe."
}

$arguments = @(
    "-p", [string]$config.port,
    "-o", "StrictHostKeyChecking=accept-new",
    "$($config.user)@$($config.host)"
)

if ($Command -and $Command.Count -gt 0) {
    $arguments += ($Command -join " ")
}

Write-Host "Connecting to $($config.user)@$($config.host):$($config.port)"

& $sshExe @arguments

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

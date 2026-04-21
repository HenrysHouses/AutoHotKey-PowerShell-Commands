param(
    [string]$ConfigPath = "",
    [string]$KeyPath = "$HOME\.ssh\id_ed25519"
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

$publicKeyPath = "$KeyPath.pub"

if (-not (Test-Path -LiteralPath $publicKeyPath)) {
    $sshKeygenExe = "C:\Windows\System32\OpenSSH\ssh-keygen.exe"
    if (-not (Test-Path -LiteralPath $sshKeygenExe)) {
        Fail "ssh-keygen.exe not found at $sshKeygenExe."
    }

    Write-Host "Creating SSH key at $KeyPath"
    & $sshKeygenExe -t ed25519 -f $KeyPath -N ""
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$publicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($publicKey)) {
    Fail "Public key is empty: $publicKeyPath"
}

$remoteCommand = @(
    "mkdir -p ~/.ssh",
    "chmod 700 ~/.ssh",
    "touch ~/.ssh/authorized_keys",
    "grep -qxF '$publicKey' ~/.ssh/authorized_keys || printf '%s\n' '$publicKey' >> ~/.ssh/authorized_keys",
    "chmod 600 ~/.ssh/authorized_keys"
) -join "; "

Write-Host "Installing $publicKeyPath on $($config.user)@$($config.host):$($config.port)"

& $sshExe `
    "-p" [string]$config.port `
    "-o" "StrictHostKeyChecking=accept-new" `
    "$($config.user)@$($config.host)" `
    $remoteCommand

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Key installed."

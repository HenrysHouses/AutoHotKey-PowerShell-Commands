[CmdletBinding()]
param(
    [string]$Command,
    [string]$Name,
    [string]$PipeName = "PWSH_COMMAND_PIPE",
    [switch]$Restart,
    [switch]$Help
)

if ($Help)
{
    Write-Host "Usage: pwsh-msg.ps1 -Command <String> [-Name <String>] [-PipeName <String>] [-Restart] [-Help]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Command <Str>   The PowerShell command or script block to execute on the daemon. `n                   Requesting an identical command will automatically cancel the command that is running instead of executing a copy. Essentially a toggle."
    Write-Host "  -Cancel          Cancels the sent command if it is running. (will not start any executions)"
    Write-Host "  -Restart         Restarts the sent command if it is running. (cancels the command then re-executes it)"
    Write-Host "  -Name <Str>      Optional name to identify the sender in daemon logs."
    Write-Host "  -PipeName <Str>  The name of the pipe to connect to (default: PWSH_COMMAND_PIPE)."
    Write-Host "  -Help            Show this help message."
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  This script is just a named pipe wrapper that helps sending commands to pipes which pwsh-pipe-daemons are listening to."
    Write-Host "  It is not so useful to use via external sources, but great for debugging, testing and other automation via powershell or shell scripting."
    Write-Host ""
    Write-Host "Note:"
    Write-Host "  If you are looking to send messages to the daemon from outside a terminal, use the pipe instead."
    Write-Host "  It will be faster than calling this script which needs need a shell instance to run, and without one, the caller will need to create one."
    Write-Host "  Which defeats the purpose of the daemon to begin with which is meant to skip this step."
    exit 0
}

$client = New-Object System.IO.Pipes.NamedPipeClientStream(
    ".",
    $PipeName,
    [System.IO.Pipes.PipeDirection]::Out
)

$client.Connect()

$writer = New-Object System.IO.StreamWriter($client)
$writer.AutoFlush = $true

# Auto-detect SSH session
$sshSession = $null
if (-not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION))
{
    $parts = $env:SSH_CONNECTION -split ' '
    if ($parts.Count -ge 1)
    {
        $sshSession = "ssh:$($parts[0])"
    }
} elseif (-not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT))
{
    $parts = $env:SSH_CLIENT -split ' '
    if ($parts.Count -ge 1)
    {
        $sshSession = "ssh:$($parts[0])"
    }
}

# Build final sender name
$finalName = $null
if ($sshSession)
{
    if ($Name)
    {
        # If Name is provided, add SSH session if not already present
        if ($Name -notmatch [regex]::Escape($sshSession))
        {
            $finalName = "$sshSession | $Name"
        } else
        {
            $finalName = $Name
        }
    } else
    {
        # If no Name, use just the SSH session
        $finalName = $sshSession
    }
} else
{
    # No SSH session, use Name as-is
    $finalName = $Name
}

if ($Restart)
{
    $Command = "__RESTART__:$Command"
}

# Format message with sender name if available
if ($finalName)
{
    $message = "__FROM__:$finalName`n$Command"
} else
{
    $message = $Command
}

$writer.WriteLine($message)
$writer.WriteLine("Close Pipe")

try
{
    if ($writer)
    {
        $writer.Close()
    }
} finally
{
}

try
{
    if ($client)
    {
        $client.Close()
    }

} finally
{
}

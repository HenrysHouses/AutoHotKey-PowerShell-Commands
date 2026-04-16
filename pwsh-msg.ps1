[CmdletBinding()]
param(
    [string]$Command,
    [string]$Name,
    [string]$PipeName = "PWSH_COMMAND_PIPE",
    [switch]$Restart
)

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

[CmdletBinding()]
param(
    [string]$Commamd,
    [string]$Name
)

$pipeName = "PWSH_COMMAND_PIPE"

$client = New-Object System.IO.Pipes.NamedPipeClientStream(
    ".",
    $pipeName,
    [System.IO.Pipes.PipeDirection]::Out
)

$client.Connect()

$writer = New-Object System.IO.StreamWriter($client)
$writer.AutoFlush = $true

# Format message with sender name if provided
if ($Name) {
    $message = "__FROM__:$Name`n$Commamd"
} else {
    $message = $Commamd
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

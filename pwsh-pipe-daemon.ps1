$pipeName = "PWSH_COMMAND_PIPE"
$previousInvoke = ""
$previousTime = ""
$pipe = $nul
$closed = $false

$powerShellInstances = @{}
$activeCommands = @{}
$instanceCount = 0
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$runspacePool.Open()

$cancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
$token = $cancellationTokenSource.Token

Write-Host "[Daemon] Listening on pipe '$pipeName'`n"
Write-Host "[Time Stamp] - [Event Log]"
Write-Host "----------------------------------------------------"

function CreatePipe()
{
    $pipe = [System.IO.Pipes.NamedPipeServerStream]::new(
        $pipeName,
        [System.IO.Pipes.PipeDirection]::In,
        5,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous
    )
    return $pipe
}

try
{
    $pipe = CreatePipe

    while ($true)
    {
        try
        {
            $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
            Write-Host "$time - [Daemon] Waiting For Connection"

            $connectTask = $pipe.WaitForConnectionAsync()
            while (-not $connectTask.IsCompleted)
            {
                Start-Sleep -Milliseconds 100
            }

            $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
            Write-Host "$time - [Messager] Connected"
            $reader = [System.IO.StreamReader]::new($pipe)

            while ($pipe)
            {
                if (-not $pipe.IsConnected)
                {
                    if ($pipe)
                    {
                        $pipe.Dispose()
                    }
                    if ($reader)
                    {
                        $reader.Close()
                    }
                    $pipe = CreatePipe
                    break
                }

                $buffer = New-Object byte[] 1024
                $readTask = $pipe.ReadAsync($buffer, 0, $buffer.Length, $token)

                while (-not $readTask.Wait(10, $token))
                {
                    $completedCommands = $activeCommands.GetEnumerator() |
                        Where-Object { $_.Value.AsyncResult.IsCompleted } |
                        ForEach-Object { $_.Key }

                    foreach ($cmd in $completedCommands)
                    {
                        $time = [DateTime]::UtcNow
                        $timeFormatted = $time.ToString("HH:mm:ss.fff")
                        $startedTime = [DateTime]::ParseExact($activeCommands[$cmd].StartTime, "HH:mm:ss.fff", $null)
                        $duration = $time - $startedTime
                        $durationFormatted = $duration.ToString("hh\:mm\:ss\.fff")

                        $results = $activeCommands[$cmd].PowerShell.EndInvoke($activeCommands[$cmd].AsyncResult)
                        if ($results)
                        {
                            Write-Host "Results for '$cmd':"
                            $results | ForEach-Object { Write-Host "  $_" }
                        }
                        Write-Host "$timeFormatted - [Daemon] Completed Invocation: $cmd, duration: $durationFormatted"
                        $activeCommands.Remove($cmd)
                    }

                    if ($powerShellInstances.Count -gt 2)
                    {
                        $instancesToRemove = $powerShellInstances.Count - 2
                        $idleInstances = $powerShellInstances.GetEnumerator() |
                            Where-Object { -not $activeCommands.ContainsKey($_.Key) } |
                            Select-Object -First $instancesToRemove

                        foreach ($instance in $idleInstances)
                        {
                            $instance.Value.Dispose()
                            $powerShellInstances.Remove($instance.Key)
                            $instanceCount--
                        }
                    }
                }

                if ($readTask.IsCompleted)
                {
                    $bytesRead = $readTask.Result
                }

                if ($bytesRead -gt 0)
                {
                    $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)

                    $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
                    $currentMessage = "$time - $message"

                    if ($message -and $currentMessage -ne $previousInvoke)
                    {
                        $previousTime = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
                        $previousInvoke = "$previousTime - $message"

                        if ($activeCommands.ContainsKey($message))
                        {
                            $time = [DateTime]::UtcNow
                            $timeFormatted = $time.ToString("HH:mm:ss.fff")
                            $startedTime = [DateTime]::ParseExact($activeCommands[$message].StartTime, "HH:mm:ss.fff", $null)
                            $duration = $time - $startedTime
                            $durationFormatted = $duration.ToString("hh\:mm\:ss\.fff")
                            Write-Host "$timeFormatted - [Daemon] Cancelled Invocation: $message, duration: $durationFormatted"

                            $activeCommands[$message].PowerShell.Stop()
                            $activeCommands.Remove($message)
                        } else
                        {
                            $ps = $null
                            if ($powerShellInstances.Count -lt 2)
                            {
                                $ps = [PowerShell]::Create()
                                $ps.RunspacePool = $runspacePool
                                $powerShellInstances[$message] = $ps
                                $instanceCount++
                            } else
                            {
                                $ps = $powerShellInstances.GetEnumerator() |
                                    Where-Object { -not $activeCommands.ContainsKey($_.Key) } |
                                    Select-Object -First 1 -ExpandProperty Value
                            }

                            if ($message -eq "Close Pipe")
                            {
                                $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
                                Write-Host "$time - [Messager] Disconnected"
                                $closed = $true

                                if ($pipe)
                                {
                                    $pipe.Dispose()
                                }
                                if ($reader)
                                {
                                    $reader.Close()
                                }
                                $pipe = CreatePipe
                                break
                            } else
                            {
                                if (-not $ps)
                                {
                                    $ps = [PowerShell]::Create()
                                    $ps.RunspacePool = $runspacePool
                                    $powerShellInstances[$message] = $ps
                                    $instanceCount++
                                }

                                $ps.Commands.Clear()
                                $ps.AddScript($message) | Out-Null

                                $input = [System.Management.Automation.PSDataCollection[object]]::new()
                                $settings = New-Object System.Management.Automation.PSInvocationSettings
                                $settings.AddToHistory = $true

                                Write-Host "$previousTime - [Daemon] Invoking: '$message'"
                                $asyncResult = $ps.BeginInvoke($input, $settings, $null, $null)

                                $activeCommands[$message] = @{
                                    PowerShell = $ps
                                    AsyncResult = $asyncResult
                                    StartTime = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
                                }
                            }
                        }
                    } else
                    {
                        Write-Host "$time - [Daemon] Skipped Identical Command"
                    }
                }
            }
        } finally
        {
            if (-not $closed)
            {
                $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
                Write-Host "$time - [Messager] Lost Connection"

            }

            if (-not $pipe)
            {
                if ($pipe)
                {
                    $pipe.Dispose()
                }
                if ($reader)
                {
                    $reader.Close()
                }

                $pipe = CreatePipe
            }
            $closed = $false
        }
    }
} finally
{
    $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
    Write-Host "$time - [Daemon] Killing Process"
    if ($pipe)
    {
        $pipe.Dispose()
    }
    if ($reader)
    {
        $reader.Close()
    }
    $cancellationTokenSource.Dispose()

    foreach ($cmd in $activeCommands.Keys)
    {
        $activeCommands[$cmd].PowerShell.Stop()
        $activeCommands[$cmd].PowerShell.Dispose()
    }
    $runspacePool.Dispose()
}

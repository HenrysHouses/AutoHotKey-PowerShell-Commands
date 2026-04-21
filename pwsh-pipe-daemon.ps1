param(
    [switch]$List,
    [int]$Kill = -1,
    [string]$PipeName = "PWSH_COMMAND_PIPE"
)

Import-Module Microsoft.PowerShell.Utility  
Import-Module Microsoft.PowerShell.Management

$pipeName = $PipeName
$powerShellInstances = @{}
$activeCommands = @{}

# Handle -List parameter to show running instances
if ($List)
{
    $daemonTempDir = Join-Path $env:TEMP 'pwsh-daemon-instances'
    
    if (-not (Test-Path $daemonTempDir))
    {
        Write-Host "[INFO] No pwsh-daemon instances found"
        exit 0
    }
    
    $daemonFiles = Get-ChildItem -Path $daemonTempDir -Filter "daemon_*.json" -ErrorAction SilentlyContinue
    
    if (-not $daemonFiles)
    {
        Write-Host "[INFO] No pwsh-daemon instances found"
        exit 0
    }
    
    Write-Host "[Daemon Instances]`n"
    
    $instances = @()
    foreach ($file in $daemonFiles)
    {
        try
        {
            $content = Get-Content -Path $file.FullName | ConvertFrom-Json
            $proc = Get-Process -Id $content.PID -ErrorAction SilentlyContinue
            
            if ($proc)
            {
                # Process is still running
                $instances += $content

                if ($content.PoolSize -lt 1)
                {
                    $Connector = "└──"
                } else
                {
                    $Connector = "└┬─"
                }

                Write-Host "DEMON: $($content.WindowTitle) | Created: $($content.CreatedAt)" -ForegroundColor Cyan
                Write-Host "$Connector $($content.PoolSize)/5 instances | Commands: $($content.RunningCommands.Count)" -ForegroundColor Gray
                
                # Show all instances in the pool
                if ($content.Instances -and $content.Instances.Count -gt 0)
                {
                    # foreach ($inst in $content.Instances)
                    for ($index = 0; $index -lt $content.Instances.Count; $index++)
                    {
                        $inst = $content.instances[$index]
                        $status = "IDLE"
                        if ($inst.IsActive)
                        { $status = "ACTIVE" 
                        } elseif ($inst.IsBusy)
                        { $status = "BUSY" 
                        } elseif ($inst.IsDirty)
                        { $status = "DIRTY" 
                        }
                        
                        $color = if ($inst.IsActive)
                        { "Green" 
                        } elseif ($inst.IsBusy)
                        { "Yellow" 
                        } elseif ($inst.IsDirty)
                        { "Red" 
                        } else
                        { "Gray" 
                        }

                        if ($index -lt $content.instances.Count-1)
                        {
                            if ($content.instances[$index].Command)
                            {
                                $Connector =    "├┬─"
                                $CmdConnector = "│└──"
                            }
                            else
                            {
                                $Connector =    "├──"
                                $CmdConnector = ""
                            }
                        } else
                        {
                            if ($content.instances[$index].Command)
                            {
                                $Connector =    "└┬─"
                                $CmdConnector = " └──"
                            }
                            else
                            {
                                $Connector =    "└──"
                                $CmdConnector = ""
                            }
                        }

                        $displayCommand = if ($inst.Command)
                        { " `n $CmdConnector Cmd: $($inst.Command)" 
                        } else
                        { " " 
                        }
                        Write-Host " $Connector[$status] $($inst.Id)$displayCommand" -ForegroundColor $color
                    }
                }
            } else
            {
                # Process is dead - get its state and clean up
                Write-Host "PID: $($content.PID) | $($content.WindowTitle) | State: DEAD | Created: $($content.CreatedAt)" -ForegroundColor Red
                if ($content.Instances -and $content.Instances.Count -gt 0)
                {
                    Write-Host "  Orphaned instances: $($content.Instances.Count)" -ForegroundColor Yellow
                }
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        } catch
        {
            Write-Host "[WARNING] Failed to parse: $($file.Name)" -ForegroundColor Yellow
        }
    }
    
    if ($instances.Count -eq 0)
    {
        Write-Host "[INFO] No running pwsh-daemon instances found`n"
        exit 0
    }
    
    Write-Host "`nTotal: $($instances.Count) running instance(s)`n"
    exit 0
}

# Handle -Kill parameter to gracefully terminate a daemon instance
if ($Kill -ge 0)
{
    $daemonTempDir = Join-Path $env:TEMP 'pwsh-daemon-instances'
    $daemonTempFile = Join-Path $daemonTempDir "daemon_$Kill.json"
    
    # Verify the temp file exists and the process is running
    if (Test-Path $daemonTempFile)
    {
        $daemonData = Get-Content -Path $daemonTempFile | ConvertFrom-Json
        $proc = Get-Process -Id $Kill -ErrorAction SilentlyContinue
        if ($proc)
        {
            Write-Host "[INFO] Killing pwsh-daemon instance PID: $Kill" -ForegroundColor Yellow
            
            # Kill all spawned instances first
            if ($daemonData.SpawnedInstances -and $daemonData.SpawnedInstances.Count -gt 0)
            {
                Write-Host "[INFO] Killing $($daemonData.SpawnedInstances.Count) spawned PowerShell instance(s)..." -ForegroundColor Yellow
                foreach ($instanceId in $daemonData.SpawnedInstances)
                {
                    Write-Host "  --> Terminating runspace: $instanceId" -ForegroundColor Gray
                }
            }
            
            $proc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            
            # Clean up temp file
            Remove-Item -Path $daemonTempFile -Force -ErrorAction SilentlyContinue
            
            # Verify it was killed
            if (-not (Get-Process -Id $Kill -ErrorAction SilentlyContinue))
            {
                Write-Host "[OK] pwsh-daemon instance $Kill successfully terminated" -ForegroundColor Green
            } else
            {
                Write-Host "[ERROR] Failed to terminate pwsh-daemon instance $Kill" -ForegroundColor Red
                exit 1
            }
        } else
        {
            Write-Host "[INFO] Process $Kill not running, cleaning up stale temp file" -ForegroundColor Yellow
            Remove-Item -Path $daemonTempFile -Force -ErrorAction SilentlyContinue
        }
    } else
    {
        Write-Host "[ERROR] No daemon instance found with PID: $Kill" -ForegroundColor Red
        exit 1
    }
    
    exit 0
}

$Host.UI.RawUI.WindowTitle = 'pwsh-pipe-daemon'
[Console]::Title = 'pwsh-pipe-daemon'

# Check for existing running instances using temp files
$daemonTempDir = Join-Path $env:TEMP 'pwsh-daemon-instances'

if (Test-Path $daemonTempDir)
{
    $daemonFiles = Get-ChildItem -Path $daemonTempDir -Filter "daemon_*.json" -ErrorAction SilentlyContinue
    foreach ($file in $daemonFiles)
    {
        try
        {
            $content = Get-Content -Path $file.FullName | ConvertFrom-Json
            if ($content.PipeName -eq $pipeName -and $content.PID -ne $PID)
            {
                $proc = Get-Process -Id $content.PID -ErrorAction SilentlyContinue
                if ($proc)
                {
                    Write-Host "[ERROR] Another instance of pwsh-pipe-daemon is already running with pipe: $pipeName" -ForegroundColor Red
                    Write-Host "  PID: $($content.PID), Created: $($content.CreatedAt)" -ForegroundColor Red
                    Write-Host "  If the previous instance crashed, wait a moment and try again." -ForegroundColor Yellow
                    exit 1
                } else
                {
                    # Process is dead, clean up stale file
                    Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        } catch
        { 
        }
    }
}

$LogDir = Join-Path $env:LOCALAPPDATA 'wlines'
$LogPath = Join-Path $LogDir 'pwsh-pipe-daemon.log'
if (-not (Test-Path $LogDir))
{
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
Start-Transcript -Path $LogPath -Append | Out-Null

# Create temp file to track this daemon instance
$daemonTempDir = Join-Path $env:TEMP 'pwsh-daemon-instances'
if (-not (Test-Path $daemonTempDir))
{
    New-Item -ItemType Directory -Path $daemonTempDir -Force | Out-Null
}
$daemonTempFile = Join-Path $daemonTempDir "daemon_$PID.json"

function UpdateDaemonTempFile
{
    # Update temp file with all pool instances and active command info
    $runningCommands = @($activeCommands.Keys | Where-Object { $_ })  # Filter out nulls
    
    # Build list of all instances with their status
    $allInstances = @()
    foreach ($key in $powerShellInstances.Keys)
    {
        $instance = $powerShellInstances[$key]
        
        # Find if this instance is running a command
        $activeEntry = $activeCommands.GetEnumerator() | Where-Object { $_.Value.PowerShell.InstanceId -eq $key }
        $cmdString = if ($activeEntry)
        { $activeEntry.Key 
        } else
        { $null 
        }

        $allInstances += @{
            Id = $key
            IsBusy = $instance.IsBusy
            IsDirty = $instance.IsDirty
            IsActive = $null -ne $activeEntry
            Command = $cmdString
        }
    }
    
    $metadata = @{
        PID = $PID
        PipeName = $pipeName
        ProcessName = 'pwsh-pipe-daemon'
        WindowTitle = $Host.UI.RawUI.WindowTitle
        CreatedAt = [DateTime]::UtcNow.ToString("o")
        PoolSize = $powerShellInstances.Count
        Instances = $allInstances
        RunningCommands = $runningCommands
    }
    $jsonStr = $metadata | ConvertTo-Json -Depth 3
    if (-not $jsonStr)
    {
        $jsonStr = '{}' 
    }
    Set-Content -Path $daemonTempFile -Value $jsonStr -Force
}

$previousInvoke = ""
$previousTime = ""
$pipe = $null
$closed = $false

# Update window title with pipe name and status
[Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID"
$Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID"

$instanceCount = 0
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$runspacePool.Open()

# Now initialize the temp file after $activeCommands exists
UpdateDaemonTempFile

$cancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
$token = $cancellationTokenSource.Token

$bannerWidth = 55
$col1Width = 19
$col2Width = 35

$header = "PowerShell Pipe Daemon"
$hPad = [math]::Floor(($bannerWidth - $header.Length) / 2)
$hLeft = " " * $hPad
$hRight = " " * ($bannerWidth - $header.Length - $hPad)

$pipeLabel = " Listening On Pipe"
$pVal = " $pipeName"
$pRight = " " * [math]::Max(0, ($col2Width - $pVal.Length))

$pidLabel = " Daemon PID"
$pidVal = " $PID"
$pidRight = " " * [math]::Max(0, ($col2Width - $pidVal.Length))

Write-Host "╔$((New-Object String '═', $bannerWidth))╗"
Write-Host "║$hLeft$header$hRight║"
Write-Host "╟$((New-Object String '─', $col1Width))┬$((New-Object String '─', $col2Width))╢"
Write-Host "║$($pipeLabel.PadRight($col1Width))│$pVal$pRight║"
Write-Host "╟$((New-Object String '─', $col1Width))┼$((New-Object String '─', $col2Width))╢"
Write-Host "║$($pidLabel.PadRight($col1Width))│$pidVal$pidRight║"
Write-Host "╚$((New-Object String '═', $col1Width))╧$((New-Object String '═', $col2Width))╝ `n"
# Write-Host ""

Write-Host "[Time Stamp] - [Event Log]"
Write-Host "─────────────────────────────────────────────────────────"

function IdleUpdate
{
    $completedCommands = $activeCommands.GetEnumerator() |
        Where-Object { $_.Value.AsyncResult.IsCompleted } |
        ForEach-Object { $_.Key }

    foreach ($cmd in $completedCommands)
    {
        $time = [DateTime]::UtcNow
        $timeFormatted = $time.ToString("HH:mm:ss.fff")
        $startedTime = $activeCommands[$cmd].StartTime
        $duration = $time - $startedTime
        $durationString = Format-Duration $duration
        $instanceID = $activeCommands[$cmd].PowerShell.InstanceId
        $results = $activeCommands[$cmd].PowerShell.EndInvoke($activeCommands[$cmd].AsyncResult)
        if ($results)
        {
            Write-Host "$time - [Results] '$cmd':"
            $results | ForEach-Object { Write-Host "  $_" }
        }

        Write-Host "$timeFormatted - [INFO] Completed Invocation: '$cmd', duration: $durationString" -ForegroundColor Green
                        
        $instanceID = $activeCommands[$cmd].PowerShell.InstanceId
        if ($instanceID)
        {
            if ($powerShellInstances.Count -gt 0)
            {
                $powerShellInstances[$instanceID].IsBusy = $false
            }
        }

        if ($powerShellInstances[$instanceID].IsDirty -and -not $powerShellInstances[$instanceID].IsBusy)
        {
            $powerShellInstances[$instanceID].Shell.Dispose()
            $powerShellInstances.Remove($instanceID)
        }
        $activeCommands.Remove($cmd)
        
        # Update temp file after all state changes and command removal
        UpdateDaemonTempFile

        # Update window title based on remaining active commands
        try
        {
            if ($activeCommands.Count -eq 0)
            {
                # No more commands - return to idle state
                [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID"
                $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID"
            } elseif ($activeCommands.Count -eq 1)
            {
                # One command left - show it specifically
                $remainingCmd = $activeCommands.Keys | Select-Object -First 1
                [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $remainingCmd"
                $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $remainingCmd"
            } else
            {
                # Multiple commands still running - show count
                [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
                $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
            }
        } catch
        {
            # Silently ignore title update failures
            Write-Host "$time - [Warning] Failed to update window title on completion: $_"
        }
    }

    if ($powerShellInstances.Count -gt 5)
    {
        # Remove all instances over the limit (keep it at exactly 5)
        $excessCount = $powerShellInstances.Count - 5
        $idleInstances = $powerShellInstances.GetEnumerator() |
            Where-Object { -not $_.value.IsBusy } |
            Select-Object -First $excessCount
        
        foreach ($instance in $idleInstances)
        {
            $instance.Value.Shell.Dispose()
            $powerShellInstances.Remove($instance.Key)
            $instanceCount--
        }
        UpdateDaemonTempFile
    }
}

function CreatePipe
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

function Get-PowerShellInstance
{
    # Try to find an idle instance
    $ps = $powerShellInstances.Values | 
        Where-Object { -not $_.IsBusy -and -not $_.IsDirty } |
        Select-Object -First 1

    if (-not $ps)
    {
        # No idle instances found, create a new one
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $runspacePool
        $powerShellInstances[$ps.InstanceId] = @{
            Shell = $ps
            IsBusy = $true
            IsDirty = $false
        }
        $instanceCount++
        UpdateDaemonTempFile
    } else
    {
        # Found idle instance, mark it as busy and extract Shell
        $powerShellInstances[$ps.Shell.InstanceId].IsBusy = $true
        UpdateDaemonTempFile
        $ps = $ps.Shell
    }
    return $ps
}

function Format-Duration([TimeSpan]$ts)
{
    $parts = @()
    $totalHours = [int]($ts.TotalHours)
    if ($ts.Hours -gt 0 -or $ts.Days -gt 0)
    {
        $parts += "$totalHours`h"
    }
    if ($ts.Minutes -gt 0 -or $totalHours -gt 0)
    {
        $parts += "$($ts.Minutes)`m"
    }
    # seconds with milliseconds: format "S.mmm"
    $secs = '{0:0}.{1:000}' -f $ts.Seconds, $ts.Milliseconds
    $parts += "$secs`s"
    return ($parts -join ' ')
}

function InvokeMessage
{
    param(
        [object]$powershell,
        [string]$msg
    )

    $powershell.Commands.Clear()
    $powershell.Streams.ClearStreams()
    $powershell.AddScript($msg) | Out-Null
    # Check if the command spawns a new process  
    if ($msg -match '&\s+pwsh|Start-Process')
    {  
        $powerShellInstances[$powershell.InstanceId].IsDirty = $true
    }
    $input = [System.Management.Automation.PSDataCollection[object]]::new()
    $settings = New-Object System.Management.Automation.PSInvocationSettings
    $settings.AddToHistory = $true

    # Display invocation with sender name if provided
    if ($senderName)
    {
        if ($senderName -imatch "ssh:")
        {
            Write-Host "$previousTime - [ACTION] Invoke requested by [$senderName]: '$msg'" -ForegroundColor Cyan
        } else
        {
            Write-Host "$previousTime - [ACTION] Invoke requested by [$senderName]: '$msg'" -ForegroundColor DarkCyan
        }
    } else
    {
        Write-Host "$previousTime - [ACTION] Invoking command: '$msg'" -ForegroundColor Blue
    }
                            
    # Track this command before updating title
    $asyncResult = $powershell.BeginInvoke($input, $settings, $null, $null)

    $activeCommands[$msg] = @{
        PowerShell = $powershell
        AsyncResult = $asyncResult
        StartTime = [DateTime]::UtcNow
    }
                            
    # Update temp file with new active command
    UpdateDaemonTempFile
                            
    # Update window title to show running command(s)
    # Only update if this is the only command, or show count if multiple
    try
    {
        if ($activeCommands.Count -eq 1)
        {
            # First command - show it specifically
            [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $msg"
            $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $msg"
        } elseif ($activeCommands.Count -gt 1)
        {
            # Multiple commands running - show count instead
            [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
            $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
        }
    } catch
    {
        # Silently ignore title update failures to prevent crashes
        Write-Host "[Warning] Failed to update window title: $_"
    }
}

try
{
    $pipe = CreatePipe

    while ($true)
    {
        try
        {
            $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
            # Write-Host "$time - [Daemon] Waiting For Connection"

            $connectTask = $pipe.WaitForConnectionAsync()
            while (-not $connectTask.IsCompleted)
            {
                Start-Sleep -Milliseconds 100
                IdleUpdate
            }

            $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
            # Write-Host "$time - [Messager] Connected"
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
                    IdleUpdate
                }

                if ($readTask.IsCompleted)
                {
                    $bytesRead = $readTask.Result
                }

                if ($bytesRead -gt 0)
                {
                    $rawMessage = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                    
                    # Extract sender name if present (before cleaning control characters)
                    $senderName = $null
                    $isRestart = $false

                    $pattern = '^(?:__FROM__:([^\r\n]+)[\r\n]+)?(?:__RESTART__:(?:\r?\n)?([\s\S]+)|([\s\S]+))$'

                    if ($rawMessage -match $pattern)
                    {
                        if ($matches[1])
                        { $senderName = $matches[1] 
                        }

                        if ($matches[2])
                        {
                            $isRestart = $true
                            $rawMessage = $matches[2]
                        } else
                        {
                            $rawMessage = $matches[3]
                        }

                        $rawMessage = $rawMessage.TrimStart("`r","`n"," ")
                        $message = [regex]::Replace($rawMessage, '[\p{C}]', '')
                    } else
                    {
                        # fallback: sanitize original
                        $message = [regex]::Replace($rawMessage, '[\p{C}]', '')
                    }

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
                            $startedTime = $activeCommands[$message].StartTime
                            $duration = $time - $startedTime
                            $durationString = Format-Duration $duration

                            Write-Host "$timeFormatted - [ACTION] Cancelled Invocation: $message, duration: $durationString" -ForegroundColor DarkYellow

                            $cancelledPs = $activeCommands[$message].PowerShell.InstanceId
                            $powerShellInstances[$cancelledPs].IsBusy = $false
                            $activeCommands[$message].PowerShell.Stop()
                            $activeCommands.Remove($message)

                            UpdateDaemonTempFile

                            if ($isRestart)
                            {
                                if ($powerShellInstances[$cancelledPs].IsDirty)
                                {
                                    $powerShellInstances[$cancelledPs].Shell.Dispose()
                                    $powerShellInstances.Remove($cancelledPs)
                                }
                                $ps = Get-PowerShellInstance
                                InvokeMessage -powershell $ps -msg $message
                            } else
                            {
                            }
                        } elseif ($message -eq "Close Pipe")
                        {
                            $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
                            # Write-Host "$time - [Messager] Disconnected"
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
                            $ps = Get-PowerShellInstance
                            InvokeMessage -powershell $ps -msg $message
                        }
                    } else
                    {
                        Write-Host "$time - [INFO] Skipped Identical Command"
                    }
                }
            }
        } catch 
        {
            $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
            Write-Host "$time - [ERROR] Exception Message:`n   $($_.Exception.Message)" -ForegroundColor Red
        } finally
        {
            $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
            if ($_.Exception -and $_.Exception.Message)
            {
                Write-Host "$time - [ERROR] Named pipe broke due to an error: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "$time - [INFO] Recreating pipe..." -ForegroundColor Yellow
            } elseif (-not $closed)
            {
                Write-Host "$time - [INFO] Connection closed. Listening for new connection..." -ForegroundColor Gray
            }

            if ($null -eq $pipe -or -not $pipe.IsConnected)
            {
                try
                {
                    if ($pipe)
                    { $pipe.Dispose() 
                    }
                    if ($reader)
                    { $reader.Dispose() 
                    }
                } catch
                { 
                }
                $pipe = CreatePipe
            }
            $closed = $false
        }
    }
} catch
{
    $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
    Write-Host "$time - [ERROR] Could not recover from fatal error. Exception Message:`n   $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally
{
    $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
    Write-Host "$time - [DAEMON] Killing Process"
    [Console]::Title = "pwsh-pipe-daemon [DEAD] - PID: $PID"
    
    # Clean up temp file tracking this instance
    if (Test-Path $daemonTempFile)
    {
        Remove-Item -Path $daemonTempFile -Force -ErrorAction SilentlyContinue
    }
    
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
    Stop-Transcript | Out-Null
}

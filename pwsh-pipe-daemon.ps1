param(
    [switch]$List,
    [int]$Kill = -1
)

Import-Module Microsoft.PowerShell.Utility  
Import-Module Microsoft.PowerShell.Management

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
                Write-Host "PID: $($content.PID) | $($content.WindowTitle) | Created: $($content.CreatedAt)" -ForegroundColor Cyan
                Write-Host "  Pool: $($content.PoolSize)/5 instances | Commands: $($content.RunningCommands.Count)" -ForegroundColor Gray
                
                # Show all instances in the pool
                if ($content.Instances -and $content.Instances.Count -gt 0)
                {
                    foreach ($inst in $content.Instances)
                    {
                        $status = "idle"
                        if ($inst.IsActive) { $status = "ACTIVE" }
                        elseif ($inst.IsBusy) { $status = "busy" }
                        elseif ($inst.IsDirty) { $status = "dirty" }
                        
                        $color = if ($inst.IsActive) { "Green" } elseif ($inst.IsBusy) { "Yellow" } elseif ($inst.IsDirty) { "Red" } else { "Gray" }
                        Write-Host "    [$status] $($inst.Id)" -ForegroundColor $color
                    }
                }
            }
            else
            {
                # Process is dead - get its state and clean up
                Write-Host "PID: $($content.PID) | $($content.WindowTitle) | State: DEAD | Created: $($content.CreatedAt)" -ForegroundColor Red
                if ($content.Instances -and $content.Instances.Count -gt 0)
                {
                    Write-Host "  Orphaned instances: $($content.Instances.Count)" -ForegroundColor Yellow
                }
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        catch
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
            }
            else
            {
                Write-Host "[ERROR] Failed to terminate pwsh-daemon instance $Kill" -ForegroundColor Red
                exit 1
            }
        }
        else
        {
            Write-Host "[INFO] Process $Kill not running, cleaning up stale temp file" -ForegroundColor Yellow
            Remove-Item -Path $daemonTempFile -Force -ErrorAction SilentlyContinue
        }
    }
    else
    {
        Write-Host "[ERROR] No daemon instance found with PID: $Kill" -ForegroundColor Red
        exit 1
    }
    
    exit 0
}

$Host.UI.RawUI.WindowTitle = 'pwsh-pipe-daemon'
[Console]::Title = 'pwsh-pipe-daemon'

# Get the script path for singleton check
$scriptPath = $PSScriptRoot

# Singleton check - ensure only one instance of this daemon is running
$daemonProcessName = 'pwsh'
$currentProcessId = $PID

# Check for existing running instances
$existingInstances = Get-Process -Name $daemonProcessName -ErrorAction SilentlyContinue | Where-Object {
    $proc = $_
    try
    {
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
        $cmdLine -and $cmdLine -match ([regex]::Escape($scriptPath)) -and $proc.Id -ne $currentProcessId
    } catch
    {
        $false
    }
}

# If an instance exists, check if it actually exited gracefully
if ($existingInstances)
{
    $logDir = Join-Path $env:LOCALAPPDATA 'wlines'
    $logPath = Join-Path $logDir 'pwsh-pipe-daemon.log'
    
    $cleanExit = $false
    if (Test-Path $logPath)
    {
        # Check if the log shows a clean shutdown from the last run
        $lastLines = Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue
        $cleanExit = $lastLines | Where-Object { $_ -match '\[Daemon\] Killing Process' }
    }
    
    if ($cleanExit)
    {
        # Previous instance shut down cleanly but process still exists - allow restart
        Write-Host "[INFO] Previous instance shutdown detected (found 'Killing Process' in logs)." -ForegroundColor Yellow
        Write-Host "[INFO] Proceeding with restart..." -ForegroundColor Yellow
    } else
    {
        # Previous instance is still running or crashed without clean shutdown
        $existingInstances | ForEach-Object {
            if ($_.CommandLine -eq "pwsh -Command pwsh-pipe-daemon")
            {
                Write-Host "[ERROR] Another instance of pwsh-pipe-daemon is already running:" -ForegroundColor Red
                Write-Host "  PID: $($_.Id), Command: $($_.CommandLine)" -ForegroundColor Red
                Write-Host "`nIf the previous instance crashed, wait a moment and try again." -ForegroundColor Yellow
                Write-Host "Or kill it manually: Stop-Process -Id $($_.Id) -Force`n" -ForegroundColor Yellow
            }
        }
        exit 1
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

function UpdateDaemonTempFile()
{
    # Update temp file with all pool instances and active command info
    $runningCommands = @($activeCommands.Keys | Where-Object { $_ })  # Filter out nulls
    
    # Build list of all instances with their status
    $allInstances = @()
    foreach ($key in $powerShellInstances.Keys)
    {
        $instance = $powerShellInstances[$key]
        $isActive = $activeCommands.Values | Where-Object { $_.PowerShell.InstanceId -eq $key }
        $allInstances += @{
            Id = $key
            IsBusy = $instance.IsBusy
            IsDirty = $instance.IsDirty
            IsActive = $isActive -ne $null
        }

    }
    
    $metadata = @{
        PID = $PID
        ProcessName = 'pwsh-pipe-daemon'
        WindowTitle = $Host.UI.RawUI.WindowTitle
        CreatedAt = [DateTime]::UtcNow.ToString("o")
        ScriptPath = $scriptPath
        PoolSize = $powerShellInstances.Count
        Instances = $allInstances
        RunningCommands = $runningCommands
    }
    $jsonStr = $metadata | ConvertTo-Json -Depth 3
    if (-not $jsonStr) {
        $jsonStr = '{}' 
    }
    Set-Content -Path $daemonTempFile -Value $jsonStr -Force
}

$pipeName = "PWSH_COMMAND_PIPE"
$previousInvoke = ""
$previousTime = ""
$pipe = $nul
$closed = $false

# Update window title with pipe name and status
[Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID"
$Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID"

$powerShellInstances = @{}
$activeCommands = @{}
$instanceCount = 0
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$runspacePool.Open()

# Now initialize the temp file after $activeCommands exists
UpdateDaemonTempFile

$cancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
$token = $cancellationTokenSource.Token

Write-Host "[Daemon] Listening on pipe '$pipeName'`n"
Write-Host "[Time Stamp] - [Event Log]"
Write-Host "----------------------------------------------------"

function IdleUpdate()
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

        $instanceID = $activeCommands[$cmd].PowerShell.InstanceId
        $results = $activeCommands[$cmd].PowerShell.EndInvoke($activeCommands[$cmd].AsyncResult)
        if ($results)
        {
            Write-Host "$time - [Results] '$cmd':"
            $results | ForEach-Object { Write-Host "  $_" }
        }

        Write-Host "$timeFormatted - [Daemon] Completed Invocation: '$cmd', duration: $durationFormatted"
                        
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
            Write-Host "Removed bad powershell instance"
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
            Write-Host "[Warning] Failed to update window title on completion: $_"
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
            Write-Host "Removing excess idle instance: $($instance.Key)"
            $instance.Value.Shell.Dispose()
            $powerShellInstances.Remove($instance.Key)
            $instanceCount--
        }
        UpdateDaemonTempFile
    }
}

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
                IdleUpdate
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
                    if ($rawMessage -match '__FROM__:([^\r\n]+)[\r\n]+(.+)') {
                        $senderName = $matches[1]
                        $rawMessage = $matches[2]
                    }
                    
                    $message = [regex]::Replace($rawMessage, '[\p{C}]', '')

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

                            $cancelledPs = $activeCommands[$message].PowerShell.InstanceId
                            $powerShellInstances[$cancelledPs].IsBusy = $false
                            $activeCommands[$message].PowerShell.Stop()
                            $activeCommands.Remove($message)
                        } elseif ($message -eq "Close Pipe")
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

                            $ps.Commands.Clear()
                            $ps.Streams.ClearStreams()
                            $ps.AddScript($message) | Out-Null
                            # Check if the command spawns a new process  
                            if ($message -match '&\s+pwsh|Start-Process')
                            {  
                                $powerShellInstances[$ps.InstanceId].IsDirty = $true
                            }
                            $input = [System.Management.Automation.PSDataCollection[object]]::new()
                            $settings = New-Object System.Management.Automation.PSInvocationSettings
                            $settings.AddToHistory = $true

                            # Display invocation with sender name if provided
                            if ($senderName) {
                                Write-Host "$previousTime - [Daemon] Invoking from [$senderName]: '$message'"
                            } else {
                                Write-Host "$previousTime - [Daemon] Invoking: '$message'"
                            }
                            
                            # Track this command before updating title
                            $asyncResult = $ps.BeginInvoke($input, $settings, $null, $null)

                            $activeCommands[$message] = @{
                                PowerShell = $ps
                                AsyncResult = $asyncResult
                                StartTime = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
                            }
                            
                            # Update window title to show running command(s)
                            # Only update if this is the only command, or show count if multiple
                            try
                            {
                                if ($activeCommands.Count -eq 1)
                                {
                                    # First command - show it specifically
                                    [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $message"
                                    $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $message"
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
} catch
{
    $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
    Write-Host "$time - [Daemon] Could not recover from fatal error"
    Write-Host $_.Exception.Message
    exit 1
} finally
{
    $time = [DateTime]::UtcNow.ToString("HH:mm:ss.fff")
    Write-Host "$time - [Daemon] Killing Process"
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

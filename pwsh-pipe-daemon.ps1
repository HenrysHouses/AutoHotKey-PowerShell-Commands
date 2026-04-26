[CmdletBinding()]
param(
    [switch]$List,
    [int]$Log = 0,
    [string]$PipeName = "PWSH_COMMAND_PIPE",
    [switch]$Help,
    [string]$Preview,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $RemainingArgs = @()
)

$Kill = $null

for ($i = 0; $i -lt $RemainingArgs.Count; $i++)
{
    switch ($RemainingArgs[$i])
    {
        '-Kill'
        {
            if ($i + 1 -lt $RemainingArgs.Count -and $args[$i + 1] -notmatch '^-')
            {
                $Kill = [int]$RemainingArgs[++$i]
            } else
            {
                $Kill = -1
            }
        }

        default
        {
            throw "Unknown argument: $($RemainingArgs[$i])"
        }
    }
}

# Force UTF-8 for box characters and handle ANSI colors
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if ($PSStyle)
{ $PSStyle.OutputRendering = 'Ansi' 
}

# Define color codes for ANSI-aware output
$esc = [char]27
$C_Reset   = if ($PSStyle)
{ $PSStyle.Reset 
} else
{ "$esc[0m" 
}

$C_Black   = if ($PSStyle)
{ $PSStyle.Foreground.Black 
} else
{ "$esc[30m" 
}
$C_Red     = if ($PSStyle)
{ $PSStyle.Foreground.Red 
} else
{ "$esc[31m" 
}
$C_Green   = if ($PSStyle)
{ $PSStyle.Foreground.Green 
} else
{ "$esc[32m" 
}
$C_Yellow  = if ($PSStyle)
{ $PSStyle.Foreground.Yellow 
} else
{ "$esc[33m" 
}
$C_Blue    = if ($PSStyle)
{ $PSStyle.Foreground.Blue 
} else
{ "$esc[34m" 
}
$C_Magenta = if ($PSStyle)
{ $PSStyle.Foreground.Magenta 
} else
{ "$esc[35m" 
}
$C_Cyan    = if ($PSStyle)
{ $PSStyle.Foreground.Cyan 
} else
{ "$esc[36m" 
}
$C_White   = if ($PSStyle)
{ $PSStyle.Foreground.White 
} else
{ "$esc[37m" 
}

$C_Gray          = if ($PSStyle)
{ $PSStyle.Foreground.BrightBlack 
} else
{ "$esc[90m" 
}
$C_BrightRed     = if ($PSStyle)
{ $PSStyle.Foreground.BrightRed 
} else
{ "$esc[91m" 
}
$C_BrightGreen   = if ($PSStyle)
{ $PSStyle.Foreground.BrightGreen 
} else
{ "$esc[92m" 
}
$C_BrightYellow  = if ($PSStyle)
{ $PSStyle.Foreground.BrightYellow 
} else
{ "$esc[93m" 
}
$C_BrightBlue    = if ($PSStyle)
{ $PSStyle.Foreground.BrightBlue 
} else
{ "$esc[94m" 
}
$C_BrightMagenta = if ($PSStyle)
{ $PSStyle.Foreground.BrightMagenta 
} else
{ "$esc[95m" 
}
$C_BrightCyan    = if ($PSStyle)
{ $PSStyle.Foreground.BrightCyan 
} else
{ "$esc[96m" 
}
$C_BrightWhite   = if ($PSStyle)
{ $PSStyle.Foreground.BrightWhite 
} else
{ "$esc[97m" 
}

function Write-Output-Color
{
    param([string]$Message)
    if ($Preview -or $List)
    { Write-Output $Message 
    } else
    { Write-Host $Message 
    }
}

if ($Help)
{
    Write-Host "Usage: pwsh-pipe-daemon.ps1 [-List] [-Kill <PID>] [-PipeName <String>] [-Help]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -List              Show all running daemon instances and their status."
    Write-Host "                     Cleans broken instances when detected."
    Write-Host "  -Log <Str>         Outputs the logs for the matching pipe daemon"
    Write-Host "  -Kill              Gracefully terminate a daemon through an interactive menu"
    Write-Host "  -Kill <PID>        Gracefully terminate a daemon instance by its Process ID."
    Write-Host "  -DisposeShell <ID> Gracefully terminate an instanced shell. (not implemented)"
    Write-Host "  -PipeName <Str>    Specify a custom pipe name (default: PWSH_COMMAND_PIPE)."
    Write-Host "  -Preview <Str>     Preview the metadata from one of the daemon's json files."
    Write-Host "                     Helper method for displaying data in fzf."
    Write-Host "  -Help              Show this help message."
    Write-Host ""
    Write-Host "Messages:"
    Write-Host "  Main Behaviour:"
    Write-Host "    This daemon is meant to invoke short term commands, reusing available powershell"
    Write-Host "    instances for quick executuion. Since this is its main purpose, it prefers to not"
    Write-Host "    invoke duplicate indentical commands. Instead if one is detected it will act as"
    Write-Host "    a toggle. cancelling the command instead if a duplicate is detected. This behaviour"
    Write-Host "    can be altered with attaching flags to the message. For logging, tracking and"
    Write-Host "    debugging purposes names can be attached to messages in addition to altering behaviour."
    Write-Host ""
    Write-Host "  Message Prefixes:"
    Write-Host "    <string>                             Default message. No arguments."
    Write-Host "    __FROM__:<string>``n<string>          Includes the name / source in the logs"
    Write-Host "                                         The new line character acts as a delimiter"
    Write-Host "                                         between the name and the command string."
    Write-Host "    __CANCEL__:<string>                  Cancels any matching commands."
    Write-Host "    __RESTART__:<string>                 requests an active command to be"
    Write-Host "                                         cancelled and reinvoked"
    Write-Host ""
    Write-Host "    Example 0: Default Message"
    Write-Host "      yt-dlp https://some-link.com/my-audio-stream"
    Write-Host ""
    Write-Host "    Example 1: Named Message"
    Write-Host "      __FROM__:Quake Terminal``nffplay https://some-link.com/my-audio-stream"
    Write-Host ""
    Write-Host "    Example 2: Message With Argument"
    Write-Host "      __RESTART__:ffplay https://some-link.com/my-audio-stream"
    Write-Host ""
    Write-Host "    Example 3: Named Message With Argument"
    Write-Host "      __FROM__:AutoHotKey Script``n__CANCEL__ffplay https://some-link.com/my-audio-stream"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  The daemon acts as a singleton based on the pipe name. It writes to temp files to track instances"
    Write-Host "  and states which are automatically checked for validation."
    Write-Host "  Running the daemon in the background will allow you to use pwsh-msg.ps1 to send commands through" 
    Write-Host "  pipes to execute them within the daemon. This can also be utilized by anything which can write"
    Write-Host "  to the pipe the daemon is listning on such as AHK, powershell or anything else."
    Write-Host "  This enables near instant execution of scripts and terminal commands from external sources"
    Write-Host "  pwsh-msg.ps1 is a short hand utility for sending messages. Mainly for testing, debugging, and automation."
    exit 0
}

Import-Module Microsoft.PowerShell.Utility  
Import-Module Microsoft.PowerShell.Management

$pipeName = $PipeName
$powerShellInstances = @{}
$activeCommands = @{}
$daemonTempDir = Join-Path $env:TEMP 'pwsh-daemon-instances'

function Get-DaemonPID
{
    if (-not (Test-Path $daemonTempDir))
    {
        Write-Host "[INFO] No pwsh-daemon instances found"
        exit "NONE"
    }
    
    $daemonFiles = Get-ChildItem -Path $daemonTempDir -Filter "daemon_*.json" -ErrorAction SilentlyContinue
    
    if (-not $daemonFiles)
    {
        Write-Host "[INFO] No pwsh-daemon instances found"
        exit "NONE"
    }
    
    foreach ($file in $daemonFiles)
    {
        try
        {
            $content = Get-Content -Path $file.FullName | ConvertFrom-Json
            $proc = Get-Process -Id $content.PID -ErrorAction SilentlyContinue
            
            if ($proc)
            {
                return $content.PID
                
            } else
            {
                return "DEAD"
            }
        } catch
        {
        }
    }
    return "NONE"
}

function Write-DaemonInfo
{
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

    if ($Log -gt 0)
    {
        $DaemonPID = Get-DaemonPID
        $pidVal = " $DaemonPID"
    } else
    {
        $pidVal = " $PID"
    }

    $pidRight = " " * [math]::Max(0, ($col2Width - $pidVal.Length))

    Write-Host "╔$((New-Object String '═', $bannerWidth))╗"
    Write-Host "║$hLeft$header$hRight║"
    Write-Host "╟$((New-Object String '─', $col1Width))┬$((New-Object String '─', $col2Width))╢"
    Write-Host "║$($pipeLabel.PadRight($col1Width))│$pVal$pRight║"
    Write-Host "╟$((New-Object String '─', $col1Width))┼$((New-Object String '─', $col2Width))╢"
    Write-Host "║$($pidLabel.PadRight($col1Width))│$pidVal$pidRight║"
    Write-Host "╚$((New-Object String '═', $col1Width))╧$((New-Object String '═', $col2Width))╝"
    Write-Host ""
    Write-Host "[Time Stamp] - [Event Log]"
    Write-Host "─────────────────────────────────────────────────────────"
}

function Write-DaemonFile
{
    param(
        [string]$TempFile,
        [switch]$NoClean
    )

    $instances = @()

    try
    {
        if (-not (Test-Path $TempFile))
        { 
            Write-Output-Color "${C_Red}[ERROR] File not found: $TempFile${C_Reset}"; return 0 
        }

        $content = Get-Content -Path $TempFile | ConvertFrom-Json
            
        if (Get-Process -Id $content.PID -ErrorAction SilentlyContinue)
        {
            $instances += $content

            if ($content.PoolSize -lt 1)
            {
                $Connector = "└──"
            } else
            {
                $Connector = "└┬─"
            }

            Write-Output-Color "${C_Cyan}DEMON: $($content.WindowTitle) | Created: $($content.CreatedAt)${C_Reset}"
            Write-Output-Color "${C_Reset}$Connector $($content.PoolSize)/5 instances | Commands: $($content.RunningCommands.Count)${C_Reset}"
                
            if ($content.Instances -and $content.Instances.Count -gt 0)
            {
                for ($index = 0; $index -lt $content.Instances.Count; $index++)
                {
                    $inst = $content.instances[$index]
                    $status = "IDLE"
                    $color = $C_Gray
                    if ($inst.IsActive)
                    { 
                        $status = "ACTIVE" 
                        $color = $C_Green
                    } elseif ($inst.IsBusy)
                    { 
                        $status = "BUSY" 
                        $color = $C_Yellow
                    } elseif ($inst.IsDirty)
                    { 
                        $status = "DIRTY" 
                        $color = $C_Red
                    }

                    if ($index -lt $content.instances.Count-1)
                    {
                        if ($content.instances[$index].Command)
                        {
                            $Connector =    "├┬─"
                            $CmdConnector = "│└──"
                        } else
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
                        } else
                        {
                            $Connector =    "└──"
                            $CmdConnector = ""
                        }
                    }

                    $displayCommand = if ($inst.Command)
                    { " `n $C_Reset$CmdConnector$color Cmd: $($inst.Command)${C_Reset}" 
                    } else
                    { " " 
                    }
                    Write-Output-Color " $Connector$color[$status] $($inst.Id)$displayCommand${C_Reset}"
                }
            }
        } else
        {
            Write-Output-Color "${C_Red}PID: $($content.PID) | $($content.WindowTitle) | State: DEAD${C_Reset}"
            if ($content.Instances -and $content.Instances.Count -gt 0)
            {
                Write-Output-Color "${C_Yellow}Orphaned instances: $($content.Instances.Count)${C_Reset}"
            }
            if (-not $NoClean)
            {
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    } catch
    {
        Write-Output-Color "${C_Yellow}[WARNING] Failed to parse: $(Split-Path $TempFile -Leaf)${C_Reset}" 
    }
}

if ($List)
{
    if (-not (Test-Path $daemonTempDir))
    {
        Write-Output-Color "${C_Yellow}[INFO] No pwsh-daemon instances found${C_Reset}"
        exit 0
    }
    
    $daemonFiles = Get-ChildItem -Path $daemonTempDir -Filter "daemon_*.json" -ErrorAction SilentlyContinue
    
    if (-not $daemonFiles)
    {
        Write-Output-Color "${C_Yellow}[INFO] No pwsh-daemon instances found${C_Reset}"
        exit 0
    }
    
    Write-Output-Color "${C_Reset}[Daemon Instances]`n${C_Reset}"
    
    $instances = 0
    foreach ($file in $daemonFiles)
    {
        $instances += 1
        Write-DaemonFile -TempFile $file
    }
    
    if ($instances.Count -eq 0)
    {
        Write-Output-Color "${C_Reset}[INFO] No running pwsh-daemon instances found`n${C_Reset}"
        exit 0
    }
    
    Write-Output-Color "${C_Reset}`nTotal: $($instances.Count) running instance(s)`n${C_Reset}"
    exit 0
}

if ($Log -gt 0)
{
    Write-DaemonInfo
    $foundError = $false
    $LoggedEvents = Get-Content $env:LOCALAPPDATA\pwsh-pipe-daemon\$($PipeName)-daemon.log -Tail $Log
    $LoggedEvents | ForEach-Object { 
        if (Write-Output $_ | rg ".*\[INFO\] Completed Invocation.*")
        {
            $foundError = $false 
            Write-Output-Color "${C_BrightGreen}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[INFO\] Recreating pipe.*")
        {
            $foundError = $false 
            Write-Output-Color "${C_BrightYellow}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[INFO\] Connection closed.*")
        {
            $foundError = $false 
            Write-Output-Color "${C_Gray}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[INFO\] Cancel requested.*but it was not running")
        {
            $foundError = $false 
            Write-Output-Color "${C_Gray}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[ACTION\] Invoke requested by \[.*ssh:.*]\.*")
        {
            $foundError = $false 
            Write-Output-Color "${C_BrightCyan}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[ACTION\] Invoke requested by.*")
        {
            $foundError = $false 
            Write-Output-Color "${C_Cyan}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[ACTION\] Invoking command.*")
        {
            $foundError = $false 
            Write-Output-Color "${C_BrightBlue}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[ACTION\] Cancelled Invocation.*")
        {
            $foundError = $false 
            Write-Output-Color "${C_Yellow}$_${C_Reset}"
        } elseif (Write-Output $_ | rg ".*\[ERROR\].*")
        {
            $foundError = $true 
            Write-Output-Color "${C_BrightRed}$_${C_Reset}"
        } elseif (Write-Output $_ | rg "^(?!..:..:..\.... - \[[^\]]*\]).*$" --pcre2)
        {
            if ($foundError -eq $true)
            {
                Write-Output-Color "${C_BrightRed}$_${C_Reset}"
            } else 
            {
                $foundError = $false 
                Write-Output-Color "${C_Reset}$_${C_Reset}"
            }
        } else
        {
            $foundError = $false
            Write-Output-Color "${C_Reset}$_${C_Reset}"
        }
    }

    exit 0
}

if ($Preview)
{
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    if ($PSStyle)
    { $PSStyle.OutputRendering = 'Ansi' 
    }
    if ($Preview -match '\|([^\|]+)$')
    { $Preview = $matches[1] 
    }
    if (Test-Path $Preview)
    {
        Write-DaemonFile -TempFile $Preview -NoClean
        if (Get-Command bat -ErrorAction SilentlyContinue)
        { bat --color=always $Preview 
        } else
        { Get-Content $Preview 
        }
    } else
    { Write-Output-Color "${C_Red}Preview file not found: $Preview${C_Reset}" 
    }
    exit 0
}

function Stop-Daemon 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DaemonTempFile,
        [Parameter(Mandatory = $true)]
        [int]$DaemonPid
    )
    
    $daemonData = if (Test-Path $DaemonTempFile)
    { 
        Get-Content $DaemonTempFile | ConvertFrom-Json 
    }

    if (Get-Process -Id $DaemonPID -ErrorAction SilentlyContinue)
    {
        Write-Host "[INFO] Killing pwsh-daemon instance PID: $DaemonPID" -ForegroundColor Yellow
            
        # Kill all spawned instances first
        if ($daemonData.SpawnedInstances -and $daemonData.SpawnedInstances.Count -gt 0)
        {
            Write-Host "[INFO] Killing $($daemonData.SpawnedInstances.Count) spawned PowerShell instance(s)..." -ForegroundColor Yellow
            foreach ($instanceId in $daemonData.SpawnedInstances)
            {
                Write-Host "  --> Terminating runspace: $instanceId" -ForegroundColor Gray
            }
        }
            
        Stop-Process -Id $DaemonPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
            
        Remove-Item -Path $DaemonTempFile -Force -ErrorAction SilentlyContinue
            
        if (-not (Get-Process -Id $DaemonPID -ErrorAction SilentlyContinue))
        {
            Write-Host "[INFO] pwsh-daemon instance $DaemonPID successfully terminated" -ForegroundColor Green
        } else
        {
            Write-Host "[ERROR] Failed to terminate pwsh-daemon instance $DaemonPID" -ForegroundColor Red
            exit 1
        }
    } else
    {
        Write-Host "[INFO] Process $DaemonPID not running, cleaning up stale temp file" -ForegroundColor Yellow
        Remove-Item -Path $DaemonTempFile -Force -ErrorAction SilentlyContinue
    }
}

if ($Kill -eq -1)
{
    $daemonFiles = $daemonTempDir | Get-ChildItem -File -Name

    if ($daemonFiles.Count -eq 0)
    {
        Write-Host "[INFO] Could not find any known daemons by metadata. If any daemons are still running specify its PID in the command"
        exit 0
    }

    $pipeNames = @()
    $pipeDictionary = @{}

    if ($null -ne (Get-Command fzf))
    {
        $daemonFiles | ForEach-Object {
            $jsonPath = Join-Path $env:TEMP 'pwsh-daemon-instances' $_
            $name = (Get-Content $jsonPath | ConvertFrom-Json).PipeName
            $pipePID = (Get-Content $jsonPath | ConvertFrom-Json).PID
            $displayName = "$name - PID: $pipePID|$jsonPath"

            $pipeNames += $displayName
            $pipeDictionary[$displayName] = @{
                target = $pipePID
                json = $jsonPath
            }
        }

        $previewCmd = "pwsh -NoProfile -File `"$PSCommandPath`" -Preview {2}"
        $selected = $pipeNames | fzf --prompt "Kill: " --footer "Select Daemon To Kill" --footer-label-pos "center" --preview $previewCmd --preview-window='top,80%' --delimiter='|' --with-nth='{1}' --ansi
    } else
    {
        Write-Host ""
        Write-Host "─────────────────────────────────────────────────────────"
        Write-Output-Color "                  ${C_Cyan}Select Daemon To Kill${C_Reset}"
        $i = 0
        $daemonFiles | ForEach-Object {
            $jsonPath = Join-Path $env:TEMP 'pwsh-daemon-instances' $_
            $name = (Get-Content $jsonPath | ConvertFrom-Json).PipeName
            $pipePID = (Get-Content $jsonPath | ConvertFrom-Json).PID
            $displayName = "$name - PID: $pipePID"

            $pipeNames += $displayName
            $pipeDictionary[$i] = @{
                target = $pipePID
                json = $jsonPath
            }

            Write-Host "─────────────────────────────────────────────────────────"
            Write-Output-Color "Index: ${C_Cyan}$($i)${C_Reset} - ${C_Blue}$displayName${C_Reset}"
            Write-Host "─────────────────────────────────────────────────────────"
            Write-DaemonFile -TempFile $jsonPath
            Write-Host ""
            $i += 1
        }

        Write-Output-Color "${C_Gray}─────────────────────────────────────────────────────────${C_Reset}"
        Write-Output-Color "${C_Blue}Select an Index: ${C_Cyan}0${C_Reset} - ${C_Cyan}$($i-1)${C_Reset}"
        Write-Output-Color "${C_Gray}─────────────────────────────────────────────────────────${C_Reset}"

        $selected = "Select"
        while ($selected -notmatch '^\d+$')
        {
            $selected = Read-Host

            if ($selected -match '^\s*([jJ])\s+[:=]?\s*(\d+)\s*$')
            {
                $idx = [int]$Matches[2]
                if ($pipeDictionary.ContainsKey($idx))
                {
                    $previewFile = $pipeDictionary[$idx].json
                    if (Get-Command bat -ErrorAction SilentlyContinue)
                    { bat --color=always $previewFile 
                    } else
                    { Get-Content $previewFile 
                    }
                } else
                {
                    Write-Output-Color "${C_Red}Index $idx not found${C_Reset}"
                }
                $selected = "Select"
            } elseif ($selected -match '^\d+$')
            {
                if (-not $pipeDictionary.ContainsKey([int]$selected))
                {
                    Write-Output-Color "${C_Red}Invalid Index: $selected${C_Reset}"
                    $selected = "Select"
                }
            } else
            {
                Write-Output-Color "${C_Red}Invalid Input${C_Reset}"
                Write-Output-Color "View Metadata with: ${C_Green}j${C_Blue} <Index>${C_Reset}"
                $selected = "Select"
            }
        }
    }

    if ($selected -match '^\d+$')
    {
        $idx = [int]$selected
        Stop-Daemon -DaemonPID $pipeDictionary[$idx].target -DaemonTempFile $pipeDictionary[$idx].json
    }

    exit 0
} elseif ($Kill -ge 0)
{ 
    $daemonTempFile = Join-Path $daemonTempDir "daemon_$Kill.json"
    if (Test-Path $daemonTempFile)
    {
        $daemonData = Get-Content -Path $daemonTempFile | ConvertFrom-Json
        Stop-Daemon $daemonTempFile $Kill
    } else
    {
        Write-Host "[ERROR] No daemon instance found with PID: $Kill" -ForegroundColor Red
        exit 1
    }
    
    exit 0
}

# --- Main Daemon ---

$Host.UI.RawUI.WindowTitle = 'pwsh-pipe-daemon'
[Console]::Title = 'pwsh-pipe-daemon'

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
                if (Get-Process -Id $content.PID -ErrorAction SilentlyContinue)
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

$LogDir = Join-Path $env:LOCALAPPDATA 'pwsh-pipe-daemon'
$LogName = "$($PipeName)-daemon.log"
$LogPath = Join-Path $LogDir $LogName
if (-not (Test-Path $LogDir))
{
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

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
        { 
            $activeEntry.Key 
        } else
        { 
            $null 
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

Write-DaemonInfo
Start-Transcript -Path $LogPath -Append | Out-Null

[Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID"
$Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID"

$instanceCount = 0
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$runspacePool.Open()

$lastQueueChangeTime = [DateTime]::UtcNow
$lastMaintenanceTime = [DateTime]::UtcNow
$maintenanceIdleThreshold = [TimeSpan]::FromSeconds(20)
$maintenanceInterval = [TimeSpan]::FromHours(1)

UpdateDaemonTempFile

$cancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
$token = $cancellationTokenSource.Token


function Perform-Maintenance
{
    $now = [DateTime]::UtcNow
    $timeFormatted = $now.ToString("HH:mm:ss.fff")
    Write-Host "$timeFormatted - [MAINTENANCE] Starting scheduled cleanup..." -ForegroundColor Magenta

    $memBefore = (Get-Process -Id $PID).WorkingSet64

    try
    { 
        Stop-Transcript | Out-Null 
    } catch
    { 
    }

    if (Test-Path $LogPath)
    {
        try
        {
            $content = Get-Content -Path $LogPath -Tail 1000 -ErrorAction SilentlyContinue
            if ($content)
            {
                Set-Content -Path $LogPath -Value $content -Force
            }
        } catch
        { 
        }
    }

    $idleInstanceIds = $powerShellInstances.Keys | Where-Object { -not $powerShellInstances[$_].IsBusy }
    foreach ($id in $idleInstanceIds)
    {
        try
        {
            $powerShellInstances[$id].Shell.Dispose()
            $powerShellInstances.Remove($id)
            $instanceCount--
        } catch
        { 
        }
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()

    try
    { Start-Transcript -Path $LogPath -Append | Out-Null 
    } catch
    { 
    }

    $memAfter = (Get-Process -Id $PID).WorkingSet64
    $releasedMB = [math]::Round(($memBefore - $memAfter) / 1MB, 2)
    $totalMB = [math]::Round($memAfter / 1MB, 2)

    $script:lastMaintenanceTime = $now
    UpdateDaemonTempFile
    
    $releasedMsg = if ($releasedMB -gt 0)
    { 
        "Released: ${releasedMB}MB | " 
    } else
    { 
        "" 
    }
    Write-Host "$([DateTime]::UtcNow.ToString('HH:mm:ss.fff')) - [MAINTENANCE] Cleanup complete. ${releasedMsg}Current Usage: ${totalMB}MB" -ForegroundColor Magenta
}

function IdleUpdate
{
    $now = [DateTime]::UtcNow
    $completedCommands = $activeCommands.GetEnumerator() |
        Where-Object { $_.Value.AsyncResult.IsCompleted } |
        ForEach-Object { $_.Key }

    foreach ($cmd in $completedCommands)
    {
        $global:lastQueueChangeTime = $now
        
        $timeFormatted = $now.ToString("HH:mm:ss.fff")
        $startedTime = $activeCommands[$cmd].StartTime
        $duration = $now - $startedTime
        $durationString = Format-Duration $duration

        $instanceID = $activeCommands[$cmd].PowerShell.InstanceId
        $results = $activeCommands[$cmd].PowerShell.EndInvoke($activeCommands[$cmd].AsyncResult)
        if ($results)
        {
            Write-Host "$timeFormatted - [Results] '$cmd':"
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
        
        UpdateDaemonTempFile

        try
        {
            if ($activeCommands.Count -eq 0)
            {
                [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID"
                $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID"
            } elseif ($activeCommands.Count -eq 1)
            {
                $remainingCmd = $activeCommands.Keys | Select-Object -First 1
                [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $remainingCmd"
                $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $remainingCmd"
            } else
            {
                [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
                $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
            }
        } catch
        {
            Write-Host "$timeFormatted - [Warning] Failed to update window title on completion: $_"
        }
    }

    $timeSinceChange = $now - $script:lastQueueChangeTime
    $timeSinceMaintenance = $now - $script:lastMaintenanceTime

    if ($timeSinceChange -gt $maintenanceIdleThreshold -and $timeSinceMaintenance -gt $maintenanceInterval)
    {
        Perform-Maintenance
    }

    if ($powerShellInstances.Count -gt 5)
    {
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
        # Found idle instance
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

    $global:lastQueueChangeTime = [DateTime]::UtcNow

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
                            
    $asyncResult = $powershell.BeginInvoke($input, $settings, $null, $null)

    $activeCommands[$msg] = @{
        PowerShell = $powershell
        AsyncResult = $asyncResult
        StartTime = [DateTime]::UtcNow
    }
                            
    UpdateDaemonTempFile
                            
    try
    {
        if ($activeCommands.Count -eq 1)
        {
            [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $msg"
            $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $msg"
        } elseif ($activeCommands.Count -gt 1)
        {
            [Console]::Title = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
            $Host.UI.RawUI.WindowTitle = "pwsh-pipe-daemon [$pipeName] - PID: $PID | Running: $($activeCommands.Count) commands"
        }
    } catch
    {
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
            $buffer = New-Object byte[] 1024

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
                    
                    $senderName = $null
                    $isRestart = $false
                    $isCancel = $false

                    if ($rawMessage -match '^__FROM__:([^\r\n]+)[\r\n]+([\s\S]+)$')
                    {
                        $senderName = $matches[1]
                        $rawMessage = $matches[2]
                    }

                    if ($rawMessage -match '^__RESTART__:([\s\S]+)$')
                    {
                        $isRestart = $true
                        $rawMessage = $matches[1]
                    } elseif ($rawMessage -match '^__CANCEL__:([\s\S]+)$')
                    {
                        $isCancel = $true
                        $rawMessage = $matches[1]
                    }

                    $rawMessage = $rawMessage.TrimStart("`r", "`n", " ")
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
                            }
                        } elseif ($isCancel)
                        {
                            Write-Host "$time - [INFO] Cancel requested for '$message' but it was not running." -ForegroundColor Gray
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
        $reader.Dispose()
    }
    $cancellationTokenSource.Dispose()

    # Dispose of all PowerShell instances in the pool
    foreach ($instanceId in $powerShellInstances.Keys)
    {
        try
        {
            $powerShellInstances[$instanceId].Shell.Stop()
            $powerShellInstances[$instanceId].Shell.Dispose()
        } catch
        { 
        }
    }
    $powerShellInstances.Clear()

    foreach ($cmd in $activeCommands.Keys)
    {
        try
        {
            $activeCommands[$cmd].PowerShell.Stop()
            $activeCommands[$cmd].PowerShell.Dispose()
        } catch
        { 
        }
    }
    $activeCommands.Clear()

    $runspacePool.Dispose()
    Stop-Transcript | Out-Null
}

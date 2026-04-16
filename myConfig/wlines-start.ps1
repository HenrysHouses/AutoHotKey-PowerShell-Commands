[CmdletBinding()]
param(
    [switch]$Refresh,
    [switch]$List,
    [switch]$fzf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WlinesWrapper = if ($fzf)
{
    Join-Path $PSScriptRoot 'wlines-fzf.ps1'
} else
{
    Join-Path $PSScriptRoot 'wlines-rofi.ps1'
}

# Auto-detect SSH session
$IsRemoteSession = -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)
if ($IsRemoteSession)
{
    Write-Host "SSH session detected - commands will execute on local machine via pwsh-daemon"
}

function Invoke-RemoteCommand
{
    param([string]$Command)
    
    if ($IsRemoteSession)
    {
        # Send to daemon for remote execution (pwsh-msg handles SSH detection)
        & (Join-Path $PSScriptRoot 'pwsh-msg.ps1') -Command $Command -Name "Start"
    } else
    {
        # Execute locally
        Invoke-Expression $Command
    }
}
$CacheDir = Join-Path $env:LOCALAPPDATA 'wlines'
$CachePath = Join-Path $CacheDir 'start-menu-cache.json'
$PathExtensions = @('.exe', '.bat', '.cmd', '.ps1')
$StartMenuExtensions = @('.lnk', '.appref-ms', '.url', '.exe', '.bat', '.cmd', '.ps1')
$ExtraCommandDirs = @(
    (Join-Path $env:USERPROFILE 'bin'),
    (Join-Path $env:USERPROFILE '.local\bin')
) | Where-Object { Test-Path $_ }
$IgnoredExecutables = @(
    'powershell.exe',
    'pwsh.exe',
    'cmd.exe',
    'where.exe',
    'whoami.exe',
    'find.exe',
    'sort.exe',
    'timeout.exe'
)

function Resolve-UniqueLabel
{
    param(
        [Parameter(Mandatory)]
        [string]$BaseLabel,
        [Parameter(Mandatory)]
        [string]$Detail,
        [Parameter(Mandatory)]
        [hashtable]$Seen
    )

    $label = $BaseLabel.Trim()
    if ([string]::IsNullOrWhiteSpace($label))
    {
        $label = 'Unnamed app'
    }

    if (-not $Seen.ContainsKey($label))
    {
        $Seen[$label] = 1
        return $label
    }

    $qualified = "$label [$Detail]"
    if (-not $Seen.ContainsKey($qualified))
    {
        $Seen[$qualified] = 1
        return $qualified
    }

    $index = 2
    while ($true)
    {
        $candidate = "$qualified ($index)"
        if (-not $Seen.ContainsKey($candidate))
        {
            $Seen[$candidate] = 1
            return $candidate
        }
        $index++
    }
}

function New-LauncherItem
{
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [ValidateSet('Appx', 'Shortcut', 'Command')]
        [string]$Kind,
        [Parameter(Mandatory)]
        [string]$Target,
        [Parameter(Mandatory)]
        [string]$Detail,
        [Parameter(Mandatory)]
        [hashtable]$Seen
    )

    $label = Resolve-UniqueLabel -BaseLabel $Name -Detail $Detail -Seen $Seen
    [PSCustomObject]@{
        Label  = $label
        Name   = $Name
        Kind   = $Kind
        Target = $Target
        Detail = $Detail
    }
}

function Get-StartMenuFileItems
{
    param([hashtable]$Seen)

    $directories = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    ) | Where-Object { Test-Path $_ }

    foreach ($directory in $directories)
    {
        Get-ChildItem -Path $directory -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension.ToLowerInvariant() -in $StartMenuExtensions } |
            ForEach-Object {
                $relativeDirectory = Split-Path ($_.FullName.Substring($directory.Length).TrimStart('\')) -Parent
                if ([string]::IsNullOrWhiteSpace($relativeDirectory))
                {
                    $relativeDirectory = 'Programs'
                }

                New-LauncherItem `
                    -Name $_.BaseName `
                    -Kind 'Shortcut' `
                    -Target $_.FullName `
                    -Detail $relativeDirectory `
                    -Seen $Seen
            }
    }
}

function Get-StartAppsItems
{
    param([hashtable]$Seen)

    foreach ($app in Get-StartApps | Sort-Object Name, AppID)
    {
        if ([string]::IsNullOrWhiteSpace($app.Name) -or [string]::IsNullOrWhiteSpace($app.AppID))
        {
            continue
        }

        New-LauncherItem `
            -Name $app.Name `
            -Kind 'Appx' `
            -Target $app.AppID `
            -Detail 'StartApps' `
            -Seen $Seen
    }
}

function Get-PathCommandItems
{
    param([hashtable]$Seen)

    foreach ($directory in $ExtraCommandDirs)
    {
        Get-ChildItem -Path $directory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension.ToLowerInvariant() -in $PathExtensions -and
                $_.Name -notin $IgnoredExecutables
            } |
            ForEach-Object {
                New-LauncherItem `
                    -Name $_.BaseName `
                    -Kind 'Command' `
                    -Target $_.FullName `
                    -Detail (Split-Path $directory -Leaf) `
                    -Seen $Seen
            }
    }
}

function Build-LauncherCache
{
    $seen = @{}
    $items = @()
    $items += Get-StartAppsItems -Seen $seen
    $items += Get-StartMenuFileItems -Seen $seen
    $items += Get-PathCommandItems -Seen $seen

    $items = $items |
        Sort-Object Label -Unique

    if (-not (Test-Path $CacheDir))
    {
        New-Item -ItemType Directory -Path $CacheDir | Out-Null
    }

    $items | ConvertTo-Json -Depth 3 | Set-Content -Path $CachePath -Encoding UTF8
    return $items
}

function Get-LauncherItems
{
    if ($Refresh -or -not (Test-Path $CachePath))
    {
        return Build-LauncherCache
    }

    try
    {
        $cached = Get-Content -Path $CachePath -Raw | ConvertFrom-Json
        if ($null -eq $cached)
        {
            return Build-LauncherCache
        }

        return @($cached)
    } catch
    {
        return Build-LauncherCache
    }
}

function Test-LaunchMinimized
{
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path))
    {
        return $false
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin @('.ps1', '.bat', '.cmd'))
    {
        return $false
    }

    try
    {
        $lines = Get-Content -Path $Path -TotalCount 8 -ErrorAction Stop
    } catch
    {
        return $false
    }

    foreach ($line in $lines)
    {
        if ($line -match '^\s*#\s*RunAsMinimized\s*$')
        {
            return $true
        }
    }

    return $false
}

function Invoke-LauncherItem
{
    param([Parameter(Mandatory)]$Item)

    switch ($Item.Kind)
    {
        'Appx'
        {
            $cmd = "Start-Process 'explorer.exe' `"shell:AppsFolder\$($Item.Target)`""
            Invoke-RemoteCommand -Command $cmd
            return
        }
        'Shortcut'
        {
            $cmd = "Start-Process -FilePath `"$($Item.Target)`""
            Invoke-RemoteCommand -Command $cmd
            return
        }
        'Command'
        {
            $extension = [System.IO.Path]::GetExtension($Item.Target).ToLowerInvariant()
            $windowStyle = if (Test-LaunchMinimized -Path $Item.Target)
            { 'Minimized' 
            } else
            { 'Normal' 
            }
            switch ($extension)
            {
                '.ps1'
                {
                    $cmd = "Start-Process -FilePath 'pwsh.exe' -WindowStyle $windowStyle -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', `"$($Item.Target)`")"
                    Invoke-RemoteCommand -Command $cmd
                    return
                }
                '.bat'
                {
                    $cmd = "Start-Process -FilePath 'cmd.exe' -WindowStyle $windowStyle -ArgumentList @('/c', `"$($Item.Target)`")"
                    Invoke-RemoteCommand -Command $cmd
                    return
                }
                '.cmd'
                {
                    $cmd = "Start-Process -FilePath 'cmd.exe' -WindowStyle $windowStyle -ArgumentList @('/c', `"$($Item.Target)`")"
                    Invoke-RemoteCommand -Command $cmd
                    return
                }
                default
                {
                    $cmd = "Start-Process -FilePath `"$($Item.Target)`""
                    Invoke-RemoteCommand -Command $cmd
                    return
                }
            }
            return
        }
    }
}

$items = @(Get-LauncherItems)
if ($items.Count -eq 0)
{
    throw 'No launcher entries were found.'
}

if ($List)
{
    $items |
        Select-Object Label, Kind, Target, Detail |
        Format-Table -AutoSize
    return
}

$labels = @(
    'Refresh applications cache'
    $items.Label
) -join "`n"

$selection = & $WlinesWrapper -InputContent $labels -p 'Start'
if ([string]::IsNullOrWhiteSpace($selection))
{
    return
}

if ($selection -eq 'Refresh applications cache')
{
    Build-LauncherCache | Out-Null
    return
}

$selectedItem = $items | Where-Object { $_.Label -eq $selection } | Select-Object -First 1
if ($null -eq $selectedItem)
{
    throw "Selected entry was not found: $selection"
}

Invoke-LauncherItem -Item $selectedItem

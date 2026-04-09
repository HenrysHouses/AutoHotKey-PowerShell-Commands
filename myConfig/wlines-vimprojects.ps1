[CmdletBinding()]
param(
    [switch]$List,
    [switch]$fzf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WlinesWrapper = if ($fzf) {
    Join-Path $PSScriptRoot 'wlines-fzf.ps1'
} else {
    Join-Path $PSScriptRoot 'wlines-rofi.ps1'
}
$WorkspaceDir = Join-Path $env:LOCALAPPDATA 'nvim-data\Workspaces'

function ConvertTo-CmdArgument
{
    param([Parameter(Mandatory)][string]$Value)

    return '"' + ($Value -replace '"', '""') + '"'
}

function Escape-CmdTitleText
{
    param([Parameter(Mandatory)][string]$Value)

    $escaped = $Value -replace '\^', '^^'
    $escaped = $escaped -replace '([&|<>()])', '^$1'
    $escaped = $escaped -replace '%', '%%'
    return $escaped
}

function Resolve-InputPath
{
    param([Parameter(Mandatory)][string]$InputPath)

    $candidate = $InputPath.Trim()
    if ($candidate.StartsWith('"') -and $candidate.EndsWith('"'))
    {
        $candidate = $candidate.Trim('"')
    }

    if ($candidate.StartsWith("'") -and $candidate.EndsWith("'"))
    {
        $candidate = $candidate.Trim("'")
    }

    $candidate = [Environment]::ExpandEnvironmentVariables($candidate)

    if ($candidate.StartsWith('~'))
    {
        $candidate = Join-Path $env:USERPROFILE $candidate.Substring(1).TrimStart('\', '/')
    }

    try
    {
        return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
    } catch
    {
        try
        {
            $combined = Join-Path (Get-Location).Path $candidate
            return (Resolve-Path -LiteralPath $combined -ErrorAction Stop).Path
        } catch
        {
            return $null
        }
    }
}

function Open-InNeovim
{
    param([Parameter(Mandatory)][string]$ResolvedPath)

    $item = Get-Item -LiteralPath $ResolvedPath -ErrorAction Stop
    $workingDirectory = if ($item.PSIsContainer)
    { $ResolvedPath 
    } else
    { $item.DirectoryName 
    }
    $targetArgument = if ($item.PSIsContainer)
    { '.' 
    } else
    { $ResolvedPath 
    }
    $titleTarget = Split-Path -Leaf $ResolvedPath
    if ([string]::IsNullOrWhiteSpace($titleTarget))
    {
        $titleTarget = $ResolvedPath
    }
    $tabTitle = "Neovim: $titleTarget"
    $escapedTitle = Escape-CmdTitleText -Value $tabTitle
    $quotedTarget = ConvertTo-CmdArgument -Value $targetArgument
    $command = "title $escapedTitle & nvim -- $quotedTarget"

    Start-Process -FilePath 'wt.exe' -ArgumentList @(
        'new-tab'
        '-d'
        $workingDirectory
        'cmd.exe'
        '/c'
        $command
    )
}

function Get-LuaFieldValue
{
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$FieldName
    )

    $pattern = '{0}\s*=\s*"([^"]*)"' -f [regex]::Escape($FieldName)
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success)
    {
        return ''
    }

    return $match.Groups[1].Value
}

function Get-WorkspaceItems
{
    if (-not (Test-Path $WorkspaceDir))
    {
        return @()
    }

    $items = foreach ($file in Get-ChildItem -Path $WorkspaceDir -Filter *.lua -File | Sort-Object Name)
    {
        try
        {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
            $projectLocation = Get-LuaFieldValue -Content $content -FieldName 'project_location'
            $projectName = Get-LuaFieldValue -Content $content -FieldName 'project_name'
            $tag = Get-LuaFieldValue -Content $content -FieldName 'tag'

            if ([string]::IsNullOrWhiteSpace($projectLocation))
            {
                continue
            }

            $resolvedLocation = $projectLocation -replace '/', '\'
            $displayName = if ([string]::IsNullOrWhiteSpace($projectName))
            { $file.BaseName 
            } else
            { $projectName 
            }
            $parts = @($displayName)
            if (-not [string]::IsNullOrWhiteSpace($tag))
            {
                $parts += $tag
            }
            $parts += $resolvedLocation

            [PSCustomObject]@{
                Label           = ($parts -join ' | ')
                ProjectName     = $displayName
                ProjectLocation = $resolvedLocation
                WorkspaceFile   = $file.FullName
                Tag             = $tag
            }
        } catch
        {
            continue
        }
    }

    return @($items)
}

$items = @(Get-WorkspaceItems)
if ($items.Count -eq 0)
{
    Write-Warning "No workspace files found in $WorkspaceDir"
    return
}

if ($List)
{
    $items |
        Select-Object ProjectName, Tag, ProjectLocation, WorkspaceFile |
        Format-Table -AutoSize
    return
}

$selection = & $WlinesWrapper -InputContent ($items.Label -join "`n") 'Open Neovim'
if ([string]::IsNullOrWhiteSpace($selection))
{
    return
}

$selectedItem = $items | Where-Object { $_.Label -eq $selection } | Select-Object -First 1
$resolvedPath = $null
if ($null -eq $selectedItem)
{
    $resolvedPath = Resolve-InputPath -InputPath $selection
    if ([string]::IsNullOrWhiteSpace($resolvedPath))
    {
        Write-Warning 'The selected workspace or path could not be identified.'
        return
    }
} else
{
    $resolvedPath = $selectedItem.ProjectLocation
}

if (-not (Test-Path -LiteralPath $resolvedPath))
{
    Write-Warning "Path not found: $resolvedPath"
    return
}

Open-InNeovim -ResolvedPath $resolvedPath

[CmdletBinding()]
param(
    [switch]$Explorer,
    [switch]$fzf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WlinesWrapper = if ($fzf) {
    Join-Path $PSScriptRoot 'wlines-fzf.ps1'
} else {
    Join-Path $PSScriptRoot 'wlines-rofi.ps1'
}
$HistoryDir = Join-Path $env:LOCALAPPDATA 'wlines'
$HistoryPath = Join-Path $HistoryDir 'path-history.txt'
$YaziExe = (Get-Command yazi -ErrorAction Stop).Source

function ConvertTo-CmdArgument
{
    param([Parameter(Mandatory)][string]$Value)

    return '"' + ($Value -replace '"', '""') + '"'
}

function ConvertTo-PowerShellLiteral
{
    param([Parameter(Mandatory)][string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Escape-CmdTitleText
{
    param([Parameter(Mandatory)][string]$Value)

    $escaped = $Value -replace '\^', '^^'
    $escaped = $escaped -replace '([&|<>()])', '^$1'
    $escaped = $escaped -replace '%', '%%'
    return $escaped
}

function Resolve-ZoxidePath
{
    param([Parameter(Mandatory)][string]$Query)

    try
    {
        $result = & zoxide query -- $Query 2>$null
        if ($LASTEXITCODE -ne 0)
        {
            return $null
        }

        $candidate = ($result | Select-Object -First 1).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate))
        {
            return $null
        }

        return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
    } catch
    {
        return $null
    }
}

function Get-HistoryEntries
{
    if (-not (Test-Path $HistoryPath))
    {
        return @()
    }

    return @(
        Get-Content -Path $HistoryPath -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
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
            return Resolve-ZoxidePath -Query $candidate
        }
    }
}

function Update-History
{
    param([Parameter(Mandatory)][string]$ResolvedPath)

    if (-not (Test-Path $HistoryDir))
    {
        New-Item -ItemType Directory -Path $HistoryDir -Force | Out-Null
    }

    $entries = @($ResolvedPath)
    $entries += Get-HistoryEntries | Where-Object { $_ -ne $ResolvedPath }
    $entries | Set-Content -Path $HistoryPath -Encoding UTF8
}

function Open-InExplorer
{
    param([Parameter(Mandatory)][string]$ResolvedPath)

    $item = Get-Item -LiteralPath $ResolvedPath -ErrorAction Stop
    if ($item.PSIsContainer)
    {
        Start-Process -FilePath 'explorer.exe' -ArgumentList @($ResolvedPath)
    } else
    {
        Start-Process -FilePath 'explorer.exe' -ArgumentList @("/select,$ResolvedPath")
    }
}

function Open-InYazi
{
    param([Parameter(Mandatory)][string]$ResolvedPath)

    $item = Get-Item -LiteralPath $ResolvedPath -ErrorAction Stop
    $workingDirectory = if ($item.PSIsContainer)
    { $ResolvedPath 
    } else
    { $item.DirectoryName 
    }
    $titleTarget = Split-Path -Leaf $ResolvedPath
    if ([string]::IsNullOrWhiteSpace($titleTarget))
    {
        $titleTarget = $ResolvedPath
    }
    $tabTitle = "Yazi: $titleTarget"

    $command = @"
`$host.UI.RawUI.WindowTitle = "$tabTitle"
`$p = [string]::Join('', @'
$ResolvedPath
'@)
& "$YaziExe" -- "`$p"
"@
    Start-Process -FilePath 'wt.exe' -ArgumentList @(  
        'new-tab', 
        '-d',
        "`"$workingDirectory`"",
        'pwsh.exe',
        '-NoExit',
        '-Command',
        $Command
    )  
}

$historyEntries = Get-HistoryEntries
$inputContent = $historyEntries -join "`n"
$prompt = if ($Explorer)
{ 'Path (Explorer)' 
} else
{ 'Path (Yazi)' 
}
$selection = & $WlinesWrapper -InputContent $inputContent $prompt

if ([string]::IsNullOrWhiteSpace($selection))
{
    return
}

$resolvedPath = Resolve-InputPath -InputPath $selection
if ([string]::IsNullOrWhiteSpace($resolvedPath))
{
    Write-Warning "Path not found: $selection"
    return
}

try
{
    if ($Explorer)
    {
        Open-InExplorer -ResolvedPath $resolvedPath
    } else
    {
        Open-InYazi -ResolvedPath $resolvedPath
    }

    Update-History -ResolvedPath $resolvedPath
} catch
{
    Write-Warning $_.Exception.Message
}

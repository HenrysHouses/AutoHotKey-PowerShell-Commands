param (
    [Parameter(ValueFromPipeline)]
    [string]$InputContent,  # Captures single input from the pipeline
    [string]$p              # Captures single input from the argument (matches wrofi.ps1)
)

# Capture pipeline input if it's provided
if ($InputContent -eq $null)
{
    $InputContent = @($input) -join "`n"
}

$fzfArgs = @(
    '--multi',
    '--cycle',
    '--print-query'
)

if ($p)
{
    $fzfArgs += @('--prompt', "$p> ")
}

# Pipe content to fzf and get selection
$output = $InputContent | fzf @fzfArgs 2>&1

# --print-query returns the query on the first line, selections on subsequent lines
# We want the last selected item, or the query if nothing was selected
$lines = @($output)
if ($lines.Count -gt 1)
{
    # Return the last line (selected item) if there are multiple results
    Write-Output $lines[-1]
} elseif ($lines.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($lines[0]))
{
    # If only one line, it could be the query (no selection) or a selection
    # fzf with --print-query returns query first, so we need to check
    # Return it as-is - it will either be a selected item or the typed query
    Write-Output $lines[0]
}

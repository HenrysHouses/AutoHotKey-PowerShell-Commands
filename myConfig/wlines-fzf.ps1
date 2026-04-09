param (
    [string]$InputContent,
    [string]$Prompt
)

# Capture pipeline input if it's provided
if ($InputContent -eq $null)
{
    $InputContent = $input | Out-String
}

$fzfArgs = @(
    '--multi',
    '--cycle',
    '--height=50%'
)

if ($Prompt)
{
    $fzfArgs += @('--prompt', "$Prompt> ")
}

# Pipe content to fzf and get selection
$output = $InputContent | fzf @fzfArgs 2>&1

Write-Output $output

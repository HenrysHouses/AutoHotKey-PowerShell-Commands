param (
    [Parameter(ValueFromPipeline)]
    [string]$InputContent,  # Captures single input from the pipeline
    [string]$p              # Captures single input from the argument (matches wlines-rofi.ps1)
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

if ($p)
{
    $fzfArgs += @('--prompt', "$p> ")
}

# Pipe content to fzf and get selection
$output = $InputContent | fzf @fzfArgs 2>&1

Write-Output $output

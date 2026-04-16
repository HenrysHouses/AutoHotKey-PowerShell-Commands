param (
    [Parameter(ValueFromPipeline)]
    [string]$InputContent,  # Captures single input from the pipeline
    [string]$p  # Captures single input from the argument
)

# Auto-detect SSH session
$IsRemoteSession = -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)
if ($IsRemoteSession)
{
    Write-Host "SSH session detected - cannot launch wlines-horiz (requires GUI)"
    return
}

# Capture pipeline input if it's provided
if ($InputContent -eq $null)
{
    $InputContent = $input | Out-String  # Convert pipeline input to a string
}

$mainforeground = "#b5b5a880"
$mainbackground = "#27282280"
$selectedforeground = "#161c0f80"
$selectedbackground = "#9beb2e80"
$textforeground = $selectedforeground
$textbackground = "#72756e80"
$font = "JetBrainsMono Nerd Font Propo"
$fontsize = 21
$padding = 4
$inputWidth = 200
# Modes: complete, keywords
$mode = "complete"

if ($p)
{
    $output = $InputContent | ~/repos/wlines/wlines.exe -px $padding -hl $inputWidth -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -f $font -fs $fontsize -p $p 2>&1
    Write-Output $output
} else
{
    $output = $InputContent | ~/repos/wlines/wlines.exe -px $padding -hl $inputWidth -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -f $font -fs $fontsize 2>&1
    Write-Output $output
}


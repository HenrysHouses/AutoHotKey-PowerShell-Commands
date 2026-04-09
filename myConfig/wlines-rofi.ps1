param (
    [string]$InputContent,  # Captures single input from the pipeline
    [string]$p  # Captures single input from the argument
)

# Capture pipeline input if it's provided
if ($InputContent -eq $null)
{
    $InputContent = $input | Out-String  # Convert pipeline input to a string
}

$mainforeground = "#b5b5a8"
$mainbackground = "#272822"
$selectedforeground = "#161c0f"
$selectedbackground = "#9beb2e"
$textforeground = "#ffffff"
$textbackground = "#72756e"
$font = "JetBrainsMono Nerd Font Propo"
$fontsize = 21
$padding = 4
$width = 600
# Modes: complete, keywords
$mode = "complete"

if ($p)
{
    $output = $InputContent | wlines -px $padding -wx $width -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $selectedforeground -f $font -fs $fontsize -p $p 2>&1
    Write-Output $output
} else
{
    $output = $InputContent | wlines -px $padding -wx $width -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $selectedforeground -f $font -fs $fontsize 2>&1
    Write-Output $output
}

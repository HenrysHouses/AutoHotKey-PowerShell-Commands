param (
    [Parameter(ValueFromPipeline)]
    [string]$InputContent,  # Captures single input from the pipeline
    [string]$p,  # Captures single input from the argument
    [switch]$Opaque 
)

# Auto-detect SSH session
$IsRemoteSession = -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)
if ($IsRemoteSession)
{
    Write-Host "SSH session detected - cannot launch whoriz (requires GUI)"
    return
}

# Capture pipeline input if it's provided
if ($InputContent -eq $null)
{
    $InputContent = $input | Out-String  # Convert pipeline input to a string
}

$mainforeground = "#b5b5a8"
$mainbackground = "#272822"
$selectedforeground = "#161c0f"
$selectedbackground = "#9beb2e"
$textforeground = $selectedforeground
$textbackground = "#72756e"
$borderColor = "#9beb2e"

$mainforegroundBlurred = "#b5b5a8"
$mainbackgroundBlurred = "#27282240"
$selectedforegroundBlurred = "#9beb2e"
$selectedbackgroundBlurred = "#9beb2e00"
$textforegroundBlurred = "#f2f2f8"
$textbackgroundBlurred = "#9beb2e00"
$borderColorBlurred = "#9beb2e"

$font = "JetBrainsMono NF"
$fontsize = 21
$padding = 4
$inputWidth = 200
# Modes: complete, keywords
$mode = "complete"

if ($Opaque)
{
    if ($p)
    {
        if ([string]::IsNullOrWhiteSpace($InputContent)) {
            $output = wlines -px $padding -hl $inputWidth -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize -p $p 2>&1
        } else {
            $output = $InputContent | wlines -px $padding -hl $inputWidth -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize -p $p 2>&1
        }
        Write-Output $output
    } else
    {
        if ([string]::IsNullOrWhiteSpace($InputContent)) {
            $output = wlines -px $padding -hl $inputWidth -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize 2>&1
        } else {
            $output = $InputContent | wlines -px $padding -hl $inputWidth -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize 2>&1
        }
        Write-Output $output
    }
} else {
    if ($p)
    {
        if ([string]::IsNullOrWhiteSpace($InputContent)) {
            $output = wlines -px $padding -hl $inputWidth -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize -p $p 2>&1
        } else {
            $output = $InputContent | wlines -px $padding -hl $inputWidth -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize -p $p 2>&1
        }
            Write-Output $output
    } else
    {
        if ([string]::IsNullOrWhiteSpace($InputContent)) {
            $output = wlines -px $padding -hl $inputWidth -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize 2>&1
        } else {
            $output = $InputContent | wlines -px $padding -hl $inputWidth -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize 2>&1
        }
            Write-Output $output
    }
}


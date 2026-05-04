param (
    [Parameter(ValueFromPipeline)]
    [string]$InputContent,  # Captures single input from the pipeline
    [string]$p,  # Captures single input from the argument
    [switch]$Opaque 
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
$textforeground = $selectedforeground
$textbackground = "#72756e"
$borderColor = "#9beb2e"

$mainforegroundBlurred = "#b5b5a8"
$mainbackgroundBlurred = "#3a3a3a40"
$selectedforegroundBlurred = "#9beb2e"
$selectedbackgroundBlurred = "#9beb2e00"
$textforegroundBlurred = "#f2f2f8"
$textbackgroundBlurred = "#9beb2e00"
$borderColorBlurred = "#9beb2e"

# $textOutline = "#6d6d6d"
$aliasType = 1
# $antiAliasTextbg = "#212121"
$acryllic = "#27282240"
$autoAcryllicBright = "#27282299"

$font = "JetBrainsMono NFM Regular"
$fontsize = 21
$padding = 4
$width = 600
# Modes: complete, keywords
$mode = "complete"

if ($Opaque) 
{
    if ($p)
    {
        if ([string]::IsNullOrWhiteSpace($InputContent))
        {
            $output = wlines -px $padding -wx $width -aabg $antiAliasTextbg -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize -p $p 2>&1
        } else
        {
            $output = $InputContent | wlines -px $padding -wx $width -aabg $antiAliasTextbg -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize -p $p 2>&1
        }
        Write-Output $output
    } else
    {
        if ([string]::IsNullOrWhiteSpace($InputContent))
        {
            $output = wlines -px $padding -wx $width -aabg $antiAliasTextbg -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize 2>&1
        } else
        {
            $output = $InputContent | wlines -px $padding -wx $width -aabg $antiAliasTextbg -bg $mainbackground -fg $mainforeground -sbg $selectedbackground -sfg $selectedforeground -tbg $textbackground -tfg $textforeground -border -bp $padding -bc $borderColor -f $font -fs $fontsize 2>&1
        }
        Write-Output $output
    }
} else
{
    if ($p)
    {
        if ([string]::IsNullOrWhiteSpace($InputContent))
        {
            $output = wlines -px $padding -wx $width -aa $aliasType -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -ac $acryllic -aac $autoAcryllicBright -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize -p $p 2>&1
        } else
        {
            $output = $InputContent | wlines -px $padding -wx $width -aa $aliasType  -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -ac $acryllic -aac $autoAcryllicBright -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize -p $p 2>&1
        }
        Write-Output $output
    } else
    {
        if ([string]::IsNullOrWhiteSpace($InputContent))
        {
            $output = wlines -px $padding -wx $width -aa $aliasType -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -ac $acryllic -aac $autoAcryllicBright -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize 2>&1
        } else
        {
            $output = $InputContent | wlines -px $padding -wx $width -aa $aliasType -bg $mainbackgroundBlurred -fg $mainforegroundBlurred -sbg $selectedbackgroundBlurred -sfg $selectedforegroundBlurred -tbg $textbackgroundBlurred -tfg $textforegroundBlurred -blur -ac $acryllic -aac $autoAcryllicBright -border -bp $padding -bc $borderColorBlurred -f $font -fs $fontsize 2>&1
        }
        Write-Output $output
    }
}

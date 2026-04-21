# Files
# Put your files in .config/bookmarks/.
$ConfigDir = Join-Path $env:USERPROFILE ".config\bookmarks"
$PERS_FILE = Join-Path $ConfigDir "personal.txt"
$WORK_FILE = Join-Path $ConfigDir "work.txt"

# Browsers
$ZEN = "C:\Program Files\Zen Browser\zen.exe"
$CHROME = "C:\Program Files\Google\Chrome\Application\chrome.exe"

# Ensure directory exists
if (-not (Test-Path $ConfigDir)) {
    New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
}

# Ensure files exist with default content
if (-not (Test-Path $PERS_FILE)) {
    @'
# personal
tonybtw :: https://tonybtw.com
https://youtube.com
'@ | Set-Content $PERS_FILE
}

if (-not (Test-Path $WORK_FILE)) {
    @'
# work
[docs] NixOS Manual :: https://nixos.org/manual/
'@ | Set-Content $WORK_FILE
}

function Emit-Bookmarks($Tag, $FilePath) {
    if (-not (Test-Path $FilePath)) { return }
    $lines = Get-Content $FilePath | Where-Object { $_ -notmatch '^\s*(#|$)' }
    foreach ($line in $lines) {
        if ($line -like '*::*') {
            $parts = $line -split '::', 2
            $lhs = $parts[0].Trim()
            $rhs = $parts[1].Trim()
            "[$Tag] $lhs :: $rhs"
        } else {
            $trimmed = $line.Trim()
            "[$Tag] $trimmed :: $trimmed"
        }
    }
}

# Build combined list
$List = @()
$List += Emit-Bookmarks "personal" $PERS_FILE
$List += Emit-Bookmarks "work" $WORK_FILE
$List = $List | Sort-Object

if ($List.Count -eq 0) {
    Write-Warning "No bookmarks found."
    return
}

# Call wrofi.ps1
$WlinesWrapper = Join-Path $PSScriptRoot 'wrofi.ps1'
$Selection = $List -join "`n" | & $WlinesWrapper -p "Bookmarks:"

if ([string]::IsNullOrWhiteSpace($Selection)) {
    return
}

# Parse tag and raw URL
$tag = ""
if ($Selection -match '^\[([^\]]+)\]') {
    $tag = $Matches[1]
}

$raw = ""
if ($Selection -match ' :: (.*)$') {
    $raw = $Matches[1]
} else {
    # Fallback if the format was somehow lost
    $raw = $Selection -replace '^\[[^\]]+\]\s*', ''
}

# Strip inline comments and trim
$url = $raw -replace '\s+(#|//).*$', ''
$url = $url.Trim()

# Ensure scheme
if ($url -notmatch '^(http://|https://|file://|about:|chrome:|edge:)' -and $url -ne "") {
    $url = "https://$url"
}

if ([string]::IsNullOrWhiteSpace($url)) {
    return
}

function Open-With($BrowserPath, $TargetUrl) {
    if (Test-Path $BrowserPath) {
        # Using Start-Process to run in background
        Start-Process $BrowserPath -ArgumentList "--new-tab", $TargetUrl
    } else {
        # Fallback to default browser
        Start-Process $TargetUrl
    }
}

# Pick browser by tag
switch ($tag) {
    "personal" { Open-With $ZEN $url }
    "work"     { Open-With $CHROME $url }
    Default    { Start-Process $url }
}

$sourceBase = Join-Path $PSScriptRoot "myConfig"
$sourceDirs = @(
    $PSScriptRoot,
    $sourceBase,
    (Join-Path $sourceBase "wsl"),
    (Join-Path $sourceBase "ssh"),
    (Join-Path $sourceBase "wlines")
)
$targetDir = "C:\Users\Henri\bin"
$allowedExtensions = @('.ps1', '.exe', '.sh')

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

Write-Host "Cleaning up existing symlinks in $targetDir pointing to $PSScriptRoot..."
Get-ChildItem -Path $targetDir | Where-Object { 
    ($_.Attributes -match "ReparsePoint") -and ($_.Target -like "$PSScriptRoot*")
} | ForEach-Object {
    Write-Host "Removing old symlink: $($_.FullName)"
    Remove-Item $_.FullName -Force
}

foreach ($dir in $sourceDirs) {
    if (-not (Test-Path $dir)) { continue }
    
    # Link only executable types (.ps1, .exe, .sh)
    $files = Get-ChildItem -Path $dir -File | Where-Object { $_.Extension -in $allowedExtensions }
    foreach ($file in $files) {
        # Skip this setup script
        if ($file.Name -eq "setup-symlinks.ps1") { continue }

        $targetPath = Join-Path $targetDir $file.Name
        if (Test-Path $targetPath) {
            Remove-Item $targetPath -Force
        }
        
        Write-Host "Creating symlink: $targetPath -> $($file.FullName)"
        New-Item -ItemType SymbolicLink -Path $targetPath -Value $file.FullName -Force | Out-Null
    }
}

Write-Host "Symlinks created successfully in $targetDir"

# RunAsMinimized
[CmdletBinding()]
param(
    [switch]$fzf
)

$WlinesWrapper = if ($fzf)
{
    Join-Path $PSScriptRoot 'wlines-fzf.ps1'
} else
{
    Join-Path $PSScriptRoot 'wlines-rofi.ps1'
}

# Auto-detect SSH session
$IsRemoteSession = -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or `
    -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)
if ($IsRemoteSession)
{
    Write-Host "SSH session detected - Unity Editor will launch on local machine via pwsh-daemon"
}

$TARGET_DIR = "$env:USERPROFILE\repos"
$UNITY_PROJECTS = ""

if (Test-Path $TARGET_DIR)
{
    $files = Get-ChildItem -Path $TARGET_DIR
    foreach ($path in $files)
    {
        $manifest = "$path/Packages/manifest.json"
        if(Test-Path $manifest)
        {
            if (Select-String -Path $manifest "com.unity")
            {
                if ($UNITY_PROJECTS -eq "")
                {
                    $UNITY_PROJECTS = "$path"
                } else
                {
                    $UNITY_PROJECTS = "$UNITY_PROJECTS`n$path"
                }
                 
            }
        }
    }
    $targetProject = & $WlinesWrapper -InputContent "$UNITY_PROJECTS" -p "Open Project"
        
    if (-not $targetProject -eq "")
    {
        $version = Select-String -Path $targetProject\\ProjectSettings\\ProjectVersion.txt -Pattern '(?<=m_EditorVersion: ).*' | ForEach-Object { $_.Matches.Value }
        $cmd = "`"C:\Program Files\Unity\Hub\Editor\$version\Editor\Unity.exe`" `"-projectPath`" `"$targetProject`""
        
        if ($IsRemoteSession)
        {
            & (Join-Path $PSScriptRoot 'pwsh-msg.ps1') -Command "&$cmd" -Name "Unity Launcher"
        } else
        {
            & "C:\Program Files\Unity\Hub\Editor\$version\Editor\Unity.exe" "-projectPath" "$targetProject"
        }
    }
}

# does not work to execute in non admin
# > & "C:\Program Files\Unity\Hub\Editor\6000.0.58f2\Editor\Unity.exe" "-projectPath" "C:\Users\roock\repos\test"
#
# > Start-Process -FilePath "C:\Program Files\Unity\Hub\Editor\6000.0.58f2\Editor\Unity.exe" -ArgumentList "-projectPath", "C:\Users\roock\repos\test" -Verb RunAsUser
# # (both with and without -Verb)
#
# > Start-UnelevatedProcess -process "C:\Program Files\Unity\Hub\Editor\6000.0.58f2\Editor\Unity.exe" -arguments @("-projectPath", "C:\Users\roock\repos\test")

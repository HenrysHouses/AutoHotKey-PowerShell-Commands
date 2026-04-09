Dependencies:

- AutoHotKeys v 2.0

    `winget install 9PLQFDG8HH9D`

(Optional but recommended) 
- PowerShell 7.x

    `winget install Microsoft.PowerShell`

Once installed, keep the two scripts running and that's it

Optional step: add the pwsh-pipe-daemon script to your shell's path environment variable

My config scripts rely on the wlines binary. it should be portable so it can work on any machine.
but the -fzf flag relies on fzf being installed. This is to make the same scripts usable as TUI instead of GUI

j# Features

- pwsh-pipe-daemon.ps1
    Creates powershell instances to run commands without any additional overhead from windows API.
    - Allows reuse of powershell instances
    - Automatically gets rid of broken / dirty / unusuable instances. typically happens when the powershell state cant be cleaned
    - Singleton and restart support. will attempt to recover from errors.
    - prints all data stored in temp files
    - kill helper to forcably kill unresponsive daemons
    - from applies a name to the logs to signal what requested the invoked message
    - pipename to start a daemon using a unique pipe name overriding the default
    
- pwsh-msg.ps1
    Allows you to send messages directly to pwsh-pipe-daemon.ps1 from cli with ssh support and logging


Dependencies:

- AutoHotKeys v 2.0

    ```pwsh
    winget install 9PLQFDG8HH9D
    ```
    If you want a portable config then make your AHK scripts and compile them to binaries

(Optional but recommended) 
- PowerShell 7.x

    ```pwsh
    winget install Microsoft.PowerShell
    ```

Once installed, keep the two scripts running and that's it

Optional step: add the pwsh-pipe-daemon script to your shell's path environment variable


# My config

Dependencies:

- fzf

    ```pwsh 
    winget install fzf
    ```

My config scripts rely on the wlines binary. it should be portable so it can work on any machine.
but the -fzf flag relies on fzf being installed. This is to make the same scripts usable as TUI instead of GUI

As i use glazewm for window management the tab replacement script i use by defult also uses the glazewm cli. so if you dont have that. use the windows-tab script instead
The open directory / path script also relies on zoxide to resolve unknown paths. so if you want an easier time using that script. get zoxide
https://github.com/ajeetdsouza/zoxide

On wsl i have connected RMPC up with my linux dual boot drive to give me a cross OS music player.

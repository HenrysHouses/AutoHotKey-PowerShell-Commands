# PowerShell Pipe Commands

A set of scripts to enable near-instant execution of PowerShell commands from external sources (AHK, CLI, etc.) by using a background daemon that reuses PowerShell instances.

## Core Components

### pwsh-pipe-daemon.ps1
The background service that listens on a named pipe and manages a pool of PowerShell instances.

**Usage:**
```powershell
pwsh-pipe-daemon.ps1 [-List] [-Kill <PID>] [-PipeName <String>] [-Help]
```

**Options:**
- `-List`: Show all running daemon instances and their status. Automatically cleans up broken instances when detected.
- `-Log <str>`: Outputs the logs for the matching pipe daemon *(not implemented yet)*
- `-Kill <PID>`: Gracefully terminate a daemon instance by its Process ID.
- `-Help`: Show the built-in help message.
- `-PipeName <Str>`: Specify a custom pipe name (default: `PWSH_COMMAND_PIPE`).
- `-Help`: Show the built-in help message.


**Features:**
- **Instance Reuse:** Creates and manages a pool of up to 5 PowerShell instances to minimize overhead.
- **State Management:** Automatically detects and replaces broken, dirty, or unusable instances.
- **Singleton Support:** Operates as a singleton based on the pipe name.
- **Logging:** Tracks instances and states via temporary JSON files for validation.
    Daemon logs: `$env:LOCALAPPDATA/pwsh-pipe-daemons/$pipeName-daemon.log`
    Instance temp tracking: `$env:TEMP/pwsh-daemon-instances`
- **External Integration:** Can be utilized by anything that can write to a named pipe (AHK, PowerShell, etc.).

### pwsh-msg.ps1
A named pipe wrapper to send commands to a running daemon.

**Usage:**
```powershell
pwsh-msg.ps1 -Command <String> [-Name <String>] [-PipeName <String>] [-Restart] [-Help]
```

**Options:**
- `-Command <Str>`: The PowerShell command or script block to execute.
    - *Toggle Behavior:* Requesting an identical command while it is already running will automatically cancel it.
- `-Cancel`: Cancels the command if it is running. (will not start any executions) *(not implemented yet)*
- `-Restart`: Restarts the command if it is already running (cancels and then re-executes). 
- `-Name <Str>`: Optional identifier to show in the daemon logs (useful for SSH sessions or specific tools).
- `-PipeName <Str>`: Specify the target pipe (default: `PWSH_COMMAND_PIPE`).
- `-Help`: Show the built-in help message.

**Note:** For maximum performance from outside a terminal, writing directly to the named pipe is faster than calling this script, as it avoids the overhead of spawning a new PowerShell process just to send a message.

## Dependencies

- **AutoHotKeys v2.0**

    AutoHotKeys is only a requirement to execute uncompiled scripts. 

    This dependency only applies to you if:
    - you want to be able to edit and relaunch the `.ahk` script.

    otherwise if you already have a usable compiled script, then this can be skipped.

    ```powershell
    winget install 9PLQFDG8HH9D
    ```

## Installation & Setup

1. Keep the two scripts in a directory accessible to your tools. I keep mine in ~/bin, or symlinked to that location
2. (Optional) Add the script directory to your system's `PATH`.
3. Start the daemon in the background or a dedicated terminal.

## Advanced Configuration (My Config)

These additional scripts and tools build on the pipe daemon:

- **fzf:** Required for TUI-based scripts (`winget install fzf`).
- **wlines:** A portable binary used by many scripts for dmenu / rofi based operations.
- **GlazeWM CLI:** Used by the default alt+tab replacement script.
- **Zoxide:** Used for resolving unknown paths in directory scripts.
- **WSL integration:** Includes RMPC setup for dual boot music control.

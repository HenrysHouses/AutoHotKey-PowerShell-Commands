# PowerShell Pipe Daemon & Messenger

This project provides a mechanism to execute PowerShell commands asynchronously via a named pipe, allowing for communication between different processes or even from remote SSH sessions to a local Windows host.

## Components

### 1. PowerShell Pipe Daemon (`pwsh-pipe-daemon.ps1`)

The daemon acts as a server that listens on a named pipe. It manages a pool of PowerShell runspaces to execute incoming commands without blocking the main loop.

#### Flags and Parameters

- **`-PipeName <string>`**: The name of the named pipe to create. Defaults to `PWSH_COMMAND_PIPE`. Both the daemon and messenger must use the same name.
- **`-List`**: Displays all active and recently dead daemon instances found in the temporary directory. It shows details like PID, creation time, pool size, and currently running commands.
- **`-Kill <PID>`**: Gracefully terminates a daemon instance with the specified Process ID (PID).
- **`-Help`**: Displays the usage information and features of the script.

#### Key Features

- **Runspace Pooling**: Uses a `RunspacePool` to handle up to 5 concurrent commands.
- **Async Execution**: Commands are executed in the background, allowing the daemon to remain responsive to new connections.
- **State Persistence**: Metadata about running instances is stored in `$env:TEMP\pwsh-daemon-instances\`, allowing for easy monitoring and management via `-List`.
- **Command Cancellation/Restart**: Supports special prefixes (`__RESTART__`) to stop an existing command if it's already running and start it fresh.
- **Sender Identification**: Can identify and log the sender of a command (e.g., from an SSH session).

---

### 2. PowerShell Pipe Messenger (`pwsh-msg.ps1`)

The messenger is a client script used to send commands to a running daemon.

#### Flags and Parameters

- **`-Command <string>`** (Position 0): The PowerShell command or script block you want the daemon to execute.
- **`-Name <string>`**: An optional name to identify the sender. If omitted, the script automatically attempts to detect if it's running in an SSH session and includes the source IP.
- **`-PipeName <string>`**: The name of the target pipe. Must match the daemon's `PipeName`. Defaults to `PWSH_COMMAND_PIPE`.
- **`-Restart`**: If this switch is used, it tells the daemon to cancel any currently running instance of the *exact same command* before executing it again. This is useful for scripts that should only have one instance running at a time.
- **`-Help`**: Displays the usage information and an example.

#### Key Features

- **SSH Detection**: Automatically prepends `ssh:<IP>` to the sender name if an SSH environment variable (`SSH_CONNECTION` or `SSH_CLIENT`) is detected.
- **Lightweight**: Connects, sends the message, and disconnects quickly.

---

## Example Usage

### 1. Start the Daemon
In one PowerShell window:
```powershell
.\pwsh-pipe-daemon.ps1
```

### 2. Send a Command
In another window (or via SSH):
```powershell
.\pwsh-msg.ps1 "Write-Host 'Hello from the pipe!'"
```

### 3. Restart a Long-Running Task
```powershell
.\pwsh-msg.ps1 "Start-Sleep -Seconds 60; Write-Host 'Finished'" -Restart
```
Running this again while the first is still active will cancel the first 60-second sleep and start a new one.

### 4. List Active Daemons
```powershell
.\pwsh-pipe-daemon.ps1 -List
```

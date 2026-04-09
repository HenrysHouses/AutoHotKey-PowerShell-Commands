#Requires AutoHotkey v2.0
#SingleInstance

pipeName := "PWSH_COMMAND_PIPE"
global pipe := -1
OnExit(KillConnection)

; --- Keybinds ---

^Space:: {
    content := "__FROM__:AutoHotKeys`nwlines-start"
    PipeWrite(content, pipeName)
}

^!k:: {
    content := "__FROM__:AutoHotKeys`nwlines-close"
    PipeWrite(content, pipeName)
}

^!+k:: {
    content := "__FROM__:AutoHotKeys`nwlines-close -force"
    PipeWrite(content, pipeName)
}

!Tab:: {
    content := "__FROM__:AutoHotKeys`nwlines-glazewm-tab"
    PipeWrite(content, pipeName)
}

^!Tab:: {
    content := "__FROM__:AutoHotKeys`nwlines-windows-tab -HideMode"
    PipeWrite(content, pipeName)
}

^!o:: {
content := "__FROM__:AutoHotKeys`nwlines-path"
             PipeWrite(content, pipeName)
}

^!+o:: {
content := "__FROM__:AutoHotKeys`nwlines-path -Explorer"
             PipeWrite(content, pipeName)
}

^!u:: {
    content := "__FROM__:AutoHotKeys`nwlines-unity"
    PipeWrite(content, pipeName)
}

^!p:: {
    content := "__FROM__:AutoHotKeys`nwlines-vimprojects"
    PipeWrite(content, pipeName)
}


; JSON library for v2.0
class JSON {
    static Parse(text) {
        static q := Chr(34)
        text := Trim(text)
        return JSON.Decode(text, q)
    }
    
    static Decode(&text, q) {
        text := Trim(text)
        if (text = "null")
            return ""
        else if (text = "true")
            return 1
        else if (text = "false")
            return 0
        else if (SubStr(text, 1, 1) = q) {
            i := 2
            while (i <= StrLen(text)) {
                c := SubStr(text, i, 1)
                if (c = q)
                    return SubStr(text, 2, i - 2)
                i++
            }
        }
        else if (SubStr(text, 1, 1) = "{") {
            obj := {}
            i := 2
            while (i <= StrLen(text)) {
                c := SubStr(text, i, 1)
                if (c = "}")
                    return obj
                if (c = ",")
                    i++
                while (i <= StrLen(text) && SubStr(text, i, 1) ~= "[ `t`r`n]")
                    i++
                key := JSON.Decode(SubStr(text, i), q)
                while (i <= StrLen(text) && SubStr(text, i, 1) != ":")
                    i++
                i++
                value := JSON.Decode(SubStr(text, i), q)
                obj[key] := value
                while (i <= StrLen(text) && SubStr(text, i, 1) ~= "[ `t`r`n,:]")
                    i++
            }
            return obj
        }
        else if (SubStr(text, 1, 1) = "[") {
            arr := []
            i := 2
            while (i <= StrLen(text)) {
                c := SubStr(text, i, 1)
                if (c = "]")
                    return arr
                if (c = ",")
                    i++
                value := JSON.Decode(SubStr(text, i), q)
                arr.Push(value)
                while (i <= StrLen(text) && SubStr(text, i, 1) ~= "[ `t`r`n,\]]")
                    i++
            }
            return arr
        }
        return ""
    }
}

; --- Methods ---

TryConnect() {
    global pipe := DllCall("CreateFileW",
        "Str",  "\\.\pipe\" pipeName,
        "UInt", 0x40000000, ; dwDesiredAccess (GENERIC_WRITE)
        "UInt", 0,          ; dwShareMode
        "Ptr",  0,          ; lpSecurityAttributes
        "UInt", 3,          ; dwCreationDisposition (OPEN_EXISTING)
        "UInt", 0,          ; dwFlagsAndAttributes
        "Ptr",  0           ; hTemplateFile
    )
}

KillConnection(ExitReason, ExitCode)
{
    content := "Close Pipe"
    PipeWrite(content, pipeName)
    CleanupPipe()
}

Disconnect()
{
    content := "Close Pipe"
    PipeWrite(content, pipeName)
    CleanupPipe()
}

TestPipe() {
    global pipe
    return DllCall("WriteFile", "Ptr", pipe, "Ptr", 0, "UInt", 0, "UInt*", 0, "Ptr", 0)
}

CleanupPipe() {
    global pipe
    if (pipe != -1) {
        DllCall("CloseHandle", "Ptr", pipe)
        pipe := -1
    }
}

WriteString(str, pipe) {
    bytesLength := StrPut(str, "UTF-8") -1
    buff := Buffer(bytesLength)
    StrPut(str, buff, "UTF-8")

    try {
        if not DllCall("WriteFile", "Ptr", pipe, "Ptr", buff, "UInt", bytesLength, "UInt*", &_:=0, "Ptr", 0) {
            throw OSError(A_LastError)
        }
    } catch Error as e {
        CleanupPipe()
        throw e
    }
}

PipeWrite(content, pipeName) {
    global pipe

    if (pipe == -1) {
        TryConnect()
    }

    if (pipe == -1) {
        ; Check daemon state from temp files
        daemonTempDir := A_Temp . "\pwsh-daemon-instances"
        daemonFiles := ""
        totalBusy := 0
        totalIdle := 0
        
        Loop Files, daemonTempDir . "\daemon_*.json" {
            try {
                daemonFile := FileRead(A_LoopFileFullPath)
                daemonData := JSON.Parse(daemonFile)
                
                busyCount := 0
                idleCount := 0
                for instance in daemonData.Instances {
                    if (instance.IsBusy) {
                        busyCount++
                        totalBusy++
                    } else {
                        idleCount++
                        totalIdle++
                    }
                }
                daemonFiles .= A_LoopFileName . " (Busy: " . busyCount . ", Idle: " . idleCount . ")`n"
            } catch Error as e {
                daemonFiles .= A_LoopFileName . " (Error reading)`n"
            }
        }
        
        if (daemonFiles = "") {
            result := MsgBox(
                "No daemon instances found.`n`n"
                "Would you like to start one now?",
                "Daemon Not Running",
                "0x4"
            )
            if (result = "Yes") {
                Run("pwsh -NoProfile -Command pwsh-pipe-daemon", , "Hide")
                Sleep(1000)
                TryConnect()
            }
        } else if (totalIdle = 0) {
            MsgBox(
                "All daemon instances are busy (0 idle).`n`n"
                "Instances:`n" . daemonFiles . "`n"
                "Waiting for resources to free up...",
                "All Instances Busy",
                "0x30"
            )
        } else {
            MsgBox(
                "Failed to connect to daemon pipe.`n`n"
                "Idle instances available:`n" . daemonFiles . "`n"
                "Try restarting this script.",
                "Connection Error",
                "0x30"
            )
        }
        return
    }

    try {
        WriteString(content, pipe)
        WriteString("Close Pipe", pipe)
        CleanupPipe()
    } catch Error as e {
        CleanupPipe()
    }
}

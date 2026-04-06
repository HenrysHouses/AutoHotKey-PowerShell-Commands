#Requires AutoHotkey v2.0
#SingleInstance
pipeName := "PWSH_COMMAND_PIPE"
global pipe := -1
OnExit(Disconnect)

; --- Keybinds ---

^!i:: {
    content := "echo test"
    PipeWrite(content, pipeName)
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

Disconnect(ExitReason, ExitCode)
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

PipeWrite(content, pipeName) {
    global pipe

    if (pipe != -1 && !TestPipe()) {
        CleanupPipe()
    }

    if pipe == -1 {
        TryConnect()
    }

    if pipe == -1 {
        result := MsgBox("there is no pwsh-pipe-daemon with open pipes available, Try to start one?", "Confirmation", "0x4")
        if (result = "Yes")
        {
            Run("pwsh -Command pwsh-pipe-daemon", , "Hide")
        }
        return
    }

    WriteString(content, pipe)

    return

    WriteString(str, pipe) {
        bytesLength := StrPut(str, "UTF-8") -1
        buff := Buffer(bytesLength)
        StrPut(str, buff, "UTF-8")

        if not DllCall("WriteFile", "Ptr", pipe, "Ptr", buff, "UInt", bytesLength, "UInt*", &_:=0, "Ptr", 0) {
            throw OSError()
        }
    }
}

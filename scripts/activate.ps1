# Protocol handler for ccwinnotify://<path>
# Force-activates the Cursor window of the given project, bypassing Windows
# foreground-lock denials (the "taskbar button flashes but nothing focuses" case).
# Logs every stage to %TEMP%\ccwinnotify.log for diagnosis.
# Pure ASCII: Windows PowerShell 5.1 parses BOM-less .ps1 as ANSI.
param([Parameter(Position = 0)][string]$Uri = '')
$ErrorActionPreference = 'SilentlyContinue'
$logFile = Join-Path $env:TEMP 'ccwinnotify.log'
function Log([string]$m) {
    $line = (Get-Date -Format 'HH:mm:ss') + ' ' + $m
    Add-Content -Path $logFile -Value $line
    Write-Output $line
}

Log ('invoked uri=' + $Uri)
$path = $Uri -replace '^ccwinnotify://(file/)?', '' -replace '/', '\'
$path = $path.TrimEnd('\')
if (-not $path) { Log 'empty path, exit'; exit 0 }
$leaf = Split-Path $path -Leaf
Log ('leaf=' + $leaf)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinAct {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    public static bool Force(IntPtr hWnd) {
        if (IsIconic(hWnd)) { ShowWindow(hWnd, 9); }
        uint pid;
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        uint myThread = GetCurrentThreadId();
        bool attached = fgThread != myThread && AttachThreadInput(myThread, fgThread, true);
        keybd_event(0x12, 0, 0, UIntPtr.Zero);
        keybd_event(0x12, 0, 2, UIntPtr.Zero);
        bool ok = SetForegroundWindow(hWnd);
        if (attached) { AttachThreadInput(myThread, fgThread, false); }
        return ok;
    }
}
"@

$wins = Get-Process -Name Cursor -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
Log ('cursor windows: ' + ((@($wins) | ForEach-Object { $_.Id.ToString() + ':' + $_.MainWindowTitle }) -join ' | '))
$win = $wins | Where-Object { $_.MainWindowTitle -like ('*' + $leaf + '*') } | Select-Object -First 1
if ($win) {
    $r = [WinAct]::Force($win.MainWindowHandle)
    Log ('focus attempt pid=' + $win.Id + ' title=' + $win.MainWindowTitle + ' setfg=' + $r)
    exit 0
}
Log 'no window match, fallback to cursor protocol'
Start-Process ('cursor://file/' + ($path -replace '\\', '/'))
exit 0

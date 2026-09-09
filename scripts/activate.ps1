# Protocol handler for ccwinnotify://<path>
# Force-activates the Cursor window of the given project, bypassing Windows
# foreground-lock denials (the "taskbar button flashes but nothing focuses" case).
# Pure ASCII: Windows PowerShell 5.1 parses BOM-less .ps1 as ANSI.
param([Parameter(Position = 0)][string]$Uri = '')
$ErrorActionPreference = 'SilentlyContinue'

$path = $Uri -replace '^ccwinnotify://', '' -replace '/', '\'
$path = $path.TrimEnd('\')
if (-not $path) { exit 0 }
$leaf = Split-Path $path -Leaf

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
    public static void Force(IntPtr hWnd) {
        ShowWindow(hWnd, 9); // SW_RESTORE
        uint pid;
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        uint myThread = GetCurrentThreadId();
        bool attached = fgThread != myThread && AttachThreadInput(myThread, fgThread, true);
        keybd_event(0x12, 0, 0, UIntPtr.Zero); // ALT down/up satisfies the foreground lock
        keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(hWnd);
        if (attached) { AttachThreadInput(myThread, fgThread, false); }
    }
}
"@

$win = Get-Process -Name Cursor -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like ('*' + $leaf + '*') } |
    Select-Object -First 1
if ($win) {
    [WinAct]::Force($win.MainWindowHandle)
    exit 0
}
# No matching window: fall back to the IDE protocol (opens/creates the window)
Start-Process ('cursor://file/' + ($path -replace '\\', '/'))
exit 0

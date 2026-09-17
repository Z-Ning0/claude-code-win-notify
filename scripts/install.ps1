# One-time setup: register the "Claude Code" AppUserModelId so Windows 11 delivers
# WinRT toasts from this desktop sender. Without a registered AUMID, Show() succeeds
# but the toast is silently dropped (never reaches the Action Center).
# Idempotent: safe to re-run.
$ErrorActionPreference = 'Stop'
$key = 'HKCU:\Software\Classes\AppUserModelId\Claude Code'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name 'DisplayName' -Value 'Claude Code'
Set-ItemProperty -Path $key -Name 'ShowInSettings' -Value 1 -Type DWord
Write-Output "registered: $key"

# ccwinnotify:// protocol -> force-foreground window activation (beats the
# intermittent foreground-lock denial of plain cursor:// jumps)
$protoKey = 'HKCU:\Software\Classes\ccwinnotify'
$cmdKey = Join-Path (Join-Path $protoKey 'shell') 'open\command'
New-Item -Path $cmdKey -Force | Out-Null
Set-ItemProperty -Path $protoKey -Name '(default)' -Value 'URL:ccwinnotify'
Set-ItemProperty -Path $protoKey -Name 'URL Protocol' -Value ''
$handler = '"' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'activate.ps1') + '" "%1"'
Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $handler
Write-Output "registered: $cmdKey -> activate.ps1"

# COM toast activator: compile, register per-user CLSID, stamp Start Menu shortcut
$clsid = '{7E3B5A19-9F1D-4E1B-89B0-48A8E2F8C0AA}'
$exeDir = Join-Path $env:LOCALAPPDATA 'claude-win-notify'
if (-not (Test-Path $exeDir)) { New-Item -ItemType Directory -Path $exeDir | Out-Null }
$exe = Join-Path $exeDir 'toast-activator.exe'
$src = Join-Path $PSScriptRoot 'toast-activator.cs'
Copy-Item (Join-Path $PSScriptRoot 'activate.ps1') $exeDir -Force
if ((-not (Test-Path $exe)) -or ((Get-Item $src).LastWriteTime -gt (Get-Item $exe).LastWriteTime)) {
    & (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /out:$exe $src
    if (-not (Test-Path $exe)) { throw 'csc compile failed' }
}
$ck = 'HKCU:\Software\Classes\CLSID\' + $clsid
New-Item -Path $ck -Force | Out-Null
Set-ItemProperty -Path $ck -Name '(default)' -Value 'Claude Code Toast Activator'
New-Item -Path (Join-Path $ck 'LocalServer32') -Force | Out-Null
Set-ItemProperty -Path (Join-Path $ck 'LocalServer32') -Name '(default)' -Value ('"' + $exe + '"')
$lnk = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Claude Code.lnk'
if (-not (Test-Path $lnk)) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $sc.Save()
}
$hr = & $exe /stamp $lnk $clsid
Write-Output ("stamp shortcut hr=" + $hr)
Write-Output 'Done. Windows may need a few seconds before toasts from this sender appear.'

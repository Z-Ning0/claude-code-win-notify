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
$handler = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'activate.ps1') + '" "%1"'
Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $handler
Write-Output "registered: $cmdKey -> activate.ps1"
Write-Output 'Done. Windows may need a few seconds before toasts from this sender appear.'

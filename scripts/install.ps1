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
Write-Output 'Done. Windows may need a few seconds before toasts from this sender appear.'

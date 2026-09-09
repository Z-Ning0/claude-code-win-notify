# Claude Code Windows toast notification hook.
# Reads hook JSON on stdin (.message / .error / .cwd / .hook_event_name).
# -Text overrides the body when stdin carries no message (Stop / StopFailure).
# Env overrides (all optional):
#   CC_NOTIFY_PROTOCOL         IDE protocol for the jump button (default: cursor; e.g. vscode)
#   CC_NOTIFY_TEXT_STOP        body for Stop events
#   CC_NOTIFY_TEXT_STOPFAILURE body for StopFailure events
# Keep this file pure ASCII: Windows PowerShell 5.1 parses BOM-less .ps1 as ANSI.
param([string]$Text = '')
$ErrorActionPreference = 'SilentlyContinue'

try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$raw = [Console]::In.ReadToEnd()
$obj = $null
if ($raw) {
    try { $obj = $raw | ConvertFrom-Json } catch {}
}

$msg = $null
if ($obj) { $msg = $obj.message }
if (-not $msg) {
    if ($obj -and $obj.hook_event_name -eq 'StopFailure' -and $env:CC_NOTIFY_TEXT_STOPFAILURE) { $msg = $env:CC_NOTIFY_TEXT_STOPFAILURE }
    elseif ($obj -and $obj.hook_event_name -eq 'Stop' -and $env:CC_NOTIFY_TEXT_STOP) { $msg = $env:CC_NOTIFY_TEXT_STOP }
    elseif ($Text) { $msg = $Text }
}
if ($obj -and $obj.error) { $msg = $msg + ' [' + $obj.error + ']' }
if (-not $msg) { $msg = 'Claude Code needs your attention' }

# Prefix the project folder so parallel sessions are tellable apart
$proj = $null
if ($obj -and $obj.cwd) { try { $proj = Split-Path $obj.cwd -Leaf } catch {} }
if ($proj) { $msg = '[' + $proj + '] ' + $msg }
# Control chars (tab/newline) mangle toast text
$msg = $msg -replace '[\x00-\x1F]', ' '
if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) }
$safe = $msg.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')

# Sound: CC_NOTIFY_SOUND picks a system preset (IM, Mail, Reminder, Looping.Alarm2, ...
# or a full ms-winsoundevent: URI); CC_NOTIFY_SOUND_FILE plays a custom .wav instead
# (toast audio muted to avoid double sound).
$soundSrc = 'ms-winsoundevent:Notification.Default'
if ($env:CC_NOTIFY_SOUND) {
    $soundSrc = $env:CC_NOTIFY_SOUND
    if ($soundSrc -notlike 'ms-winsoundevent:*') { $soundSrc = 'ms-winsoundevent:Notification.' + $soundSrc }
}
$audioXml = '<audio src="' + $soundSrc + '"/>'
$playFile = $env:CC_NOTIFY_SOUND_FILE
if ($playFile) { $audioXml = '<audio silent="true"/>' }

# Jump button: default goes through our ccwinnotify:// handler, which force-activates
# the IDE window (plain protocol jumps intermittently lose the foreground-lock race).
# CC_NOTIFY_PROTOCOL overrides with a direct IDE protocol (cursor, vscode, ...).
$launch = ''
$launchAttr = ''
$actionsXml = ''
if ($obj -and $obj.cwd) {
    $slashes = $obj.cwd -replace '\\','/'
    $jump = 'ccwinnotify://' + $slashes
    if ($env:CC_NOTIFY_PROTOCOL) { $jump = $env:CC_NOTIFY_PROTOCOL + '://file/' + $slashes }
    $launch = $jump.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
    $launchAttr = ' launch="' + $launch + '"'
    $actionsXml = '  <actions><action activationType="protocol" arguments="' + $launch + '" content="Open project window"/></actions>'
}

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

    $xmlString = @"
<toast$launchAttr scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>Claude Code</text>
      <text>$safe</text>
    </binding>
  </visual>
  $audioXml
$actionsXml
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlString)
    $toast = New-Object Windows.UI.Notifications.ToastNotification($xml)
    $toast.SuppressPopup = $false
    $toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(30)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show($toast)
    if ($playFile) {
        try {
            $sp = New-Object System.Media.SoundPlayer $playFile
            $sp.PlaySync()
        } catch {}
    }
    exit 0
} catch {
    # Fallback: legacy tray balloon (keep alive while it shows; disposing kills it)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.Visible = $true
        $n.BalloonTipTitle = 'Claude Code'
        $n.BalloonTipText = $msg
        $n.ShowBalloonTip(10000)
        [System.Media.SystemSounds]::Asterisk.Play()
        Start-Sleep -Seconds 8
        $n.Dispose()
    } catch {}
    exit 0
}

# claude-win-notify

Windows toast notifications for [Claude Code](https://docs.claude.com/en/docs/claude-code), built for the cases other notifiers miss:

- **Reply completed** (`Stop`) — know when a long task finished while you were away
- **Needs attention** (`Notification`) — permission prompts and idle-waiting
- **Turn died on an API/gateway error** (`StopFailure`) — 503s, SSE drops, bad-channel 400s: the terminal shows a red line and nothing else happens; now you get a toast with the error category
- **One-click jump back** — an "Open project window" button routes through a bundled `ccwinnotify://` handler that force-activates the IDE window of the notifying session (Alt-trick + SetForegroundWindow), beating the intermittent Windows foreground-lock denial that makes plain `cursor://` jumps flash the taskbar instead; set `CC_NOTIFY_PROTOCOL` to fall back to a direct IDE protocol
- **Multi-session safe** — every toast is prefixed with the project folder name from the hook's `cwd`
- **Zero dependencies** — pure PowerShell + WinRT, no modules, no binaries

## Install

From GitHub (after publish):

```
/plugin marketplace add <your-org>/claude-code-win-notify
/plugin install claude-win-notify@zning-plugins
```

From a local clone:

```
/plugin marketplace add D:\path\to\claude-code-win-notify
/plugin install claude-win-notify@zning-plugins
```

Then, once per machine (fixes Windows 11 silently dropping desktop toasts):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin-dir>\scripts\install.ps1
```

Restart your Claude Code session — `Stop`/`StopFailure` hooks load at session start.

> If you already have manual `Notification`/`Stop`/`StopFailure` hooks in `settings.json`, remove them after installing, or every event fires two toasts.

## Customize (optional env vars)

| Variable | Default | Purpose |
|---|---|---|
| `CC_NOTIFY_PROTOCOL` | unset = built-in force-foreground handler | direct IDE protocol for the jump button (`cursor`, `vscode`) as a fallback |
| `CC_NOTIFY_TEXT_STOP` | `Claude finished - waiting for your input` | body for completion toasts |
| `CC_NOTIFY_TEXT_STOPFAILURE` | `Claude turn failed (API/gateway error) - check terminal` | body for failure toasts |
| `CC_NOTIFY_SOUND` | unset = default chime | system preset: `IM`, `Mail`, `Reminder`, `Looping.Alarm2`, ... or a full `ms-winsoundevent:` URI |
| `CC_NOTIFY_SOUND_FILE` | unset | path to a custom `.wav`; toast audio is muted and the file plays instead |

Set them in `settings.json` `env` (Unicode-safe, so non-English text works there).

## 中文说明

Windows 11 桌面 Toast 有四个坑，本插件已全部处理：

1. **发送方 AUMID 未注册 → Toast 静默丢弃**（`Show()` 成功但通知中心无记录）。解法：`install.ps1` 写入 `HKCU\Software\Classes\AppUserModelId\Claude Code`。
2. **点正文不触发跳转**：非打包发送方没有 COM 激活器。解法：改用 `activationType="protocol"` 按钮，由系统直接派发协议。
3. **ps1 含中文即乱码**：Write/无 BOM 的 UTF-8 被 PowerShell 5.1 按 GBK 解析。解法：脚本纯 ASCII，中文文案走 stdin/argv/env。
4. **托盘气球 Dispose 即灭**：旧式气球方案必须保活进程，本插件仅在 WinRT 失败回退时使用并保活 8 秒。

## Troubleshooting

- **No toast at all, Action Center empty** → run `install.ps1` (AUMID registration), check Windows Settings → System → Notifications is on and not in Do-Not-Disturb.
- **Toast appears for a split second** → you are on the balloon fallback and something disposed it; report your Windows build.
- **Jump button opens the wrong app** → set `CC_NOTIFY_PROTOCOL` to your IDE (`vscode`).
- **Jump only flashes the taskbar** → foreground-lock denial; v1.1+ routes jumps through the bundled `ccwinnotify://` force-activation handler. Re-run `install.ps1` after updating to (re)register the protocol. If your IDE is not Cursor, set `CC_NOTIFY_PROTOCOL` instead.
- **Hooks fire twice** → manual hooks still present in `settings.json`; remove them.

## Notes

- `Stop`/`StopFailure` fire once per main-agent turn; subagent completion is not covered (add a `SubagentStop` entry if you want it).
- Toasts stay in the Action Center for 30 minutes even if you miss the banner.

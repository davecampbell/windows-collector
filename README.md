# Windows foreground-window collection with Telegraf

This package records every visible top-level window with a nonempty title bar once a minute. Each window record includes its application, title, process ID, and whether it is the foreground (keyboard-active) window. It also saves a PNG of all active displays every 15 minutes. Telegraf receives activity metadata only; the helper writes the image files locally.

## Documentation

- [Install guide](INSTALL-GUIDE.md): download and verify Telegraf, install it on Windows, test the collector, and run it in the signed-in user's session.
- [Deployment options](DEPLOYMENT.md): choose direct shared-drive writes, a resilient local spool and uploader, or separate telemetry and image storage; includes identity, retention, and security guidance.
- [Network storage and upload](NETWORK-STORAGE.md): configure direct OMV UNC writes or prepare the recommended local-spool-and-upload approach.

## Quick start

1. Copy `foreground-window.ps1` to `C:\ProgramData\Telegraf\scripts\foreground-window.ps1`.
2. Copy `start-telegraf-hidden.vbs` to `C:\ProgramData\Telegraf\scripts\start-telegraf-hidden.vbs` for the recommended hidden Scheduled Task launcher.
3. Copy `telegraf-activity.conf` to `C:\Program Files\InfluxData\telegraf\telegraf-activity.conf`, beside `telegraf.exe`. It includes a local telemetry-spool output at `C:\ProgramData\Telegraf\spool\telemetry\activity.lp` and leaves the default `telegraf.conf` untouched.
4. Create `C:\ProgramData\Telegraf\screen-captures` and `C:\ProgramData\Telegraf\spool\telemetry`, and restrict them to the intended account and administrators.
5. Run the collector in the signed-in user's session. A standard Windows service runs outside that interactive session and will not reliably see the foreground window or capture the display. A practical approach is a Scheduled Task set to **Run only when user is logged on**, started at logon, that launches a user-scoped Telegraf instance with this config.
6. Test the script interactively before deploying:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Telegraf\scripts\foreground-window.ps1 -CaptureScreenshot -CaptureEveryMinutes 1
   ```

The command emits one JSON object. Telegraf's `inputs.exec` input parses it every minute.

### Screenshot schedule

Window inventory runs every minute. In `telegraf-activity.conf`, change the value after `-CaptureEveryMinutes` to select the screenshot interval:

| Value | Screenshot cadence |
|---:|---|
| `2` | Every 2 minutes |
| `5` | Every 5 minutes |
| `15` | Every 15 minutes (default) |

The script accepts any whole number of minutes from 1 through 1,440. Restart the user-session Telegraf task after changing its configuration.

Start Telegraf with the dedicated collector configuration file beside the executable:

```powershell
.\telegraf.exe --config '.\telegraf-activity.conf'
```

## Data handling

Window titles and screenshots may contain passwords, messages, customer information, browser content, or health/financial data. Treat them as sensitive endpoint telemetry:

- Inform and obtain approval from affected users as your policy requires.
- Encrypt data in transit and at rest; limit access to the telemetry bucket and screenshot directory.
- Apply a short retention period.
- Upload screenshots to an approved private object store, then send only an opaque image ID or protected URL as the `screenshot_path` field. Do not put image bytes in Telegraf metrics.

`application` and `user` are appropriate candidates for tags if you add a Telegraf processor later. Leave `window_title` as a field: a changing title as a tag creates excessive time-series cardinality.

## Scope and behavior

- It enumerates visible top-level windows that expose a nonempty title bar. Background processes and apps without a normal top-level window are not included.
- The `is_foreground` field identifies the one keyboard-active window when one is available.
- It uses the virtual desktop, so a screenshot includes all monitors.
- The collector requests per-monitor DPI awareness before capture so screenshots use native physical pixels rather than Windows display-scaling dimensions.
- Screen capture is best-effort: activity data is still emitted if a capture fails.
- The default schedule captures at minute 00, 15, 30, and 45 of each hour. This is deliberately simple and avoids maintaining state.

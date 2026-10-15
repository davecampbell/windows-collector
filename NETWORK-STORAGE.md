# Optional network storage and upload

By default, this collector saves screenshots and telemetry to the local computer. Network storage is optional. Use Windows UNC paths with backslashes:

```text
\\OMV\data-dumps\machine-info\
```

Do not use a mapped drive letter or the forward-slash form (`//OMV/...`). The signed-in account that runs the collector must have permission to create folders and files on the SMB share.

Before changing the collector, test share access in PowerShell while signed in as that user:

```powershell
Test-Path '\\OMV\data-dumps\machine-info'
```

## Choose a delivery mode

| Mode | How it works | Best for |
|---|---|---|
| Direct UNC write | Screenshots and telemetry write straight to OMV. | A stable LAN and low setup overhead. |
| Local spool + upload | The collector always writes locally; a separate uploader copies completed files to OMV and retries after outages. | High-frequency, full-resolution capture; recommended. |

## Option A: Direct UNC write

This is the simplest option, but a temporary share outage can cause a screenshot attempt to fail. Create the target directories on OMV before starting Telegraf. Use a separate directory for each computer/account to avoid file collisions.

Example paths for one machine:

```text
\\OMV\data-dumps\machine-info\screenshots\DESKTOP-7M2Q\CONTOSO_alex
\\OMV\data-dumps\machine-info\telemetry\DESKTOP-7M2Q\CONTOSO_alex
```

In `telegraf-activity.conf`, change the screenshot argument from:

```toml
'-ScreenshotDirectory', 'C:\ProgramData\Telegraf\screen-captures'
```

to:

```toml
'-ScreenshotDirectory', '\\OMV\data-dumps\machine-info\screenshots\DESKTOP-7M2Q\CONTOSO_alex'
```

Then change the file-output path from:

```toml
files = ['C:\ProgramData\Telegraf\spool\telemetry\activity.lp']
```

to:

```toml
files = ['\\OMV\data-dumps\machine-info\telemetry\DESKTOP-7M2Q\CONTOSO_alex\activity.lp']
```

Restart the user-session Scheduled Task after saving the configuration. The script will create date folders beneath the screenshot directory only if it is configured to do so; the current collector writes directly to the directory supplied above. Create the desired date hierarchy in the collector before relying on it for multiple days.

## Option B: Local spool plus automatic upload (recommended)

With this mode, **do not change the screenshot directory or the output `files` path** in `telegraf-activity.conf`. Keep these local values:

```toml
'-ScreenshotDirectory', 'C:\ProgramData\Telegraf\screen-captures'
files = ['C:\ProgramData\Telegraf\spool\telemetry\activity.lp']
```

Enable telemetry rotation so the uploader only handles closed files rather than the file Telegraf is actively appending to:

```toml
[[outputs.file]]
  files = ['C:\ProgramData\Telegraf\spool\telemetry\activity.lp']
  data_format = "influx"
  namepass = ["foreground_window"]
  rotation_interval = "15m"
  rotation_max_archives = -1
```

The separate uploader should run every minute and use this remote root:

```text
\\OMV\data-dumps\machine-info\
```

Its job is to copy only completed PNGs and rotated telemetry files. It should copy each item to a temporary remote filename, verify it, rename it to the final filename, and retain the local source until that succeeds. If OMV is unavailable, it leaves the item in the local spool and retries later.

The automatic uploader is not included in this package yet. This section defines the expected configuration boundary so it can be added without changing the capture collector.

## Recommended remote layout

```text
\\OMV\data-dumps\machine-info\
  screenshots\
    COMPUTERNAME\
      DOMAIN_username\
        2026-10-15\
          screen-...png
  telemetry\
    COMPUTERNAME\
      DOMAIN_username\
        activity-...lp
```

Treat screenshots, titles, and telemetry as sensitive. Restrict SMB permissions, encrypt storage, and define separate retention periods for raw images and telemetry.

# Install guide: Windows Telegraf desktop collector

This guide installs Telegraf on Windows and configures the foreground-window collector in this project. The collector needs the signed-in user's desktop, so it is run from a user logon task—not only as a conventional Windows service.

## Before you start

- Use a supported 64-bit Windows installation (choose the ARM64 Telegraf package only for ARM Windows devices).
- Have local administrator access for the initial Telegraf installation and Scheduled Task creation.
- Decide the telemetry destination: local spool, a UNC share, or a central metrics endpoint.
- Obtain approval for screen/title collection and configure access-controlled, encrypted storage before enabling screenshots.
- Synchronize the computer clock; capture and OCR timelines rely on accurate timestamps.

## 1. Download and verify Telegraf

Download the current stable Windows ZIP from the official [Telegraf installation page](https://docs.influxdata.com/telegraf/v1/install/?t=Windows). Download its published SHA-256 checksum too, then use PowerShell to check the archive before extracting it:

```powershell
Get-FileHash .\telegraf-<version>_windows_amd64.zip -Algorithm SHA256
```

Compare the resulting hash with the value published for that exact release. Do not use nightly builds for this collector.

## 2. Install the binary

Open PowerShell **as Administrator** and create the installation directory:

```powershell
New-Item -ItemType Directory -Force 'C:\Program Files\InfluxData\telegraf'
Expand-Archive .\telegraf-<version>_windows_amd64.zip `
  -DestinationPath 'C:\Program Files\InfluxData\telegraf\'
```

Move `telegraf.exe` and the supplied `telegraf.conf` from the extracted versioned directory into `C:\Program Files\InfluxData\telegraf\`, or create a symlink from that directory to the extracted versioned folder. Confirm the binary works:

```powershell
& 'C:\Program Files\InfluxData\telegraf\telegraf.exe' version
```

## 3. Create the collector directories

Keep scripts and writable capture data outside `Program Files`:

```powershell
New-Item -ItemType Directory -Force 'C:\ProgramData\Telegraf\scripts'
New-Item -ItemType Directory -Force 'C:\ProgramData\Telegraf\spool\screenshots'
New-Item -ItemType Directory -Force 'C:\ProgramData\Telegraf\spool\telemetry'
```

Copy this project's files as follows:

```text
foreground-window.ps1  → C:\ProgramData\Telegraf\scripts\foreground-window.ps1
start-telegraf-hidden.vbs → C:\ProgramData\Telegraf\scripts\start-telegraf-hidden.vbs
telegraf-activity.conf → C:\Program Files\InfluxData\telegraf\telegraf.d\activity.conf
```

Create the `telegraf.d` folder if it does not exist. `activity.conf` includes a local file output at `C:\ProgramData\Telegraf\spool\telemetry\activity.lp`, so Telegraf has a valid output from the first run. Edit or add an output later for your selected local spool, UNC path, or central system. Use a UNC path such as `\\fileserver\EndpointTelemetry\...`; do not use a mapped drive letter.

To change screenshot frequency, edit the value after `-CaptureEveryMinutes` in `activity.conf`: use `2` for every two minutes, `5` for every five minutes, or `15` for the default every 15 minutes. Keep the Telegraf input interval at `1m` so open-window inventory is still recorded every minute. Restart the Scheduled Task after editing the configuration.

## 4. Test the PowerShell collector interactively

While signed in as the intended collecting user, run:

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
  -NoProfile -ExecutionPolicy Bypass `
  -File 'C:\ProgramData\Telegraf\scripts\foreground-window.ps1' `
  -CaptureScreenshot -CaptureEveryMinutes 1 `
  -ScreenshotDirectory 'C:\ProgramData\Telegraf\spool\screenshots'
```

It should write JSON to the console and create a PNG. Verify that it lists several visible windows, correctly marks one `is_foreground`, and records the expected user/session. A blank result usually means the script is running outside the interactive desktop or against a locked session.

## 5. Test the Telegraf configuration

From the Telegraf installation directory, run Telegraf once with its main config and the activity configuration directory:

```powershell
& .\telegraf.exe `
  --config '.\telegraf.conf' `
  --config-directory '.\telegraf.d' `
  --test
```

`--test` prints collected metrics but does not send them to configured outputs. Fix configuration or script errors before scheduling it. Telegraf expects UTF-8 configuration files.

For a normal, continuous run, include the same configuration directory:

```powershell
& .\telegraf.exe `
  --config '.\telegraf.conf' `
  --config-directory '.\telegraf.d'
```

If Telegraf reports `no outputs found`, it loaded a configuration without any enabled `[[outputs.*]]` table. Confirm `telegraf.d\activity.conf` is present and that `--config-directory '.\telegraf.d'` is included. A configuration used for a normal run must have at least one input and one output; `--test` is the exception.

## 6. Run it in the interactive user session

Create a Scheduled Task that launches Telegraf at user logon without exposing a console window:

- **General:** choose the intended account and select **Run only when user is logged on**.
- **Triggers:** At log on for that user.
- **Actions → Program/script:** `C:\Windows\System32\wscript.exe`
- **Arguments:** `"C:\ProgramData\Telegraf\scripts\start-telegraf-hidden.vbs"`
- **Settings:** restart on failure; do not start a second instance if one is already running.

`wscript.exe` launches the supplied Visual Basic Script without a console window; the script starts Telegraf hidden. Do not use `cscript.exe`, which is a console host. If the task runs under a managed/domain account, give that account the minimum required NTFS and network-share permissions. A per-user task is required for each simultaneously active session. The task should have no more privilege than it needs.

## 7. Optional: system-wide Telegraf service

You may also run the ordinary Telegraf Windows service for CPU, disk, Windows-service, or network metrics. Do not expect it to capture the active desktop. Install it separately with absolute configuration paths:

```powershell
& 'C:\Program Files\InfluxData\telegraf\telegraf.exe' `
  --config 'C:\Program Files\InfluxData\telegraf\telegraf.conf' `
  service install --auto-restart

& 'C:\Program Files\InfluxData\telegraf\telegraf.exe' service start
```

Use a separate configuration or filters to avoid duplicating the user-session collector's activity records. View service startup events in **Event Viewer → Windows Logs → Application**.

## 8. Operational checks

- Confirm new window records appear at the expected cadence.
- Confirm screenshot paths resolve and only authorized users can read the files.
- Disconnect the network briefly if using the local spool design; verify captures continue and upload/retry works after reconnection.
- Monitor free disk space and implement retention before increasing capture frequency.
- Keep Telegraf and the collector script patched; sign the PowerShell script and use an appropriate execution policy for production.

For the official Telegraf service commands and troubleshooting, see [Telegraf on Windows](https://docs.influxdata.com/telegraf/v1/commands/service/) and [running Telegraf as a service](https://docs.influxdata.com/telegraf/v1/administer/run-as-service/).

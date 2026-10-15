# Deployment options

This collector samples visible top-level windows and can save full-resolution desktop screenshots. It must run in the interactive user session to inspect the active desktop; a conventional Windows service runs outside that session and cannot reliably obtain the foreground window or a screen image.

## Recommended identity and folder layout

Use both the Windows machine name and the signed-in identity. The machine name is the stable endpoint identifier; the user identifies the active session on shared or multi-user devices.

```text
\\fileserver\EndpointTelemetry\
  screenshots\
    DESKTOP-7M2Q\
      CONTOSO_alex\
        2026-10-14\
          screen-20261014T143000123Z.png
  telemetry\
    DESKTOP-7M2Q\
      CONTOSO_alex\
        2026-10-14\
          activity.ndjson
```

Replace the domain separator in an account name (`CONTOSO\alex`) with an underscore before using it as a path component. Also sanitize other characters Windows does not allow in file names. The collector records the original user identity as telemetry.

## Option 1: Directly write to the shared drive

Set the screenshot directory to a UNC path, not a mapped drive letter:

```powershell
-ScreenshotDirectory '\\fileserver\EndpointTelemetry\screenshots\DESKTOP-7M2Q\CONTOSO_alex\2026-10-14'
```

Point a Telegraf file output, or a separate telemetry writer, at the corresponding telemetry path. Grant the account running the interactive collector Create/Append access only to its endpoint directory. This is simple and makes captures available immediately.

**Trade-offs:** a slow or unavailable share can delay capture, and disconnected devices have nowhere durable to write. Never embed share credentials in the Telegraf configuration; use the scheduled task's account and normal Windows/AD permissions.

## Option 2: Local spool, then asynchronous upload (recommended)

Write screenshots and newline-delimited telemetry locally first, such as:

```text
C:\ProgramData\Telegraf\spool\
  screenshots\
  telemetry\
```

Run a second scheduled task or lightweight uploader in the same user context to copy completed files to the UNC share. It should use a temporary filename during copy and rename only after the transfer succeeds. Keep a manifest or upload checkpoint so an image is uploaded once, retry after network failures with backoff, and delete a local item only after the remote copy is verified.

This decouples capture timing from network availability and is the better choice for high-frequency, full-resolution screenshots.

## Option 3: Split telemetry from images

Send structured telemetry to the central metrics/logging system with Telegraf while using the shared drive (or object storage) only for images. A screenshot telemetry record should contain an opaque `image_id` and the relative storage path, not the image bytes. When OCR is added, it writes a separate record keyed by the same `image_id`.

```text
image_id → screenshot path + capture time + window inventory
image_id → OCR engine/version + extracted text + processing result
```

This makes application/title queries fast without repeatedly reading image files and lets OCR be re-run as the engine improves.

## Interactive-session deployment

Create a Scheduled Task for each enrolled user:

- Trigger: at user logon; restart on failure.
- Security option: **Run only when user is logged on**.
- Account: the intended collecting user, without elevated privileges unless separately needed.
- Action: use `wscript.exe` to launch `start-telegraf-hidden.vbs`, which starts the user-scoped Telegraf process/configuration without a visible console window.

Do not rely on the machine-wide Telegraf service alone for desktop capture. If more than one user can be signed in concurrently, run one collector per interactive session and keep both user and session ID in the telemetry.

## Capture rate, capacity, and retention

Keep original PNGs for OCR quality. Their size depends on content and display layout; measure a representative week before choosing the schedule. At a 10 MB average image size, a single device produces roughly 14 GB/day at one capture per minute and 58 GB/day at one per 15 seconds.

Use a short local spool retention period sized for expected offline time. Apply central retention and access rules separately to screenshots, telemetry, and OCR text. Consider future adaptive capture: capture on foreground-window changes and periodically while unchanged, then add screen-change detection before increasing the fixed rate further.

## Security and governance

Window titles, screenshots, and OCR output can expose credentials, messages, customer data, and other sensitive information. Before rollout:

- obtain the required notice, consent, and organizational approval;
- encrypt network transport and storage;
- restrict share permissions by endpoint/user path and use separate read access for reviewers;
- audit access and define deletion/retention periods;
- keep credentials out of scripts and Telegraf configuration.

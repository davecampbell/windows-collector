[CmdletBinding()]
param(
    [switch]$CaptureScreenshot,
    [ValidateRange(1, 1440)]
    [int]$CaptureEveryMinutes = 15,
    [string]$ScreenshotDirectory = 'C:\ProgramData\Telegraf\screen-captures'
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ForegroundWindowApi
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextLength(IntPtr hWnd);
}
'@

function Get-WindowRecord {
    param(
        [IntPtr]$Window,
        [IntPtr]$ForegroundWindow
    )

    if ($Window -eq [IntPtr]::Zero -or -not [ForegroundWindowApi]::IsWindowVisible($Window)) {
        return $null
    }

    [uint32]$processId = 0
    [void][ForegroundWindowApi]::GetWindowThreadProcessId($Window, [ref]$processId)
    if ($processId -eq 0) {
        return $null
    }

    $titleLength = [ForegroundWindowApi]::GetWindowTextLength($Window)
    $title = ''
    if ($titleLength -gt 0) {
        $buffer = [System.Text.StringBuilder]::new($titleLength + 1)
        [void][ForegroundWindowApi]::GetWindowText($Window, $buffer, $buffer.Capacity)
        $title = $buffer.ToString()
    }

    # Ignore visible shell/helper windows that have no title bar text.
    if ([string]::IsNullOrWhiteSpace($title)) {
        return $null
    }

    try {
        $process = Get-Process -Id $processId -ErrorAction Stop
        $application = $process.ProcessName
        $path = $null
        try { $path = $process.Path } catch { }
    }
    catch {
        $application = 'unknown'
        $path = $null
    }

    [pscustomobject]@{
        record_type    = 'window'
        application    = $application
        window_title   = $title
        process_id     = [int64]$processId
        executable_path = $path
        window_handle  = ('0x{0:X}' -f $Window.ToInt64())
        is_foreground  = ($Window -eq $ForegroundWindow)
    }
}

function Save-Screenshot {
    param([string]$Directory)

    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $fileName = 'screen-{0}.png' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
        $path = Join-Path $Directory $fileName
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        return $path
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$now = [DateTime]::UtcNow
$foregroundWindow = [ForegroundWindowApi]::GetForegroundWindow()
$windows = [System.Collections.Generic.List[object]]::new()
$callback = [ForegroundWindowApi+EnumWindowsProc]{
    param([IntPtr]$window, [IntPtr]$ignored)
    $record = Get-WindowRecord -Window $window -ForegroundWindow $foregroundWindow
    if ($null -ne $record) {
        $windows.Add($record)
    }
    return $true
}
[void][ForegroundWindowApi]::EnumWindows($callback, [IntPtr]::Zero)

$screenshotPath = $null
$screenshotCaptured = $false

if ($CaptureScreenshot -and (($now.Minute % $CaptureEveryMinutes) -eq 0)) {
    try {
        $screenshotPath = Save-Screenshot -Directory $ScreenshotDirectory
        $screenshotCaptured = $true
    }
    catch { $screenshotPath = $null }
}

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId

# Add shared metadata to each window record, then emit a summary record. This
# allows Telegraf's JSON parser to consume the entire array in one execution.
foreach ($record in $windows) {
    $record | Add-Member -NotePropertyName user -NotePropertyValue $identity
    $record | Add-Member -NotePropertyName session_id -NotePropertyValue $sessionId
    $record | Add-Member -NotePropertyName sample_time_utc -NotePropertyValue $now.ToString('o')
}

$records = [System.Collections.Generic.List[object]]::new()
foreach ($record in $windows) { $records.Add($record) }
$records.Add([pscustomobject]@{
    record_type = 'inventory'
    window_count = $windows.Count
    user = $identity
    session_id = $sessionId
    sample_time_utc = $now.ToString('o')
})

if ($screenshotCaptured) {
    $records.Add([pscustomobject]@{
        record_type = 'screenshot'
        screenshot_captured = $true
        screenshot_path = $screenshotPath
        user = $identity
        session_id = $sessionId
        sample_time_utc = $now.ToString('o')
    })
}

$records | ConvertTo-Json -Compress

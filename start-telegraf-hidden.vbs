Option Explicit

' Launches the interactive-session Telegraf collector without a console window.
' Run this with wscript.exe from the Scheduled Task, not cscript.exe.

Dim shell, command
Set shell = CreateObject("WScript.Shell")

command = _
  """C:\Program Files\InfluxData\telegraf\telegraf.exe""" & _
  " --config ""C:\Program Files\InfluxData\telegraf\telegraf-activity.conf"""

' 0 = hidden window; False = do not wait for the long-running Telegraf process.
shell.Run command, 0, False

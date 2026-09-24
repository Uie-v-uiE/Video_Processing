# board/uart_cmd_script.ps1 -- send a list of console commands to the board over a COM port
# and capture everything the board answers, segmented per command.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File board\uart_cmd_script.ps1 `
#     -Port COM6 -File board\cmd_battery_v81.txt -DelayMs 900 -Out board\uart_script_capture.txt
#
# Why this exists next to uart_cap_once.ps1: that one takes -Cmds "A,B" and splits on
# [,\s]+, so a command with a SPACE in it ("th 80" = V8 spec section 14 syntax) arrives as two
# commands. This script reads one command per line from a file, so the real grammar is testable.
#
# THIS FILE STAYS ASCII-ONLY (comments too): PS 5.1 decodes a BOM-less .ps1 with the local ANSI
# codepage, so a CJK comment can swallow the quote on the next line and the parser then reports
# "UnexpectedToken" somewhere innocent. Hit exactly that on 2026-09-24; the board's own Chinese
# replies are fine because they are decoded as UTF-8 below.

param(
  [string]$Port = 'COM6',
  [int]$Baud = 115200,
  [string]$File = 'board\cmd_battery_v81.txt',
  [int]$DelayMs = 900,
  [string]$Out = 'board\uart_script_capture.txt'
)

$ErrorActionPreference = 'Stop'
$lines = Get-Content -LiteralPath $File -Encoding UTF8 |
  Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') }

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
# SerialPort defaults to ASCII decoding, which turns every Chinese byte the firmware prints into
# "?" and makes keyword matching impossible. Source is UTF-8, xil_printf sends the bytes as-is,
# so decode as UTF-8.
$sp.Encoding = [System.Text.Encoding]::UTF8
$sp.ReadTimeout = 200
$sp.WriteTimeout = 1000
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.Open()

$sb = New-Object System.Text.StringBuilder

function Drain {
  $deadline = (Get-Date).AddMilliseconds($DelayMs)
  while ((Get-Date) -lt $deadline) {
    try {
      $n = $sp.BytesToRead
      if ($n -gt 0) { [void]$sb.Append($sp.ReadExisting()) }
    } catch { Start-Sleep -Milliseconds 20 }
    Start-Sleep -Milliseconds 20
  }
  # ReadExisting can leave a tail behind if the board answers exactly at the deadline
  try { if ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()) } } catch {}
}

# Segmentation is the fragile part: if the previous window ended mid-line (board was printing when
# the deadline hit), the following ">> cmd" gets appended to that half line, the command then
# "disappears" from the capture and every later segment shifts by one. First run showed exactly
# that: 27 of 28 segments and bilin=0 at the end, which looked like a firmware bug but was the
# slice. So: always start a marker on its own line.
function Ensure-LineStart {
  if ($sb.Length -gt 0) {
    $last = $sb.Chars($sb.Length - 1)
    if ([int]$last -ne 10) { [void]$sb.Append("`r`n") }
  }
}

[void]$sb.Append("=== CAPTURE START $($lines.Count) commands ===`r`n")
Drain
foreach ($l in $lines) {
  Ensure-LineStart
  [void]$sb.Append(">> $($l)`r`n")
  $sp.WriteLine($l.Trim())
  Drain
}
Ensure-LineStart
[void]$sb.Append("=== CAPTURE END ===`r`n")
$sp.Close()
Set-Content -LiteralPath $Out -Value $sb.ToString() -Encoding UTF8
Write-Output "SENT $($lines.Count) CMD  CAPTURED -> $Out"

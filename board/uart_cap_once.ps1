param([string]$Port = 'COM6', [int]$Seconds = 8, [string]$Out = 'board\uart_capture.txt',
      [string[]]$Cmd = @(), [string]$Cmds = '', [double]$CmdDelay = 0.12, [switch]$Drain)
# One-shot serial send/capture for the Z7 console (src/ps/main.c). No pyserial needed.
#   boot banner only : -Seconds 20
#   one command      : -Cmd STAT
#   several, spaced  : -Cmds "SD,PLAY,STOP" -CmdDelay 12 -Seconds 8
# -CmdDelay is the gap as seen by the board, and everything is read inside one port session,
# so "frames counted / (CmdDelay * (n-1))" is a defensible rate measurement.
# -Drain discards what the FTDI buffer already holds, so a previous run's banner cannot leak
# into this run's evidence.
#
# Three traps this file now guards against (all hit tonight, 2026-09-23):
#  1. Keep it ASCII-only: PowerShell 5.1 decodes a BOM-less .ps1 as the local ANSI codepage,
#     and a CJK comment can swallow the following quote -> "TerminatorExpectedAtEndOfString"
#     pointing at an innocent line.
#  2. 'powershell -File x.ps1 -Cmd "A","B"' does NOT give a [string[]] of 2; it arrives as the
#     single string "A,B", the board's parser matches the prefix and only runs the first one.
#     So multi-command goes through -Cmds; we also split on whitespace because the binder may
#     have joined an array with spaces before a [string] parameter saw it.
#  3. ';' and '|' are PowerShell command-line operators: '-Cmds "A;B"' gets truncated at the
#     semicolon by the shell. Use commas.
$ErrorActionPreference = 'Stop'
if ($Cmds) { $Cmd = @($Cmds -split '[,\s]+' | Where-Object { $_ -ne '' }) }
if (@($Cmd).Count -eq 1 -and "$($Cmd[0])" -match '[,;]') {
    Write-Output 'FATAL: use -Cmds "A,B" for multiple commands (-File does not bind [string[]])'
    exit 2
}
$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 500
$sp.Open()
if ($Drain) { while ($sp.BytesToRead -gt 0) { $null = $sp.ReadExisting() } }

$sb = New-Object System.Text.StringBuilder
$list = @($Cmd)          # NOT $cmds: PowerShell names are case-insensitive, $cmds IS $Cmds
$start = Get-Date
$next = $start
# Horizon computed up front. An earlier version pushed "end = now + Seconds" on every send, so
# with -CmdDelay > -Seconds the loop quit *between* commands and the remaining commands were
# never sent - three measurements were lost that way while the board looked guilty.
$t_end = $start.AddSeconds((@($list).Count * $CmdDelay) + $Seconds + 2)
$i = 0
while ((Get-Date) -lt $t_end) {
    if ($i -lt $list.Count -and (Get-Date) -ge $next) {
        $sp.Write([string]$list[$i].Trim() + "`r`n")
        $i++
        $next = (Get-Date).AddSeconds($CmdDelay)
    }
    try {
        while ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()) }
    } catch {}
    Start-Sleep -Milliseconds 40
}
$sp.Close()
$s = $sb.ToString()
$s | Out-File -Encoding ascii -FilePath $Out
Write-Output ("SENT {0}/{1}  CAPTURED_LEN {2}" -f $i, @($list).Count, $s.Length)
Write-Output $s

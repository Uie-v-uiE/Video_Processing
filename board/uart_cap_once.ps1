param([string]$Port = 'COM6', [int]$Seconds = 8, [string]$Out = 'board\uart_boot_capture.txt',
      [string[]]$Cmd = @(), [switch]$Drain)
# 一次性串口收发：
#   只抓开机横幅：  -Seconds 20            （不传 -Cmd）
#   发命令并收回应： -Cmd "STAT" / -Cmd "SRC1","STAT"
# 用 Windows 自带的 SerialPort，不依赖 pyserial（验收机不保证装了 pyserial）。
# 注意 -Drain：先把缓冲里攒下的旧输出读掉再发命令，否则会把上一次的横幅混进这次的判据里。
$ErrorActionPreference = 'Stop'
$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 500
$sp.Open()
if ($Drain) { while ($sp.BytesToRead -gt 0) { $null = $sp.ReadExisting() } }
$sb = New-Object System.Text.StringBuilder
$end = (Get-Date).AddSeconds($Seconds)
foreach ($c in $Cmd) {
    $sp.Write($c.Trim() + "`r`n")
    Start-Sleep -Milliseconds 120
}
while ((Get-Date) -lt $end) {
    try {
        while ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()) }
    } catch {}
    Start-Sleep -Milliseconds 40
}
$sp.Close()
$s = $sb.ToString()
$s | Out-File -Encoding ascii -FilePath $Out
Write-Output ("CAPTURED_LEN {0}" -f $s.Length)
Write-Output $s

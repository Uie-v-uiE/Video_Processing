param([string]$Port = 'COM6', [string]$Cmd = 'split', [int]$Seconds = 4, [string]$Out = 'build/serial_hex.txt')
# Raw-byte capture: what the board ACTUALLY put on the wire (not what a console renders).
# Why: the user reports "a long run of blanks" after typing a command. Two causes look identical
# on screen: (a) the firmware really emits 0x20 padding, (b) the console cannot render the UTF-8
# CJK bytes and shows blanks. Only the raw byte stream tells them apart.
# NOTE: do NOT use ReadExisting() here - it decodes with $sp.Encoding first, and a byte that is
# invalid in that encoding is silently replaced, which is exactly the evidence we need.
# Keep this file ASCII-only: PowerShell 5.1 decodes a BOM-less .ps1 with the ANSI codepage.
$ErrorActionPreference = 'Stop'
$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 200
$sp.Open()
$buf = New-Object byte[] 4096
while ($sp.BytesToRead -gt 0) { $null = $sp.Read($buf, 0, $buf.Length) }   # drain
$sp.Write([System.Text.Encoding]::ASCII.GetBytes($Cmd + "`r`n"))
$all = New-Object System.Collections.Generic.List[byte]
$t0 = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $t0) {
    try {
        $n = $sp.Read($buf, 0, $buf.Length)
        for ($i = 0; $i -lt $n; $i++) { $all.Add($buf[$i]) }
    } catch [System.TimeoutException] { Start-Sleep -Milliseconds 60 }
}
$sp.Close()
$arr = $all.ToArray()
$rows = @()
$rows += "SENT: $Cmd"
$rows += "BYTES: $($arr.Length)"
$runs = @{}
foreach ($b in $arr) {
    $k = '0x' + $b.ToString('X2')
    if ($runs.ContainsKey($k)) { $runs[$k] = $runs[$k] + 1 } else { $runs[$k] = 1 }
}
$rows += 'HISTOGRAM (descending by count):'
$runs.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { $rows += ("  {0} = {1}" -f $_.Key, $_.Value) }
$hi = @($arr | Where-Object { $_ -gt 127 }).Count
$sp2 = @($arr | Where-Object { $_ -eq 32 }).Count
$rows += "HIGH-BYTES (>=0x80, i.e. UTF-8 CJK payload) = $hi"
$rows += "SPACES (0x20) = $sp2"
$rows += 'DECODED AS UTF-8:'
$rows += [System.Text.Encoding]::UTF8.GetString($arr)
$rows += 'FIRST 160 BYTES HEX:'
$hex = ($arr | Select-Object -First 160 | ForEach-Object { $_.ToString('X2') }) -join ' '
$rows += $hex
$rows | Out-File -Encoding utf8 -FilePath $Out
Write-Output ("bytes={0} high={1} spaces={2} -> {3}" -f $arr.Length, $hi, $sp2, $Out)

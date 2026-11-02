$p = New-Object System.IO.Ports.SerialPort COM6,115200,None,8,One
$p.ReadTimeout = 3000
try {
    $p.Open()
    $p.Write("help" + [char]13)
    Start-Sleep -Milliseconds 2500
    $sb = New-Object System.Text.StringBuilder
    while ($p.BytesToRead -gt 0) {
        [void]$sb.Append([char]$p.ReadByte())
        Start-Sleep -Milliseconds 5
    }
    $t = $sb.ToString()
    Write-Output ("REPLY_LEN=" + $t.Length)
    if ($t.Length -gt 0) {
        $n = [Math]::Min(600, $t.Length)
        Write-Output $t.Substring(0, $n)
    }
} catch {
    Write-Output ("ERR: " + $_.Exception.Message)
} finally {
    $p.Close()
}

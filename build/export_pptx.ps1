param(
  [Parameter(Mandatory=$true)][string]$Pptx,
  [Parameter(Mandatory=$true)][string]$OutBase,
  [int]$Width = 2560,
  [int]$Height = 1440
)
$ErrorActionPreference = 'Stop'
$pptxPath = (Resolve-Path $Pptx).Path
$OutBase = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutBase))
$outDir = Split-Path -Parent $OutBase
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$tmp = Join-Path $env:TEMP ("pptx_export_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

$ppt = $null
try {
  Write-Output "step open-app"
  $ppt = New-Object -ComObject PowerPoint.Application
  Write-Output "step open-pres"
  $pres = $ppt.Presentations.Open($pptxPath, $true, $false, $true)
  Write-Output "step export-png"
  $pres.Export($tmp, "PNG", $Width, $Height)
  Write-Output "step save-pdf"
  $pres.SaveAs(($OutBase + ".pdf"), 32)
  Write-Output "step close"
  $pres.Close()
} catch {
  Write-Output ("FAILED: " + $_.Exception.Message)
  throw
} finally {
  if ($ppt) { try { $ppt.Quit() } catch {} }
}

$png = Get-ChildItem -Path $tmp -Filter *.PNG | Sort-Object Name | Select-Object -First 1
if (-not $png) { throw "No PNG produced" }
Copy-Item $png.FullName ($OutBase + ".png") -Force
Remove-Item -Recurse -Force $tmp
Write-Output ("OK " + $OutBase + ".png " + $OutBase + ".pdf")

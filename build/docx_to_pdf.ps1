param(
  [string]$Docx = "technical_document.docx",
  [string]$Pdf  = "technical_document.pdf"
)
$root = Split-Path -Parent $PSScriptRoot
$docxPath = Join-Path $root $Docx
$pdfPath  = Join-Path $root $Pdf
if (-not (Test-Path -LiteralPath $docxPath)) { throw "DOCX not found: $docxPath" }
$word = New-Object -ComObject Word.Application
$word.Visible = $false
try {
  $doc = $word.Documents.Open($docxPath, $false, $true)
  $doc.ExportAsFixedFormat($pdfPath, 17)
  $doc.Close($false)
} finally {
  $word.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
Write-Output "PDF_OK $pdfPath"

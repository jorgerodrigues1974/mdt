$auditDir = "c:\Users\jorgerodrigues\Documents\MDT\auditoria"
$logFile = Join-Path $auditDir "log_2026-04-22.txt"
if (Test-Path $logFile) {
    $lines = @(Get-Content $logFile -Encoding UTF8)
    $resData = @{ status = "success"; date = "2026-04-22"; content = $lines } | ConvertTo-Json -Depth 5
    Write-Host "--- JSON OUTPUT ---"
    $resData
} else {
    Write-Host "Ficheiro nao encontrado em $logFile"
}

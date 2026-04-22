$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('c:\Users\Jorge Rodrigues\Documents\MDT\Start-MDT.ps1', [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "$($_.Message) at line $($_.Extent.StartLineNumber)" }
    exit 1
} else {
    Write-Host 'Syntax OK'
}

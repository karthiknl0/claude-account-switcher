# Syntax check for every script, under whichever PowerShell runs this file
# (CI runs it under both Windows PowerShell 5.1 and PowerShell 7).
# Also enforces ASCII-only scripts: Windows PowerShell 5.1 misreads other
# characters in files without a byte-order mark.

$repo  = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem (Join-Path $repo 'src') -Filter '*.ps1') +
         @(Get-Item (Join-Path $repo 'install.ps1'), (Join-Path $repo 'uninstall.ps1')) +
         @(Get-ChildItem $PSScriptRoot -Filter '*.ps1')
$bad = 0
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $bad++
        Write-Host ("SYNTAX ERROR {0} line {1}: {2}" -f $f.Name, $errors[0].Extent.StartLineNumber, $errors[0].Message) -ForegroundColor Red
        continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    if ($nonAscii -gt 0) {
        $bad++
        Write-Host ("NON-ASCII     {0}: {1} byte(s)" -f $f.Name, $nonAscii) -ForegroundColor Red
        continue
    }
    Write-Host ("ok  {0}" -f $f.Name)
}
Write-Host ("PowerShell {0}" -f $PSVersionTable.PSVersion)
if ($bad) { exit 1 }
exit 0

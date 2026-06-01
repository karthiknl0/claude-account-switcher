<#
    Claude Account Switcher - uninstaller

    One-line uninstall:
      irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/uninstall.ps1 | iex

    Removes the scripts, the Desktop shortcut, and the added functions from your
    PowerShell profiles. Does NOT touch your saved accounts (~/.claude-accounts)
    or your Claude login. Remove saved accounts manually if you want:
      Remove-Item -Recurse -Force ~/.claude-accounts
#>

Write-Host "Removing Claude Account Switcher..." -ForegroundColor Cyan

# 1. Tools dir
$ToolsDir = Join-Path $env:USERPROFILE '.claude-tools'
if (Test-Path $ToolsDir) { Remove-Item -Recurse -Force $ToolsDir; Write-Host " - removed $ToolsDir" }

# 2. Desktop shortcut
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude Switch Account.lnk'
if (Test-Path $lnk) { Remove-Item -Force $lnk; Write-Host " - removed Desktop shortcut" }

# 3. Functions from both profiles
$docs = [Environment]::GetFolderPath('MyDocuments')
$profiles = @(
    (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')
)
foreach ($pf in $profiles) {
    if (-not (Test-Path $pf)) { continue }
    $lines = Get-Content $pf
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*#\s*Claude desktop account switcher') { $skip = $true; continue }
        if ($skip -and $line -match '^\s*function\s+claude-(switch|add)-account') { continue }
        if ($skip -and $line -match '^\s*&\s') { continue }
        if ($skip -and $line -match '^\s*\}') { continue }
        if ($skip -and $line.Trim() -eq '') { $skip = $false; continue }
        $out.Add($line)
    }
    Set-Content -Path $pf -Value $out -Encoding UTF8
    Write-Host " - cleaned $pf"
}

Write-Host "Done. Open a new PowerShell window for changes to take effect." -ForegroundColor Green

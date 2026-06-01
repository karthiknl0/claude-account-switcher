# Snapshot the Claude account that is CURRENTLY logged into ~/.claude into the
# switcher store, so it can be switched to later. Run this while the desktop app
# (or CLI) is logged in as the account you want to save.

$store = Join-Path $env:USERPROFILE '.claude-accounts'
$cred  = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$cfg   = Join-Path $env:USERPROFILE '.claude\.claude.json'

if (-not (Test-Path $cred)) {
    Write-Host "No ~/.claude/.credentials.json found - log into Claude first." -ForegroundColor Red
    Start-Sleep -Seconds 2; return
}

$c = Get-Content $cred -Raw | ConvertFrom-Json
if (-not $c.claudeAiOauth) {
    Write-Host "No Claude OAuth token in .credentials.json - nothing to save." -ForegroundColor Red
    Start-Sleep -Seconds 2; return
}

# Work out a human label (the account email) from .claude.json if available.
$email = $null
if (Test-Path $cfg) {
    try { $email = (Get-Content $cfg -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch {}
}
if ([string]::IsNullOrWhiteSpace($email)) { $email = "account-" + (Get-Date -Format 'yyyyMMddHHmmss') }

New-Item -ItemType Directory -Force -Path $store | Out-Null
$safe = ($email -replace '[^\w.@+-]', '_')
$file = Join-Path $store "$safe.json"

[ordered]@{ email = $email; claudeAiOauth = $c.claudeAiOauth } |
    ConvertTo-Json -Depth 20 | Set-Content -Path $file -Encoding UTF8

Write-Host "Saved Claude account: $email" -ForegroundColor Green
Write-Host "Stored at: $file" -ForegroundColor DarkGray
Start-Sleep -Seconds 2

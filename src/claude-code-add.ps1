# Save the Claude Code (CLI) account currently logged in, so it can be switched
# to later. Claude Code stores its login in ~/.claude/.credentials.json - a flat
# OAuth token file - so this is a simple, safe snapshot (like Codex's auth.json).
#
# Run from a NORMAL PowerShell window.

$store = Join-Path $env:USERPROFILE '.claude-cc-accounts'
$cred  = Join-Path $env:USERPROFILE '.claude\.credentials.json'

Write-Host ""
Write-Host "=== Add Claude Code account ===" -ForegroundColor Cyan

if (-not (Test-Path $cred)) {
    Write-Host "Claude Code is not logged in (no ~/.claude/.credentials.json)." -ForegroundColor Red
    Write-Host "Open Claude Code, run /login, then re-run this." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}
try { $c = Get-Content $cred -Raw | ConvertFrom-Json } catch {
    Write-Host "Could not read ~/.claude/.credentials.json." -ForegroundColor Red
    Start-Sleep -Seconds 2; return
}
if (-not $c.claudeAiOauth) {
    Write-Host "No subscription login found in credentials (API-key setup?)." -ForegroundColor Red
    Start-Sleep -Seconds 2; return
}

$email = Read-Host "Email of the account currently logged into Claude Code"
if ([string]::IsNullOrWhiteSpace($email)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

New-Item -ItemType Directory -Force -Path $store | Out-Null
$safe = ($email -replace '[^\w.@+-]', '_')
$file = Join-Path $store "$safe.json"

[ordered]@{ email = $email; savedAt = (Get-Date -Format o); credentials = $c } |
    ConvertTo-Json -Depth 20 | Set-Content -Path $file -Encoding UTF8

Write-Host ""
Write-Host "Saved Claude Code account: $email" -ForegroundColor Green
Write-Host ""

# Offer to set up the NEXT account. Clearing the LOCAL credentials (deleting the
# file) does NOT call the logout API, so the account we just saved stays valid.
$more = Read-Host "Add ANOTHER account now? (clears local login WITHOUT logging out) [y/N]"
if ($more -match '^(y|yes)$') {
    Remove-Item $cred -Force -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Local Claude Code login cleared (not revoked)." -ForegroundColor Green
    Write-Host "In Claude Code: run /login as the NEXT account, then run 'claude-code-add' again." -ForegroundColor Green
    Write-Host "(If a Claude Code session is open, restart it so it sees the cleared login.)" -ForegroundColor DarkGray
}
Start-Sleep -Seconds 2

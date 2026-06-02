# Save the Claude Code (CLI) account currently logged in, so it can be switched
# to later. Claude Code stores its login as a flat OAuth token (like Codex's
# auth.json), so this is a simple, safe snapshot.
#
# Cross-platform (Windows / Linux / macOS) - on Unix run with PowerShell (pwsh).
# Windows + Linux read it from ~/.claude/.credentials.json; macOS reads it from
# the login Keychain ("Claude Code-credentials") via the `security` CLI.

# -- Platform detection ($IsMacOS etc. only exist on PowerShell Core/7+) -------
$PlatformMac = $false
if (Test-Path variable:IsMacOS) { $PlatformMac = $IsMacOS }

$store = Join-Path $HOME '.claude-cc-accounts'
$cred  = Join-Path (Join-Path $HOME '.claude') '.credentials.json'
$cfg   = Join-Path (Join-Path $HOME '.claude') '.claude.json'
$KeychainService = 'Claude Code-credentials'
$credLabel = if ($PlatformMac) { 'the login Keychain' } else { '~/.claude/.credentials.json' }

# Extract a top-level object value as RAW JSON text (brace-balanced, string-aware)
# so oauthAccount is copied byte-for-byte (a ConvertTo-Json round-trip would
# mangle its dates / nested fields).
function Get-JsonObjRaw($text, $key) {
    $m = [regex]::Match($text, '"' + [regex]::Escape($key) + '"\s*:\s*')
    if (-not $m.Success) { return $null }
    $i = $m.Index + $m.Length
    if ($i -ge $text.Length -or $text[$i] -ne '{') { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($j = $i; $j -lt $text.Length; $j++) {
        $ch = $text[$j]
        if ($esc) { $esc = $false; continue }
        if ($ch -eq '\') { $esc = $true; continue }
        if ($ch -eq '"') { $inStr = -not $inStr; continue }
        if ($inStr) { continue }
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($i, $j - $i + 1) } }
    }
    return $null
}

# -- Platform-aware live-credential access -------------------------------------
function Get-LiveCredsRaw {
    if ($PlatformMac) {
        try {
            $out = & security find-generic-password -s $KeychainService -w 2>$null
            if ($LASTEXITCODE -eq 0 -and $out) { return ($out -join "`n") }
        } catch {}
        return $null
    }
    if (Test-Path $cred) { try { return (Get-Content $cred -Raw) } catch {} }
    return $null
}

function Remove-LiveCreds {
    if ($PlatformMac) {
        & security delete-generic-password -s $KeychainService 2>$null | Out-Null
        return
    }
    Remove-Item $cred -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Add Claude Code account ===" -ForegroundColor Cyan

$raw = Get-LiveCredsRaw
if (-not $raw) {
    Write-Host "Claude Code is not logged in (no credentials in $credLabel)." -ForegroundColor Red
    Write-Host "Open Claude Code, run /login, then re-run this." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}
try { $c = $raw | ConvertFrom-Json } catch {
    Write-Host "Could not read the Claude Code credentials." -ForegroundColor Red
    Start-Sleep -Seconds 2; return
}
if (-not $c.claudeAiOauth) {
    Write-Host "No subscription login found in credentials (API-key setup?)." -ForegroundColor Red
    Start-Sleep -Seconds 2; return
}

$email = Read-Host "Email of the account currently logged into Claude Code"
if ([string]::IsNullOrWhiteSpace($email)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

# Capture this account's display identity (oauthAccount) so a later switch can
# update ~/.claude/.claude.json too - otherwise Claude Code's /status keeps
# showing the previous account's email/org after switching.
$oauthAccountRaw = $null
if (Test-Path $cfg) { try { $oauthAccountRaw = Get-JsonObjRaw (Get-Content $cfg -Raw) 'oauthAccount' } catch {} }

New-Item -ItemType Directory -Force -Path $store | Out-Null
$safe = ($email -replace '[^\w.@+-]', '_')
$file = Join-Path $store "$safe.json"

$entry = [ordered]@{ email = $email; savedAt = (Get-Date -Format o); credentials = $c }
if ($oauthAccountRaw) { $entry.oauthAccountRaw = $oauthAccountRaw }
$entry | ConvertTo-Json -Depth 20 | Set-Content -Path $file -Encoding UTF8

Write-Host ""
Write-Host "Saved Claude Code account: $email" -ForegroundColor Green
Write-Host ""

# Offer to set up the NEXT account. Clearing the LOCAL credentials does NOT call
# the logout API, so the account we just saved stays valid.
$more = Read-Host "Add ANOTHER account now? (clears local login WITHOUT logging out) [y/N]"
if ($more -match '^(y|yes)$') {
    Remove-LiveCreds
    Write-Host ""
    Write-Host "Local Claude Code login cleared (not revoked)." -ForegroundColor Green
    Write-Host "In Claude Code: run /login as the NEXT account, then run 'claude-code-add' again." -ForegroundColor Green
    Write-Host "(If a Claude Code session is open, restart it so it sees the cleared login.)" -ForegroundColor DarkGray
}
Start-Sleep -Seconds 2

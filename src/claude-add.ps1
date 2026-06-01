# Snapshot the Claude account currently logged in and save it to ~/.claude-accounts
# so it can be switched to later. Works with both storage formats:
#   - New (Electron safeStorage): %APPDATA%\Claude\config.json -> oauth:tokenCache
#   - Legacy (.credentials.json): ~/.claude/.credentials.json  -> claudeAiOauth

Add-Type -AssemblyName System.Security

$configPath = Join-Path $env:APPDATA    'Claude\config.json'
$credPath   = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$cfgPath    = Join-Path $env:USERPROFILE '.claude\.claude.json'
$store      = Join-Path $env:USERPROFILE '.claude-accounts'

Write-Host ""
Write-Host "=== Add Claude account ===" -ForegroundColor Cyan
Write-Host "Make sure you are logged into the account you want to save in the Claude app." -ForegroundColor DarkGray
Write-Host ""

# ── Locate the token ──────────────────────────────────────────────────────────
$blob        = $null   # encrypted blob (new format)
$legacyCred  = $null   # plaintext token (legacy format)
$tokenParsed = $null   # decrypted token object (for email extraction)

# Try new format first: %APPDATA%\Claude\config.json
if (Test-Path $configPath) {
    try {
        $cfg  = Get-Content $configPath -Raw | ConvertFrom-Json
        $raw  = $cfg.'oauth:tokenCache'
        if ($raw) {
            $blob = $raw   # store the blob regardless of whether we can decrypt it
            try {
                $bytes     = [Convert]::FromBase64String($raw)
                $encrypted = $bytes[3..($bytes.Length - 1)]   # strip v10 prefix
                $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
                    $encrypted, $null,
                    [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $tokenParsed = [System.Text.Encoding]::UTF8.GetString($decrypted) | ConvertFrom-Json
            } catch {}
        }
    } catch {}
}

# Fall back to legacy ~/.claude/.credentials.json
if (-not $blob -and (Test-Path $credPath)) {
    try {
        $cred = Get-Content $credPath -Raw | ConvertFrom-Json
        if ($cred.claudeAiOauth) {
            $legacyCred  = $cred.claudeAiOauth
            $tokenParsed = $cred.claudeAiOauth
        }
    } catch {}
}

if (-not $blob -and -not $legacyCred) {
    Write-Host "No Claude login found." -ForegroundColor Red
    Write-Host "Open the Claude desktop app, log in, then re-run this." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# ── Get the account email ─────────────────────────────────────────────────────
$email = $null

# 1. Direct field on token object
if ($tokenParsed.email)                   { $email = $tokenParsed.email }
if (-not $email -and $tokenParsed.claudeAiOauth.email) { $email = $tokenParsed.claudeAiOauth.email }

# 2. ~/.claude/.claude.json
if (-not $email -and (Test-Path $cfgPath)) {
    try { $email = (Get-Content $cfgPath -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch {}
}

# 3. Decode JWT access token
if (-not $email) {
    $at = $tokenParsed.accessToken
    if (-not $at) { $at = $tokenParsed.claudeAiOauth.accessToken }
    if ($at) {
        try {
            $parts = $at -split '\.'
            $pad   = 4 - ($parts[1].Length % 4)
            $b64   = if ($pad -ne 4) { $parts[1] + ('=' * $pad) } else { $parts[1] }
            $email = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json).'https://api.anthropic.com/profile'.email
        } catch {}
    }
}

# If all auto-detection failed, ask the user
if (-not $email) {
    Write-Host "Could not auto-detect the account email." -ForegroundColor Yellow
    $email = Read-Host "Enter the email address for this Claude account"
    if ([string]::IsNullOrWhiteSpace($email)) {
        Write-Host "No email provided - cancelled." -ForegroundColor Red
        Start-Sleep -Seconds 2; return
    }
}

# ── Save snapshot ─────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $store | Out-Null
$safe = ($email -replace '[^\w.@+-]', '_')
$file = Join-Path $store "$safe.json"

$entry = [ordered]@{ email = $email }
if ($blob)       { $entry.tokenCache    = $blob }
else             { $entry.claudeAiOauth = $legacyCred }

$entry | ConvertTo-Json -Depth 20 | Set-Content -Path $file -Encoding UTF8

Write-Host "Saved: $email" -ForegroundColor Green
Write-Host "File:  $file"  -ForegroundColor DarkGray
Start-Sleep -Seconds 2

# Snapshot the Claude account currently logged in and save it to ~/.claude-accounts
# so it can be switched to later. Works with both storage formats:
#   - New (Electron safeStorage): %APPDATA%\Claude\config.json -> oauth:tokenCache
#   - Legacy (.credentials.json): ~/.claude/.credentials.json  -> claudeAiOauth

Add-Type -AssemblyName System.Security

$configPath    = Join-Path $env:APPDATA    'Claude\config.json'
$localState    = Join-Path $env:APPDATA    'Claude\Local State'
$credPath      = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$cfgPath       = Join-Path $env:USERPROFILE '.claude\.claude.json'
$store         = Join-Path $env:USERPROFILE '.claude-accounts'

Write-Host ""
Write-Host "=== Add Claude account ===" -ForegroundColor Cyan
Write-Host "Make sure the Claude desktop app is open and you are logged in." -ForegroundColor DarkGray
Write-Host ""

# ── Read config.json safely (Claude may have it open) ─────────────────────────
function Read-FileShared($path) {
    try {
        $fs     = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($fs)
        $text   = $reader.ReadToEnd()
        $reader.Close(); $fs.Close()
        return $text
    } catch { return $null }
}

# ── Locate the token blob ─────────────────────────────────────────────────────
$blob       = $null
$legacyCred = $null

if (Test-Path $configPath) {
    $raw = Read-FileShared $configPath
    if ($raw) {
        try {
            $blob = ($raw | ConvertFrom-Json).'oauth:tokenCache'
        } catch {}
    }
}

# Fall back to legacy ~/.claude/.credentials.json
if (-not $blob -and (Test-Path $credPath)) {
    try {
        $cred = Get-Content $credPath -Raw | ConvertFrom-Json
        if ($cred.claudeAiOauth) { $legacyCred = $cred.claudeAiOauth }
    } catch {}
}

if (-not $blob -and -not $legacyCred) {
    Write-Host "No Claude login found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Diagnostics:" -ForegroundColor DarkGray
    Write-Host "  config.json path : $configPath" -ForegroundColor DarkGray
    Write-Host "  config.json found: $(Test-Path $configPath)" -ForegroundColor DarkGray
    Write-Host "  running as admin : $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Open the Claude desktop app, log in, then re-run this" -ForegroundColor Red
    Write-Host "in a NORMAL (non-Administrator) PowerShell window." -ForegroundColor Red
    Start-Sleep -Seconds 4; return
}

# ── Get the account email ─────────────────────────────────────────────────────
$email = $null

# Method 1: AES-256-GCM decrypt via Node.js (new Electron safeStorage format)
if ($blob -and (Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path $localState)) {
    try {
        # DPAPI-decrypt the AES key stored in Local State
        $lsJson     = Read-FileShared $localState
        $encKeyB64  = ($lsJson | ConvertFrom-Json).os_crypt.encrypted_key
        $encKeyBytes = [Convert]::FromBase64String($encKeyB64)
        $keyBytes   = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encKeyBytes[5..($encKeyBytes.Length - 1)], $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        $keyHex     = ($keyBytes | ForEach-Object { $_.ToString('x2') }) -join ''

        # Extract nonce + ciphertext from the v10 blob
        $blobBytes  = [Convert]::FromBase64String($blob)
        $nonceHex   = ($blobBytes[3..14]  | ForEach-Object { $_.ToString('x2') }) -join ''
        $cipherHex  = ($blobBytes[15..($blobBytes.Length - 1)] | ForEach-Object { $_.ToString('x2') }) -join ''

        # Node.js does the AES-256-GCM decryption
        $nodeCode = @"
const c=require('crypto');
const ct=Buffer.from('$cipherHex','hex');
const d=c.createDecipheriv('aes-256-gcm',Buffer.from('$keyHex','hex'),Buffer.from('$nonceHex','hex'));
d.setAuthTag(ct.slice(-16));
let r=d.update(ct.slice(0,-16),'','utf8')+d.final('utf8');
const t=JSON.parse(r);
console.log(t.email||t.claudeAiOauth&&t.claudeAiOauth.email||'');
"@
        $email = ($nodeCode | node --input-type=commonjs 2>$null).Trim()
        if (-not $email) { $email = $null }
    } catch {}
}

# Method 2: ~/.claude/.claude.json
if (-not $email -and (Test-Path $cfgPath)) {
    try { $email = (Get-Content $cfgPath -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch {}
}

# Method 3: legacy plaintext token
if (-not $email -and $legacyCred) {
    $email = $legacyCred.email
}

# Method 4: ask the user
if (-not $email) {
    Write-Host "Could not auto-detect the account email." -ForegroundColor Yellow
    try {
        $email = Read-Host "Enter the email address for this account"
    } catch {
        Write-Host "Please pass your email as an argument: claude-add-account your@email.com" -ForegroundColor Yellow
        Start-Sleep -Seconds 3; return
    }
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

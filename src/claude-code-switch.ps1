# Switch the Claude Code (CLI) account by swapping its stored OAuth credentials.
# Simple, safe credential swap (like Codex). The conversation transcripts in
# ~/.claude/projects are shared across accounts, so after switching you can
# `claude --resume` to continue the same work under the new account.
#
# Cross-platform (Windows / Linux / macOS) - on Unix run with PowerShell (pwsh).
# Windows + Linux store the login in the flat file ~/.claude/.credentials.json;
# macOS keeps it in the login Keychain ("Claude Code-credentials"), so this
# script reads/writes it there via the `security` CLI.
#
# Close any open Claude Code session first so it re-reads the new credentials.

# -- Platform detection ($IsMacOS etc. only exist on PowerShell Core/7+) -------
$PlatformMac = $false; $PlatformWin = $true
if (Test-Path variable:IsMacOS)   { $PlatformMac = $IsMacOS }
if (Test-Path variable:IsWindows) { $PlatformWin = $IsWindows }

$store   = Join-Path $HOME '.claude-cc-accounts'
$KeychainService = 'Claude Code-credentials'

# --- Dynamic location resolution (works across machines / layouts) ------------
# Honours CLAUDE_CONFIG_DIR, and auto-detects the real .credentials.json and the
# real .claude.json (the file that actually contains oauthAccount), so the
# switcher targets the correct files no matter how Claude Code is set up here.
$ConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }

$credCandidates = @(
    (Join-Path $ConfigDir '.credentials.json'),
    (Join-Path (Join-Path $HOME '.claude') '.credentials.json')
) | Select-Object -Unique
$cred = ($credCandidates | Where-Object { Test-Path $_ } | Get-Item -EA SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (-not $cred) { $cred = $credCandidates[0] }

$cfgCandidates = @(
    (Join-Path $HOME '.claude.json'),
    (Join-Path $ConfigDir '.claude.json'),
    (Join-Path (Join-Path $HOME '.claude') '.claude.json')
) | Select-Object -Unique
$cfg = $null
foreach ($c in ($cfgCandidates | Where-Object { Test-Path $_ } | Get-Item -EA SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
    try { if ((Get-Content $c.FullName -Raw) -match '"oauthAccount"') { $cfg = $c.FullName; break } } catch {}
}
if (-not $cfg) { $cfg = $cfgCandidates[0] }
$RawBase = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'

# Replace a top-level object value with raw JSON text, brace-balanced and
# string-aware, leaving the rest of the file byte-for-byte unchanged. Used to
# update oauthAccount in .claude.json without a lossy ConvertTo-Json round-trip.
function Set-JsonObjRaw($text, $key, $newRaw) {
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
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring(0, $i) + $newRaw + $text.Substring($j + 1) } }
    }
    return $null
}

# -- Platform-aware live-credential access -------------------------------------
# Returns the raw credentials JSON string for the account currently logged in.
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

# Writes the raw credentials JSON for the account being switched to.
function Set-LiveCredsRaw($json) {
    if ($PlatformMac) {
        $acct = $env:USER; if (-not $acct) { try { $acct = (& id -un) } catch {} }
        & security add-generic-password -U -s $KeychainService -a $acct -w $json 2>$null | Out-Null
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $cred) | Out-Null
    [System.IO.File]::WriteAllText($cred, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-ForUpdate {
    try {
        $checkFile = Join-Path (Join-Path $HOME '.claude-tools') '.update-check'
        if (Test-Path $checkFile) {
            if (((Get-Date) - (Get-Item $checkFile).LastWriteTime) -lt [TimeSpan]::FromDays(1)) { return }
        }
        New-Item -ItemType File -Force -Path $checkFile | Out-Null
        (Get-Date -Format o) | Set-Content -Path $checkFile -ErrorAction SilentlyContinue
        $remote  = (Invoke-RestMethod -Uri "$RawBase/VERSION" -TimeoutSec 4).ToString().Trim()
        $verFile = Join-Path (Join-Path $HOME '.claude-tools') '.version'
        $local   = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '0.0.0' }
        if ([version]$remote -gt [version]$local) {
            Write-Host ""
            Write-Host "  * Update available: v$local -> v$remote   (run 'claude-switch-update')" -ForegroundColor Yellow
        }
    } catch {}
}

function Get-ClaudeUsage($accessToken) {
    if (-not $accessToken) { return $null }
    try {
        $h = @{ 'Authorization' = "Bearer $accessToken"; 'anthropic-version' = '2023-06-01'; 'anthropic-beta' = 'oauth-2025-04-20' }
        return Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $h -TimeoutSec 6
    } catch { return $null }
}

# Format the reset times into a short, human line (local time). The 5h limit is
# close so it's shown as a countdown; the weekly limit is shown as a date+time.
function Format-Resets($u) {
    if (-not $u) { return $null }
    $now   = Get-Date
    $parts = @()
    try {
        $r5 = [datetimeoffset]::Parse($u.five_hour.resets_at).LocalDateTime
        $d  = $r5 - $now
        if ($d.TotalSeconds -gt 0) {
            $rel = if ($d.TotalHours -ge 1) { "{0}h{1:00}m" -f [int]$d.TotalHours, $d.Minutes } else { "{0}m" -f [int]$d.TotalMinutes }
            $parts += "5h resets in $rel ($($r5.ToString('HH:mm')))"
        }
    } catch {}
    try {
        $r7 = [datetimeoffset]::Parse($u.seven_day.resets_at).LocalDateTime
        $parts += "7d resets $($r7.ToString('ddd MMM d, HH:mm'))"
    } catch {}
    if ($parts.Count) { return ($parts -join '   |   ') }
    return $null
}

# -- Load saved accounts (exclude backups / non-account files) -----------------
$accounts = Get-ChildItem $store -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike 'backup-*' }
if (-not $accounts) {
    Write-Host "No saved Claude Code accounts." -ForegroundColor Yellow
    Write-Host "Log into Claude Code (/login), then run 'claude-code-add' to save each account." -ForegroundColor Yellow
    Start-Sleep -Seconds 3; return
}

# Current account = live credentials' access token matches a saved one.
$liveToken = $null
$liveRaw   = Get-LiveCredsRaw
if ($liveRaw) {
    try { $liveToken = ($liveRaw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {}
}

$list = @()
foreach ($a in $accounts) {
    try { $j = Get-Content $a.FullName -Raw | ConvertFrom-Json } catch { continue }
    if (-not $j.email -or -not $j.credentials) { continue }   # skip non-account files
    $list += [pscustomobject]@{
        Email    = $j.email
        File     = $a.FullName
        Creds    = $j.credentials
        Token    = $j.credentials.claudeAiOauth.accessToken
        OAuthRaw = $j.oauthAccountRaw
    }
}

# -- Display picker ------------------------------------------------------------
Write-Host ""
Write-Host "=== Switch Claude Code account ===" -ForegroundColor Cyan
Test-ForUpdate
Write-Host "Fetching usage..." -ForegroundColor DarkGray
for ($i = 0; $i -lt $list.Count; $i++) {
    $mark = if ($liveToken -and $list[$i].Token -eq $liveToken) { '*' } else { ' ' }
    $u = Get-ClaudeUsage $list[$i].Token
    $usageStr = if ($u) { "  5h {0,3}% / 7d {1,3}% used" -f [int]$u.five_hour.utilization, [int]$u.seven_day.utilization } else { "  usage n/a" }
    Write-Host ("  [{0}] {1} {2,-32}{3}" -f ($i + 1), $mark, $list[$i].Email, $usageStr)
    $resetStr = Format-Resets $u
    if ($resetStr) { Write-Host ("        $resetStr") -ForegroundColor DarkGray }
}
Write-Host "  (* = current   |   lower % = more headroom)" -ForegroundColor DarkGray
Write-Host ""

$pick = Read-Host "Pick an account number (or Enter to cancel)"
if ([string]::IsNullOrWhiteSpace($pick)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $list.Count) {
    Write-Host "Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 2; return
}
$chosen = $list[[int]$pick - 1]

if ($chosen.Token -and $chosen.Token -eq $liveToken) {
    Write-Host "Already on $($chosen.Email)." -ForegroundColor Green
    # The token already matches, but the displayed identity (oauthAccount in
    # ~/.claude.json) can be out of sync - re-sync it so /status is correct.
    if ($chosen.OAuthRaw -and (Test-Path $cfg)) {
        try {
            $cjRaw = Get-Content $cfg -Raw
            $u = Set-JsonObjRaw $cjRaw 'oauthAccount' $chosen.OAuthRaw
            if ($u -and $u -ne $cjRaw) {
                Copy-Item $cfg "$cfg.bak" -Force -ErrorAction SilentlyContinue
                [System.IO.File]::WriteAllText($cfg, $u, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Re-synced the displayed identity. Restart Claude Code if /status looked wrong." -ForegroundColor Cyan
            }
        } catch {}
    }
    Start-Sleep -Seconds 2; return
}

# Back up the current live creds (in a hidden subfolder so they never show in
# the picker). Works on every platform - we snapshot the raw JSON, wherever it
# came from (file on Windows/Linux, Keychain on macOS).
$backupDir = Join-Path $store '.backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
if ($liveRaw) {
    [System.IO.File]::WriteAllText(
        (Join-Path $backupDir ("backup-{0}.credentials.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),
        $liveRaw, (New-Object System.Text.UTF8Encoding($false)))
}
Get-ChildItem $backupDir -Filter 'backup-*.credentials.json' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -Skip 1 | Remove-Item -Force -ErrorAction SilentlyContinue

$json = $chosen.Creds | ConvertTo-Json -Depth 20
Set-LiveCredsRaw $json

# Also update the cached display identity in .claude.json so Claude Code's
# /status shows the right account (it reads the email from oauthAccount, not the
# token). Surgical replace - the rest of .claude.json is left untouched. Older
# accounts saved before this feature have no OAuthRaw; switch to + re-run
# 'claude-code-add' once to capture it.
if ($chosen.OAuthRaw -and (Test-Path $cfg)) {
    try {
        $cjRaw   = Get-Content $cfg -Raw
        $updated = Set-JsonObjRaw $cjRaw 'oauthAccount' $chosen.OAuthRaw
        if ($updated -and $updated -ne $cjRaw) {
            Copy-Item $cfg "$cfg.bak" -Force -ErrorAction SilentlyContinue
            [System.IO.File]::WriteAllText($cfg, $updated, (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch {}
}

Write-Host ""
Write-Host "Switched Claude Code to $($chosen.Email)." -ForegroundColor Green
Write-Host "Open Claude Code and run 'claude --resume' to continue your work as this account." -ForegroundColor Cyan
Write-Host "(If a Claude Code session is already open, restart it to pick up the new login.)" -ForegroundColor DarkGray
Start-Sleep -Seconds 2

# Switch the Claude Code (CLI) account by swapping ~/.claude/.credentials.json.
# Simple, safe flat-file swap (like Codex). The conversation transcripts in
# ~/.claude/projects are shared across accounts, so after switching you can
# `claude --resume` to continue the same work under the new account.
#
# Run from a NORMAL PowerShell window. Close any open Claude Code session first
# so it re-reads the new credentials.

$store   = Join-Path $env:USERPROFILE '.claude-cc-accounts'
$cred    = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$RawBase = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'

function Test-ForUpdate {
    try {
        $checkFile = Join-Path $env:USERPROFILE '.claude-tools\.update-check'
        if (Test-Path $checkFile) {
            if (((Get-Date) - (Get-Item $checkFile).LastWriteTime) -lt [TimeSpan]::FromDays(1)) { return }
        }
        New-Item -ItemType File -Force -Path $checkFile | Out-Null
        (Get-Date -Format o) | Set-Content -Path $checkFile -ErrorAction SilentlyContinue
        $remote  = (Invoke-RestMethod -Uri "$RawBase/VERSION" -TimeoutSec 4).ToString().Trim()
        $verFile = Join-Path $env:USERPROFILE '.claude-tools\.version'
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
if (Test-Path $cred) {
    try { $liveToken = (Get-Content $cred -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {}
}

$list = @()
foreach ($a in $accounts) {
    try { $j = Get-Content $a.FullName -Raw | ConvertFrom-Json } catch { continue }
    if (-not $j.email -or -not $j.credentials) { continue }   # skip non-account files
    $list += [pscustomobject]@{
        Email = $j.email
        File  = $a.FullName
        Creds = $j.credentials
        Token = $j.credentials.claudeAiOauth.accessToken
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
    Start-Sleep -Seconds 2; return
}

# Back up current creds (in a hidden subfolder so they never show in the picker).
New-Item -ItemType Directory -Force -Path (Split-Path $cred) | Out-Null
$backupDir = Join-Path $store '.backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
if (Test-Path $cred) {
    Copy-Item $cred (Join-Path $backupDir ("backup-{0}.credentials.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force
}
Get-ChildItem $backupDir -Filter 'backup-*.credentials.json' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue

$json = $chosen.Creds | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($cred, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Switched Claude Code to $($chosen.Email)." -ForegroundColor Green
Write-Host "Open Claude Code and run 'claude --resume' to continue your work as this account." -ForegroundColor Cyan
Write-Host "(If a Claude Code session is already open, restart it to pick up the new login.)" -ForegroundColor DarkGray
Start-Sleep -Seconds 2

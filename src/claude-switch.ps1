# Switch the Claude desktop app's account: pick a saved account, swap its OAuth
# token into ~/.claude/.credentials.json (preserving mcpOAuth and leaving
# .claude.json untouched), then restart the Claude desktop app.
#
# Shows best-effort usage (5h / 7-day % used) for each account, queried from
# Anthropic's OAuth usage endpoint with each account's saved token. Tokens
# expire ~hourly; an account whose cached token has expired shows "usage n/a"
# until you next switch to it (which refreshes its token).
#
# IMPORTANT: run this from a STANDALONE PowerShell window, not from inside Claude
# - it closes the Claude desktop app (and any session running in it).

$store = Join-Path $env:USERPROFILE '.claude-accounts'
$cred  = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$cfg   = Join-Path $env:USERPROFILE '.claude\.claude.json'

function Get-ClaudeAumid {
    $a = Get-StartApps | Where-Object { $_.Name -match 'claude' } | Select-Object -First 1
    return $a.AppID
}

function Get-ClaudeUsage($token) {
    if (-not $token) { return $null }
    try {
        $h = @{ 'Authorization' = "Bearer $token"; 'anthropic-version' = '2023-06-01'; 'anthropic-beta' = 'oauth-2025-04-20' }
        return Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $h -TimeoutSec 8
    } catch { return $null }
}

$accounts = Get-ChildItem $store -Filter '*.json' -ErrorAction SilentlyContinue
if (-not $accounts) {
    Write-Host "No saved Claude accounts." -ForegroundColor Yellow
    Write-Host "Log into the account in Claude, then run 'claude-add-account' to save it." -ForegroundColor Yellow
    Start-Sleep -Seconds 3; return
}

# Which account is active right now (for display only)?
$currentEmail = $null
if (Test-Path $cfg) { try { $currentEmail = (Get-Content $cfg -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch {} }

$list = @()
foreach ($a in $accounts) {
    try { $j = Get-Content $a.FullName -Raw | ConvertFrom-Json } catch { continue }
    $list += [pscustomobject]@{ Email = $j.email; File = $a.FullName; Token = $j.claudeAiOauth; Usage = $null }
}

Write-Host ""
Write-Host "=== Switch Claude account ===" -ForegroundColor Cyan
Write-Host "Fetching usage..." -ForegroundColor DarkGray
foreach ($item in $list) { $item.Usage = Get-ClaudeUsage $item.Token.accessToken }

for ($i = 0; $i -lt $list.Count; $i++) {
    $mark = if ($list[$i].Email -eq $currentEmail) { "*" } else { " " }
    if ($list[$i].Usage) {
        $u = $list[$i].Usage
        $usage = ("5h {0,3}% / 7d {1,3}% used" -f [int]$u.five_hour.utilization, [int]$u.seven_day.utilization)
    } else {
        $usage = "usage n/a"
    }
    Write-Host ("  [{0}] {1} {2,-32} {3}" -f ($i + 1), $mark, $list[$i].Email, $usage)
}
Write-Host "  (% used - lower means more usage left)" -ForegroundColor DarkGray
Write-Host ""
$pick = Read-Host "Pick an account number (or Enter to cancel)"
if ([string]::IsNullOrWhiteSpace($pick)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $list.Count) {
    Write-Host "Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 2; return
}
$chosen = $list[[int]$pick - 1]

if ($chosen.Email -eq $currentEmail) {
    Write-Host "Already on $($chosen.Email) - nothing to do." -ForegroundColor Green
    Start-Sleep -Seconds 2; return
}

# Back up current credentials, then swap ONLY claudeAiOauth (keep mcpOAuth).
New-Item -ItemType Directory -Force -Path $store | Out-Null
if (Test-Path $cred) {
    Copy-Item $cred (Join-Path $store ("backup-{0}.credentials.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force
    $cur = Get-Content $cred -Raw | ConvertFrom-Json
} else {
    $cur = [pscustomobject]@{}
}
$cur | Add-Member -NotePropertyName claudeAiOauth -NotePropertyValue $chosen.Token -Force
$cur | ConvertTo-Json -Depth 20 | Set-Content -Path $cred -Encoding UTF8

Write-Host "Switched credentials to $($chosen.Email). Restarting Claude desktop app..." -ForegroundColor Cyan

Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "*WindowsApps\Claude_*" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$aumid = Get-ClaudeAumid
if ($aumid) {
    Start-Process "shell:AppsFolder\$aumid"
    Write-Host "Done - Claude is reopening as $($chosen.Email)." -ForegroundColor Green
    Write-Host "(The displayed email can take a few seconds to refresh.)" -ForegroundColor DarkGray
} else {
    Write-Host "Credentials swapped, but the Claude app wasn't found to relaunch - open it manually." -ForegroundColor Yellow
}
Start-Sleep -Seconds 2

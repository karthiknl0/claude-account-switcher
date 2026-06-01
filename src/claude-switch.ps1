# Switch the Claude desktop app's account. Works with both storage formats:
#   - New (Electron safeStorage): %APPDATA%\Claude\config.json -> oauth:tokenCache
#   - Legacy (.credentials.json): ~/.claude/.credentials.json  -> claudeAiOauth
#
# IMPORTANT: run from a STANDALONE PowerShell window, not inside a Claude session.

Add-Type -AssemblyName System.Security

$store    = Join-Path $env:USERPROFILE '.claude-accounts'
$credPath = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$cfgPath  = Join-Path $env:USERPROFILE '.claude\.claude.json'
$RawBase  = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'

# -- Update check (best-effort, cached once per day) ---------------------------
function Test-ForUpdate {
    try {
        $checkFile = Join-Path $env:USERPROFILE '.claude-tools\.update-check'
        if (Test-Path $checkFile) {
            $age = (Get-Date) - (Get-Item $checkFile).LastWriteTime
            if ($age -lt [TimeSpan]::FromDays(1)) { return }
        }
        New-Item -ItemType File -Force -Path $checkFile | Out-Null
        (Get-Date -Format o) | Set-Content -Path $checkFile -ErrorAction SilentlyContinue

        $remote  = (Invoke-RestMethod -Uri "$RawBase/VERSION" -TimeoutSec 4).ToString().Trim()
        $verFile = Join-Path $env:USERPROFILE '.claude-tools\.version'
        $local   = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '0.0.0' }
        if ([version]$remote -gt [version]$local) {
            Write-Host ""
            Write-Host "  * Update available: v$local -> v$remote" -ForegroundColor Yellow
            Write-Host "    Run 'claude-switch-update' to upgrade." -ForegroundColor Yellow
        }
    } catch {}
}

# -- Helpers -------------------------------------------------------------------
function Read-FileShared($path) {
    try {
        $fs     = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($fs)
        $text   = $reader.ReadToEnd()
        $reader.Close(); $fs.Close()
        return $text
    } catch { return $null }
}

# Resolve Claude data files across normal + MSIX (Store) installs (newest first).
function Get-ClaudeFiles($leaf) {
    $candidates = @( (Join-Path $env:APPDATA "Claude\$leaf") )
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pkgRoot) {
        Get-ChildItem $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
            $candidates += (Join-Path $_.FullName "LocalCache\Roaming\Claude\$leaf")
        }
    }
    $candidates | Where-Object { Test-Path $_ } |
        Get-Item -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -ExpandProperty FullName -Unique
}

# All config.json copies (we read the newest, write to ALL so any view stays in sync).
$configPaths = @(Get-ClaudeFiles 'config.json')
$configPath  = $configPaths | Select-Object -First 1

function Get-ClaudeAumid {
    $a = Get-StartApps | Where-Object { $_.Name -match 'claude' } | Select-Object -First 1
    return $a.AppID
}

function Decrypt-Blob($blob) {
    try {
        $bytes     = [Convert]::FromBase64String($blob)
        $encrypted = $bytes[3..($bytes.Length - 1)]
        $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted, $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($decrypted) | ConvertFrom-Json
    } catch { return $null }
}

function Get-AccessToken($entry) {
    if ($entry.tokenCache) {
        $t = Decrypt-Blob $entry.tokenCache
        if ($t.accessToken)              { return $t.accessToken }
        if ($t.claudeAiOauth.accessToken){ return $t.claudeAiOauth.accessToken }
    }
    if ($entry.claudeAiOauth.accessToken) { return $entry.claudeAiOauth.accessToken }
    return $null
}

function Get-ClaudeUsage($accessToken) {
    if (-not $accessToken) { return $null }
    try {
        $h = @{
            'Authorization'    = "Bearer $accessToken"
            'anthropic-version'= '2023-06-01'
            'anthropic-beta'   = 'oauth-2025-04-20'
        }
        return Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $h -TimeoutSec 8
    } catch { return $null }
}

function Get-ActiveEmail {
    # Identify the active account by matching the live tokenCache blob against
    # our saved snapshots (the blob isn't DPAPI-decryptable, but it's a stable
    # identifier per account until the token refreshes).
    if ($configPath) {
        $raw = Read-FileShared $configPath
        if ($raw) {
            try {
                $liveBlob = ($raw | ConvertFrom-Json).'oauth:tokenCache'
                if ($liveBlob) {
                    $hit = Get-ChildItem $store -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
                        try { Get-Content $_.FullName -Raw | ConvertFrom-Json } catch {}
                    } | Where-Object { $_.tokenCache -eq $liveBlob } | Select-Object -First 1
                    if ($hit) { return $hit.email }
                }
            } catch {}
        }
    }
    # Legacy format
    if (Test-Path $cfgPath) {
        try { return (Get-Content $cfgPath -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch {}
    }
    return $null
}

function Save-Snapshot($email, $entry) {
    $safe = ($email -replace '[^\w.@+-]', '_')
    $file = Join-Path $store "$safe.json"
    $entry | ConvertTo-Json -Depth 20 | Set-Content -Path $file -Encoding UTF8
}

# -- Load saved accounts -------------------------------------------------------
$accounts = Get-ChildItem $store -Filter '*.json' -ErrorAction SilentlyContinue
if (-not $accounts) {
    Write-Host "No saved Claude accounts." -ForegroundColor Yellow
    Write-Host "Log into Claude, then run 'claude-add-account' to save it." -ForegroundColor Yellow
    Start-Sleep -Seconds 3; return
}

$currentEmail = Get-ActiveEmail

$list = @()
foreach ($a in $accounts) {
    try { $j = Get-Content $a.FullName -Raw | ConvertFrom-Json } catch { continue }
    $list += [pscustomobject]@{
        Email       = $j.email
        File        = $a.FullName
        Entry       = $j
        AccessToken = Get-AccessToken $j
    }
}

# -- Display picker ------------------------------------------------------------
Write-Host ""
Write-Host "=== Switch Claude account ===" -ForegroundColor Cyan
Test-ForUpdate
Write-Host "Fetching usage..." -ForegroundColor DarkGray

for ($i = 0; $i -lt $list.Count; $i++) {
    $usage = Get-ClaudeUsage $list[$i].AccessToken
    $mark  = if ($list[$i].Email -eq $currentEmail) { "*" } else { " " }
    $usageStr = if ($usage) {
        "5h {0,3}% / 7d {1,3}% used" -f [int]$usage.five_hour.utilization, [int]$usage.seven_day.utilization
    } else { "usage n/a" }
    Write-Host ("  [{0}] {1} {2,-36} {3}" -f ($i + 1), $mark, $list[$i].Email, $usageStr)
}
Write-Host "  (* = current account   |   lower % = more headroom)" -ForegroundColor DarkGray
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

# -- Swap the token ------------------------------------------------------------
if ($chosen.Entry.tokenCache) {
    # New format: replace oauth:tokenCache in EVERY config.json copy (normal + MSIX)
    if (-not $configPaths -or $configPaths.Count -eq 0) {
        Write-Host "Claude config.json not found in any known location." -ForegroundColor Red
        Start-Sleep -Seconds 2; return
    }
    foreach ($cp in $configPaths) {
        $raw = Read-FileShared $cp
        if (-not $raw) { continue }
        if ($raw -match '"oauth:tokenCache"') {
            $raw = $raw -replace '"oauth:tokenCache"\s*:\s*"[^"]*"', """oauth:tokenCache"": ""$($chosen.Entry.tokenCache)"""
        } else {
            $raw = $raw -replace '}\s*$', (", `"oauth:tokenCache`": `"$($chosen.Entry.tokenCache)`"`n}")
        }
        try { Set-Content -Path $cp -Value $raw -Encoding UTF8 } catch {}
    }
} else {
    # Legacy format: swap claudeAiOauth in .credentials.json
    $cur = if (Test-Path $credPath) { Get-Content $credPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    $cur | Add-Member -NotePropertyName claudeAiOauth -NotePropertyValue $chosen.Entry.claudeAiOauth -Force
    $cur | ConvertTo-Json -Depth 20 | Set-Content -Path $credPath -Encoding UTF8
}

Write-Host "Switched to $($chosen.Email). Restarting Claude..." -ForegroundColor Cyan

# Kill Claude
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "*WindowsApps\Claude_*" -or $_.ProcessName -eq 'Claude' } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$aumid = Get-ClaudeAumid
if ($aumid) {
    Start-Process "shell:AppsFolder\$aumid"
    Write-Host "Done - Claude is reopening as $($chosen.Email)." -ForegroundColor Green

    # Wait for Claude to refresh the token, then re-snapshot so next switch has a fresh token.
    Write-Host "Waiting for token refresh..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 8
    if ($chosen.Entry.tokenCache) {
        try {
            # Re-resolve in case the app wrote to a different copy on startup.
            $newPath = Get-ClaudeFiles 'config.json' | Select-Object -First 1
            $raw     = if ($newPath) { Read-FileShared $newPath } else { $null }
            $newBlob = if ($raw) { ($raw | ConvertFrom-Json).'oauth:tokenCache' } else { $null }
            if ($newBlob -and $newBlob -ne $chosen.Entry.tokenCache) {
                $updated = [ordered]@{ email = $chosen.Email; tokenCache = $newBlob }
                Save-Snapshot $chosen.Email $updated
                Write-Host "Token snapshot updated." -ForegroundColor DarkGray
            }
        } catch {}
    }
} else {
    Write-Host "Token swapped, but Claude app wasn't found - open it manually." -ForegroundColor Yellow
}
Start-Sleep -Seconds 2

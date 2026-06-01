# Switch the Claude desktop account by swapping its Electron web session.
# The Claude desktop app keeps its login in the browser session (cookies +
# Local Storage + IndexedDB), so switching means closing the app, swapping
# those session folders for a saved account's, and restarting.
#
# IMPORTANT: run from a STANDALONE PowerShell window - THIS CLOSES the Claude
# app (and any session running inside it).

$store          = Join-Path $env:USERPROFILE '.claude-accounts'
$RawBase        = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'
$SessionFolders = @('Network', 'Local Storage', 'IndexedDB', 'Session Storage')

# -- Update check (best-effort, cached once per day) ---------------------------
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

# -- Resolve the live session root (handles MSIX/Store + plain installs) --------
function Get-SessionRoot {
    $roots = @( Join-Path $env:APPDATA 'Claude' )
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pkgRoot) {
        Get-ChildItem $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
            $roots += (Join-Path $_.FullName 'LocalCache\Roaming\Claude')
        }
    }
    $roots = $roots | Where-Object { Test-Path $_ } | Select-Object -Unique
    $live = $null; $newest = $null; $newestTime = [datetime]::MinValue
    foreach ($r in $roots) {
        $ck = Join-Path $r 'Network\Cookies'
        if (Test-Path $ck) {
            try { $fs = [IO.File]::Open($ck,'Open','Read','None'); $fs.Close() } catch { $live = $r }
            $t = (Get-Item $ck).LastWriteTime
            if ($t -gt $newestTime) { $newestTime = $t; $newest = $r }
        }
    }
    if ($live)   { return $live }
    if ($newest) { return $newest }
    return ($roots | Select-Object -First 1)
}

function Stop-Claude($root) {
    Get-Process -Name 'Claude' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like '*WindowsApps\Claude_*' -or $_.Path -like '*\Claude\Claude.exe' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $ck = Join-Path $root 'Network\Cookies'
    for ($i = 0; $i -lt 30; $i++) {
        if (-not (Test-Path $ck)) { return $true }
        try { $fs = [IO.File]::Open($ck,'Open','Read','None'); $fs.Close(); return $true } catch { Start-Sleep -Milliseconds 500 }
    }
    return $false
}

function Start-Claude {
    $a = Get-StartApps | Where-Object { $_.Name -match 'claude' } | Select-Object -First 1
    if ($a) { Start-Process "shell:AppsFolder\$($a.AppID)" ; return $true }
    return $false
}

function Copy-Session($srcRoot, $dstRoot) {
    foreach ($f in $SessionFolders) {
        $src = Join-Path $srcRoot $f
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $dstRoot $f
        robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    }
}

# -- Usage display (best-effort; needs Node for AES-GCM decrypt) ----------------
function Read-FileShared($path) {
    try {
        $fs     = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($fs)
        $text   = $reader.ReadToEnd()
        $reader.Close(); $fs.Close()
        return $text
    } catch { return $null }
}

function Get-AesKeyHex($root) {
    try {
        $ls = Read-FileShared (Join-Path $root 'Local State')
        if (-not $ls) { return $null }
        $b64   = ($ls | ConvertFrom-Json).os_crypt.encrypted_key
        $bytes = [Convert]::FromBase64String($b64)
        $key   = [System.Security.Cryptography.ProtectedData]::Unprotect(
                     $bytes[5..($bytes.Length - 1)], $null,
                     [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return ($key | ForEach-Object { $_.ToString('x2') }) -join ''
    } catch { return $null }
}

function Get-TokenFromBlob($blob, $keyHex) {
    if (-not $blob -or -not $keyHex) { return $null }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $null }
    $tmp = Join-Path $env:TEMP ("ccsw_" + [guid]::NewGuid().ToString('N') + ".js")
    try {
        $bytes     = [Convert]::FromBase64String($blob)
        $nonceHex  = ($bytes[3..14]               | ForEach-Object { $_.ToString('x2') }) -join ''
        $cipherHex = ($bytes[15..($bytes.Length-1)] | ForEach-Object { $_.ToString('x2') }) -join ''
        $code = "const c=require('crypto');const ct=Buffer.from('$cipherHex','hex');const d=c.createDecipheriv('aes-256-gcm',Buffer.from('$keyHex','hex'),Buffer.from('$nonceHex','hex'));d.setAuthTag(ct.slice(-16));const r=JSON.parse(d.update(ct.slice(0,-16),'','utf8')+d.final('utf8'));const v=Object.values(r)[0];process.stdout.write((v&&v.token)||'');"
        Set-Content -Path $tmp -Value $code -Encoding ASCII
        # Run via cmd so stderr is suppressed by cmd (avoids PowerShell's native-stderr quirk).
        $tok = cmd /c "node ""$tmp"" 2>nul"
        if ($tok) { return ([string]$tok).Trim() }
    } catch {} finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Get-ClaudeUsage($accessToken) {
    if (-not $accessToken) { return $null }
    try {
        $h = @{ 'Authorization' = "Bearer $accessToken"; 'anthropic-version' = '2023-06-01'; 'anthropic-beta' = 'oauth-2025-04-20' }
        return Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $h -TimeoutSec 6
    } catch { return $null }
}

# -- Load saved accounts -------------------------------------------------------
$accounts = Get-ChildItem $store -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'meta.json') }
if (-not $accounts) {
    Write-Host "No saved Claude accounts." -ForegroundColor Yellow
    Write-Host "Log into Claude, then run 'claude-add-account' to save each account." -ForegroundColor Yellow
    Start-Sleep -Seconds 3; return
}

$list = @()
foreach ($a in $accounts) {
    try { $m = Get-Content (Join-Path $a.FullName 'meta.json') -Raw | ConvertFrom-Json } catch { continue }
    $tcFile = Join-Path $a.FullName 'tokenCache.txt'
    $tc     = if (Test-Path $tcFile) { (Get-Content $tcFile -Raw).Trim() } else { $null }
    $list += [pscustomobject]@{ Email = $m.email; Dir = $a.FullName; Token = $tc }
}

# -- Display picker ------------------------------------------------------------
Write-Host ""
Write-Host "=== Switch Claude account ===" -ForegroundColor Cyan
Test-ForUpdate

# Identify the current account (live config token matches a saved one) + fetch usage.
$liveRoot   = Get-SessionRoot
$liveToken  = $null
if ($liveRoot) {
    try { $liveToken = (Read-FileShared (Join-Path $liveRoot 'config.json') | ConvertFrom-Json).'oauth:tokenCache' } catch {}
}
$keyHex = if ($liveRoot) { Get-AesKeyHex $liveRoot } else { $null }
$haveNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
if ($haveNode) { Write-Host "Fetching usage..." -ForegroundColor DarkGray }

for ($i = 0; $i -lt $list.Count; $i++) {
    $mark = if ($liveToken -and $list[$i].Token -eq $liveToken) { '*' } else { ' ' }
    $usageStr = ''
    if ($haveNode) {
        $u = Get-ClaudeUsage (Get-TokenFromBlob $list[$i].Token $keyHex)
        $usageStr = if ($u) { "  5h {0,3}% / 7d {1,3}% used" -f [int]$u.five_hour.utilization, [int]$u.seven_day.utilization } else { "  usage n/a" }
    }
    Write-Host ("  [{0}] {1} {2,-32}{3}" -f ($i + 1), $mark, $list[$i].Email, $usageStr)
}
if ($haveNode) { Write-Host "  (* = current   |   lower % = more headroom)" -ForegroundColor DarkGray }
Write-Host ""
$pick = Read-Host "Pick an account number (or Enter to cancel)"
if ([string]::IsNullOrWhiteSpace($pick)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $list.Count) {
    Write-Host "Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 2; return
}
$chosen      = $list[[int]$pick - 1]
$chosenSess  = Join-Path $chosen.Dir 'session'
if (-not (Test-Path $chosenSess)) {
    Write-Host "Saved session for $($chosen.Email) is missing - re-add it with claude-add-account." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# -- Perform the swap ----------------------------------------------------------
$root = Get-SessionRoot
if (-not $root) { Write-Host "Claude app data not found." -ForegroundColor Red; Start-Sleep -Seconds 2; return }

Write-Host ""
Write-Host "Closing Claude..." -ForegroundColor Cyan
if (-not (Stop-Claude $root)) {
    Write-Host "Could not fully close Claude (session locked). Close all windows and retry." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# Back up the current live session so a bad swap is recoverable.
$backup = Join-Path $store ('.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host "Backing up current session..." -ForegroundColor DarkGray
Copy-Session $root $backup

# Prune old backups (keep the 3 most recent).
Get-ChildItem $store -Directory -Filter '.backup-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -Skip 3 |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Loading session for $($chosen.Email)..." -ForegroundColor Cyan
Copy-Session $chosenSess $root

# Also restore the account's oauth:tokenCache into config.json (the identity the
# app displays). Written WITHOUT a BOM - a BOM makes the app reset its settings.
$tcFile = Join-Path $chosen.Dir 'tokenCache.txt'
if (Test-Path $tcFile) {
    $tc  = (Get-Content $tcFile -Raw).Trim()
    $cfg = Join-Path $root 'config.json'
    if ($tc -and (Test-Path $cfg)) {
        try {
            $raw = Get-Content $cfg -Raw
            $kv  = '"oauth:tokenCache": "' + $tc + '"'
            $m   = [Regex]::Match($raw, '"oauth:tokenCache"\s*:\s*"[^"]*"')
            if ($m.Success) {
                $raw = $raw.Substring(0, $m.Index) + $kv + $raw.Substring($m.Index + $m.Length)
            } else {
                $raw = [Regex]::Replace($raw, '\}\s*$', (', ' + $kv + "`n}"))
            }
            [System.IO.File]::WriteAllText($cfg, $raw, (New-Object System.Text.UTF8Encoding($false)))
        } catch {}
    }
}

Write-Host "Reopening Claude..." -ForegroundColor Cyan
if (Start-Claude) {
    Write-Host ""
    Write-Host "Done - Claude is reopening as $($chosen.Email)." -ForegroundColor Green
    Write-Host "If it still shows the old account, fully quit Claude from the tray and reopen." -ForegroundColor DarkGray
} else {
    Write-Host "Session swapped, but the Claude app wasn't found to relaunch - open it manually." -ForegroundColor Yellow
}
Start-Sleep -Seconds 2

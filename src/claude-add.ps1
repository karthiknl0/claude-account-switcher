# Snapshot the Claude desktop account that is CURRENTLY logged in, so it can be
# switched to later. The Claude desktop app is an Electron web app: its login
# lives in the browser session (cookies + Local Storage + IndexedDB), not in a
# single token file. So we copy those session folders wholesale.
#
# Run from a NORMAL PowerShell window. THIS CLOSES THE CLAUDE APP.

$store          = Join-Path $env:USERPROFILE '.claude-accounts'
$SessionFolders = @('Network', 'Local Storage', 'IndexedDB', 'Session Storage')

Write-Host ""
Write-Host "=== Add Claude account (session snapshot) ===" -ForegroundColor Cyan
Write-Host "1. Log into the account you want to save in the Claude desktop app." -ForegroundColor DarkGray
Write-Host "2. Then run this - it CLOSES Claude to copy its session, then reopens it." -ForegroundColor DarkGray
Write-Host ""

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
    if ($a) { Start-Process "shell:AppsFolder\$($a.AppID)" }
}

# Detect the email of the account ACTUALLY logged in, by decrypting the app's
# oauth:tokenCache (AES-GCM via node, key via DPAPI) and asking the OAuth
# profile endpoint. Guards against snapshotting under a mistyped email or
# while the app is logged out (same guard claude-code-add has). Best-effort:
# returns $null when node is missing or the token is dead.
function Get-LoggedInEmail($root) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $null }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $ls  = $null
        try { $fs=[IO.File]::Open((Join-Path $root 'Local State'),'Open','Read','ReadWrite'); $r=New-Object IO.StreamReader($fs); $ls=$r.ReadToEnd(); $r.Close(); $fs.Close() } catch { return $null }
        $b   = [Convert]::FromBase64String(($ls | ConvertFrom-Json).os_crypt.encrypted_key)
        $k   = [System.Security.Cryptography.ProtectedData]::Unprotect($b[5..($b.Length-1)], $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        $keyHex = ($k | ForEach-Object { $_.ToString('x2') }) -join ''
        $cfgRaw = $null
        try { $fs=[IO.File]::Open((Join-Path $root 'config.json'),'Open','Read','ReadWrite'); $r=New-Object IO.StreamReader($fs); $cfgRaw=$r.ReadToEnd(); $r.Close(); $fs.Close() } catch { return $null }
        $blob = ($cfgRaw | ConvertFrom-Json).'oauth:tokenCache'
        if (-not $blob) { return $null }
        $bytes     = [Convert]::FromBase64String($blob)
        $nonceHex  = ($bytes[3..14]                 | ForEach-Object { $_.ToString('x2') }) -join ''
        $cipherHex = ($bytes[15..($bytes.Length-1)] | ForEach-Object { $_.ToString('x2') }) -join ''
        $tmp  = Join-Path $env:TEMP ("ccadd_" + [guid]::NewGuid().ToString('N') + ".js")
        $code = "const c=require('crypto');const ct=Buffer.from('$cipherHex','hex');const d=c.createDecipheriv('aes-256-gcm',Buffer.from('$keyHex','hex'),Buffer.from('$nonceHex','hex'));d.setAuthTag(ct.slice(-16));const r=JSON.parse(d.update(ct.slice(0,-16),'','utf8')+d.final('utf8'));const v=Object.values(r)[0];const t=(v&&v.token)||'';if(!t)process.exit(0);fetch('https://api.anthropic.com/api/oauth/profile',{headers:{'Authorization':'Bearer '+t,'anthropic-version':'2023-06-01','anthropic-beta':'oauth-2025-04-20'},signal:AbortSignal.timeout(6000)}).then(function(x){return x.ok?x.json():null}).then(function(j){if(j&&j.account&&j.account.email)process.stdout.write(j.account.email)}).catch(function(){});"
        Set-Content -Path $tmp -Value $code -Encoding ASCII
        $out = cmd /c "node ""$tmp"" 2>nul"
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($out) { return ([string]($out -join '')).Trim() }
    } catch {}
    return $null
}

$root = Get-SessionRoot
if (-not $root) {
    Write-Host "Claude app data not found. Open Claude, log in, then retry." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

$detected = Get-LoggedInEmail $root
$email = $null
if ($detected) {
    $ans = Read-Host "Detected logged-in account: $detected - save this one? [Y/n]"
    if ($ans -notmatch '^(n|no)$') { $email = $detected }
} else {
    Write-Host "Could not verify which account is logged in (token dead or node missing)." -ForegroundColor Yellow
    Write-Host "If the app shows a sign-in screen, log in first - saving now would snapshot a logged-out session." -ForegroundColor Yellow
}
if (-not $email) {
    $email = Read-Host "Email of the account currently logged into Claude"
    if ([string]::IsNullOrWhiteSpace($email)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    if ($detected -and $email -ne $detected) {
        Write-Host "You typed '$email' but the live session belongs to '$detected' - not saving a mislabeled snapshot." -ForegroundColor Red
        Start-Sleep -Seconds 4; return
    }
}

Write-Host "Closing Claude..." -ForegroundColor Cyan
if (-not (Stop-Claude $root)) {
    Write-Host "Could not fully close Claude (session still locked)." -ForegroundColor Red
    Write-Host "Close every Claude window manually, then retry." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

$safe        = ($email -replace '[^\w.@+-]', '_')
$dest        = Join-Path $store $safe
$sessionDest = Join-Path $dest 'session'
New-Item -ItemType Directory -Force -Path $sessionDest | Out-Null

Write-Host "Saving session for $email ..." -ForegroundColor Cyan
foreach ($f in $SessionFolders) {
    $src = Join-Path $root $f
    if (-not (Test-Path $src)) { continue }
    $dst = Join-Path $sessionDest $f
    robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
}

# Also capture config.json's oauth:tokenCache - the desktop app reads THIS for
# the account identity/plan it displays, independent of the web cookies. Both
# must be swapped together for the switch to take effect.
$cfgFile = Join-Path $root 'config.json'
if (Test-Path $cfgFile) {
    try {
        $tc = (Get-Content $cfgFile -Raw | ConvertFrom-Json).'oauth:tokenCache'
        if ($tc) { Set-Content -Path (Join-Path $dest 'tokenCache.txt') -Value $tc -Encoding ASCII -NoNewline }
    } catch {}
}

[ordered]@{ email = $email; savedAt = (Get-Date -Format o); sourceRoot = $root } |
    ConvertTo-Json | Set-Content -Path (Join-Path $dest 'meta.json') -Encoding UTF8

# Mark this account as the one the live session belongs to, so claude-switch
# can sync the live session back into this snapshot even after the app rotates
# its tokens (a rotated token no longer matches the saved tokenCache).
try {
    [System.IO.File]::WriteAllText((Join-Path $store '.current'), $email,
        (New-Object System.Text.UTF8Encoding($false)))
} catch {}

Write-Host ""
Write-Host "Saved account: $email" -ForegroundColor Green
Write-Host ""

# Offer to set up the NEXT account. We clear the LOCAL session (delete the
# session folders + blank the token cache) instead of using the app's "Log out"
# - logging out revokes the session server-side, which would kill the snapshot
# we just saved. Clearing locally leaves the saved account valid to switch to.
$more = Read-Host "Add ANOTHER account now? (clears local login WITHOUT logging out, shows sign-in) [y/N]"
if ($more -match '^(y|yes)$') {
    Write-Host "Clearing local session (not logging out $email)..." -ForegroundColor Cyan
    # The live session is about to belong to a different (not yet saved)
    # account - drop the marker so claude-switch doesn't sync the new login
    # back into this account's snapshot.
    Remove-Item (Join-Path $store '.current') -Force -ErrorAction SilentlyContinue
    foreach ($f in $SessionFolders) {
        $p = Join-Path $root $f
        if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $cfgFile = Join-Path $root 'config.json'
    if (Test-Path $cfgFile) {
        try {
            $raw = Get-Content $cfgFile -Raw
            $raw = [Regex]::Replace($raw, '"oauth:tokenCache"\s*:\s*"[^"]*"', '"oauth:tokenCache": ""')
            [System.IO.File]::WriteAllText($cfgFile, $raw, (New-Object System.Text.UTF8Encoding($false)))
        } catch {}
    }
    Start-Claude
    Write-Host ""
    Write-Host "Claude is reopening at a SIGN-IN screen." -ForegroundColor Green
    Write-Host "Log in as the NEXT account, then run 'claude-add-account' again." -ForegroundColor Green
} else {
    Write-Host "Reopening Claude..." -ForegroundColor DarkGray
    Start-Claude
}
Start-Sleep -Seconds 2

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

$root = Get-SessionRoot
if (-not $root) {
    Write-Host "Claude app data not found. Open Claude, log in, then retry." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

$email = Read-Host "Email of the account currently logged into Claude"
if ([string]::IsNullOrWhiteSpace($email)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

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

Write-Host ""
Write-Host "Saved account: $email" -ForegroundColor Green
Write-Host "Reopening Claude..." -ForegroundColor DarkGray
Start-Claude
Start-Sleep -Seconds 2

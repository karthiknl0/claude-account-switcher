# Diagnostics for the Claude Code (CLI) account switcher. Prints which platform
# and credential backend were detected, whether a live login is found, and which
# accounts are saved - so you can verify the switcher before relying on it
# (handy on macOS, where the login lives in the Keychain).
#
# Cross-platform (Windows / Linux / macOS) - on Unix run with PowerShell (pwsh).

# -- Platform detection ($IsMacOS etc. only exist on PowerShell Core/7+) -------
$PlatformMac = $false; $PlatformWin = $true; $PlatformLinux = $false
if (Test-Path variable:IsMacOS)   { $PlatformMac   = $IsMacOS }
if (Test-Path variable:IsWindows) { $PlatformWin   = $IsWindows }
if (Test-Path variable:IsLinux)   { $PlatformLinux = $IsLinux }
$osName = if ($PlatformMac) { 'macOS' } elseif ($PlatformLinux) { 'Linux' } elseif ($PlatformWin) { 'Windows' } else { 'Unknown' }

$store = Join-Path $HOME '.claude-cc-accounts'
$cred  = Join-Path (Join-Path $HOME '.claude') '.credentials.json'
$KeychainService = 'Claude Code-credentials'

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

function Show-Line($label, $value, $color) {
    if (-not $color) { $color = 'Gray' }
    Write-Host ("  {0,-22}" -f $label) -NoNewline
    Write-Host $value -ForegroundColor $color
}

Write-Host ""
Write-Host "=== Claude Code switcher - doctor ===" -ForegroundColor Cyan
Write-Host ""

# -- Environment ---------------------------------------------------------------
Show-Line "Platform"        $osName
Show-Line "PowerShell"      $PSVersionTable.PSVersion.ToString()
Show-Line "Home"            $HOME

# -- Credential backend --------------------------------------------------------
if ($PlatformMac) {
    Show-Line "Credential backend" "macOS Keychain ($KeychainService)"
    $hasSecurity = [bool](Get-Command security -ErrorAction SilentlyContinue)
    Show-Line "security CLI"  $(if ($hasSecurity) { "found" } else { "MISSING" }) $(if ($hasSecurity) { 'Green' } else { 'Red' })
} else {
    Show-Line "Credential backend" "file"
    Show-Line "Credential file" $cred
}

# -- Live login ----------------------------------------------------------------
$raw = Get-LiveCredsRaw
if ($raw) {
    $tail = ''
    try {
        $tok  = ($raw | ConvertFrom-Json).claudeAiOauth.accessToken
        if ($tok) { $tail = " (token ...{0})" -f $tok.Substring([Math]::Max(0, $tok.Length - 6)) }
    } catch {}
    Show-Line "Live login"     "detected$tail" 'Green'
} else {
    $hint = if ($PlatformMac) { "no Keychain item - run /login in Claude Code" } else { "not logged in - run /login in Claude Code" }
    Show-Line "Live login"     "none ($hint)" 'Yellow'
}

# -- Saved accounts ------------------------------------------------------------
Show-Line "Accounts folder"  $store
$accounts = Get-ChildItem $store -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike 'backup-*' }
$names = @()
foreach ($a in $accounts) {
    try { $j = Get-Content $a.FullName -Raw | ConvertFrom-Json } catch { continue }
    if ($j.email -and $j.credentials) { $names += $j.email }
}
if ($names.Count) {
    Show-Line "Saved accounts"  ("{0} found" -f $names.Count) 'Green'
    foreach ($n in $names) { Write-Host "      - $n" -ForegroundColor Gray }
} else {
    Show-Line "Saved accounts"  "none yet (run 'claude-code-add')" 'Yellow'
}

Write-Host ""
$ready = $names.Count -gt 0 -and (-not $PlatformMac -or (Get-Command security -ErrorAction SilentlyContinue))
if ($ready) {
    Write-Host "Looks good - 'claude-code-switch' is ready to use." -ForegroundColor Green
} else {
    Write-Host "Setup incomplete - see the notes above." -ForegroundColor Yellow
}
Write-Host ""

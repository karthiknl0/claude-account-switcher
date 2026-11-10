# Shared helpers for the Claude Code (CLI) account switcher. Dot-sourced by
# claude-code-add / claude-code-switch / claude-code-doctor.
#
# v4 model: ONE CONFIG FOLDER PER ACCOUNT (Anthropic's documented way to stay
# signed in to several accounts - the CLAUDE_CONFIG_DIR environment variable).
#
# Versions 3.x swapped the OAuth tokens inside one shared .credentials.json.
# That stopped being reliable: Claude Code rotates the refresh token every time
# it refreshes, so a saved copy goes stale, and any session still open under
# the previous account writes ITS tokens back over the file a few hours later.
# The result was exactly "it logged me out" / "it didn't switch".
#
# Now every account signs in once into its own folder and stays signed in
# there. Claude Code refreshes each login in place; this tool never copies,
# edits or deletes a token again. "Switching" only changes which folder the
# `claude` command points at (a one-line marker file read by a small `claude`
# wrapper function the installer adds to your shell).
#
# Cross-platform (Windows / Linux / macOS). Must stay compatible with Windows
# PowerShell 5.1 (the Desktop shortcut's shell) - no PS7-only syntax, ASCII only.

# -- Platform detection ($IsMacOS etc. only exist on PowerShell Core/7+) -------
$PlatformMac = $false; $PlatformWin = $true; $PlatformLinux = $false
if (Test-Path variable:IsMacOS)   { $PlatformMac   = $IsMacOS }
if (Test-Path variable:IsWindows) { $PlatformWin   = $IsWindows }
if (Test-Path variable:IsLinux)   { $PlatformLinux = $IsLinux }

$CcStore    = Join-Path $HOME '.claude-cc-accounts'
$CcRegistry = Join-Path $CcStore 'accounts.json'
$CcActive   = Join-Path $CcStore '.active'
$CcUtf8     = New-Object System.Text.UTF8Encoding($false)
$CcRawBase  = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'
$CcKeychainService = 'Claude Code-credentials'

# Folders/files every account folder shares with the main one, so settings,
# plugins, skills and - most importantly - conversation transcripts are common
# to all accounts ('claude --resume' continues the same work on another account).
$CcSharedDirs  = @('projects', 'todos', 'tasks', 'plans', 'file-history',
                   'commands', 'agents', 'skills', 'plugins', 'output-styles', 'rules', 'ide')
$CcSharedFiles = @('settings.json', 'CLAUDE.md', 'keybindings.json')

function Write-TextNoBom($path, $text) {
    [System.IO.File]::WriteAllText($path, $text, $CcUtf8)
}

# -- The real `claude` program (NOT the wrapper function in the profile) -------
function Get-ClaudeExe {
    $c = @(Get-Command claude -CommandType ExternalScript, Application -ErrorAction SilentlyContinue)
    if ($c.Count -gt 0) { return $c[0].Path }
    return $null
}

# -- Registry ------------------------------------------------------------------
# accounts.json: { version, mainDir, accounts: [ { email, dir, isDefault } ] }
# The "default" account is the one living in the normal Claude Code folder
# (~/.claude) - it is used with NO environment variable, exactly as before.
function Get-DefaultConfigDir {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-Path $HOME '.claude')
}

function Read-Registry {
    if (-not (Test-Path $CcRegistry)) { return $null }
    try { $r = Get-Content $CcRegistry -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $r -or -not $r.mainDir) { return $null }
    $list = @()
    foreach ($a in @($r.accounts)) {
        if ($a -and $a.email -and $a.dir) {
            $list += [pscustomobject]@{ email = [string]$a.email; dir = [string]$a.dir; isDefault = [bool]$a.isDefault }
        }
    }
    return [pscustomobject]@{ mainDir = [string]$r.mainDir; accounts = $list }
}

function Save-Registry($reg) {
    New-Item -ItemType Directory -Force -Path $CcStore | Out-Null
    $o = [ordered]@{ version = 2; mainDir = $reg.mainDir; accounts = @($reg.accounts) }
    Write-TextNoBom $CcRegistry ($o | ConvertTo-Json -Depth 6)
}

function Get-ActiveAccount($reg) {
    $accts = @($reg.accounts)
    if ($accts.Count -eq 0) { return $null }
    $val = $null
    if (Test-Path $CcActive) { try { $val = (Get-Content $CcActive -Raw).Trim() } catch {} }
    if ($val -and $val -ne 'default') {
        $m = $accts | Where-Object { -not $_.isDefault -and $_.dir -eq $val } | Select-Object -First 1
        if ($m) { return $m }
    }
    $d = $accts | Where-Object { $_.isDefault } | Select-Object -First 1
    if ($d) { return $d }
    # No default account and no (valid) marker: `claude` runs in the main
    # folder, which has no saved account - so nothing is "current".
    return $null
}

function Set-ActiveAccount($acct) {
    New-Item -ItemType Directory -Force -Path $CcStore | Out-Null
    $val = if ($acct.isDefault) { 'default' } else { $acct.dir }
    Write-TextNoBom $CcActive $val
}

# -- Per-account files ---------------------------------------------------------
function Get-AccountConfigFile($acct) {
    # Without CLAUDE_CONFIG_DIR, Claude Code keeps .claude.json in the HOME
    # folder; with it, inside the config folder.
    $cands = @()
    if ($acct.isDefault) { $cands += (Join-Path $HOME '.claude.json') }
    $cands += (Join-Path $acct.dir '.claude.json')
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    return $cands[0]
}

function Get-AccountEmailFromConfig($acct) {
    $f = Get-AccountConfigFile $acct
    if (-not (Test-Path $f)) { return $null }
    try { return (Get-Content $f -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch { return $null }
}

function Get-Sha256Hex8($text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
        return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 8)
    } finally { $sha.Dispose() }
}

# READ-ONLY access to an account's stored login (used only to show usage).
function Get-AccountCredsRaw($acct) {
    if ($PlatformMac) {
        # macOS keeps the login in the Keychain; a non-default config folder
        # gets its own entry, suffixed with a hash of the folder path.
        $svc = $CcKeychainService
        if (-not $acct.isDefault) { $svc = $CcKeychainService + '-' + (Get-Sha256Hex8 $acct.dir) }
        try {
            $out = & security find-generic-password -s $svc -w 2>$null
            if ($LASTEXITCODE -eq 0 -and $out) { return ($out -join "`n") }
        } catch {}
    }
    $f = Join-Path $acct.dir '.credentials.json'
    if (Test-Path $f) { try { return (Get-Content $f -Raw) } catch {} }
    return $null
}

# -> @{ HasLogin; Token; Expired }
function Get-AccountLogin($acct) {
    $res = [pscustomobject]@{ HasLogin = $false; Token = $null; Expired = $false }
    $raw = Get-AccountCredsRaw $acct
    if (-not $raw) { return $res }
    try { $o = ($raw | ConvertFrom-Json).claudeAiOauth } catch { return $res }
    if (-not $o) { return $res }
    if ($o.refreshToken -or $o.accessToken) { $res.HasLogin = $true }
    $res.Token = $o.accessToken
    try {
        if ($o.expiresAt) {
            $nowMs = [int64](([datetime]::UtcNow - [datetime]'1970-01-01').TotalMilliseconds)
            if ([int64]$o.expiresAt -lt $nowMs) { $res.Expired = $true }
        }
    } catch {}
    return $res
}

# -- Running the real claude for one account -----------------------------------
function Invoke-ClaudeFor($acct, $cliArgs, [switch]$Capture) {
    $exe = Get-ClaudeExe
    if (-not $exe) { return $null }
    $old = $env:CLAUDE_CONFIG_DIR
    try {
        if (-not $acct.isDefault) { $env:CLAUDE_CONFIG_DIR = $acct.dir }
        if ($Capture) { return (& $exe @cliArgs 2>$null) }
        & $exe @cliArgs
    } finally {
        $env:CLAUDE_CONFIG_DIR = $old
    }
}

# `claude auth status` -> object ({ loggedIn, email, ... }) or $null.
function Get-AuthStatus($acct) {
    try {
        $out = Invoke-ClaudeFor $acct @('auth', 'status') -Capture
        if (-not $out) { return $null }
        # Tolerate extra lines around the JSON (notices, warnings).
        $text = ($out -join "`n")
        $a = $text.IndexOf('{'); $b = $text.LastIndexOf('}')
        if ($a -lt 0 -or $b -le $a) { return $null }
        $o = $text.Substring($a, $b - $a + 1) | ConvertFrom-Json
        # Only trust it if it has the field this tool relies on; otherwise the
        # callers fall back to checking the stored login directly.
        if ($null -eq $o.loggedIn) { return $null }
        return $o
    } catch { return $null }
}

# Email of the login stored in an account folder ($null when unknown).
function Get-AccountEmail($acct, $status) {
    if ($status -and $status.email) { return [string]$status.email }
    $e = Get-AccountEmailFromConfig $acct
    if ($e) { return [string]$e }
    return $null
}

# -- Account folder creation ---------------------------------------------------
# Remove a top-level `"key": { ... }` member from JSON TEXT, leaving every other
# byte untouched (a ConvertTo-Json round-trip under PowerShell 5.1 is lossy).
function Remove-JsonObjRaw($text, $key) {
    $m = [regex]::Match($text, '"' + [regex]::Escape($key) + '"\s*:\s*')
    if (-not $m.Success) { return $text }
    $i = $m.Index + $m.Length
    if ($i -ge $text.Length -or $text[$i] -ne '{') { return $null }
    $depth = 0; $inStr = $false; $esc = $false; $end = -1
    for ($j = $i; $j -lt $text.Length; $j++) {
        $ch = $text[$j]
        if ($esc) { $esc = $false; continue }
        if ($ch -eq '\') { $esc = $true; continue }
        if ($ch -eq '"') { $inStr = -not $inStr; continue }
        if ($inStr) { continue }
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { $end = $j; break } }
    }
    if ($end -lt 0) { return $null }
    $start = $m.Index
    $after = $end + 1
    $k = $after
    while ($k -lt $text.Length -and [char]::IsWhiteSpace($text[$k])) { $k++ }
    if ($k -lt $text.Length -and $text[$k] -eq ',') {
        $after = $k + 1                       # member had a trailing comma
    } else {
        $b = $start - 1                       # last member: drop the comma before it
        while ($b -ge 0 -and [char]::IsWhiteSpace($text[$b])) { $b-- }
        if ($b -ge 0 -and $text[$b] -eq ',') { $start = $b }
    }
    return $text.Substring(0, $start) + $text.Substring($after)
}

function New-DirLink($link, $target) {
    try {
        if ($PlatformWin) {
            # A junction needs no admin rights / Developer Mode.
            New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
        } else {
            New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
        }
        return $true
    } catch { return $false }
}

# Create (or complete) an account folder that shares transcripts, settings,
# plugins etc. with the main Claude Code folder. Never overwrites or deletes
# anything that already exists.
function Initialize-AccountDir($dir, $mainDir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    New-Item -ItemType Directory -Force -Path $mainDir | Out-Null

    foreach ($name in $CcSharedDirs) {
        $link = Join-Path $dir $name
        if (Test-Path $link) { continue }
        $target = Join-Path $mainDir $name
        if (-not (Test-Path $target)) { New-Item -ItemType Directory -Force -Path $target | Out-Null }
        [void](New-DirLink $link $target)
    }

    foreach ($name in $CcSharedFiles) {
        $link   = Join-Path $dir $name
        $target = Join-Path $mainDir $name
        if ((Test-Path $link) -or -not (Test-Path $target)) { continue }
        $linked = $false
        try { New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null; $linked = $true } catch {}
        # Windows without Developer Mode can't create file symlinks: fall back
        # to a one-time copy so the account at least starts with your settings.
        if (-not $linked) { try { Copy-Item $target $link -ErrorAction Stop } catch {} }
    }

    # Seed .claude.json (theme, onboarding state, MCP servers, trusted folders)
    # from the main one, minus the signed-in identity, so a new account folder
    # doesn't start from a blank first-run setup.
    $newCfg = Join-Path $dir '.claude.json'
    if (-not (Test-Path $newCfg)) {
        $mainCfg = $null
        foreach ($c in @((Join-Path $HOME '.claude.json'), (Join-Path $mainDir '.claude.json'))) {
            if (Test-Path $c) { $mainCfg = $c; break }
        }
        if ($mainCfg) {
            try {
                $seed = Remove-JsonObjRaw (Get-Content $mainCfg -Raw) 'oauthAccount'
                if ($seed) {
                    $null = $seed | ConvertFrom-Json          # must still be valid JSON
                    Write-TextNoBom $newCfg $seed
                }
            } catch {}
        }
    }
}

function Get-SafeName($email) { return ($email -replace '[^\w.@+-]', '_') }

# Accounts saved by versions 3.x (token snapshots: <email>.json). They are no
# longer used - only their emails are read, to tell the user what to re-add.
function Get-LegacyEmails {
    $out = @()
    $files = Get-ChildItem $CcStore -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'accounts.json' -and $_.Name -notlike 'backup-*' }
    foreach ($f in $files) {
        try { $j = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if ($j.email -and $j.credentials) { $out += [string]$j.email }
    }
    return $out
}

# -- Update check (best-effort, cached once per day) ---------------------------
function Test-ForUpdate {
    try {
        $tools     = Join-Path $HOME '.claude-tools'
        $checkFile = Join-Path $tools '.update-check'
        if (Test-Path $checkFile) {
            if (((Get-Date) - (Get-Item $checkFile).LastWriteTime) -lt [TimeSpan]::FromDays(1)) { return }
        }
        New-Item -ItemType File -Force -Path $checkFile | Out-Null
        (Get-Date -Format o) | Set-Content -Path $checkFile -ErrorAction SilentlyContinue
        $remote  = (Invoke-RestMethod -Uri "$CcRawBase/VERSION" -TimeoutSec 4).ToString().Trim()
        $verFile = Join-Path $tools '.version'
        $local   = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '0.0.0' }
        if ([version]$remote -gt [version]$local) {
            Write-Host ""
            Write-Host "  * Update available: v$local -> v$remote   (run 'claude-switch-update')" -ForegroundColor Yellow
        }
    } catch {}
}

# -- Usage readout -------------------------------------------------------------
# HttpClient, not Invoke-RestMethod: under Windows PowerShell 5.1
# Invoke-RestMethod can hang reading a SUCCESSFUL response from this endpoint
# (-TimeoutSec doesn't cover the read stall). HttpClient with its own Timeout
# is immune. This is a read-only GET; it never refreshes or rotates a token.
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
$script:CcHttpClient = $null
function Get-ClaudeUsage($accessToken) {
    if (-not $accessToken) { return $null }
    try {
        if (-not $script:CcHttpClient) {
            $handler = New-Object System.Net.Http.HttpClientHandler
            $script:CcHttpClient = New-Object System.Net.Http.HttpClient($handler)
            $script:CcHttpClient.Timeout = [TimeSpan]::FromSeconds(6)
        }
        $req = New-Object System.Net.Http.HttpRequestMessage('GET', 'https://api.anthropic.com/api/oauth/usage')
        $req.Headers.Add('Authorization', "Bearer $accessToken")
        $req.Headers.Add('anthropic-version', '2023-06-01')
        $req.Headers.Add('anthropic-beta', 'oauth-2025-04-20')
        $resp = $script:CcHttpClient.SendAsync($req).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { return $null }
        $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return ($body | ConvertFrom-Json)
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
            $rel = if ($d.TotalHours -ge 1) { "{0}h{1:00}m" -f [int][math]::Floor($d.TotalHours), $d.Minutes } else { "{0}m" -f [int]$d.TotalMinutes }
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

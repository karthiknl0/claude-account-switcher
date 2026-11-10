# Diagnostics for the Claude account switchers. Prints what was detected on
# this machine - where the logins live, which accounts are saved and whether
# each one is still signed in - so a problem can be pinpointed quickly.
# It only READS; it never changes anything and never prints a token.
#
# Cross-platform (Windows / Linux / macOS) - on Unix run with PowerShell (pwsh).
# The desktop-app section is Windows-only.

. (Join-Path $PSScriptRoot 'cc-common.ps1')

$osName = if ($PlatformMac) { 'macOS' } elseif ($PlatformLinux) { 'Linux' } elseif ($PlatformWin) { 'Windows' } else { 'Unknown' }

function Show-Line($label, $value, $color) {
    if (-not $color) { $color = 'Gray' }
    Write-Host ("  {0,-22}" -f $label) -NoNewline
    Write-Host $value -ForegroundColor $color
}

Write-Host ""
Write-Host "=== Claude account switcher - doctor ===" -ForegroundColor Cyan
Write-Host ""

# -- Environment ---------------------------------------------------------------
$verFile = Join-Path (Join-Path $HOME '.claude-tools') '.version'
$ver = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { 'unknown' }
Show-Line "Switcher version" $ver
Show-Line "Platform"         $osName
Show-Line "PowerShell"       $PSVersionTable.PSVersion.ToString()
Show-Line "Home"             $HOME

# ======================================================== Claude Code (CLI) ===
Write-Host ""
Write-Host "-- Claude Code (CLI) --" -ForegroundColor Cyan
$exe = Get-ClaudeExe
if ($exe) {
    $cliVer = $null
    try { $cliVer = (& $exe --version 2>$null | Select-Object -First 1) } catch {}
    Show-Line "claude command" "$exe  ($cliVer)" 'Green'
} else {
    Show-Line "claude command" "NOT FOUND on PATH" 'Red'
}

# Is the `claude` wrapper (which applies the chosen account) installed?
$wrapperOk = $false
$profileFiles = @()
if ($PlatformWin) {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $profileFiles += (Join-Path (Join-Path $docs 'WindowsPowerShell') 'Microsoft.PowerShell_profile.ps1')
    $profileFiles += (Join-Path (Join-Path $docs 'PowerShell') 'Microsoft.PowerShell_profile.ps1')
} else {
    $profileFiles += (Join-Path $HOME '.bashrc')
    $profileFiles += (Join-Path $HOME '.zshrc')
}
foreach ($pf in $profileFiles) {
    if (Test-Path $pf) {
        try { if ((Get-Content $pf -Raw) -match 'claude-cc-accounts') { $wrapperOk = $true } } catch {}
    }
}
if ($wrapperOk) {
    Show-Line "claude wrapper" "installed (new terminals follow claude-code-switch)" 'Green'
} else {
    Show-Line "claude wrapper" "MISSING - run 'claude-switch-update', then open a new terminal" 'Red'
}
if ($env:CLAUDE_CONFIG_DIR) { Show-Line "CLAUDE_CONFIG_DIR" "$($env:CLAUDE_CONFIG_DIR)  (set in this shell)" 'Yellow' }

$reg = Read-Registry
$accts = @()
if ($reg) { $accts = @($reg.accounts) }
$allSignedIn = $true
if ($reg) {
    Show-Line "Main folder" $reg.mainDir
    $active = Get-ActiveAccount $reg
    Show-Line "Saved accounts" ("{0} found" -f $accts.Count) $(if ($accts.Count) { 'Green' } else { 'Yellow' })
    foreach ($a in $accts) {
        $mark = if ($active -and $a.dir -eq $active.dir) { '*' } else { ' ' }
        $st   = $null
        if ($exe) { $st = Get-AuthStatus $a }
        $login = Get-AccountLogin $a
        if ($st -and $st.loggedIn) {
            $state = 'signed in'; $color = 'Green'
            $who = Get-AccountEmail $a $st
            if ($who -and $who -ne $a.email) { $state = "signed in as $who (expected $($a.email))"; $color = 'Red'; $allSignedIn = $false }
        } elseif ($st) {
            $state = "NOT signed in - run 'claude-code-add' and enter this email"; $color = 'Red'; $allSignedIn = $false
        } elseif ($login.HasLogin) {
            $state = 'login stored (could not ask claude to confirm it)'; $color = 'Yellow'
        } else {
            $state = "NOT signed in - run 'claude-code-add' and enter this email"; $color = 'Red'; $allSignedIn = $false
        }
        Write-Host ("    {0} {1}" -f $mark, $a.email) -NoNewline
        Write-Host "  - $state" -ForegroundColor $color
        $kind = if ($a.isDefault) { 'main folder' } else { 'own folder' }
        Write-Host ("        {0}: {1}" -f $kind, $a.dir) -ForegroundColor DarkGray
        if (-not $a.isDefault) {
            if (-not (Test-Path $a.dir)) {
                Write-Host "        folder is MISSING" -ForegroundColor Red; $allSignedIn = $false
            } elseif (-not (Test-Path (Join-Path $a.dir 'projects'))) {
                Write-Host "        transcripts are not shared with the main folder ('claude --resume' won't see other accounts' work)" -ForegroundColor Yellow
            }
        }
    }
} else {
    Show-Line "Saved accounts" "none yet (run 'claude-code-add')" 'Yellow'
}
$legacy = @(Get-LegacyEmails)
if ($legacy.Count -gt 0) {
    $missing = @($legacy | Where-Object { $e = $_; -not ($accts | Where-Object { $_.email -eq $e }) })
    if ($missing.Count -gt 0) {
        Show-Line "Old-format accounts" ("{0} not re-added yet: {1}" -f $missing.Count, ($missing -join ', ')) 'Yellow'
    }
}

# ============================================================= Desktop app ====
if ($PlatformWin) {
    Write-Host ""
    Write-Host "-- Claude desktop app --" -ForegroundColor Cyan
    . (Join-Path $PSScriptRoot 'desktop-common.ps1')
    foreach ($r in @(Get-DataRootCandidates)) {
        $tag = if (Test-RootAbandoned $r) { 'abandoned by the app (data moved)' } elseif (Test-RootHasProfile $r) { 'has a profile' } else { 'empty' }
        Write-Host "    $r" -ForegroundColor Gray
        Write-Host "        $tag" -ForegroundColor DarkGray
    }
    $root = Get-SessionRoot
    if ($root) {
        Show-Line "Live profile" $root 'Green'
        $live = Get-ProfileState $root
        $who = $null
        if ($live.Token) { $who = Get-TokenEmail $live.Token }
        $desc = switch ($live.State) {
            'SIGNEDIN' { if ($who) { "signed in as $who" } else { 'signed in (account could not be verified online)' } }
            'EMPTY'    { 'NOT signed in' }
            'MISSING'  { 'no config.json (app never started here?)' }
            default    { 'sign-in cache present but unreadable' }
        }
        Show-Line "Live session" $desc $(if ($live.State -eq 'SIGNEDIN') { 'Green' } else { 'Yellow' })
    } else {
        Show-Line "Live profile" "NOT FOUND - open the Claude app once" 'Red'
    }
    $saved = @(Get-SavedAccounts)
    Show-Line "Saved accounts" ("{0} found (marker: {1})" -f $saved.Count, (Get-CurrentMarker)) $(if ($saved.Count) { 'Green' } else { 'Yellow' })
    foreach ($s in $saved) {
        $state = switch ($s.State) {
            'SIGNEDIN' { 'snapshot has a sign-in' }
            'UNKNOWN'  { 'snapshot present (sign-in not readable)' }
            default    { "snapshot has NO sign-in - sign in to it and run 'claude-add-account' again" }
        }
        $color = if ($s.State -eq 'SIGNEDIN') { 'Green' } elseif ($s.State -eq 'UNKNOWN') { 'Yellow' } else { 'Red' }
        Write-Host "      $($s.Email)" -NoNewline
        Write-Host "  - $state" -ForegroundColor $color
    }
}

Write-Host ""
if ($accts.Count -gt 0 -and $allSignedIn -and $wrapperOk -and $exe) {
    Write-Host "Claude Code switcher looks good - 'claude-code-switch' is ready to use." -ForegroundColor Green
} else {
    Write-Host "Claude Code switcher needs attention - see the notes above." -ForegroundColor Yellow
}
Write-Host ""

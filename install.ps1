<#
    Claude Account Switcher - installer

    One-line install:
      Windows (PowerShell):
        irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
      macOS / Linux (needs PowerShell - https://aka.ms/powershell):
        pwsh -c "irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex"

    Installs (Windows):
      - ~/.claude-tools/*.ps1 (desktop + Claude Code switchers)
      - claude-switch-account / claude-add-account / claude-code-switch /
        claude-code-add commands in your PowerShell profiles (5.1 and 7)
      - a small `claude` wrapper function, so `claude` runs as the account
        chosen with claude-code-switch
      - Desktop shortcuts

    Installs (macOS / Linux):
      - ~/.claude-tools/claude-code-*.ps1, cc-common.ps1
      - claude-code-switch / claude-code-add / claude-switch-update functions
        and the `claude` wrapper in your shell (~/.bashrc and ~/.zshrc)
      (The desktop-app switcher is Windows-only and is skipped.)

    No npm required.

    To try an unreleased branch, set $env:CLAUDE_SWITCHER_REF to its name first
    (and use that branch name in the URL above).
#>

$Ref = 'main'
if ($env:CLAUDE_SWITCHER_REF) { $Ref = $env:CLAUDE_SWITCHER_REF }
$RawBase     = "https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/$Ref"
$MainRawBase = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'
$ToolsDir    = Join-Path $HOME '.claude-tools'
$SwitchPath  = Join-Path $ToolsDir 'claude-switch.ps1'
$AddPath     = Join-Path $ToolsDir 'claude-add.ps1'
$CcSwitchPath= Join-Path $ToolsDir 'claude-code-switch.ps1'
$CcAddPath   = Join-Path $ToolsDir 'claude-code-add.ps1'
$CcDoctorPath= Join-Path $ToolsDir 'claude-code-doctor.ps1'
$CleanupPath = Join-Path $ToolsDir 'claude-cleanup.ps1'
$CcCommonPath= Join-Path $ToolsDir 'cc-common.ps1'
$DtCommonPath= Join-Path $ToolsDir 'desktop-common.ps1'
$VersionPath = Join-Path $ToolsDir '.version'

# -- Platform detection ($IsWindows etc. only exist on PowerShell Core/7+) -----
$PlatformWin = $true; $PlatformMac = $false
if (Test-Path variable:IsWindows) { $PlatformWin = $IsWindows }
if (Test-Path variable:IsMacOS)   { $PlatformMac = $IsMacOS }

Write-Host ""
Write-Host "=== Claude Account Switcher - installer ===" -ForegroundColor Cyan

# 1. Fetch the scripts (CLI switcher works on every platform; the desktop
#    switcher is Windows-only).
Write-Host "[1/3] Installing scripts to $ToolsDir ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
try {
    Invoke-RestMethod -Uri "$RawBase/src/claude-code-switch.ps1" -OutFile $CcSwitchPath
    Invoke-RestMethod -Uri "$RawBase/src/claude-code-add.ps1"    -OutFile $CcAddPath
    Invoke-RestMethod -Uri "$RawBase/src/claude-code-doctor.ps1" -OutFile $CcDoctorPath
    Invoke-RestMethod -Uri "$RawBase/src/claude-cleanup.ps1"     -OutFile $CleanupPath
    Invoke-RestMethod -Uri "$RawBase/src/cc-common.ps1"          -OutFile $CcCommonPath
    if ($PlatformWin) {
        Invoke-RestMethod -Uri "$RawBase/src/desktop-common.ps1" -OutFile $DtCommonPath
        Invoke-RestMethod -Uri "$RawBase/src/claude-switch.ps1"  -OutFile $SwitchPath
        Invoke-RestMethod -Uri "$RawBase/src/claude-add.ps1"     -OutFile $AddPath
    }
} catch {
    Write-Host "ERROR: could not download scripts from GitHub." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    return
}

# Record the installed version (used by the daily update check).
try {
    $ver = (Invoke-RestMethod -Uri "$RawBase/VERSION" -TimeoutSec 8).ToString().Trim()
    Set-Content -Path $VersionPath -Value $ver -Encoding ASCII
    Write-Host "      Installed version $ver" -ForegroundColor DarkGray
} catch {}

if ($PlatformWin) {
    # ---------------------------------------------------------------- Windows --
    # 2. Add commands to PowerShell profiles (5.1 + 7)
    Write-Host "[2/3] Adding desktop + Claude Code switch commands to your PowerShell profiles..." -ForegroundColor Cyan
    $docs = [Environment]::GetFolderPath('MyDocuments')   # honours OneDrive redirection
    $profiles = @(
        (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')
    )
    # Marker-delimited block so re-running the installer cleanly REPLACES the old
    # definitions (lets us add/rename commands on update without leaving dupes).
    $beginMark = '# >>> claude-account-switcher >>>'
    $endMark   = '# <<< claude-account-switcher <<<'
    # Literal template (no PowerShell expansion) with __PLACEHOLDERS__ filled in below.
    $func = @'
__BEGIN__
# Claude account switcher (managed by claude-account-switcher installer)
# Desktop app (claude.ai chats):
function claude-switch-account { & "__SWITCH__" }
function claude-add-account    { & "__ADD__" }
# Claude Code CLI (coding work / usage):
function claude-code-switch    { & "__CCSWITCH__" @args }
function claude-code-add       { & "__CCADD__" }
function claude-code-doctor    { & "__CCDOCTOR__" }
function claude-switch-cleanup { & "__CLEANUP__" }
# Runs the real `claude` as the account chosen with claude-code-switch. Each
# account has its own Claude Code config folder; the choice is the one line in
# ~/.claude-cc-accounts/.active ('default' = your normal ~/.claude folder).
function claude {
    $casCmd = @(Get-Command claude -CommandType ExternalScript, Application -ErrorAction SilentlyContinue)
    if ($casCmd.Count -eq 0) { Write-Host "Claude Code ('claude') is not installed or not on PATH." -ForegroundColor Red; return }
    $casExe = $casCmd[0].Path
    $casOld = $env:CLAUDE_CONFIG_DIR
    $casSet = $false
    $casMarker = Join-Path (Join-Path $HOME '.claude-cc-accounts') '.active'
    if (Test-Path $casMarker) {
        $casDir = $null
        try { $casDir = (Get-Content $casMarker -Raw).Trim() } catch {}
        if ($casDir -and $casDir -ne 'default' -and (Test-Path $casDir)) { $env:CLAUDE_CONFIG_DIR = $casDir; $casSet = $true }
    }
    try {
        if ($MyInvocation.ExpectingInput) { $input | & $casExe @args } else { & $casExe @args }
    } finally {
        if ($casSet) { $env:CLAUDE_CONFIG_DIR = $casOld }
    }
}
function claude-switch-update {
    Write-Host "Updating Claude Account Switcher..." -ForegroundColor Cyan
    Remove-Item Env:CLAUDE_SWITCHER_REF -ErrorAction SilentlyContinue
    irm __RAW__/install.ps1 | iex
    Write-Host "Done. Open a new PowerShell window to load the updated commands." -ForegroundColor Green
}
__END__
'@
    $func = $func.Replace('__BEGIN__', $beginMark).Replace('__END__', $endMark)
    $func = $func.Replace('__SWITCH__', $SwitchPath).Replace('__ADD__', $AddPath)
    $func = $func.Replace('__CCSWITCH__', $CcSwitchPath).Replace('__CCADD__', $CcAddPath)
    $func = $func.Replace('__CCDOCTOR__', $CcDoctorPath).Replace('__RAW__', $MainRawBase)
    $func = $func.Replace('__CLEANUP__', $CleanupPath)
    foreach ($pf in $profiles) {
        $dir = Split-Path $pf
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if (-not (Test-Path $pf))  { New-Item -ItemType File -Force -Path $pf | Out-Null }
        $c = Get-Content $pf -Raw -ErrorAction SilentlyContinue
        if ($null -eq $c) { $c = '' }
        # Remove any previous managed block (and legacy un-marked block), then append fresh.
        $pattern = [Regex]::Escape($beginMark) + '.*?' + [Regex]::Escape($endMark)
        $c = [Regex]::Replace($c, $pattern, '', 'Singleline')
        # Legacy cleanup: drop any old un-delimited block from earlier versions.
        $c = $c -replace '(?s)\r?\n#\s*Claude desktop account switcher[^\r\n]*.*?function\s+claude-add-account\s*\{[^}]*\}', ''
        $c = $c.TrimEnd() + "`r`n`r`n" + $func + "`r`n"
        Set-Content -Path $pf -Value $c -Encoding UTF8
    }

    # 3. Desktop shortcuts (one per switcher)
    Write-Host "[3/3] Creating Desktop shortcuts..." -ForegroundColor Cyan
    $desktop = [Environment]::GetFolderPath('Desktop')
    $psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    $icon = $null
    $pkg  = Get-AppxPackage | Where-Object { $_.PackageFamilyName -eq 'Claude_pzs8sxrjxfjjc' } | Select-Object -First 1
    if ($pkg) {
        $cand = Join-Path $pkg.InstallLocation 'app\Claude.exe'
        if (Test-Path $cand) { $icon = "$cand,0" }
    }

    $ws = New-Object -ComObject WScript.Shell
    function New-SwitchShortcut($name, $scriptPath, $desc) {
        $sc = $ws.CreateShortcut((Join-Path $desktop $name))
        $sc.TargetPath       = $psExe
        $sc.Arguments        = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
        $sc.WorkingDirectory = $HOME
        if ($icon) { $sc.IconLocation = $icon }
        $sc.Description       = $desc
        $sc.WindowStyle      = 1
        $sc.Save()
    }
    New-SwitchShortcut 'Claude Switch Account.lnk' $SwitchPath   'Switch the Claude desktop app account'
    New-SwitchShortcut 'Claude Code Switch.lnk'    $CcSwitchPath 'Switch the Claude Code (CLI) account'

    # Launch shortcuts for the Claude Code CLI (open a console running the command).
    function New-ClaudeLaunchShortcut($name, $cliArgs, $desc) {
        $sc = $ws.CreateShortcut((Join-Path $desktop $name))
        $sc.TargetPath       = $psExe
        $sc.Arguments        = "-NoExit -Command `"claude $cliArgs`""
        $sc.WorkingDirectory = $HOME
        if ($icon) { $sc.IconLocation = $icon }
        $sc.Description       = $desc
        $sc.WindowStyle      = 1
        $sc.Save()
    }
    # (-CommandType: the `claude` wrapper function above must not count as the CLI.)
    if (Get-Command claude -CommandType ExternalScript, Application -ErrorAction SilentlyContinue) {
        New-ClaudeLaunchShortcut 'Claude Code.lnk'          ''           'Launch Claude Code (claude)'
        New-ClaudeLaunchShortcut 'Claude Code Resume.lnk'   '--resume'   'Resume a Claude Code session (claude --resume)'
        New-ClaudeLaunchShortcut 'Claude Code Continue.lnk' '--continue' 'Continue the last Claude Code session (claude --continue)'
    } else {
        Write-Host "      (claude CLI not on PATH - skipped Claude Code launch shortcuts)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Done! Claude Account Switcher is installed." -ForegroundColor Green
    Write-Host ""
    Write-Host "Open a NEW PowerShell window so the commands load. Two switchers:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  DESKTOP APP (claude.ai chats):" -ForegroundColor Gray
    Write-Host "    claude-add-account      save each account (don't use the app's Log out)" -ForegroundColor Gray
    Write-Host "    claude-switch-account   switch (also on the Desktop shortcut)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  CLAUDE CODE CLI (coding work + usage):" -ForegroundColor Gray
    Write-Host "    claude-code-add         save each account (signs each one in, once)" -ForegroundColor Gray
    Write-Host "    claude-code-switch      switch, then 'claude --resume' to continue work" -ForegroundColor Gray
    Write-Host "    claude-code-doctor      check setup (both switchers: logins, accounts, folders)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  claude-switch-cleanup     show disk use and remove leftovers from older versions" -ForegroundColor Gray
    Write-Host "  claude-switch-update      update to the latest version" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Updating from 3.x? Run claude-code-add and claude-add-account once -" -ForegroundColor Yellow
    Write-Host "  accounts are stored differently now (see the README, 'Upgrading from 3.x')." -ForegroundColor Yellow
}
else {
    # ----------------------------------------------------------- macOS / Linux --
    # 2. Add shell functions to the user's shell rc files. Each one invokes the
    #    .ps1 with `pwsh` so the user gets plain `claude-code-switch` commands in
    #    their normal bash/zsh shell.
    Write-Host "[2/2] Adding Claude Code switch commands to your shell (bash/zsh)..." -ForegroundColor Cyan

    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host "WARNING: 'pwsh' was not found on PATH." -ForegroundColor Yellow
        Write-Host "Install PowerShell (https://aka.ms/powershell) so the commands can run." -ForegroundColor Yellow
    }

    $beginMark = '# >>> claude-account-switcher >>>'
    $endMark   = '# <<< claude-account-switcher <<<'
    # Literal template (no PowerShell expansion) with __PLACEHOLDERS__ filled in below.
    $block = @'
__BEGIN__
# Claude Code account switcher (managed by claude-account-switcher installer)
claude-code-switch() { pwsh -NoProfile -File "__CCSWITCH__" "$@"; }
claude-code-add()    { pwsh -NoProfile -File "__CCADD__"; }
claude-code-doctor() { pwsh -NoProfile -File "__CCDOCTOR__"; }
claude-switch-cleanup() { pwsh -NoProfile -File "__CLEANUP__"; }
claude-switch-update() { CLAUDE_SWITCHER_REF= pwsh -NoProfile -Command "irm __RAW__/install.ps1 | iex"; }
# Runs the real `claude` as the account chosen with claude-code-switch. Each
# account has its own Claude Code config folder; the choice is the one line in
# ~/.claude-cc-accounts/.active ('default' = your normal ~/.claude folder).
unalias claude 2>/dev/null || true
function claude {
  local cas_dir="" cas_bin=""
  [ -f "$HOME/.claude-cc-accounts/.active" ] && cas_dir="$(cat "$HOME/.claude-cc-accounts/.active" 2>/dev/null)"
  cas_bin="$(whence -p claude 2>/dev/null || type -P claude 2>/dev/null)"
  [ -z "$cas_bin" ] && [ -x "$HOME/.claude/local/claude" ] && cas_bin="$HOME/.claude/local/claude"
  if [ -z "$cas_bin" ]; then echo "Claude Code ('claude') is not installed or not on PATH." >&2; return 127; fi
  if [ -n "$cas_dir" ] && [ "$cas_dir" != "default" ] && [ -d "$cas_dir" ]; then
    CLAUDE_CONFIG_DIR="$cas_dir" "$cas_bin" "$@"
  else
    "$cas_bin" "$@"
  fi
}
__END__
'@
    $block = $block.Replace('__BEGIN__', $beginMark).Replace('__END__', $endMark)
    $block = $block.Replace('__CCSWITCH__', $CcSwitchPath).Replace('__CCADD__', $CcAddPath)
    $block = $block.Replace('__CCDOCTOR__', $CcDoctorPath).Replace('__RAW__', $MainRawBase)
    $block = $block.Replace('__CLEANUP__', $CleanupPath)

    $rcFiles = @(
        (Join-Path $HOME '.bashrc'),
        (Join-Path $HOME '.zshrc')
    )
    $touched = @()
    foreach ($rc in $rcFiles) {
        # Only update an rc file that already exists, plus always ensure ~/.bashrc
        # exists on Linux and ~/.zshrc on macOS (the common default shells).
        $isDefault = ($PlatformMac -and $rc.EndsWith('.zshrc')) -or ((-not $PlatformMac) -and $rc.EndsWith('.bashrc'))
        if (-not (Test-Path $rc) -and -not $isDefault) { continue }
        if (-not (Test-Path $rc)) { New-Item -ItemType File -Force -Path $rc | Out-Null }
        $c = Get-Content $rc -Raw -ErrorAction SilentlyContinue
        if ($null -eq $c) { $c = '' }
        $pattern = [Regex]::Escape($beginMark) + '.*?' + [Regex]::Escape($endMark)
        $c = [Regex]::Replace($c, $pattern, '', 'Singleline')
        $c = $c.TrimEnd() + "`n`n" + $block + "`n"
        # Write LF-only, no BOM (shells choke on BOM/CRLF).
        [System.IO.File]::WriteAllText($rc, ($c -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
        $touched += $rc
    }

    Write-Host ""
    Write-Host "Done! Claude Code account switcher is installed." -ForegroundColor Green
    if ($PlatformMac) {
        Write-Host "Note: macOS stores the Claude Code login in the Keychain. The first time" -ForegroundColor DarkGray
        Write-Host "the switcher reads it (to show usage), macOS may ask you to Allow access." -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host ("Updated: " + ($touched -join ', ')) -ForegroundColor DarkGray
    Write-Host "Run 'source ~/.bashrc' (or ~/.zshrc), or open a new terminal, then:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  claude-code-add         save each account (signs each one in, once)" -ForegroundColor Gray
    Write-Host "  claude-code-switch      switch, then 'claude --resume' to continue work" -ForegroundColor Gray
    Write-Host "  claude-code-doctor      check setup (logins, accounts, folders)" -ForegroundColor Gray
    Write-Host "  claude-switch-cleanup   show disk use and remove leftovers from older versions" -ForegroundColor Gray
    Write-Host "  claude-switch-update    update to the latest version" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Updating from 3.x? Run claude-code-add once - accounts are stored differently now." -ForegroundColor Yellow
}

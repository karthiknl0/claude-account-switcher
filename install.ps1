<#
    Claude Account Switcher - installer

    One-line install (run in PowerShell):
      irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex

    Installs:
      - ~/.claude-tools/claude-switch.ps1, claude-add.ps1
      - `claude-switch-account` / `claude-add-account` commands in your
        PowerShell profiles (Windows PowerShell 5.1 and PowerShell 7)
      - a "Claude Switch Account" shortcut on your Desktop

    No npm required - it works directly on Claude's credentials file.
#>

$RawBase     = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'
$ToolsDir    = Join-Path $env:USERPROFILE '.claude-tools'
$SwitchPath  = Join-Path $ToolsDir 'claude-switch.ps1'
$AddPath     = Join-Path $ToolsDir 'claude-add.ps1'
$CcSwitchPath= Join-Path $ToolsDir 'claude-code-switch.ps1'
$CcAddPath   = Join-Path $ToolsDir 'claude-code-add.ps1'
$VersionPath = Join-Path $ToolsDir '.version'

Write-Host ""
Write-Host "=== Claude Account Switcher - installer ===" -ForegroundColor Cyan

# 1. Fetch the scripts
Write-Host "[1/3] Installing scripts to $ToolsDir ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
try {
    Invoke-RestMethod -Uri "$RawBase/src/claude-switch.ps1"      -OutFile $SwitchPath
    Invoke-RestMethod -Uri "$RawBase/src/claude-add.ps1"         -OutFile $AddPath
    Invoke-RestMethod -Uri "$RawBase/src/claude-code-switch.ps1" -OutFile $CcSwitchPath
    Invoke-RestMethod -Uri "$RawBase/src/claude-code-add.ps1"    -OutFile $CcAddPath
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
$func = @"
$beginMark
# Claude account switcher (managed by claude-account-switcher installer)
# Desktop app (claude.ai chats):
function claude-switch-account { & "$SwitchPath" }
function claude-add-account    { & "$AddPath" }
# Claude Code CLI (coding work / usage):
function claude-code-switch    { & "$CcSwitchPath" }
function claude-code-add       { & "$CcAddPath" }
function claude-switch-update {
    Write-Host "Updating Claude Account Switcher..." -ForegroundColor Cyan
    irm $RawBase/install.ps1 | iex
    Write-Host "Done. Open a new PowerShell window to load the updated commands." -ForegroundColor Green
}
$endMark
"@
foreach ($pf in $profiles) {
    $dir = Split-Path $pf
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path $pf))  { New-Item -ItemType File -Force -Path $pf | Out-Null }
    $c = Get-Content $pf -Raw -ErrorAction SilentlyContinue
    if ($null -eq $c) { $c = '' }
    # Remove any previous managed block (and legacy un-marked block), then append fresh.
    $pattern = [Regex]::Escape($beginMark) + '.*?' + [Regex]::Escape($endMark)
    $c = [Regex]::Replace($c, $pattern, '', 'Singleline')
    # Legacy cleanup: drop any old un-delimited block from earlier versions
    # (header may be bare "# Claude desktop account switcher" or with a suffix).
    $c = $c -replace '(?s)\r?\n#\s*Claude desktop account switcher[^\r\n]*.*?function\s+claude-add-account\s*\{[^}]*\}', ''
    $c = $c.TrimEnd() + "`r`n`r`n" + $func + "`r`n"
    Set-Content -Path $pf -Value $c -Encoding UTF8
}

# 3. Desktop shortcut
Write-Host "[3/3] Creating Desktop shortcut..." -ForegroundColor Cyan
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk     = Join-Path $desktop 'Claude Switch Account.lnk'
$psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$icon = $null
$pkg  = Get-AppxPackage | Where-Object { $_.PackageFamilyName -eq 'Claude_pzs8sxrjxfjjc' } | Select-Object -First 1
if ($pkg) {
    $cand = Join-Path $pkg.InstallLocation 'app\Claude.exe'
    if (Test-Path $cand) { $icon = "$cand,0" }
}

$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath       = $psExe
$sc.Arguments        = "-ExecutionPolicy Bypass -NoProfile -File `"$SwitchPath`""
$sc.WorkingDirectory = $env:USERPROFILE
if ($icon) { $sc.IconLocation = $icon }
$sc.Description       = 'Switch the active Claude account and restart the Claude desktop app'
$sc.WindowStyle      = 1
$sc.Save()

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
Write-Host "    claude-code-add         save each account (after /login in Claude Code)" -ForegroundColor Gray
Write-Host "    claude-code-switch      switch, then 'claude --resume' to continue work" -ForegroundColor Gray
Write-Host ""
Write-Host "  claude-switch-update      update to the latest version" -ForegroundColor Gray

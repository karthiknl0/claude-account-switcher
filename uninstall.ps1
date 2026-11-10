<#
    Claude Account Switcher - uninstaller

    One-line uninstall:
      Windows:        irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/uninstall.ps1 | iex
      macOS / Linux:  pwsh -c "irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/uninstall.ps1 | iex"

    Removes the scripts, the Desktop shortcuts, and the commands added to your
    shell profiles (including the `claude` wrapper - `claude` then runs as the
    login in your normal ~/.claude folder again).

    Does NOT touch your saved accounts or your Claude logins. Remove saved
    accounts manually if you want (see the README, "Uninstall").
#>

Write-Host "Removing Claude Account Switcher..." -ForegroundColor Cyan

$PlatformWin = $true
if (Test-Path variable:IsWindows) { $PlatformWin = $IsWindows }

# 0. Our status line entry in Claude Code's settings (it points at a script
#    that is about to be deleted). Uses the still-installed helper; a status
#    line you set up yourself is not touched.
$cc = Join-Path (Join-Path $HOME '.claude-tools') 'cc-common.ps1'
if (Test-Path $cc) {
    try {
        . $cc
        foreach ($f in @(Get-SettingsFiles)) {
            if ((Get-StatusLineState $f) -eq 'on' -and (Disable-StatusLine $f) -eq 'off') { Write-Host " - removed the usage status line from $f" }
        }
    } catch {}
}

# 1. Tools dir
$ToolsDir = Join-Path $HOME '.claude-tools'
if (Test-Path $ToolsDir) { Remove-Item -Recurse -Force $ToolsDir; Write-Host " - removed $ToolsDir" }

# 2. Desktop shortcuts (Windows)
if ($PlatformWin) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    foreach ($name in @('Claude Switch Account.lnk', 'Claude Code Switch.lnk', 'Claude Code.lnk',
                        'Claude Code Resume.lnk', 'Claude Code Continue.lnk')) {
        $lnk = Join-Path $desktop $name
        if (Test-Path $lnk) { Remove-Item -Force $lnk; Write-Host " - removed Desktop shortcut '$name'" }
    }
}

# 3. Managed block from the shell profiles
$beginMark = '# >>> claude-account-switcher >>>'
$endMark   = '# <<< claude-account-switcher <<<'
$pattern   = [Regex]::Escape($beginMark) + '.*?' + [Regex]::Escape($endMark)
if ($PlatformWin) {
    $docs  = [Environment]::GetFolderPath('MyDocuments')
    $files = @(
        (Join-Path (Join-Path $docs 'WindowsPowerShell') 'Microsoft.PowerShell_profile.ps1'),
        (Join-Path (Join-Path $docs 'PowerShell') 'Microsoft.PowerShell_profile.ps1')
    )
    $nl = "`r`n"
} else {
    $files = @((Join-Path $HOME '.bashrc'), (Join-Path $HOME '.zshrc'))
    $nl = "`n"
}
foreach ($pf in $files) {
    if (-not (Test-Path $pf)) { continue }
    $c = Get-Content $pf -Raw -ErrorAction SilentlyContinue
    if ($null -eq $c) { continue }
    $new = [Regex]::Replace($c, $pattern, '', 'Singleline')
    # Legacy cleanup: the un-delimited block written by the very first versions.
    $new = $new -replace '(?s)\r?\n#\s*Claude desktop account switcher[^\r\n]*.*?function\s+claude-add-account\s*\{[^}]*\}', ''
    if ($new -eq $c) { continue }
    $new = $new.TrimEnd() + $nl
    if ($PlatformWin) {
        Set-Content -Path $pf -Value $new -Encoding UTF8 -NoNewline
    } else {
        # LF-only, no BOM (shells choke on BOM/CRLF).
        [System.IO.File]::WriteAllText($pf, ($new -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Host " - cleaned $pf"
}

Write-Host "Done. Open a new terminal for changes to take effect." -ForegroundColor Green

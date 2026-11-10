# Switch which account the Claude Code (CLI) `claude` command runs as.
#
# v4: each account is signed in inside its own config folder (see
# cc-common.ps1). Switching just records which folder `claude` should use - no
# token is copied, edited or deleted, so nothing gets logged out and sessions
# that are already open simply keep running on their own account.
#
# Transcripts are shared between the account folders, so after switching you
# can `claude --resume` to continue the same work under the new account.
#
# Usage:  claude-code-switch            (menu)
#         claude-code-switch 2          (by number)
#         claude-code-switch me@x.com   (by email)
#
# Cross-platform (Windows / Linux / macOS) - on Unix run with PowerShell (pwsh).

. (Join-Path $PSScriptRoot 'cc-common.ps1')

$reg = Read-Registry
$list = @()
if ($reg) { $list = @($reg.accounts) }
if ($list.Count -eq 0) {
    Write-Host ""
    if (@(Get-LegacyEmails).Count -gt 0) {
        Write-Host "Your saved Claude Code accounts are from an older version of this tool." -ForegroundColor Yellow
        Write-Host "Claude Code now invalidates saved token copies, so accounts are kept differently." -ForegroundColor Yellow
        Write-Host "Run 'claude-code-add' once - it keeps your current login and walks you through the rest." -ForegroundColor Yellow
    } else {
        Write-Host "No saved Claude Code accounts." -ForegroundColor Yellow
        Write-Host "Run 'claude-code-add' to save each account." -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 4; return
}

$active = Get-ActiveAccount $reg
$chosen = $null

# -- Direct selection (number or email as argument) ----------------------------
$want = $null
if ($args.Count -gt 0) { $want = [string]$args[0] }
if ($want) {
    if ($want -match '^\d+$' -and [int]$want -ge 1 -and [int]$want -le $list.Count) {
        $chosen = $list[[int]$want - 1]
    } else {
        $chosen = $list | Where-Object { $_.email -eq $want } | Select-Object -First 1
    }
    if (-not $chosen) { Write-Host "No saved account matches '$want'." -ForegroundColor Red; return }
} else {
    # -- Picker ----------------------------------------------------------------
    Write-Host ""
    Write-Host "=== Switch Claude Code account ===" -ForegroundColor Cyan
    Test-ForUpdate
    Write-Host "Fetching usage..." -ForegroundColor DarkGray
    for ($i = 0; $i -lt $list.Count; $i++) {
        $a     = $list[$i]
        $mark  = if ($active -and $a.dir -eq $active.dir) { '*' } else { ' ' }
        $login = Get-AccountLogin $a
        $u     = $null
        if ($login.HasLogin -and $login.Token -and -not $login.Expired) { $u = Get-ClaudeUsage $login.Token }
        if ($u) {
            $usageStr = "  5h {0,3}% / 7d {1,3}% used" -f [int]$u.five_hour.utilization, [int]$u.seven_day.utilization
        } elseif (-not $login.HasLogin) {
            $usageStr = "  NOT SIGNED IN - run 'claude-code-add'"
        } else {
            $usageStr = "  usage n/a (shows after this account is next used)"
        }
        Write-Host ("  [{0}] {1} {2,-32}{3}" -f ($i + 1), $mark, $a.email, $usageStr)
        $resetStr = Format-Resets $u
        if ($resetStr) { Write-Host ("        $resetStr") -ForegroundColor DarkGray }
    }
    Write-Host "  (* = current   |   lower % = more headroom)" -ForegroundColor DarkGray
    Write-Host ""

    $pick = Read-Host "Pick an account number (or Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($pick)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $list.Count) {
        Write-Host "Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 2; return
    }
    $chosen = $list[[int]$pick - 1]
}

if (-not $chosen.isDefault -and -not (Test-Path $chosen.dir)) {
    Write-Host "The folder for $($chosen.email) is missing ($($chosen.dir))." -ForegroundColor Red
    Write-Host "Run 'claude-code-add' and enter $($chosen.email) to set it up again." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

Set-ActiveAccount $chosen

Write-Host ""
if ($active -and $chosen.dir -eq $active.dir) {
    Write-Host "Already on $($chosen.email)." -ForegroundColor Green
} else {
    Write-Host "Switched Claude Code to $($chosen.email)." -ForegroundColor Green
}
if (-not (Get-AccountLogin $chosen).HasLogin) {
    Write-Host "This account is not signed in on this computer - run 'claude-code-add' and enter $($chosen.email)." -ForegroundColor Yellow
}
Write-Host "New 'claude' sessions now run as this account. Run 'claude --resume' to continue your work." -ForegroundColor Cyan
Write-Host "(Sessions that are already open keep their own account - no need to close them.)" -ForegroundColor DarkGray
if (-not ($active -and $chosen.dir -eq $active.dir)) {
    Write-Host ""
    Write-Host "Saving usage on the new account: it has to read the whole conversation once." -ForegroundColor Yellow
    Write-Host "  - If Claude Code offers 'resume from summary', choose it." -ForegroundColor Gray
    Write-Host "  - Or start a new session and ask it to continue from the previous one." -ForegroundColor Gray
    Write-Host "  - Best: type /compact on the OLD account before its limit runs out" -ForegroundColor Gray
    Write-Host "    ('claude-code-statusline on' shows when)." -ForegroundColor Gray
}
Start-Sleep -Seconds 1

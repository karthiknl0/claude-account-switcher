# Switch the Claude desktop account by swapping its Electron profile.
# The Claude desktop app keeps its login in its profile folder (cookies, Local
# Storage, IndexedDB, encrypted OAuth cache), so switching means closing the
# app, swapping that profile for a saved account's, and restarting.
# Shared logic (where the profile lives, what is copied) is in
# desktop-common.ps1.
#
# IMPORTANT: run from a STANDALONE PowerShell window - THIS CLOSES the Claude
# app (and any session running inside it).

. (Join-Path $PSScriptRoot 'desktop-common.ps1')

# -- Load saved accounts -------------------------------------------------------
$list = @(Get-SavedAccounts)
if ($list.Count -eq 0) {
    Write-Host "No saved Claude accounts." -ForegroundColor Yellow
    Write-Host "Log into Claude, then run 'claude-add-account' to save each account." -ForegroundColor Yellow
    Start-Sleep -Seconds 3; return
}

Write-Host ""
Write-Host "=== Switch Claude account ===" -ForegroundColor Cyan
Test-ForUpdate

$root = Get-SessionRoot
if (-not $root) {
    Write-Host "Claude app data not found. Open the Claude app once, then retry." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# -- Who is the live session? --------------------------------------------------
# Ask the app's own token rather than trusting a marker file: if the live
# session is signed out, or belongs to someone else, it must NOT be copied over
# a saved account's good snapshot.
$live      = Get-ProfileState $root
$liveEmail = $null
if ($live.Token) { $liveEmail = Get-TokenEmail $live.Token }

$currentAcct = $null     # the saved account the live session belongs to
$syncBack    = $false    # safe to refresh that account's snapshot from the live profile
if ($liveEmail) {
    $currentAcct = $list | Where-Object { $_.Email -eq $liveEmail } | Select-Object -First 1
    $syncBack    = [bool]$currentAcct
} elseif ($live.State -eq 'SIGNEDIN' -or $live.State -eq 'UNKNOWN') {
    # Signed in but unverifiable (offline / expired token): fall back to the
    # marker written by the last add/switch.
    $curEmail = Get-CurrentMarker
    if ($curEmail) { $currentAcct = $list | Where-Object { $_.Email -eq $curEmail } | Select-Object -First 1 }
    $syncBack = [bool]$currentAcct
}

# -- Display picker ------------------------------------------------------------
Write-Host "Fetching usage..." -ForegroundColor DarkGray
for ($i = 0; $i -lt $list.Count; $i++) {
    $a    = $list[$i]
    $mark = if ($currentAcct -and $a.Email -eq $currentAcct.Email) { '*' } else { ' ' }
    $tok  = if ($mark -eq '*' -and $live.Token) { $live.Token } else { $a.Token }
    $u    = Get-ClaudeUsage $tok
    if ($a.State -eq 'MISSING' -or $a.State -eq 'EMPTY') {
        $usageStr = "  NEEDS RE-ADD (sign in to it, run claude-add-account)"
    } elseif ($u) {
        $usageStr = "  5h {0,3}% / 7d {1,3}% used" -f [int]$u.five_hour.utilization, [int]$u.seven_day.utilization
    } else {
        $usageStr = "  usage n/a"
    }
    Write-Host ("  [{0}] {1} {2,-32}{3}" -f ($i + 1), $mark, $a.Email, $usageStr)
    $resetStr = Format-Resets $u
    if ($resetStr) { Write-Host ("        $resetStr") -ForegroundColor DarkGray }
}
Write-Host "  (* = current   |   lower % = more headroom)" -ForegroundColor DarkGray
if ($live.State -eq 'EMPTY' -or $live.State -eq 'MISSING') {
    Write-Host "  The Claude app is not signed in right now." -ForegroundColor DarkGray
}
Write-Host ""
$pick = Read-Host "Pick an account number (or Enter to cancel)"
if ([string]::IsNullOrWhiteSpace($pick)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $list.Count) {
    Write-Host "Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 2; return
}
$chosen = $list[[int]$pick - 1]

if ($chosen.State -eq 'MISSING' -or $chosen.State -eq 'EMPTY') {
    Write-Host ""
    Write-Host "The saved snapshot for $($chosen.Email) has no sign-in in it, so it can't be restored." -ForegroundColor Red
    Write-Host "(Snapshots taken before the Claude app moved its data folder can be empty.)" -ForegroundColor Red
    Write-Host "Sign in to $($chosen.Email) in the Claude app, then run 'claude-add-account' to save it again." -ForegroundColor Yellow
    if ($chosen.State -eq 'MISSING') { Start-Sleep -Seconds 5; return }
    # EMPTY can also mean a newer Claude keeps its sign-in under a name this
    # tool can't read. The live profile is backed up first, so trying is safe.
    $force = Read-Host "Or type RESTORE to try this snapshot anyway (Enter to cancel)"
    if ($force -cne 'RESTORE') { return }
}
Set-RootCache $root

if ($syncBack -and $currentAcct -and $chosen.Email -eq $currentAcct.Email) {
    # Restoring an account's older snapshot over its own live session would
    # replace a fresh login with a stale one.
    # No swap happens for the account you are sitting on, so the usual sharing
    # step below never runs for it. Add the missing Code-tab entries straight
    # into the live profile (add-only, new files only - safe while the app is
    # open; it lists them the next time it starts).
    $carried = Sync-CodeSessions @($list | ForEach-Object { $_.Profile }) $root
    if ($carried -gt 0) {
        Write-Host "Added $carried Code session(s) from your saved accounts to this account's list." -ForegroundColor Green
        Write-Host "Close and reopen the Claude app to see them." -ForegroundColor Yellow
    }
    if ($liveEmail) {
        Write-Host "Already on $($chosen.Email)." -ForegroundColor Green
        Set-CurrentMarker $chosen.Email
        Start-Sleep -Seconds 2; return
    }
    Write-Host "Claude already appears to be on $($chosen.Email) (could not verify online)." -ForegroundColor Yellow
    $go = Read-Host "Restore its saved snapshot over the live session anyway? [y/N]"
    if ($go -notmatch '^(y|yes)$') { Write-Host "Cancelled." -ForegroundColor Yellow; return }
}

if ($liveEmail -and -not $currentAcct) {
    Write-Host ""
    Write-Host "The Claude app is signed in as $liveEmail, which is NOT saved yet." -ForegroundColor Yellow
    Write-Host "Switching now replaces that login (run 'claude-add-account' first to keep it)." -ForegroundColor Yellow
    $go = Read-Host "Switch anyway? [y/N]"
    if ($go -notmatch '^(y|yes)$') { Write-Host "Cancelled." -ForegroundColor Yellow; return }
}

# -- Perform the swap ----------------------------------------------------------
Write-Host ""
Write-Host "Closing Claude..." -ForegroundColor Cyan
if (-not (Stop-Claude $root)) {
    Write-Host "Could not fully close Claude (session locked). Close all windows and retry." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# Back up the live profile so a bad swap is recoverable. There is ONE backup
# slot and it is overwritten in place on every switch - nothing accumulates.
$backup = $DtBackup
Write-Host "Backing up current profile..." -ForegroundColor DarkGray
if (-not (Copy-ClaudeProfile $root (Join-Path $backup 'profile') $true)) {
    Write-Host "Could not back up the current profile. Refusing to switch." -ForegroundColor Red
    [void](Start-Claude)
    Start-Sleep -Seconds 3; return
}

# Timestamped backups left by older versions are no longer needed.
Remove-OldBackups

# Sync the live profile back into its account's snapshot before loading another
# one (the app rotates its session while it runs, so the snapshot taken at
# add-time goes stale). Only done when the live session is verified signed in
# AND known to belong to that account - never overwrite a good snapshot with a
# signed-out or foreign session.
if ($syncBack -and $currentAcct -and $currentAcct.Email -ne $chosen.Email) {
    Write-Host "Refreshing saved profile for $($currentAcct.Email)..." -ForegroundColor DarkGray
    # The account's ONE saved copy is overwritten in place with its current
    # data. Its sign-in must survive that: if the refreshed copy does not show
    # the sign-in the live profile had, redo it once from the backup (an
    # identical copy of the live profile) and refuse to switch if that fails.
    $ok = Copy-ClaudeProfile $root $currentAcct.Profile $true
    if ($ok -and $live.State -eq 'SIGNEDIN' -and (Get-ProfileState $currentAcct.Profile).State -ne 'SIGNEDIN') {
        $ok = (Copy-ClaudeProfile (Join-Path $backup 'profile') $currentAcct.Profile $true) -and
              ((Get-ProfileState $currentAcct.Profile).State -eq 'SIGNEDIN')
    }
    if (-not $ok) {
        Write-Host "Could not refresh the saved copy of $($currentAcct.Email). Refusing to switch (nothing was changed in the app)." -ForegroundColor Red
        [void](Start-Claude)
        Start-Sleep -Seconds 3; return
    }
}

# Make the Code-tab sessions of the other accounts show up in the account that
# is about to be loaded (index entries only - see Sync-CodeSessions).
$others  = @($root) + @($list | Where-Object { $_.Email -ne $chosen.Email } | ForEach-Object { $_.Profile })
$carried = Sync-CodeSessions $others $chosen.Profile
if ($carried -gt 0) {
    Write-Host "Added $carried Code session(s) from your other accounts to $($chosen.Email)'s list." -ForegroundColor DarkGray
}

Write-Host "Loading complete profile for $($chosen.Email)..." -ForegroundColor Cyan
if (-not (Copy-ClaudeProfile $chosen.Profile $root)) {
    Write-Host "Could not load the selected profile. Restore the backup at $backup if needed." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# Remember which saved account the live session now belongs to (used only when
# the live token can't be verified online).
Set-CurrentMarker $chosen.Email

Write-Host "Reopening Claude..." -ForegroundColor Cyan
if (-not (Start-Claude)) {
    Write-Host "Session swapped, but the Claude app wasn't found to relaunch - open it manually." -ForegroundColor Yellow
    Start-Sleep -Seconds 3; return
}

# -- Check the result instead of assuming it worked ----------------------------
Write-Host "Checking that Claude accepted the switch (up to 45 seconds)..." -ForegroundColor DarkGray
$check = Wait-LiveAccount $root $chosen.Email 45
# A snapshot whose sign-in this tool could not read in the first place can't
# be judged "rejected" by the same reading.
if ($check.Result -eq 'REJECTED' -and $chosen.State -ne 'SIGNEDIN') { $check.Result = 'UNSURE' }
Write-Host ""
if ($check.Result -eq 'OK') {
    Write-Host "Done - Claude is signed in as $($chosen.Email) (verified)." -ForegroundColor Green
    Start-Sleep -Seconds 2; return
}
if ($check.Result -eq 'UNSURE') {
    Write-Host "Claude was switched to $($chosen.Email), but this could not be confirmed automatically." -ForegroundColor Yellow
    Write-Host "Look at the app: if it shows $($chosen.Email), all is well. If it shows a sign-in screen," -ForegroundColor Yellow
    Write-Host "sign in to that account and run 'claude-add-account' to save it again." -ForegroundColor Yellow
    Start-Sleep -Seconds 4; return
}

if ($check.Result -eq 'OTHER') {
    Write-Host "Claude reopened as $($check.Email), not $($chosen.Email)." -ForegroundColor Red
    Set-CurrentMarker $check.Email
} else {
    Write-Host "Claude did not accept the saved sign-in for $($chosen.Email) (it expired or was signed out elsewhere)." -ForegroundColor Red
    Remove-Item $DtCurrent -Force -ErrorAction SilentlyContinue
}
Write-Host "To fix that account: sign in to it in the Claude app, then run 'claude-add-account'." -ForegroundColor Yellow

# Offer to put things back exactly as they were before this switch.
$backupProfile = Join-Path $backup 'profile'
if ($live.State -eq 'SIGNEDIN' -and (Test-Path $backupProfile)) {
    $prev = if ($currentAcct) { $currentAcct.Email } elseif ($liveEmail) { $liveEmail } else { 'the previous account' }
    $back = Read-Host "Go back to $prev now? [Y/n]"
    if ($back -notmatch '^(n|no)$') {
        Write-Host "Restoring the previous profile..." -ForegroundColor Cyan
        if ((Stop-Claude $root) -and (Copy-ClaudeProfile $backupProfile $root)) {
            if ($currentAcct) { Set-CurrentMarker $currentAcct.Email } else { Remove-Item $DtCurrent -Force -ErrorAction SilentlyContinue }
            [void](Start-Claude)
            Write-Host "Back on $prev." -ForegroundColor Green
        } else {
            Write-Host "Could not restore automatically. The backup is at $backup" -ForegroundColor Red
        }
    }
}
Start-Sleep -Seconds 3

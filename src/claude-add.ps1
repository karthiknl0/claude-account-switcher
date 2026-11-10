# Snapshot the Claude desktop account that is CURRENTLY logged in, so it can be
# switched to later. Claude's desktop authentication spans its whole Electron
# profile, not just cookies. Snapshotting only selected folders creates a mixed
# profile after a restore and can trigger server-side reauthentication. Save and
# restore the complete closed profile instead (minus caches and the bundled
# Claude Code CLI, which are not account state - see desktop-common.ps1).
#
# Run from a NORMAL PowerShell window. THIS CLOSES THE CLAUDE APP.

. (Join-Path $PSScriptRoot 'desktop-common.ps1')

Write-Host ""
Write-Host "=== Add Claude account (complete profile snapshot) ===" -ForegroundColor Cyan
Write-Host "1. Log into the account you want to save in the Claude desktop app." -ForegroundColor DarkGray
Write-Host "2. Then run this - it CLOSES Claude to copy its session, then reopens it." -ForegroundColor DarkGray
Write-Host ""

$root = Get-SessionRoot
if (-not $root) {
    Write-Host "Claude app data not found. Open Claude, log in, then retry." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# Identify the account ACTUALLY logged in (from the app's own token cache), so
# a snapshot is never saved under the wrong email or while logged out.
$live = Get-ProfileState $root
if ($live.State -eq 'MISSING') {
    Write-Host "Claude isn't logged into any account right now (no sign-in found in its profile)." -ForegroundColor Red
    Write-Host "Log in first, then run 'claude-add-account' again - saving now would snapshot a logged-out session that fails on restore." -ForegroundColor Red
    Start-Sleep -Seconds 4; return
}
if ($live.State -eq 'EMPTY') {
    Write-Host "Claude doesn't look logged in right now (no sign-in found in its profile)." -ForegroundColor Red
    Write-Host "If the app shows a sign-in screen: log in first, then run 'claude-add-account' again." -ForegroundColor Red
    Write-Host "If the app IS open on your chats, a newer Claude version may keep its sign-in" -ForegroundColor Yellow
    Write-Host "somewhere this tool doesn't know yet - you can still save the account." -ForegroundColor Yellow
    $force = Read-Host "Type SAVE to save it anyway (or Enter to cancel)"
    if ($force -cne 'SAVE') { Write-Host "Cancelled." -ForegroundColor Yellow; Start-Sleep -Seconds 2; return }
}
Set-RootCache $root
$detected = $null
if ($live.Token) { $detected = Get-TokenEmail $live.Token }

$email = $null
if ($detected) {
    $ans = Read-Host "Detected logged-in account: $detected - save this one? [Y/n]"
    if ($ans -notmatch '^(n|no)$') { $email = $detected }
} else {
    Write-Host "Could not verify which account is logged in (token expired or network unreachable)." -ForegroundColor Yellow
    Write-Host "If the app shows a sign-in screen, log in first - saving now would snapshot a logged-out session." -ForegroundColor Yellow
}
if (-not $email) {
    $email = Read-Host "Email of the account currently logged into Claude"
    if ([string]::IsNullOrWhiteSpace($email)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    $email = $email.Trim()
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

$dest        = Join-Path $DtStore (Get-SafeName $email)
$profileDest = Join-Path $dest 'profile'

Write-Host "Saving complete profile for $email ..." -ForegroundColor Cyan
if (-not (Copy-ClaudeProfile $root $profileDest $true)) {
    Write-Host "Could not save the complete Claude profile. No account was changed." -ForegroundColor Red
    [void](Start-Claude)
    Start-Sleep -Seconds 3; return
}

[ordered]@{ email = $email; savedAt = (Get-Date -Format o); sourceRoot = $root; profileFormat = 3 } |
    ConvertTo-Json | Set-Content -Path (Join-Path $dest 'meta.json') -Encoding UTF8

# Mark this account as the one the live session belongs to, so claude-switch
# can sync the live session back into this snapshot before loading another.
Set-CurrentMarker $email

Write-Host ""
Write-Host "Saved account: $email" -ForegroundColor Green
Write-Host ""

# Offer to set up the NEXT account. We clear the LOCAL profile instead of using
# the app's "Log out" - logging out revokes the session server-side, which
# would kill the snapshot we just saved. Clearing locally leaves the saved
# account valid to switch to.
$more = Read-Host "Add ANOTHER account now? (clears local login WITHOUT logging out, shows sign-in) [y/N]"
if ($more -match '^(y|yes)$') {
    Write-Host "Clearing local profile (not logging out $email)..." -ForegroundColor Cyan
    # The live session is about to belong to a different (not yet saved)
    # account - drop the marker so claude-switch doesn't sync the new login
    # back into this account's snapshot.
    Remove-Item $DtCurrent -Force -ErrorAction SilentlyContinue
    Clear-ClaudeProfile $root
    [void](Start-Claude)
    Write-Host ""
    Write-Host "Claude is reopening at a SIGN-IN screen." -ForegroundColor Green
    Write-Host "Log in as the NEXT account, then run 'claude-add-account' again." -ForegroundColor Green
} else {
    Write-Host "Reopening Claude..." -ForegroundColor DarkGray
    [void](Start-Claude)
}
Start-Sleep -Seconds 2

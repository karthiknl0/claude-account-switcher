# Add a Claude Code (CLI) account to the switcher.
#
# v4: every account gets its OWN Claude Code config folder and signs in there
# once. It then stays signed in (Claude Code keeps that login fresh by itself),
# so switching never copies tokens around and can't log an account out.
# See cc-common.ps1 for the full explanation.
#
#   - Your existing login (in the normal ~/.claude folder) is kept as the first
#     account - nothing to redo for it.
#   - Each further account gets ~/.claude-cc-accounts/<email>/ which SHARES your
#     transcripts, settings, plugins and skills with the main folder.
#
# Cross-platform (Windows / Linux / macOS) - on Unix run with PowerShell (pwsh).

. (Join-Path $PSScriptRoot 'cc-common.ps1')

Write-Host ""
Write-Host "=== Add Claude Code account ===" -ForegroundColor Cyan

if (-not (Get-ClaudeExe)) {
    Write-Host "The 'claude' command was not found on PATH. Install Claude Code first, then re-run this." -ForegroundColor Red
    Start-Sleep -Seconds 3; return
}

# -- Registry (first run of v4 creates it) -------------------------------------
$reg = Read-Registry
$firstRun = $false
if (-not $reg) {
    $firstRun = $true
    $reg = [pscustomobject]@{ mainDir = (Get-DefaultConfigDir); accounts = @() }
}
$mainAcct = [pscustomobject]@{ email = $null; dir = $reg.mainDir; isDefault = $true }

$legacy = @(Get-LegacyEmails)
if ($firstRun -and $legacy.Count -gt 0) {
    Write-Host ""
    Write-Host "This version stores accounts differently (one sign-in folder per account," -ForegroundColor Yellow
    Write-Host "instead of swapping saved tokens, which Claude Code now invalidates)." -ForegroundColor Yellow
    Write-Host "Accounts saved by the old version need ONE more sign-in each:" -ForegroundColor Yellow
    foreach ($e in $legacy) { Write-Host "      - $e" -ForegroundColor Gray }
}

# -- Keep the login that is already in the main folder as an account -----------
$defaultAcct = @($reg.accounts) | Where-Object { $_.isDefault } | Select-Object -First 1
$mainLogin   = Get-AccountLogin $mainAcct
if (-not $defaultAcct -and $mainLogin.HasLogin) {
    Write-Host ""
    Write-Host "Checking the account you're signed in to now..." -ForegroundColor DarkGray
    $st    = Get-AuthStatus $mainAcct
    $email = Get-AccountEmail $mainAcct $st
    if (-not $email) {
        $email = Read-Host "Email of the account Claude Code is signed in to right now"
    }
    if (-not [string]::IsNullOrWhiteSpace($email)) {
        $email = $email.Trim()
        # The same email may already be saved in its own folder - the main
        # folder's copy then simply becomes that account's home.
        $reg.accounts = @(@($reg.accounts) | Where-Object { $_.email -ne $email })
        $defaultAcct  = [pscustomobject]@{ email = $email; dir = $reg.mainDir; isDefault = $true }
        $reg.accounts = @($defaultAcct) + @($reg.accounts)
        Save-Registry $reg
        if (-not (Test-Path $CcActive)) { Set-ActiveAccount $defaultAcct }
        Write-Host "Saved your current login: $email  (main Claude Code folder - no sign-in needed)" -ForegroundColor Green
        if ($st -and $st.loggedIn -eq $false) {
            Write-Host "Note: Claude Code reports this login as expired - run 'claude' and /login once to renew it." -ForegroundColor Yellow
        }
    }
    $more = Read-Host "Add ANOTHER account now? [y/N]"
    if ($more -notmatch '^(y|yes)$') { Start-Sleep -Seconds 1; return }
}

# -- Add accounts (loop) -------------------------------------------------------
while ($true) {
    Write-Host ""
    $email = Read-Host "Email of the account to add (Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($email)) { Write-Host "Done." -ForegroundColor Yellow; break }
    $email = $email.Trim()

    $existing = @($reg.accounts) | Where-Object { $_.email -eq $email } | Select-Object -First 1
    if ($existing) {
        $acct = $existing
        Write-Host "$email is already saved - signing in again will renew its login." -ForegroundColor DarkGray
    } elseif (-not $defaultAcct -and -not $mainLogin.HasLogin) {
        # Nobody is signed in to the main folder yet: the first account lives there.
        $acct = [pscustomobject]@{ email = $email; dir = $reg.mainDir; isDefault = $true }
    } else {
        $dir = Join-Path $CcStore (Get-SafeName $email)
        Initialize-AccountDir $dir $reg.mainDir
        $acct = [pscustomobject]@{ email = $email; dir = $dir; isDefault = $false }
    }

    Write-Host ""
    Write-Host "A sign-in page will open in your browser." -ForegroundColor Cyan
    Write-Host "IMPORTANT: approve it as $email." -ForegroundColor Yellow
    Write-Host "If the browser is signed in to claude.ai as a different account, sign out there" -ForegroundColor Yellow
    Write-Host "first (or copy the link into a private/incognito window)." -ForegroundColor Yellow
    Write-Host ""
    Invoke-ClaudeFor $acct @('auth', 'login', '--email', $email)

    $st = Get-AuthStatus $acct
    $login = Get-AccountLogin $acct
    $signedIn = ($st -and $st.loggedIn) -or (-not $st -and $login.HasLogin)
    if (-not $signedIn) {
        Write-Host ""
        Write-Host "Sign-in was not completed, so $email was not saved. Run 'claude-code-add' to try again." -ForegroundColor Red
        Start-Sleep -Seconds 3; break
    }

    $actual = Get-AccountEmail $acct $st
    if ($actual -and $actual -ne $email) {
        $clash = @($reg.accounts) | Where-Object { $_.email -eq $actual -and $_.dir -ne $acct.dir } | Select-Object -First 1
        if ($clash) {
            Write-Host ""
            Write-Host "The browser signed in as $actual, which is already saved - not as $email." -ForegroundColor Red
            Write-Host "Nothing was saved. Sign out of claude.ai in the browser (or use a private window)," -ForegroundColor Red
            Write-Host "then run 'claude-code-add' again." -ForegroundColor Red
            Start-Sleep -Seconds 4; break
        }
        Write-Host "Note: the sign-in was for $actual (not $email) - saving it under $actual." -ForegroundColor Yellow
        $acct.email = $actual
    }

    $reg.accounts = @(@($reg.accounts) | Where-Object { $_.dir -ne $acct.dir -and $_.email -ne $acct.email }) + @($acct)
    Save-Registry $reg
    if ($acct.isDefault) { $defaultAcct = $acct; $mainLogin = Get-AccountLogin $mainAcct }
    if (-not (Test-Path $CcActive)) { Set-ActiveAccount $acct }

    Write-Host ""
    Write-Host "Saved Claude Code account: $($acct.email)" -ForegroundColor Green
    $more = Read-Host "Add ANOTHER account now? [y/N]"
    if ($more -notmatch '^(y|yes)$') { break }
}

$count = @($reg.accounts).Count
if ($count -gt 0) {
    Write-Host ""
    Write-Host "$count account(s) saved. Use 'claude-code-switch' to choose which one 'claude' runs as." -ForegroundColor Cyan
}
Start-Sleep -Seconds 1

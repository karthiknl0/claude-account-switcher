# Automated test for the DESKTOP switcher's building blocks (Windows only).
# It cannot drive the real Claude app, so it builds a look-alike profile -
# same folder layout, same encryption (Windows DPAPI key + AES-256-GCM token
# cache) - and checks that the switcher finds it, reads it, snapshots it and
# restores it correctly.
#
#   pwsh       tests/desktop.tests.ps1 -Fixture <dir> -Build   (creates the look-alike, then tests)
#   powershell tests/desktop.tests.ps1 -Fixture <dir>          (re-tests it under Windows PowerShell 5.1)
param([Parameter(Mandatory = $true)][string]$Fixture, [switch]$Build)

$ErrorActionPreference = 'Stop'
$repo  = Split-Path $PSScriptRoot -Parent
$fails = 0
$utf8  = New-Object System.Text.UTF8Encoding($false)

function Check($name, $cond) {
    if ($cond) { Write-Host "  ok    $name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:fails++ }
}
function Put($path, $text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [System.IO.File]::WriteAllText($path, $text, $utf8)
}

$pristine = Join-Path $Fixture 'pristine'
$work     = Join-Path $Fixture ('work-' + $PSVersionTable.PSVersion.Major)

# -- Build the look-alike (needs PowerShell 7 for AES-GCM encryption) ----------
if ($Build) {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    if (Test-Path $Fixture) { Remove-Item -Recurse -Force $Fixture }
    $key = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($key)
    $prot = [System.Security.Cryptography.ProtectedData]::Protect($key, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $localState = '{"os_crypt":{"encrypted_key":"' + [Convert]::ToBase64String([byte[]]([System.Text.Encoding]::ASCII.GetBytes('DPAPI') + $prot)) + '"}}'

    function New-Blob($json) {
        $plain  = [System.Text.Encoding]::UTF8.GetBytes($json)
        $nonce  = New-Object byte[] 12
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($nonce)
        $cipher = New-Object byte[] $plain.Length
        $tag    = New-Object byte[] 16
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        $aes.Encrypt($nonce, $plain, $cipher, $tag)
        $aes.Dispose()
        return [Convert]::ToBase64String([byte[]]([System.Text.Encoding]::ASCII.GetBytes('v10') + $nonce + $cipher + $tag))
    }
    $liveBlob = New-Blob '{"grant-1":{"token":"tok-live","refreshToken":"r"}}'
    $v1Blob   = New-Blob '{"grant-0":{"token":"tok-v1"}}'

    # The folder the app uses today.
    $live = Join-Path $pristine 'local\Claude-Data\claude_testpkg'
    Put (Join-Path $live 'config.json') ('{"locale":"en","oauth:tokenCacheV2":"' + $liveBlob + '"}')
    Put (Join-Path $live 'Local State') $localState
    Put (Join-Path $live 'Network\Cookies') 'cookie-db'
    Put (Join-Path $live 'Local Storage\leveldb\000003.log') 'ls'
    Put (Join-Path $live 'Cache\data_0') 'cache'
    Put (Join-Path $live 'claude-code\9.9.9\claude.exe') 'bundled-cli'
    Put (Join-Path $live 'SingletonLock') 'x'
    # The two folders it used to use, now abandoned (one still has old data).
    Put (Join-Path $pristine 'roaming\Claude\config.json') '{"locale":"en"}'
    Put (Join-Path $pristine 'roaming\Claude\.user-data-left.claude_testpkg') ''
    Put (Join-Path $pristine 'local\Packages\Claude_testpkg\LocalCache\Roaming\Claude\.user-data-left.claude_testpkg') ''
    # Profiles in other sign-in states.
    $st = Join-Path $pristine 'states'
    Put (Join-Path $st 'v1only\config.json')  ('{"oauth:tokenCache":"' + $v1Blob + '"}');           Put (Join-Path $st 'v1only\Local State') $localState
    Put (Join-Path $st 'renamed\config.json') '{"oauth:sessionStoreV9":"something-new"}';           Put (Join-Path $st 'renamed\Local State') $localState
    Put (Join-Path $st 'signedout\config.json') '{"locale":"en"}';                                  Put (Join-Path $st 'signedout\Local State') $localState
    Put (Join-Path $st 'garbled\config.json') '{"oauth:tokenCacheV2":"dGhpcyBpcyBub3QgYSByZWFsIGJsb2IgYXQgYWxs"}'; Put (Join-Path $st 'garbled\Local State') $localState
    Put (Join-Path $st 'noconfig\Local State') $localState
    Put (Join-Path $pristine 'user\keep.txt') ''
}

if (-not (Test-Path $pristine)) { Write-Host "Fixture not built: run with -Build under pwsh first." -ForegroundColor Red; exit 1 }
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
robocopy $pristine $work /E /NFL /NDL /NJH /NJS | Out-Null

# Point the switcher at the look-alike instead of the real machine.
$env:LOCALAPPDATA = Join-Path $work 'local'
$env:APPDATA      = Join-Path $work 'roaming'
$env:USERPROFILE  = Join-Path $work 'user'
$ErrorActionPreference = 'Continue'   # same as a normal PowerShell window
. (Join-Path $repo 'src\desktop-common.ps1')

$live    = Join-Path $work 'local\Claude-Data\claude_testpkg'
$roaming = Join-Path $work 'roaming\Claude'
$st      = Join-Path $work 'states'

Write-Host ("Desktop switcher tests (PowerShell {0})" -f $PSVersionTable.PSVersion) -ForegroundColor Cyan

# 1. Finding the profile the app really uses.
Check 'finds the moved Claude-Data profile'            ((Get-SessionRoot) -eq $live)
Check 'old roaming folder is recognised as abandoned'  (Test-RootAbandoned $roaming)
Check 'running-app lookup does not crash'              ($null -eq (Get-RunningDataRoot) -or $true)
Rename-Item $live 'brandnew_layout'
$renamed = Join-Path $work 'local\Claude-Data\brandnew_layout'
Check 'still found if the folder name changes'         ((Get-SessionRoot) -eq $renamed)
Rename-Item $renamed 'claude_testpkg'
$elsewhere = Join-Path $work 'local\TotallyNewPlace\profile'
robocopy $live $elsewhere /E /NFL /NDL /NJH /NJS | Out-Null
(Get-Item (Join-Path $elsewhere 'config.json')).LastWriteTime = (Get-Date).AddMinutes(5)
Check 'unknown location is not guessed'                ((Get-SessionRoot) -eq $live)
Set-RootCache $elsewhere
Check 'unknown location is used once the app reported it' ((Get-SessionRoot) -eq $elsewhere)
Remove-Item (Join-Path $DtStore '.root') -Force
Remove-Item -Recurse -Force (Join-Path $work 'local\TotallyNewPlace')

# 2. Reading the sign-in state.
$s = Get-ProfileState $live
Check 'reads the V2 sign-in (DPAPI + AES-GCM)'         ($s.State -eq 'SIGNEDIN' -and $s.Token -eq 'tok-live')
$s = Get-ProfileState (Join-Path $st 'v1only')
Check 'reads the older V1 sign-in'                     ($s.State -eq 'SIGNEDIN' -and $s.Token -eq 'tok-v1')
Check 'renamed sign-in key -> "cannot tell", not "signed out"' ((Get-ProfileState (Join-Path $st 'renamed')).State -eq 'UNKNOWN')
Check 'unreadable sign-in -> "cannot tell"'            ((Get-ProfileState (Join-Path $st 'garbled')).State -eq 'UNKNOWN')
Check 'signed-out profile is detected'                 ((Get-ProfileState (Join-Path $st 'signedout')).State -eq 'EMPTY')
Check 'missing config is detected'                     ((Get-ProfileState (Join-Path $st 'noconfig')).State -eq 'MISSING')

# 3. Saving a snapshot.
$acct = Join-Path $DtStore 'a@x.com'
$snap = Join-Path $acct 'profile'
# (an old-style copy that still contains a cache folder is already there)
Put (Join-Path $snap 'Cache\old-junk.bin') 'junk-from-version-3'
Put (Join-Path $snap 'claude-code\1.0.0\claude.exe') 'old-bundled-cli'
Check 'snapshot copy succeeds'                         (Copy-ClaudeProfile $live $snap $true)
Check 'old cache/CLI junk in the saved copy is removed' (-not (Test-Path (Join-Path $snap 'Cache')) -and -not (Test-Path (Join-Path $snap 'claude-code')))
Put (Join-Path $acct 'meta.json') '{"email":"a@x.com"}'
Check 'snapshot has the sign-in and storage'           ((Test-Path (Join-Path $snap 'config.json')) -and (Test-Path (Join-Path $snap 'Local Storage\leveldb\000003.log')) -and (Test-Path (Join-Path $snap 'Network\Cookies')))
Check 'snapshot leaves out cache and bundled CLI'      (-not (Test-Path (Join-Path $snap 'Cache')) -and -not (Test-Path (Join-Path $snap 'claude-code')))
Check 'snapshot has no lock file'                      (-not (Test-Path (Join-Path $snap 'SingletonLock')))
$saved = @(Get-SavedAccounts)
Check 'saved account is listed as signed in'           ($saved.Count -eq 1 -and $saved[0].Email -eq 'a@x.com' -and $saved[0].State -eq 'SIGNEDIN')

# 4. Restoring it over a different live session.
Put (Join-Path $live 'config.json') '{"locale":"en"}'
Put (Join-Path $live 'Local Storage\leveldb\other-account.log') 'other'
Check 'live profile now looks signed out'              ((Get-ProfileState $live).State -eq 'EMPTY')
Check 'restore copy succeeds'                          (Copy-ClaudeProfile $snap $live)
Check 'restore brings the sign-in back'                ((Get-ProfileState $live).Token -eq 'tok-live')
Check 'restore removes the other account''s leftovers' (-not (Test-Path (Join-Path $live 'Local Storage\leveldb\other-account.log')))
Check 'restore keeps the bundled CLI in place'         (Test-Path (Join-Path $live 'claude-code\9.9.9\claude.exe'))

# 5. Markers and clearing for a fresh sign-in.
Set-CurrentMarker 'a@x.com'
Check 'current-account marker round-trips'             ((Get-CurrentMarker) -eq 'a@x.com')
Clear-ClaudeProfile $live
Check 'clear removes the sign-in'                      (-not (Test-Path (Join-Path $live 'config.json')))
Check 'clear keeps the bundled CLI'                    (Test-Path (Join-Path $live 'claude-code\9.9.9\claude.exe'))
Check 'saved snapshot survives the clear'              ((Get-ProfileState $snap).State -eq 'SIGNEDIN')

# 6. Storage: one saved copy per account, one backup, nothing accumulates.
$filesBefore = @(Get-ChildItem $snap -Recurse -Force -File).Count
[void](Copy-ClaudeProfile $snap $live)
Put (Join-Path $live 'Local Storage\leveldb\000004.log') 'newer-data'
[void](Copy-ClaudeProfile $live $snap $true)
[void](Copy-ClaudeProfile $live $snap $true)
Check 'saving again overwrites the same copy (data updated)' ((Test-Path (Join-Path $snap 'Local Storage\leveldb\000004.log')) -and @(Get-ChildItem $snap -Recurse -Force -File).Count -eq ($filesBefore + 1))
Check 'the sign-in survives the overwrite'             ((Get-ProfileState $snap).Token -eq 'tok-live')
Check 'only one folder exists for the account'         (@(Get-ChildItem $acct -Force).Count -eq 2)
[void](Copy-ClaudeProfile $live (Join-Path $DtBackup 'profile') $true)
Put (Join-Path $DtStore '.backup-20260101-000000\profile\big.bin') ('x' * 2000)
Put (Join-Path $DtStore '.backup-20260202-000000\profile\big.bin') ('x' * 2000)
Put (Join-Path $DtStore 'not-an-account\stuff.bin') 'x'
Put (Join-Path $acct 'Cookies-old-format\c') 'x'
Check 'leftovers from older versions are detected'     (@(Get-StoreLeftovers).Count -eq 4)
Remove-OldBackups
Check 'old timestamped backups are removed on switch'  (@(Get-ChildItem $DtStore -Directory -Force -Filter '.backup-*').Count -eq 0 -and (Test-Path (Join-Path $DtBackup 'profile')))
$sh = (Get-Process -Id $PID).Path
$env:HOMEDRIVE = $env:USERPROFILE.Substring(0, 2); $env:HOMEPATH = $env:USERPROFILE.Substring(2); $env:HOME = $env:USERPROFILE
$out = ('y' | & $sh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'src\claude-cleanup.ps1') 2>&1 | ForEach-Object { "$_" }) -join "`n"
Check 'cleanup removes the remaining leftovers'        (@(Get-StoreLeftovers).Count -eq 0)
Check 'cleanup keeps the saved copy and its sign-in'   ((Get-ProfileState $snap).Token -eq 'tok-live')
Check 'cleanup keeps the single backup'                (Test-Path (Join-Path $DtBackup 'profile'))
if ($fails) { Write-Host $out }

Write-Host ""
if ($fails) { Write-Host "$fails check(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "All desktop checks passed." -ForegroundColor Green
exit 0

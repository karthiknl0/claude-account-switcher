# Automated test for the Claude Code (CLI) switcher. Runs the real scripts
# against tests/fake-claude.ps1 inside a throw-away home folder.
#
#   pwsh tests/cli.tests.ps1                      (scripts run under pwsh)
#   pwsh tests/cli.tests.ps1 -Shell powershell    (scripts run under Windows PowerShell 5.1)
param([string]$Shell = 'pwsh')

$ErrorActionPreference = 'Stop'
$onWindows = $true
if (Test-Path variable:IsWindows) { $onWindows = $IsWindows }
$repo  = Split-Path $PSScriptRoot -Parent
$src   = Join-Path $repo 'src'
$fails = 0

function Check($name, $cond) {
    if ($cond) { Write-Host "  ok    $name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:fails++ }
}

# -- Throw-away home + a fake `claude` on PATH ---------------------------------
$tmp  = Join-Path ([System.IO.Path]::GetTempPath()) ('cas-cli-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$home2 = Join-Path $tmp 'home'
$bin   = Join-Path $tmp 'bin'
New-Item -ItemType Directory -Force -Path $home2, $bin | Out-Null
$fake = Join-Path $PSScriptRoot 'fake-claude.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if ($onWindows) {
    [System.IO.File]::WriteAllText((Join-Path $bin 'claude.cmd'), "@pwsh -NoProfile -File `"$fake`" %*`r`n", $utf8)
    $env:USERPROFILE = $home2
    $env:HOMEDRIVE   = $home2.Substring(0, 2)
    $env:HOMEPATH    = $home2.Substring(2)
    $env:PATH = $bin + ';' + $env:PATH
} else {
    $shim = Join-Path $bin 'claude'
    [System.IO.File]::WriteAllText($shim, "#!/bin/sh`nexec pwsh -NoProfile -File `"$fake`" `"`$@`"`n", $utf8)
    & chmod +x $shim
    $env:PATH = $bin + ':' + $env:PATH
}
$env:HOME = $home2
Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

function Run-Script($file, $inputLines, $scriptArgs) {
    $a = @('-NoProfile')
    if ($Shell -eq 'powershell') { $a += @('-ExecutionPolicy', 'Bypass') }
    $a += @('-File', (Join-Path $src $file))
    if ($scriptArgs) { $a += $scriptArgs }
    $out = $inputLines | & $Shell @a 2>&1
    return (($out | ForEach-Object { "$_" }) -join "`n")
}

$main  = Join-Path $home2 '.claude'
$store = Join-Path $home2 '.claude-cc-accounts'
$reg   = Join-Path $store 'accounts.json'
$act   = Join-Path $store '.active'

# An existing, ordinary Claude Code login (account A) in the normal folder.
New-Item -ItemType Directory -Force -Path (Join-Path $main 'projects') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $main 'settings.json'), '{"theme":"dark"}', $utf8)
[System.IO.File]::WriteAllText((Join-Path $main '.credentials.json'), '{"claudeAiOauth":{"accessToken":"at-a","refreshToken":"rt-a","expiresAt":9999999999999}}', $utf8)
[System.IO.File]::WriteAllText((Join-Path $home2 '.claude.json'), '{"theme":"dark","oauthAccount":{"emailAddress":"a@x.com"},"projects":{"/p":{"x":"}{"}}}', $utf8)
$mainCredsBefore = Get-Content (Join-Path $main '.credentials.json') -Raw

Write-Host "CLI switcher tests (scripts under: $Shell)" -ForegroundColor Cyan

# 1. Add: keeps the current login, signs a second account in to its own folder.
$out = Run-Script 'claude-code-add.ps1' @('y', 'b@x.com', 'n')
$r = $null
if (Test-Path $reg) { $r = Get-Content $reg -Raw | ConvertFrom-Json }
Check 'add: registry written with two accounts' ($r -and @($r.accounts).Count -eq 2)
$bDir = Join-Path $store 'b@x.com'
Check 'add: account A stays in the main folder'   ($r -and $r.accounts[0].email -eq 'a@x.com' -and $r.accounts[0].isDefault)
Check 'add: account B has its own login'          (Test-Path (Join-Path $bDir '.credentials.json'))
Check 'add: account B shares transcripts'         (Test-Path (Join-Path $bDir 'projects'))
Check 'add: main login was not touched'           ((Get-Content (Join-Path $main '.credentials.json') -Raw) -eq $mainCredsBefore)
if ($fails) { Write-Host $out }

# 2. Switch by number, by email, and from the menu.
$out = Run-Script 'claude-code-switch.ps1' @() @('2')
Check 'switch 2: marker points at B folder' ((Test-Path $act) -and ((Get-Content $act -Raw).Trim() -eq $bDir))
$out = Run-Script 'claude-code-switch.ps1' @() @('a@x.com')
Check 'switch by email: marker is default'  ((Get-Content $act -Raw).Trim() -eq 'default')
$out = Run-Script 'claude-code-switch.ps1' @('2')
Check 'switch from menu: marker points at B' ((Get-Content $act -Raw).Trim() -eq $bDir)
Check 'switch: no login file was modified'   ((Get-Content (Join-Path $main '.credentials.json') -Raw) -eq $mainCredsBefore)

# 3. The `claude` wrapper from the installer starts claude in the chosen folder.
$inst = Get-Content (Join-Path $repo 'install.ps1') -Raw
$m = [regex]::Match($inst, '(?s)\nfunction claude \{.*?\n\}')
Check 'wrapper: found in install.ps1' $m.Success
$wrapFile = Join-Path $tmp 'wrap.ps1'
[System.IO.File]::WriteAllText($wrapFile, $m.Value + "`nclaude --resume`n'[' + `$env:CLAUDE_CONFIG_DIR + ']'`n", $utf8)
$a = @('-NoProfile'); if ($Shell -eq 'powershell') { $a += @('-ExecutionPolicy', 'Bypass') }
$out = (& $Shell @a -File $wrapFile 2>&1 | ForEach-Object { "$_" }) -join "`n"
Check 'wrapper: runs claude as account B'            ($out -like "*RUN dir=$bDir args=--resume*")
Check 'wrapper: leaves the environment clean after'  ($out -like '*`[`]*')
[System.IO.File]::WriteAllText($act, 'default', $utf8)
$out = (& $Shell @a -File $wrapFile 2>&1 | ForEach-Object { "$_" }) -join "`n"
Check 'wrapper: default account uses the main folder' ($out -like "*RUN dir=$main args=--resume*")

# 4. Future-proofing: `claude auth login` gone -> falls back to signing in inside Claude Code.
$env:FAKE_NO_AUTH_LOGIN = '1'; $env:FAKE_INTERACTIVE_LOGIN_AS = 'c@x.com'
$out = Run-Script 'claude-code-add.ps1' @('c@x.com', '', 'n')
Remove-Item Env:FAKE_NO_AUTH_LOGIN, Env:FAKE_INTERACTIVE_LOGIN_AS
$r = Get-Content $reg -Raw | ConvertFrom-Json
Check 'fallback sign-in: account C saved' (@($r.accounts | Where-Object { $_.email -eq 'c@x.com' }).Count -eq 1)
if (-not (@($r.accounts | Where-Object { $_.email -eq 'c@x.com' }).Count -eq 1)) { Write-Host $out }

# 5. Future-proofing: extra lines around `auth status` JSON are tolerated.
$env:FAKE_STATUS_NOISE = '1'
$out = Run-Script 'claude-code-doctor.ps1' @()
Remove-Item Env:FAKE_STATUS_NOISE
Check 'doctor: all three accounts reported signed in' (([regex]::Matches($out, ' - signed in')).Count -eq 3)
if (([regex]::Matches($out, ' - signed in')).Count -ne 3) { Write-Host $out }

# 6. A signed-out account is reported, not silently used.
Remove-Item (Join-Path $bDir '.credentials.json') -Force
$out = Run-Script 'claude-code-switch.ps1' @() @('b@x.com')
Check 'switch to signed-out account: warns' ($out -like '*not signed in*')

try { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue } catch {}
Write-Host ""
if ($fails) { Write-Host "$fails check(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "All CLI checks passed." -ForegroundColor Green
exit 0

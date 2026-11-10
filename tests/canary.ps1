# Early-warning check, run weekly by GitHub Actions against the NEWEST Claude
# Code release. It verifies the few things the CLI switcher depends on. If
# Anthropic changes one of them, this fails and GitHub sends an email - before
# (or soon after) the switcher breaks on a real machine.

$fails = 0
function Check($name, $cond, $hint) {
    if ($cond) { Write-Host "  ok    $name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $name" -ForegroundColor Red; Write-Host "        $hint" -ForegroundColor Yellow; $script:fails++ }
}

$exe = @(Get-Command claude -CommandType ExternalScript, Application -ErrorAction SilentlyContinue)
if ($exe.Count -eq 0) { Write-Host "claude is not installed on this runner." -ForegroundColor Red; exit 1 }
$ver = (& claude --version 2>$null | Select-Object -First 1)
Write-Host "Claude Code version: $ver" -ForegroundColor Cyan

# A brand-new, empty config folder: nobody is signed in there.
$dir = Join-Path ([System.IO.Path]::GetTempPath()) ('cas-canary-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$env:CLAUDE_CONFIG_DIR = $dir
Remove-Item Env:ANTHROPIC_API_KEY, Env:CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue

$out  = (& claude auth status 2>$null) -join "`n"
$json = $null
$a = $out.IndexOf('{'); $b = $out.LastIndexOf('}')
if ($a -ge 0 -and $b -gt $a) { try { $json = $out.Substring($a, $b - $a + 1) | ConvertFrom-Json } catch {} }
Check "'claude auth status' prints JSON"                 ($null -ne $json) "The switcher falls back to reading the login file, but 'claude-code-doctor' loses detail. Output was: $out"
Check "that JSON has a 'loggedIn' field"                 ($json -and $null -ne $json.loggedIn) "Update Get-AuthStatus in src/cc-common.ps1 for the new field name."
Check "an empty CLAUDE_CONFIG_DIR folder is 'not signed in'" ($json -and $json.loggedIn -eq $false) "CLAUDE_CONFIG_DIR may no longer isolate logins - the per-account-folder design needs a review."

$help = (& claude auth login --help 2>&1 | ForEach-Object { "$_" }) -join "`n"
Check "'claude auth login' still exists"                 ($help -match '(?i)login|sign') "claude-code-add will use its fallback (sign in inside Claude Code). Output was: $help"
Check "'claude auth login' still accepts --email"        ($help -match '--email') "Remove '--email' from the call in src/claude-code-add.ps1."

Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
Write-Host ""
if ($fails) { Write-Host "$fails assumption(s) no longer hold for $ver - the switcher needs an update." -ForegroundColor Red; exit 1 }
Write-Host "Claude Code $ver still behaves the way the switcher expects." -ForegroundColor Green
exit 0

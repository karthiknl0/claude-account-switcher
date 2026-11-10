# Stand-in for the real `claude` program, used only by the automated tests.
# It imitates the few things the switcher relies on: per-folder logins
# (CLAUDE_CONFIG_DIR), `auth login --email`, `auth status` and `--version`.
#
# Test knobs (environment variables):
#   FAKE_NO_AUTH_LOGIN=1          `auth login` fails, as if the command was removed
#   FAKE_INTERACTIVE_LOGIN_AS=x   starting `claude` with no arguments signs in as x
#   FAKE_STATUS_NOISE=1           `auth status` prints extra lines around the JSON

$dir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$cfg = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $dir '.claude.json' } else { Join-Path $HOME '.claude.json' }
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Set-Login($email) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $creds = '{"claudeAiOauth":{"accessToken":"at-' + $email + '","refreshToken":"rt-' + $email + '","expiresAt":9999999999999}}'
    [System.IO.File]::WriteAllText((Join-Path $dir '.credentials.json'), $creds, $utf8)
    $o = $null
    if (Test-Path $cfg) { try { $o = Get-Content $cfg -Raw | ConvertFrom-Json } catch {} }
    if (-not $o) { $o = [pscustomobject]@{} }
    $o | Add-Member -NotePropertyName oauthAccount -NotePropertyValue ([pscustomobject]@{ emailAddress = $email }) -Force
    [System.IO.File]::WriteAllText($cfg, ($o | ConvertTo-Json -Depth 20), $utf8)
}

if ($args.Count -eq 0) {
    if ($env:FAKE_INTERACTIVE_LOGIN_AS) { Set-Login $env:FAKE_INTERACTIVE_LOGIN_AS; Write-Output "interactive login as $($env:FAKE_INTERACTIVE_LOGIN_AS)" }
    else { Write-Output "RUN dir=$dir args=" }
    exit 0
}

if ($args[0] -eq '--version') { Write-Output '9.9.9 (Claude Code)'; exit 0 }

if ($args[0] -eq 'auth' -and $args.Count -ge 2 -and $args[1] -eq 'login') {
    if ($env:FAKE_NO_AUTH_LOGIN) { Write-Output "error: unknown command 'login'"; exit 1 }
    $email = 'unknown@example.com'
    for ($i = 2; $i -lt $args.Count - 1; $i++) { if ($args[$i] -eq '--email') { $email = $args[$i + 1] } }
    if ($env:FAKE_LOGIN_AS) { $email = $env:FAKE_LOGIN_AS }
    Set-Login $email
    Write-Output "Login successful ($email)"
    exit 0
}

if ($args[0] -eq 'auth' -and $args.Count -ge 2 -and $args[1] -eq 'status') {
    if ($env:FAKE_STATUS_NOISE) { Write-Output 'notice: a new version is available' }
    if (Test-Path (Join-Path $dir '.credentials.json')) {
        $email = $null
        try { $email = (Get-Content $cfg -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch {}
        Write-Output ('{"loggedIn":true,"authMethod":"claude.ai","email":"' + $email + '"}')
        exit 0
    }
    Write-Output '{"loggedIn":false}'
    exit 1
}

Write-Output ("RUN dir=$dir args=" + ($args -join ' '))
exit 0

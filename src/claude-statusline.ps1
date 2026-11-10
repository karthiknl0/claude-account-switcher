# Claude Code status line: shows which account this session runs as and how
# much of its 5-hour / weekly limit is used - and tells you WHEN TO COMPACT.
#
# Why that matters: when you switch accounts mid-task, the new account has to
# read the whole conversation again at full price. Running /compact on the OLD
# account just before its limit is cheap (its conversation is still cached
# there), and leaves only a short summary for the new account to read.
#
# Claude Code runs this script itself and feeds it session data as JSON on
# standard input (enable with 'claude-code-statusline on'). It only reads; it
# never calls the network and never touches a login.
# Must stay compatible with Windows PowerShell 5.1 - ASCII only.

$ErrorActionPreference = 'SilentlyContinue'
$raw = [Console]::In.ReadToEnd()
$d = $null
try { $d = $raw | ConvertFrom-Json } catch {}
if (-not $d) { exit 0 }

$esc = [char]27
function Paint($text, $code) { return "$esc[${code}m$text$esc[0m" }
function Pct($v) {
    if ($null -eq $v -or "$v" -eq '') { return $null }
    try { return [int][math]::Round([double]$v) } catch { return $null }
}
function PctColor($p) { if ($p -ge 85) { return '31' } elseif ($p -ge 70) { return '33' } else { return '32' } }

$five  = Pct $d.rate_limits.five_hour.used_percentage
$seven = Pct $d.rate_limits.seven_day.used_percentage
$ctx   = Pct $d.context_window.used_percentage
$model = [string]$d.model.display_name

# Which saved account is this session? (the folder Claude Code was started in)
$email = $null
try {
    $regFile = Join-Path (Join-Path $HOME '.claude-cc-accounts') 'accounts.json'
    if (Test-Path $regFile) {
        $reg  = Get-Content $regFile -Raw | ConvertFrom-Json
        $mine = $env:CLAUDE_CONFIG_DIR
        foreach ($a in @($reg.accounts)) {
            if ($mine) {
                if (([string]$a.dir).TrimEnd('\', '/') -eq $mine.TrimEnd('\', '/')) { $email = [string]$a.email }
            } elseif ($a.isDefault) { $email = [string]$a.email }
        }
    }
} catch {}

$parts = @()
if ($email) { $parts += $email }
if ($model) { $parts += $model }
if ($null -ne $ctx) { $parts += "ctx $ctx%" }
if ($null -ne $five) {
    $t = "5h $five%"
    try {
        $at = [DateTimeOffset]::FromUnixTimeSeconds([int64]$d.rate_limits.five_hour.resets_at).LocalDateTime
        if ($at -gt (Get-Date)) { $t += " (resets $($at.ToString('HH:mm')))" }
    } catch {}
    $parts += (Paint $t (PctColor $five))
}
if ($null -ne $seven) { $parts += (Paint "7d $seven%" (PctColor $seven)) }

# The advice goes FIRST so it is never cut off on a narrow window.
$warn = $null
if ($null -ne $five -and $five -ge 95) {
    $warn = "5h limit nearly used: type /compact NOW, then run claude-code-switch"
} elseif ($null -ne $five -and $five -ge 85) {
    $warn = "5h limit close: type /compact soon, then claude-code-switch to carry on cheaply"
} elseif ($null -ne $seven -and $seven -ge 95) {
    $warn = "weekly limit nearly used: type /compact, then claude-code-switch"
}
$line = ($parts -join ' | ')
if ($warn) { $line = (Paint ">> $warn" '1;31') + ' | ' + $line }
Write-Output $line
exit 0

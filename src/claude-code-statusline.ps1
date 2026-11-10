# Turn the usage status line for Claude Code on or off.
#
#   claude-code-statusline on      show account + 5h/7d usage + "compact now" advice
#   claude-code-statusline off     remove it again
#   claude-code-statusline         show whether it is on
#
# It adds (or removes) one "statusLine" entry in Claude Code's settings.json -
# for the main folder and for every saved account's folder. Nothing else in the
# file is changed, a status line you set up yourself is never replaced, and the
# previous file is kept next to it as settings.json.cas-backup.
#
# Cross-platform (Windows / Linux / macOS).

. (Join-Path $PSScriptRoot 'cc-common.ps1')

$mode = 'status'
if ($args.Count -gt 0) { $mode = ([string]$args[0]).ToLower() }
if (@('on', 'off', 'status') -notcontains $mode) {
    Write-Host "Usage: claude-code-statusline on | off" -ForegroundColor Yellow; return
}

Write-Host ""
Write-Host "=== Claude Code usage status line ===" -ForegroundColor Cyan
$files = @(Get-SettingsFiles)
$summary = @{}
foreach ($f in $files) {
    $r = switch ($mode) {
        'on'    { Enable-StatusLine $f }
        'off'   { Disable-StatusLine $f }
        default { Get-StatusLineState $f }
    }
    $summary[$r] = 1 + [int]$summary[$r]
    $color = switch ($r) { 'on' { 'Green' } 'off' { 'Gray' } 'yours' { 'Yellow' } default { 'Red' } }
    $text  = switch ($r) {
        'on'    { 'on' }
        'off'   { 'off' }
        'yours' { 'you already have your own status line here - left untouched' }
        default { 'could not update this file (it is not plain JSON) - left untouched' }
    }
    Write-Host ("  {0}" -f $f) -NoNewline
    Write-Host ("  - {0}" -f $text) -ForegroundColor $color
}
Write-Host ""
if ($mode -eq 'on' -and $summary['on']) {
    Write-Host "Done. It appears at the bottom of Claude Code after your next message in a NEW session:" -ForegroundColor Green
    Write-Host "  you@example.com | Opus | ctx 42% | 5h 61% (resets 21:49) | 7d 30%" -ForegroundColor Gray
    Write-Host "When the 5-hour limit gets close it tells you to type /compact - do that BEFORE" -ForegroundColor Cyan
    Write-Host "switching accounts, so the next account only has to read a short summary." -ForegroundColor Cyan
} elseif ($mode -eq 'off') {
    Write-Host "Removed. New Claude Code sessions no longer show it." -ForegroundColor Green
} elseif ($mode -eq 'status') {
    Write-Host "Run 'claude-code-statusline on' or 'claude-code-statusline off' to change it." -ForegroundColor DarkGray
}
Start-Sleep -Seconds 1

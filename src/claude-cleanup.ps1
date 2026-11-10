# Show how much disk space the switcher uses, and remove leftovers that older
# versions left behind (timestamped backups, old-format account copies, dead
# token files). It never touches a saved account's current copy, the single
# backup, or any login - and it deletes nothing without asking first.
#
# Cross-platform. The desktop-app part is Windows-only.

. (Join-Path $PSScriptRoot 'cc-common.ps1')

Write-Host ""
Write-Host "=== Claude account switcher - storage ===" -ForegroundColor Cyan

$items = @()      # leftovers: @{ Path; SizeMB }

function Get-PathSizeMB($path) {
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    $sum = [int64]0
    Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $sum += $_.Length }
    $self = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($self -and -not $self.PSIsContainer) { $sum += $self.Length }
    return [math]::Round($sum / 1MB, 1)
}

# -- Desktop app (Windows) -----------------------------------------------------
if ($PlatformWin) {
    . (Join-Path $PSScriptRoot 'desktop-common.ps1')
    Write-Host ""
    Write-Host "Desktop app  ($DtStore)" -ForegroundColor Cyan
    $saved = @(Get-SavedAccounts)
    if ($saved.Count -eq 0) { Write-Host "  no saved accounts" -ForegroundColor DarkGray }
    foreach ($s in $saved) {
        Write-Host ("  {0,-34} {1,8} MB   saved copy (overwritten on every switch)" -f $s.Email, (Get-DirSizeMB $s.Profile))
    }
    if (Test-Path $DtBackup) {
        Write-Host ("  {0,-34} {1,8} MB   single backup (overwritten on every switch)" -f 'backup of last live profile', (Get-DirSizeMB $DtBackup))
    }
    foreach ($p in @(Get-StoreLeftovers)) { $items += [pscustomobject]@{ Path = $p; SizeMB = (Get-PathSizeMB $p) } }
}

# -- Claude Code (CLI) ---------------------------------------------------------
Write-Host ""
Write-Host "Claude Code  ($CcStore)" -ForegroundColor Cyan
$reg = Read-Registry
if ($reg) {
    foreach ($a in @($reg.accounts)) {
        $kind = if ($a.isDefault) { 'main Claude Code folder' } else { 'own folder (shares transcripts with the main one)' }
        Write-Host ("  {0,-34} {1}" -f $a.email, $kind)
    }
    # Token files saved by versions 3.x. Claude Code has since replaced those
    # tokens, so they are dead - they are only listed once every account they
    # belong to has been added again.
    $known = @($reg.accounts | ForEach-Object { $_.email })
    $files = @(Get-ChildItem $CcStore -File -Force -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'accounts.json' })
    foreach ($f in $files) {
        $email = $null
        try { $email = (Get-Content $f.FullName -Raw | ConvertFrom-Json).email } catch {}
        if ($email -and ($known -notcontains [string]$email)) { continue }   # not re-added yet: keep the reminder
        $items += [pscustomobject]@{ Path = $f.FullName; SizeMB = (Get-PathSizeMB $f.FullName) }
    }
} else {
    Write-Host "  no saved accounts" -ForegroundColor DarkGray
}

# -- Leftovers -----------------------------------------------------------------
Write-Host ""
if ($items.Count -eq 0) {
    Write-Host "Nothing to clean up - only the current saved copies exist." -ForegroundColor Green
    Write-Host ""
    Start-Sleep -Seconds 1; return
}

$total = 0
Write-Host "Leftovers from older versions (not used any more):" -ForegroundColor Yellow
foreach ($i in $items) {
    Write-Host ("  {0,8} MB   {1}" -f $i.SizeMB, $i.Path)
    $total += $i.SizeMB
}
Write-Host ("  {0,8} MB   total" -f [math]::Round($total, 1)) -ForegroundColor Yellow
Write-Host ""
$go = Read-Host "Delete these leftovers? Your saved accounts and logins are not touched. [y/N]"
if ($go -notmatch '^(y|yes)$') { Write-Host "Nothing was deleted." -ForegroundColor Yellow; return }

$failed = 0
foreach ($i in $items) {
    Remove-Item -LiteralPath $i.Path -Recurse -Force -ErrorAction SilentlyContinue
    if ((Test-Path -LiteralPath $i.Path) -and $PlatformWin) { [void](Remove-TreeHard $i.Path) }
    if (Test-Path -LiteralPath $i.Path) { $failed++; Write-Host "  could not delete $($i.Path)" -ForegroundColor Red }
}
if ($failed -eq 0) { Write-Host ("Freed about {0} MB." -f [math]::Round($total, 1)) -ForegroundColor Green }
Start-Sleep -Seconds 1

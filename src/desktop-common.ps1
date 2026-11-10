# Shared helpers for the Claude DESKTOP app account switcher (Windows only).
# Dot-sourced by claude-add.ps1 / claude-switch.ps1 / claude-code-doctor.ps1.
#
# The desktop app keeps its login in its Electron profile (cookies, Local
# Storage, IndexedDB and an encrypted OAuth cache in config.json), so an
# account is saved/restored as a snapshot of that whole profile folder.
#
# What changed in the app during 2026 and is handled here:
#   * The Microsoft Store build moved its profile out of %APPDATA%\Claude (and
#     the Packages\Claude_*\LocalCache\Roaming\Claude redirect) into
#     %LOCALAPPDATA%\Claude-Data\claude_<id>\ . The old folders are left behind
#     holding only a ".user-data-left.*" marker file. Versions <= 3.7 kept
#     swapping the abandoned folder, so the app never changed account - and the
#     "refresh saved profile" step mirrored that empty folder over a good
#     snapshot.
#   * Sign-in now lives in config.json "oauth:tokenCacheV2"; the legacy
#     "oauth:tokenCache" key may be missing or hold a dead grant.
#   * The profile folder also contains the app's bundled Claude Code CLI and
#     caches (hundreds of MB, files in use) - these are not account state and
#     are excluded from snapshots.
#
# Must stay compatible with Windows PowerShell 5.1 - ASCII only.

$DtStore   = Join-Path $env:USERPROFILE '.claude-accounts'
$DtCurrent = Join-Path $DtStore '.current'
$DtRawBase = 'https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main'
$DtUtf8    = New-Object System.Text.UTF8Encoding($false)

# Not account state: never copied into / deleted from a snapshot, and never
# purged from the live profile when a snapshot is restored.
$DtExcludeDirs = @('claude-code', 'vm_bundles', 'Cache', 'Code Cache', 'GPUCache',
                   'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'GrShaderCache',
                   'ShaderCache', 'component_crx_cache', 'Crashpad', 'logs')
# Kept in place when the live profile is cleared for a fresh sign-in.
$DtKeepOnClear = @('claude-code', 'vm_bundles')

function Join-Parts {
    $p = $args[0]
    for ($i = 1; $i -lt $args.Count; $i++) { $p = Join-Path $p $args[$i] }
    return $p
}

# -- Update check (best-effort, cached once per day) ---------------------------
function Test-ForUpdate {
    try {
        $tools     = Join-Path $env:USERPROFILE '.claude-tools'
        $checkFile = Join-Path $tools '.update-check'
        if (Test-Path $checkFile) {
            if (((Get-Date) - (Get-Item $checkFile).LastWriteTime) -lt [TimeSpan]::FromDays(1)) { return }
        }
        New-Item -ItemType File -Force -Path $checkFile | Out-Null
        (Get-Date -Format o) | Set-Content -Path $checkFile -ErrorAction SilentlyContinue
        $remote  = (Invoke-RestMethod -Uri "$DtRawBase/VERSION" -TimeoutSec 4).ToString().Trim()
        $verFile = Join-Path $tools '.version'
        $local   = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '0.0.0' }
        if ([version]$remote -gt [version]$local) {
            Write-Host ""
            Write-Host "  * Update available: v$local -> v$remote   (run 'claude-switch-update')" -ForegroundColor Yellow
        }
    } catch {}
}

# -- Locating the live profile -------------------------------------------------
# Every folder the desktop app has used for its profile, newest layout first.
function Get-DataRootCandidates {
    $roots = @()
    # A folder the running app itself reported on an earlier add/switch. This
    # is how a location that no rule below knows about (a future move) is
    # still found after the app has been closed.
    $cached = Get-RootCache
    if ($cached) { $roots += $cached }
    $newBase = Join-Path $env:LOCALAPPDATA 'Claude-Data'
    if (Test-Path $newBase) {
        # Every sub-folder, not just 'claude_*' - the name may change again.
        Get-ChildItem $newBase -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $roots += $_.FullName }
    }
    $roots += (Join-Path $env:APPDATA 'Claude')
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pkgRoot) {
        Get-ChildItem $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
            ForEach-Object { $roots += (Join-Parts $_.FullName 'LocalCache' 'Roaming' 'Claude') }
    }
    return @($roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
}

# The app leaves this marker in a folder it has moved its data OUT of.
function Test-RootAbandoned($root) {
    return [bool](Get-ChildItem $root -Force -File -Filter '.user-data-left*' -ErrorAction SilentlyContinue)
}

function Get-CookiesPath($root) {
    foreach ($c in @((Join-Parts $root 'Network' 'Cookies'), (Join-Path $root 'Cookies'))) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Test-RootHasProfile($root) {
    if (Test-Path (Join-Path $root 'config.json')) { return $true }
    if (Test-Path (Join-Path $root 'Local State')) { return $true }
    if (Get-CookiesPath $root) { return $true }
    return $false
}

function Test-FileLocked($path) {
    if (-not $path -or -not (Test-Path $path)) { return $false }
    try { $fs = [IO.File]::Open($path, 'Open', 'Read', 'None'); $fs.Close(); return $false } catch { return $true }
}

# Last live profile folder confirmed by an add/switch (see Get-DataRootCandidates).
function Get-RootCache {
    $f = Join-Path $DtStore '.root'
    if (-not (Test-Path $f)) { return $null }
    try { $v = (Get-Content $f -Raw).Trim() } catch { return $null }
    if ($v -and (Test-Path $v)) { return $v }
    return $null
}

function Set-RootCache($root) {
    try {
        New-Item -ItemType Directory -Force -Path $DtStore | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $DtStore '.root'), $root, $DtUtf8)
    } catch {}
}

# Ask the RUNNING app where its profile is. Electron/Chromium passes
# --user-data-dir=<folder> to its helper processes, so this keeps working even
# if a future update moves the data somewhere this script has never heard of.
# Only trusted when the folder really looks live (has a profile, is not marked
# as abandoned, and its cookie store - if there is one - is held open).
function Get-RunningDataRoot {
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'claude%'" -ErrorAction Stop)
    } catch { return $null }
    foreach ($p in $procs) {
        $cl = [string]$p.CommandLine
        if (-not $cl) { continue }
        $m = [regex]::Match($cl, '--user-data-dir=(?:"([^"]+)"|(\S+))')
        if (-not $m.Success) { continue }
        $dir = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $dir = $dir.TrimEnd('\')
        if (-not $dir -or -not (Test-Path $dir)) { continue }
        if (-not (Test-RootHasProfile $dir) -or (Test-RootAbandoned $dir)) { continue }
        $ck = Get-CookiesPath $dir
        if ($ck -and -not (Test-FileLocked $ck)) { continue }
        return $dir
    }
    return $null
}

# The profile folder the installed app is REALLY using right now.
function Get-SessionRoot {
    $running = Get-RunningDataRoot
    if ($running) { return $running }
    $cands = @(Get-DataRootCandidates | Where-Object { Test-RootHasProfile $_ })
    if ($cands.Count -eq 0) { return $null }
    $current = @($cands | Where-Object { -not (Test-RootAbandoned $_) })
    if ($current.Count -gt 0) { $cands = $current }

    $newest = $null; $newestTime = [datetime]::MinValue
    foreach ($r in $cands) {
        # A running app holds its cookie store open - that root is the live one.
        if (Test-FileLocked (Get-CookiesPath $r)) { return $r }
        foreach ($f in @((Join-Path $r 'config.json'), (Get-CookiesPath $r), (Join-Path $r 'Local State'))) {
            if ($f -and (Test-Path $f)) {
                $t = (Get-Item $f -Force).LastWriteTime
                if ($t -gt $newestTime) { $newestTime = $t; $newest = $r }
            }
        }
    }
    if ($newest) { return $newest }
    return $cands[0]
}

# -- Stopping / starting the app -----------------------------------------------
# A standalone Claude Code CLI is also called claude.exe - it must NOT be
# killed when the desktop app is switched.
function Test-CliPath($path) {
    foreach ($pat in @('*\.local\bin\*', '*\.local\share\claude\*', '*\node_modules\*', '*\npm\*', '*\.claude\local\*')) {
        if ($path -like $pat) { return $true }
    }
    return $false
}

function Get-DesktopProcesses($root) {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch {}
        if (-not $p) { return ($_.ProcessName -eq 'Claude') }          # path hidden: old behaviour
        if ($p -like '*\WindowsApps\Claude_*') { return $true }         # Store app
        if ($root -and $p.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }  # CLI bundled inside the profile
        if ($_.ProcessName -eq 'Claude') { return (-not (Test-CliPath $p)) }
        return $false
    })
}

function Stop-Claude($root) {
    $watch = @((Get-CookiesPath $root), (Join-Path $root 'config.json')) | Where-Object { $_ }
    for ($i = 0; $i -lt 40; $i++) {
        $procs = Get-DesktopProcesses $root
        if ($procs.Count -gt 0) { $procs | Stop-Process -Force -ErrorAction SilentlyContinue }
        $locked = $false
        foreach ($f in $watch) { if (Test-FileLocked $f) { $locked = $true } }
        if ($procs.Count -eq 0 -and -not $locked) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Start-Claude {
    $apps = @(Get-StartApps | Where-Object { $_.Name -match 'claude' })
    $a = $apps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1
    if (-not $a) { $a = $apps | Where-Object { $_.Name -notmatch 'code|switch' } | Select-Object -First 1 }
    if (-not $a) { $a = $apps | Select-Object -First 1 }
    if ($a) { Start-Process "shell:AppsFolder\$($a.AppID)"; return $true }
    return $false
}

# -- Copying a profile ---------------------------------------------------------
# Mirror $source into $destination, leaving the excluded (non-account) folders
# alone on both sides.
# $prune = $true is used when the DESTINATION is a saved copy (an account
# snapshot or the backup): any cache / bundled-CLI folders already sitting in
# it (copies saved by versions before 4.0 included them - hundreds of MB) are
# deleted, so a saved copy only ever holds account state.
function Copy-ClaudeProfile($source, $destination, $prune) {
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    robocopy $source $destination /MIR /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /XD @DtExcludeDirs /XF '.user-data-left*' | Out-Null
    if ($LASTEXITCODE -gt 7) { return $false }

    # These are process-instance artifacts, never account state. Leaving one in
    # a restored profile can prevent Electron from starting cleanly.
    Get-ChildItem $destination -Force -Filter 'Singleton*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    if ($prune) {
        Get-ChildItem $destination -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $DtExcludeDirs -contains $_.Name } |
            Sort-Object { $_.FullName.Length } |
            ForEach-Object { [void](Remove-TreeHard $_.FullName) }
    }
    return $true
}

# -- Storage: ONE saved copy per account, ONE backup ---------------------------
# Saving or switching always overwrites the same folders:
#   ~/.claude-accounts/<email>/profile   the account's saved copy
#   ~/.claude-accounts/.backup/profile   the profile that was live before the last switch
# Nothing is ever added next to them, so disk use does not grow with use.
$DtBackup = Join-Path $DtStore '.backup'

function Remove-TreeHard($path) {
    if (-not (Test-Path -LiteralPath $path)) { return $true }
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $path) {
        # Very long paths defeat Remove-Item under Windows PowerShell 5.1.
        & cmd.exe /c "rd /s /q `"$path`"" 2>$null | Out-Null
    }
    return (-not (Test-Path -LiteralPath $path))
}

function Get-DirSizeMB($path) {
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    $sum = [int64]0
    Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue |
        ForEach-Object { $sum += $_.Length }
    return [math]::Round($sum / 1MB, 1)
}

# Timestamped backups written by versions before 4.2 (".backup-<date>").
function Remove-OldBackups {
    Get-ChildItem $DtStore -Directory -Filter '.backup-*' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { [void](Remove-TreeHard $_.FullName) }
}

# Everything in the store that this version does not use: old timestamped
# backups, folders that are not a saved account, and files/folders older
# versions kept beside an account's 'profile' folder.
function Get-StoreLeftovers {
    $out = @()
    if (-not (Test-Path $DtStore)) { return $out }
    foreach ($d in @(Get-ChildItem $DtStore -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name -eq '.backup') { continue }
        if ($d.Name -like '.backup-*') { $out += $d.FullName; continue }
        if (-not (Test-Path (Join-Path $d.FullName 'meta.json'))) { $out += $d.FullName; continue }
        foreach ($c in @(Get-ChildItem $d.FullName -Force -ErrorAction SilentlyContinue)) {
            if ($c.Name -ne 'profile' -and $c.Name -ne 'meta.json') { $out += $c.FullName }
        }
    }
    return $out
}

# Empty the live profile so the app opens at a sign-in screen. $root is the
# exact app-data directory resolved by Get-SessionRoot, never a parent.
function Clear-ClaudeProfile($root) {
    Get-ChildItem $root -Force -ErrorAction SilentlyContinue |
        Where-Object { $DtKeepOnClear -notcontains $_.Name } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# -- Reading the sign-in state -------------------------------------------------
# AES-256-GCM decrypt of the app's token cache via bcrypt.dll (Windows' native
# CNG crypto library) through a direct P/Invoke - no external process, no temp
# script files, no Node dependency. PowerShell 5.1's .NET Framework has no
# built-in AesGcm class (that only ships in .NET 5+), so this is the only
# in-process option that works on both 5.1 (the Desktop shortcut's shell) and
# pwsh 7. Deliberately not shelling out to node/cmd here: reading a browser-
# style credential store, decrypting it, and spawning a child process to do so
# is the exact behavioral pattern security software flags as credential
# theft - this keeps everything in-process and inspectable.
$BCryptSrc = @'
using System;
using System.Runtime.InteropServices;

public static class BCryptAesGcm
{
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)]
    static extern uint BCryptOpenAlgorithmProvider(out IntPtr phAlgorithm, string pszAlgId, string pszImplementation, uint dwFlags);
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)]
    static extern uint BCryptSetProperty(IntPtr hObject, string pszProperty, string pbInput, int cbInput, uint dwFlags);
    [DllImport("bcrypt.dll")]
    static extern uint BCryptGenerateSymmetricKey(IntPtr hAlgorithm, out IntPtr phKey, IntPtr pbKeyObject, uint cbKeyObject, byte[] pbSecret, uint cbSecret, uint dwFlags);
    [DllImport("bcrypt.dll")]
    static extern uint BCryptDestroyKey(IntPtr hKey);
    [DllImport("bcrypt.dll")]
    static extern uint BCryptCloseAlgorithmProvider(IntPtr hAlgorithm, uint dwFlags);

    [StructLayout(LayoutKind.Sequential)]
    struct BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO
    {
        public uint cbSize; public uint dwInfoVersion;
        public IntPtr pbNonce; public uint cbNonce;
        public IntPtr pbAuthData; public uint cbAuthData;
        public IntPtr pbTag; public uint cbTag;
        public IntPtr pbMacContext; public uint cbMacContext;
        public uint cbAAD; public ulong cbData; public uint dwFlags;
    }

    [DllImport("bcrypt.dll")]
    static extern uint BCryptDecrypt(IntPtr hKey, byte[] pbInput, uint cbInput, ref BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO pPaddingInfo, byte[] pbIV, uint cbIV, byte[] pbOutput, uint cbOutput, out uint pcbResult, uint dwFlags);

    public static byte[] Decrypt(byte[] key, byte[] nonce, byte[] cipherText, byte[] tag)
    {
        IntPtr hAlg = IntPtr.Zero, hKey = IntPtr.Zero;
        uint status = BCryptOpenAlgorithmProvider(out hAlg, "AES", null, 0);
        if (status != 0) throw new Exception("OpenAlgorithmProvider failed: 0x" + status.ToString("X"));
        string mode = "ChainingModeGCM";
        status = BCryptSetProperty(hAlg, "ChainingMode", mode, (mode.Length + 1) * 2, 0);
        if (status != 0) throw new Exception("SetProperty failed: 0x" + status.ToString("X"));
        status = BCryptGenerateSymmetricKey(hAlg, out hKey, IntPtr.Zero, 0, key, (uint)key.Length, 0);
        if (status != 0) throw new Exception("GenerateSymmetricKey failed: 0x" + status.ToString("X"));
        GCHandle nonceHandle = GCHandle.Alloc(nonce, GCHandleType.Pinned);
        GCHandle tagHandle = GCHandle.Alloc(tag, GCHandleType.Pinned);
        try
        {
            var info = new BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO));
            info.dwInfoVersion = 1;
            info.pbNonce = nonceHandle.AddrOfPinnedObject(); info.cbNonce = (uint)nonce.Length;
            info.pbTag = tagHandle.AddrOfPinnedObject(); info.cbTag = (uint)tag.Length;
            byte[] output = new byte[cipherText.Length];
            uint resultLen;
            status = BCryptDecrypt(hKey, cipherText, (uint)cipherText.Length, ref info, null, 0, output, (uint)output.Length, out resultLen, 0);
            if (status != 0) throw new Exception("BCryptDecrypt failed: 0x" + status.ToString("X"));
            byte[] result = new byte[resultLen];
            Array.Copy(output, result, resultLen);
            return result;
        }
        finally
        {
            nonceHandle.Free(); tagHandle.Free();
            if (hKey != IntPtr.Zero) BCryptDestroyKey(hKey);
            if (hAlg != IntPtr.Zero) BCryptCloseAlgorithmProvider(hAlg, 0);
        }
    }
}
'@
try { [BCryptAesGcm] | Out-Null } catch { Add-Type -TypeDefinition $BCryptSrc -Language CSharp -ErrorAction SilentlyContinue }
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

function Read-FileShared($path) {
    try {
        $fs     = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($fs)
        $text   = $reader.ReadToEnd()
        $reader.Close(); $fs.Close()
        return $text
    } catch { return $null }
}

# The profile's own AES key (each profile folder has its own "Local State", so
# a saved snapshot must be decrypted with ITS key, not the live profile's).
function Get-AesKey($root) {
    try {
        $ls = Read-FileShared (Join-Path $root 'Local State')
        if (-not $ls) { return $null }
        $b64   = ($ls | ConvertFrom-Json).os_crypt.encrypted_key
        $bytes = [Convert]::FromBase64String($b64)
        return [System.Security.Cryptography.ProtectedData]::Unprotect(
                   $bytes[5..($bytes.Length - 1)], $null,
                   [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    } catch { return $null }
}

# -> the decrypted JSON text of one cache blob, or $null if it can't be read.
function Get-BlobPlainText($blob, $key) {
    if (-not $blob -or -not $key) { return $null }
    try {
        $bytes        = [Convert]::FromBase64String($blob)
        $nonce        = $bytes[3..14]
        $cipherAndTag = $bytes[15..($bytes.Length - 1)]
        $cipherLen    = $cipherAndTag.Length - 16
        if ($cipherLen -le 0) { return $null }
        $cipherText   = $cipherAndTag[0..($cipherLen - 1)]
        $tag          = $cipherAndTag[$cipherLen..($cipherAndTag.Length - 1)]
        $plainBytes   = [BCryptAesGcm]::Decrypt($key, $nonce, $cipherText, $tag)
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } catch { return $null }
}

# First usable access token inside a decrypted cache ({ "<grant>": { token, ... } }).
function Get-TokenFromPlainText($plainText) {
    try { $o = $plainText | ConvertFrom-Json } catch { return $null }
    if (-not $o) { return $null }
    foreach ($v in @($o.PSObject.Properties.Value)) {
        if (-not $v) { continue }
        if ($v.token)       { return [string]$v.token }
        if ($v.accessToken) { return [string]$v.accessToken }
    }
    return $null
}

# Sign-in state of a profile folder (the live one or a saved snapshot).
#   State: 'SIGNEDIN' - a token was found (Token is set)
#          'EMPTY'    - the cache is readable and holds no login (signed out)
#          'MISSING'  - no config.json at all (not a usable profile)
#          'UNKNOWN'  - a cache exists but could not be read
function Get-ProfileState($root) {
    $res = [pscustomobject]@{ State = 'MISSING'; Token = $null }
    $cfgPath = Join-Path $root 'config.json'
    if (-not (Test-Path $cfgPath)) { return $res }
    $raw = Read-FileShared $cfgPath
    try { $cfg = $raw | ConvertFrom-Json } catch { $res.State = 'UNKNOWN'; return $res }
    # "oauth:tokenCacheV2" is the live cache on current builds; the un-suffixed
    # V1 key is kept for older ones. Newest suffix first, so a future V3 works.
    $blobs = @($cfg.PSObject.Properties |
        Where-Object { $_.Name -like 'oauth:tokenCache*' -and $_.Value -is [string] -and $_.Value } |
        Sort-Object Name -Descending | ForEach-Object { $_.Value })
    if (@($blobs).Count -eq 0) {
        # No cache under a name this version knows. If the config still holds
        # something sign-in related under ANOTHER name, a newer Claude build
        # has probably renamed it - report "can't tell", not "signed out", so
        # the tool keeps working (with a confirmation) instead of refusing.
        $other = @($cfg.PSObject.Properties |
            Where-Object { $_.Name -match 'oauth|token' -and $_.Name -notlike 'oauth:tokenCache*' -and $_.Value })
        $res.State = if ($other.Count -gt 0) { 'UNKNOWN' } else { 'EMPTY' }
        return $res
    }
    $key = Get-AesKey $root
    if (-not $key) { $res.State = 'UNKNOWN'; return $res }
    $unreadable = $false
    foreach ($b in $blobs) {
        $plain = Get-BlobPlainText $b $key
        if (-not $plain) { $unreadable = $true; continue }
        $tok = Get-TokenFromPlainText $plain
        if ($tok) { $res.State = 'SIGNEDIN'; $res.Token = $tok; return $res }
    }
    $res.State = if ($unreadable) { 'UNKNOWN' } else { 'EMPTY' }
    return $res
}

# HttpClient, not Invoke-RestMethod: under Windows PowerShell 5.1 (the Desktop
# shortcut's shell) Invoke-RestMethod hangs indefinitely reading a SUCCESSFUL
# response from these endpoints (-TimeoutSec doesn't cover the read stall).
$script:DtHttpClient = $null
function Invoke-OAuthGet($url, $accessToken) {
    if (-not $accessToken) { return $null }
    try {
        if (-not $script:DtHttpClient) {
            $handler = New-Object System.Net.Http.HttpClientHandler
            $script:DtHttpClient = New-Object System.Net.Http.HttpClient($handler)
            $script:DtHttpClient.Timeout = [TimeSpan]::FromSeconds(6)
        }
        $req = New-Object System.Net.Http.HttpRequestMessage('GET', $url)
        $req.Headers.Add('Authorization', "Bearer $accessToken")
        $req.Headers.Add('anthropic-version', '2023-06-01')
        $req.Headers.Add('anthropic-beta', 'oauth-2025-04-20')
        $resp = $script:DtHttpClient.SendAsync($req).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { return $null }
        $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return ($body | ConvertFrom-Json)
    } catch { return $null }
}

function Get-ClaudeUsage($accessToken) {
    return Invoke-OAuthGet 'https://api.anthropic.com/api/oauth/usage' $accessToken
}

# Email of the account a token belongs to ($null = could not be determined).
function Get-TokenEmail($accessToken) {
    $j = Invoke-OAuthGet 'https://api.anthropic.com/api/oauth/profile' $accessToken
    if ($j -and $j.account -and $j.account.email) { return [string]$j.account.email }
    return $null
}

# Format the reset times into a short, human line (local time). The 5h limit is
# close so it's shown as a countdown; the weekly limit is shown as a date+time.
function Format-Resets($u) {
    if (-not $u) { return $null }
    $now   = Get-Date
    $parts = @()
    try {
        $r5 = [datetimeoffset]::Parse($u.five_hour.resets_at).LocalDateTime
        $d  = $r5 - $now
        if ($d.TotalSeconds -gt 0) {
            $rel = if ($d.TotalHours -ge 1) { "{0}h{1:00}m" -f [int][math]::Floor($d.TotalHours), $d.Minutes } else { "{0}m" -f [int]$d.TotalMinutes }
            $parts += "5h resets in $rel ($($r5.ToString('HH:mm')))"
        }
    } catch {}
    try {
        $r7 = [datetimeoffset]::Parse($u.seven_day.resets_at).LocalDateTime
        $parts += "7d resets $($r7.ToString('ddd MMM d, HH:mm'))"
    } catch {}
    if ($parts.Count) { return ($parts -join '   |   ') }
    return $null
}

# After a switch: watch the restarted app and report who it is signed in as.
#   Result: 'OK'       - verified signed in as $expectEmail
#           'OTHER'    - signed in, but as a different account (Email is set)
#           'REJECTED' - the app dropped the restored sign-in (shows a login screen)
#           'UNSURE'   - could not be confirmed either way
# A restored token is often expired, so the app is given time to renew it.
function Wait-LiveAccount($root, $expectEmail, $seconds) {
    $res = [pscustomobject]@{ Result = 'UNSURE'; Email = $null }
    $deadline = (Get-Date).AddSeconds($seconds)
    $emptySeen = 0
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $st = Get-ProfileState $root
        if ($st.State -eq 'SIGNEDIN') {
            $emptySeen = 0
            $who = Get-TokenEmail $st.Token
            if ($who) {
                $res.Email = $who
                if ($who -eq $expectEmail) { $res.Result = 'OK'; return $res }
                $res.Result = 'OTHER'
            }
        } elseif ($st.State -eq 'EMPTY') {
            $emptySeen++
        }
    }
    if ($res.Result -eq 'UNSURE' -and $emptySeen -ge 3) { $res.Result = 'REJECTED' }
    return $res
}

# -- Sharing the Code-tab session list between accounts ------------------------
# The desktop app lists its Claude Code ("Code" tab) sessions per account:
#     <profile>\claude-code-sessions\<account-id>\<org-id>\local_<id>.json
# Each file is a small index entry (title, folder, cliSessionId). The real
# conversation is a transcript in ~/.claude/projects, which every account on
# this PC already shares. So after a switch the work is all still on disk -
# the other account's sidebar just doesn't list it.
#
# This copies the missing index entries from every other account into the
# profile that is about to be loaded, so any account can open and continue any
# session. Rules that keep it safe:
#   * add-only: an entry the target already has is never changed or replaced
#   * a session the target account deleted (deleted_* marker) stays deleted
#   * one entry per conversation (no duplicates by cliSessionId)
#   * only local_*.json is copied - never sign-in data, settings or tasks
# Regular claude.ai chats are NOT local files (they live in each account on
# Anthropic's servers) and cannot be shared this way.
# Create the file ~/.claude-accounts/.no-session-share to turn this off.
function Get-SessionDirs($profileRoot) {
    $base = Join-Path $profileRoot 'claude-code-sessions'
    $out = @()
    if (-not (Test-Path $base)) { return $out }
    foreach ($acct in @(Get-ChildItem $base -Directory -Force -ErrorAction SilentlyContinue)) {
        foreach ($org in @(Get-ChildItem $acct.FullName -Directory -Force -ErrorAction SilentlyContinue)) { $out += $org.FullName }
    }
    return $out
}

function Get-SessionCliId($file) {
    try { return [string]((Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).cliSessionId) } catch { return '' }
}

# -> number of session entries added to $targetProfile.
function Sync-CodeSessions($sourceProfiles, $targetProfile) {
    if (Test-Path (Join-Path $DtStore '.no-session-share')) { return 0 }
    $added = 0
    try {
        $dests = @(Get-SessionDirs $targetProfile)
        if ($dests.Count -eq 0) { return 0 }      # this account has not used the Code tab yet
        # The account the profile belongs to, when the app recorded it.
        try {
            $acctId = [string]((Get-Content (Join-Path $targetProfile 'config.json') -Raw | ConvertFrom-Json).lastKnownAccountUuid)
            if ($acctId) {
                $own = @($dests | Where-Object { (Split-Path (Split-Path $_ -Parent) -Leaf) -eq $acctId })
                if ($own.Count -gt 0) { $dests = $own }
            }
        } catch {}

        $sources = @()
        foreach ($p in @($sourceProfiles)) {
            if ($p -and (Test-Path $p)) { $sources += @(Get-SessionDirs $p) }
        }
        foreach ($dest in $dests) {
            $have    = @{}      # file names already listed
            $haveCli = @{}      # conversations already listed
            $deleted = @()      # names of deleted_* markers
            foreach ($f in @(Get-ChildItem $dest -File -Force -ErrorAction SilentlyContinue)) {
                if ($f.Name -like 'deleted_*') { $deleted += $f.Name; continue }
                if ($f.Name -like 'local_*.json') {
                    $have[$f.Name] = $true
                    $c = Get-SessionCliId $f.FullName
                    if ($c) { $haveCli[$c] = $true }
                }
            }
            foreach ($src in $sources) {
                if ($src -eq $dest) { continue }
                foreach ($f in @(Get-ChildItem $src -File -Force -Filter 'local_*.json' -ErrorAction SilentlyContinue)) {
                    if ($have.ContainsKey($f.Name)) { continue }
                    $id  = $f.BaseName.Substring(6)                       # after "local_"
                    $cli = Get-SessionCliId $f.FullName
                    if ($cli -and $haveCli.ContainsKey($cli)) { continue }
                    $gone = $false
                    foreach ($d in $deleted) {
                        if (($id -and $d -like "*$id*") -or ($cli -and $d -like "*$cli*")) { $gone = $true; break }
                    }
                    if ($gone) { continue }
                    try {
                        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name) -ErrorAction Stop
                        $have[$f.Name] = $true
                        if ($cli) { $haveCli[$cli] = $true }
                        $added++
                    } catch {}
                }
            }
        }
    } catch {}
    return $added
}

# -- Saved accounts ------------------------------------------------------------
function Get-SafeName($email) { return ($email -replace '[^\w.@+-]', '_') }

# Every saved desktop account: Email, Dir, Profile (snapshot folder), State.
function Get-SavedAccounts {
    $list = @()
    $dirs = Get-ChildItem $DtStore -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'meta.json') }
    foreach ($a in $dirs) {
        try { $m = Get-Content (Join-Path $a.FullName 'meta.json') -Raw | ConvertFrom-Json } catch { continue }
        if (-not $m.email) { continue }
        $prof = Join-Path $a.FullName 'profile'
        $st = [pscustomobject]@{ State = 'MISSING'; Token = $null }
        if (Test-Path $prof) { $st = Get-ProfileState $prof }
        $list += [pscustomobject]@{ Email = [string]$m.email; Dir = $a.FullName; Profile = $prof; State = $st.State; Token = $st.Token }
    }
    return $list
}

function Get-CurrentMarker {
    if (-not (Test-Path $DtCurrent)) { return $null }
    try { return (Get-Content $DtCurrent -Raw).Trim() } catch { return $null }
}

function Set-CurrentMarker($email) {
    try {
        New-Item -ItemType Directory -Force -Path $DtStore | Out-Null
        [System.IO.File]::WriteAllText($DtCurrent, $email, $DtUtf8)
    } catch {}
}

<#
.SYNOPSIS
    RVM - Rust Version Manager for Windows (v0.1.0)
.DESCRIPTION
    Manage multiple Rust toolchains on Windows via rustup.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1)][string]$Arg1,
    [Parameter(Position = 2)][string]$Arg2,
    [Parameter(ValueFromRemainingArguments = $true)]$RemainingArgs
)
    # Short flag aliases -d -u -c
    $script:REMAINING_ARGS = @($RemainingArgs)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RVM_VERSION = "0.1.0"
$script:DEFAULT_RVM_HOME = Join-Path $env:USERPROFILE ".rvm"
$script:RUSTUP_INIT_BASE = "https://static.rust-lang.org/rustup/dist"
$script:MIRRORS = @{
    "official" = @{ rustup_dist_server = $null; rustup_update_root = $null; cargo_registry = $null }
    # NOTE: rustup uses two separate URLs:
    #   RUSTUP_UPDATE_ROOT + "/release-stable.toml"      -> rustup self-update check
    #   RUSTUP_DIST_SERVER  + "/dist/channel-rust-*.toml" -> toolchain metadata
    # These paths differ for most mirrors — both MUST be correct or rustup fails.
    "rsproxy"  = @{ rustup_dist_server = "https://rsproxy.cn";                    rustup_update_root = "https://rsproxy.cn/rustup";                     cargo_registry = "https://rsproxy.cn/crates.io-index" }
    "tuna"     = @{ rustup_dist_server = "https://mirrors.tuna.tsinghua.edu.cn/rustup"; rustup_update_root = "https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup"; cargo_registry = "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index.git" }
    "ustc"     = @{ rustup_dist_server = "https://mirrors.ustc.edu.cn/rustup";       rustup_update_root = "https://mirrors.ustc.edu.cn/rustup/rustup";       cargo_registry = "https://mirrors.ustc.edu.cn/crates.io-index" }
    "sjtu"     = @{ rustup_dist_server = "https://mirrors.sjtug.sjtu.edu.cn/rust-static"; rustup_update_root = "https://mirrors.sjtug.sjtu.edu.cn/rust-static/rustup"; cargo_registry = "https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index.git" }
}
$script:RVM_HOME = $env:RVM_HOME
if ([string]::IsNullOrWhiteSpace($script:RVM_HOME)) {
    $maybeScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path -Parent } else { $null }
    if ($maybeScriptDir) {
        $scriptSettings = Join-Path (Split-Path $maybeScriptDir -Parent) "settings.json"
        if (Test-Path $scriptSettings) {
            try { $s = Get-Content $scriptSettings -Raw | ConvertFrom-Json; if ($s.root) { $script:RVM_HOME = $s.root } } catch { }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($script:RVM_HOME)) {
    $defaultSettingsPath = Join-Path $script:DEFAULT_RVM_HOME "settings.json"
    if (Test-Path $defaultSettingsPath) {
        try { $settings = Get-Content $defaultSettingsPath -Raw | ConvertFrom-Json; if ($settings.root) { $script:RVM_HOME = $settings.root } } catch { }
    }
}
if ([string]::IsNullOrWhiteSpace($script:RVM_HOME)) { $script:RVM_HOME = $script:DEFAULT_RVM_HOME }
$script:RUSTUP_HOME_DIR = Join-Path $script:RVM_HOME "rustup"
$script:CARGO_HOME_DIR  = Join-Path $script:RVM_HOME "cargo"
function Write-Color { param([string]$Message = "", [string]$Color = "White") if ([string]::IsNullOrWhiteSpace($Color)) { $Color = "White" }; Write-Host $Message -ForegroundColor $Color }
function Get-SettingsPath { return Join-Path $script:RVM_HOME "settings.json" }
function Show-SectionHeader {
    param([string]$Title, [string]$Color = 'White')
    Write-Host ''
    Write-Color $Title $Color
    Write-Host ('  ' + ('-' * 55)) -ForegroundColor DarkGray
}
function Get-Settings {
    $path = Get-SettingsPath
    $default = [PSCustomObject]@{
        root = $script:RVM_HOME
        rustup_dist_server = $null
        rustup_update_root = $null
        cargo_mirror_name = "official"
    }
    if (Test-Path $path) {
        try {
            $content = Get-Content $path -Raw
            if ($content) {
                $s = $content | ConvertFrom-Json
                if ($s.root) { $default.root = $s.root }
                if ($s.rustup_dist_server) { $default.rustup_dist_server = $s.rustup_dist_server }
                if ($s.rustup_update_root) { $default.rustup_update_root = $s.rustup_update_root }
                if ($s.cargo_mirror_name) { $default.cargo_mirror_name = $s.cargo_mirror_name }
                if ($s.custom_mirrors) { $default | Add-Member -NotePropertyName 'custom_mirrors' -NotePropertyValue $s.custom_mirrors -Force }
            }
        } catch { Write-Warning "Failed to read settings: $_" }
    }
    return $default
}
function Save-Settings { param($Settings)
    if (-not (Test-Path $script:RVM_HOME)) { New-Item -ItemType Directory -Path $script:RVM_HOME -Force | Out-Null }
    $out = $Settings | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    # Re-attach custom_mirrors since ConvertTo-Json loses NoteProperty
    if ($Settings.custom_mirrors) { $out | Add-Member -NotePropertyName "custom_mirrors" -NotePropertyValue $Settings.custom_mirrors -Force }
    $out | ConvertTo-Json -Depth 5 | Set-Content (Get-SettingsPath) -Encoding UTF8
}
function Get-RustupEnvBlock {
    $settings = Get-Settings
    $envBlock = @{ RUSTUP_HOME = $script:RUSTUP_HOME_DIR; CARGO_HOME = $script:CARGO_HOME_DIR }
    if ($settings.rustup_dist_server) { $envBlock.RUSTUP_DIST_SERVER = $settings.rustup_dist_server }
    if ($settings.rustup_update_root) { $envBlock.RUSTUP_UPDATE_ROOT = $settings.rustup_update_root }
    return $envBlock
}
function Invoke-WithRustupEnv {
    param([scriptblock]$ScriptBlock)
    $saved = @{}
    $envBlock = Get-RustupEnvBlock
    foreach ($key in $envBlock.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, $envBlock[$key], "Process")
    }
    try {
        $result = & $ScriptBlock
        return $result
    } finally {
        foreach ($key in $saved.Keys) {
            if ($null -eq $saved[$key]) { [Environment]::SetEnvironmentVariable($key, $null, "Process") }
            else { [Environment]::SetEnvironmentVariable($key, $saved[$key], "Process") }
        }
    }
}
function Get-RustupExePath {
    $path = Join-Path $script:CARGO_HOME_DIR "bin\rustup.exe"
    return $(if (Test-Path $path) { $path } else { $null })
}
function Get-RustupInitExePath {
    return Join-Path $script:RVM_HOME "bin\rustup-init.exe"
}
function Ensure-RustupInitialized {
    if (-not (Get-RustupExePath)) {
        Write-Color "Rustup not installed. Run 'rvm install <toolchain>' first." "Yellow"
        return $false
    }
    return $true
}
function Get-InstalledToolchains {
    $dir = Join-Path $script:RUSTUP_HOME_DIR "toolchains"
    if (-not (Test-Path $dir)) { return @() }
    $result = Get-ChildItem $dir -Directory | ForEach-Object { $_.Name }
    return [string[]]@($result)
}
function Get-CurrentToolchain {
    $rustupExe = Get-RustupExePath
    if (-not $rustupExe) { return $null }
    try {
        $result = Invoke-WithRustupEnv { & (Get-RustupExePath) default 2>&1 }
        $last = if ($result -is [array]) { $result[-1] } else { "$result" }
        # Skip error lines (e.g. "error: metadata is out of date")
        if ($last -match '^error[:]') { return $null }
        if ($last -match '^([^\s]+)') { return $Matches[1] }
        return $null
    } catch { return $null }
}
function Get-Arch {
    if ([Environment]::Is64BitOperatingSystem) { return "x86_64-pc-windows-msvc" }
    return "i686-pc-windows-msvc"
}
function Write-CargoConfig {
    param([string]$RegistryUrl)
    $cargoDir = $script:CARGO_HOME_DIR
    if (-not (Test-Path $cargoDir)) { New-Item $cargoDir -ItemType Directory -Force | Out-Null }
    # Guard against empty/null registry URL to avoid writing invalid TOML.
    if ([string]::IsNullOrWhiteSpace($RegistryUrl)) { return }
    $config = "# Generated by RVM`n"
    $config += "[source.crates-io]`n"
    $config += "registry = `"https://github.com/rust-lang/crates.io-index`"`n"
    $config += "replace-with = `"rvm-mirror`"`n"
    $config += "[source.rvm-mirror]`n"
    $config += "registry = `"$RegistryUrl`"`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $cargoDir "config.toml"), $config, $utf8NoBom)
}
function Get-RemoteVersions {
    <#
    .SYNOPSIS
        Fetch current version numbers for stable, beta, and nightly channels.
        Always fetches from official sources since channel manifests are metadata only.
    #>
    $manifestUrls = @(
        @{ Channel = "stable";  Url = "https://static.rust-lang.org/dist/channel-rust-stable.toml" }
        @{ Channel = "beta";    Url = "https://static.rust-lang.org/dist/channel-rust-beta.toml" }
        @{ Channel = "nightly"; Url = "https://static.rust-lang.org/dist/channel-rust-nightly.toml" }
    )
    $results = @()
    foreach ($m in $manifestUrls) {
        $ver = "???"; $date = "???"
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "rvm-windows/0.1.0")
            $stream = $wc.OpenRead($m.Url)
            $reader = New-Object System.IO.StreamReader($stream)
            while (($line = $reader.ReadLine()) -ne $null) {
                if ($line -match '^\[pkg\.rust\]') {
                    while (($line = $reader.ReadLine()) -ne $null) {
                        if ($line -match 'version\s*=\s*"([^"]+)"') { $ver = $Matches[1]; break }
                        if ($line -match '^\[') { break }
                    }
                }
                if ($line -match '^date\s*=\s*"([^"]+)"') { $date = $Matches[1] }
                if ($ver -ne "???" -and $date -ne "???") { break }
            }
            $reader.Dispose(); $stream.Dispose(); $wc.Dispose()
        } catch { $ver = "error"; $date = "error" }
        $results += [PSCustomObject]@{ Channel = $m.Channel; Version = $ver; Date = $date }
    }
    return $results
}
function Invoke-RvmInit {
    Write-Color "Initializing rustup in: $script:RVM_HOME" "Cyan"
    $rustupInitPath = Get-RustupInitExePath
    if (-not (Test-Path $rustupInitPath)) {
        $url = "$script:RUSTUP_INIT_BASE/$(Get-Arch)/rustup-init.exe"
        Write-Host "Downloading rustup-init.exe..." -ForegroundColor Cyan
        $rvmBin = Split-Path $rustupInitPath -Parent
        if (-not (Test-Path $rvmBin)) { New-Item $rvmBin -ItemType Directory -Force | Out-Null }
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "RVM/$script:RVM_VERSION")
            $wc.DownloadFile($url, $rustupInitPath)
        } catch { Write-Color "Download failed: $_" "Red"; return $false }
    }
    foreach ($d in @($script:RUSTUP_HOME_DIR, $script:CARGO_HOME_DIR)) {
        if (-not (Test-Path $d)) { New-Item $d -ItemType Directory -Force | Out-Null }
    }
    return $true
}
function Clear-RustupCache {
    <#
    .SYNOPSIS
        Clear stale rustup metadata cache. Safe to run — preserves installed toolchains.
        Use when rustup reports "metadata is out of date" after switching mirrors.
    #>
    $count = 0
    # tmp — stale partial downloads and lock files
    $tmpDir = Join-Path $script:RUSTUP_HOME_DIR "tmp"
    if (Test-Path $tmpDir) {
        try {
            Get-ChildItem $tmpDir -Directory | ForEach-Object { [System.IO.Directory]::Delete($_.FullName, $true); $count++ }
            Write-Color "  Cleared tmp/ ($count temp dirs)" "Gray"
        } catch { }
    }
    # downloads — stale partial downloads from failed mirror attempts
    $downloadsDir = Join-Path $script:RUSTUP_HOME_DIR "downloads"
    if (Test-Path $downloadsDir) {
        try {
            Get-ChildItem $downloadsDir -File -Filter "*.partial" | ForEach-Object { Remove-Item $_.FullName -Force; $count++ }
            Write-Color "  Cleared downloads/*.partial" "Gray"
        } catch { }
    }
    # update-hashes — rustup recreates these on next use
    $hashDir = Join-Path $script:RUSTUP_HOME_DIR "update-hashes"
    if (Test-Path $hashDir) {
        try {
            Get-ChildItem $hashDir -File | ForEach-Object { Remove-Item $_.FullName -Force }
            Write-Color "  Cleared update-hashes/" "Gray"
        } catch { }
    }
    # settings.toml — will be recreated by rustup with the right format
    $settingsFile = Join-Path $script:RUSTUP_HOME_DIR "settings.toml"
    if (Test-Path $settingsFile) {
        try {
            Remove-Item $settingsFile -Force
            Write-Color "  Cleared settings.toml (will be regenerated)" "Gray"
        } catch { }
    }
}
function Repair-Rustup {
    <#
    .SYNOPSIS
        Full rustup repair: clear cache, re-download rustup-init, re-initialize.
        Preserves all installed toolchains and cargo packages.
    #>
    Write-Color "Repairing rustup..." "Cyan"
    Write-Color "  Step 1: Clear stale metadata cache" "White"
    Clear-RustupCache
    Write-Color "  Step 2: Remove old rustup.exe (will be re-downloaded)" "White"
    $rustupExe = Join-Path $script:CARGO_HOME_DIR "bin\rustup.exe"
    if (Test-Path $rustupExe) {
        try { Remove-Item $rustupExe -Force } catch { }
    }
    $cargoRustup = Join-Path $script:CARGO_HOME_DIR "bin\rustup-init.exe"
    if (Test-Path $cargoRustup) {
        try { Remove-Item $cargoRustup -Force } catch { }
    }
    Write-Color "  Step 3: Download fresh rustup-init.exe" "White"
    if (-not (Invoke-RvmInit)) {
        Write-Color "  Failed to re-initialize rustup." "Red"
        return
    }
    Write-Color "  Step 4: Re-initialize (install stable toolchain)" "White"
    $installer = Get-RustupInitExePath
    if ($installer -and (Test-Path $installer)) {
        # Run rustup-init WITH correct RUSTUP_HOME/CARGO_HOME (mirrors don't host rustup-init.exe)
        $out = Invoke-WithRustupEnv {
            $raw = & $installer -y --no-modify-path --default-toolchain stable 2>&1 | Out-String
            return $raw
        }
        if ($out) { Write-Host "$out" }
        if ($LASTEXITCODE -eq 0) {
            Write-Color "  Repair complete. Run 'rvm use stable' to switch." "Green"
        } else {
            $outStr = "$out"
            if ($outStr -match 'metadata is out of date|TOML parse error|could not parse settings') {
                Write-Color "  Re-initialize failed due to corrupted metadata. Retry by running 'rvm repair' again." "Red"
            } else {
                Write-Color "  Re-initialize failed (exit $LASTEXITCODE)" "Red"
            }
        }
    }
}
function Invoke-RvmDoctor {
    <#
    .SYNOPSIS
        Diagnose rustup health and report issues.
    #>
    Write-Color "RVM Doctor" "Cyan"
    # RVM_HOME
    Write-Host "  RVM_HOME:  $($script:RVM_HOME)" -ForegroundColor $(if ($script:RVM_HOME) { 'Green' } else { 'Red' })
    # RUSTUP_HOME
    $rustupDir = $script:RUSTUP_HOME_DIR
    Write-Host "  RUSTUP_HOME: $rustupDir" -ForegroundColor $(if (Test-Path $rustupDir) { 'Green' } else { 'Yellow' })
    # CARGO_HOME
    $cargoDir = $script:CARGO_HOME_DIR
    Write-Host "  CARGO_HOME: $cargoDir" -ForegroundColor $(if (Test-Path $cargoDir) { 'Green' } else { 'Yellow' })
    # Settings
    $settingsFile = Join-Path $rustupDir "settings.toml"
    if (Test-Path $settingsFile) {
        $content = Get-Content $settingsFile -Raw -ErrorAction SilentlyContinue
        $hasVersion = $content -match '(?m)^version'
        $hasDefault = $content -match '(?m)^default_toolchain'
        Write-Host "  settings.toml: present" -ForegroundColor Green
        if (-not $hasVersion) { Write-Color "    ⚠ Missing version field (corrupted)" "Yellow" }
        if ($hasDefault) { Write-Color "    Default set: $($Matches[0] -replace '^default_toolchain\s*=\s*')" "Gray" }
    } else {
        Write-Color "  settings.toml: absent (will be created on next rustup use)" "Gray"
    }
    # Rustup binary
    $rustupExe = Get-RustupExePath
    if ($rustupExe) {
        try {
            $ver = Invoke-WithRustupEnv { & (Get-RustupExePath) --version 2>&1 }
            Write-Host "  rustup: $($ver[0])" -ForegroundColor Green
        } catch { Write-Color "  rustup: binary found but broken" "Red" }
    } else {
        Write-Color "  rustup: not initialized" "Yellow"
    }
    # Toolchains
    $chains = @(Get-InstalledToolchains)
    if ($chains.Count -gt 0) {
        Write-Color "  Toolchains ($($chains.Count)): $($chains -join ', ')" "Green"
    } else {
        Write-Color "  Toolchains: none" "Yellow"
    }
    # Current
    $current = Get-CurrentToolchain
    if ($current) {
        Write-Host "  Current: $current" -ForegroundColor Green
        $chains = @(Get-InstalledToolchains)
        if ($chains -notcontains $current) {
            Write-Color "    ⚠ Points to non-existent toolchain (stale default)" "Yellow"
            Write-Color "    Run 'rvm use <toolchain>' to fix." "Yellow"
        }
    } else {
        Write-Color "  Current: none (use 'rvm use <toolchain>')" "Yellow"
    }
    # Mirror
    $settings = Get-Settings
    $mirror = if ($settings.cargo_mirror_name) { $settings.cargo_mirror_name } else { "official" }
    Write-Host "  Mirror: $mirror" -ForegroundColor Gray
    Write-Color "Doctor check complete." "Cyan"
}
function Invoke-RvmInstall {
    param([string]$Toolchain)
    if (-not $Toolchain) { Write-Color "Usage: rvm install <toolchain>" "Yellow"; return }
    if (-not (Invoke-RvmInit)) { return }
    $settings = Get-Settings
    $mirrorName = if ($settings.cargo_mirror_name -and $settings.cargo_mirror_name -ne "official") { $settings.cargo_mirror_name } else { "official (default)" }
    $serverUrl = if ($settings.rustup_dist_server) { $settings.rustup_dist_server } else { "https://static.rust-lang.org/rustup/dist" }
    Write-Host ""
    Write-Host "  [Mirror] $mirrorName" -ForegroundColor Cyan
    Write-Host "  [URL]    RUSTUP_DIST_SERVER=$serverUrl" -ForegroundColor Gray
    Write-Host ""
    function _DoInstall {
        param([bool]$UseMirror = $true)
        $rustupExe = Get-RustupExePath
        if ($rustupExe) {
            $sourceName = if ($UseMirror) { $mirrorName } else { "official" }
            Write-Host "Installing toolchain '$Toolchain' via rustup (source: $sourceName)..." -ForegroundColor White
            
            # Save current env vars
            $oldDist = $env:RUSTUP_DIST_SERVER
            $oldRoot = $env:RUSTUP_UPDATE_ROOT
            $oldRustupHome = $env:RUSTUP_HOME
            $oldCargoHome = $env:CARGO_HOME
            
            # Set env vars for rustup
            $env:RUSTUP_HOME = $script:RUSTUP_HOME_DIR
            $env:CARGO_HOME = $script:CARGO_HOME_DIR
            if ($UseMirror) {
                $settings = Get-Settings
                $env:RUSTUP_DIST_SERVER = if ($settings.rustup_dist_server) { $settings.rustup_dist_server } else { $null }
                $env:RUSTUP_UPDATE_ROOT = if ($settings.rustup_update_root) { $settings.rustup_update_root } else { $null }
            } else {
                $env:RUSTUP_DIST_SERVER = $null
                $env:RUSTUP_UPDATE_ROOT = $null
            }
            
            try {
                # Directly call rustup and capture output
                $out = & $rustupExe toolchain install $Toolchain 2>&1
                $outStr = "$out"
                if ($out) { Write-Host $outStr }
                
                if ($LASTEXITCODE -eq 0) { return $true }
                
                # Check if it's a metadata error
                if ($outStr -match 'metadata is out of date|TOML parse error|could not parse settings') {
                    return "METADATA_ERROR"
                }
                # Check if it's a 404 error (version not available on mirror)
                if ($UseMirror -and $outStr -match '404|not found|nonexistent') {
                    return "MIRROR_404"
                }
                Write-Color "Install failed (exit $LASTEXITCODE)" "Red"
                return $false
            } finally {
                # Restore env vars
                $env:RUSTUP_DIST_SERVER = $oldDist
                $env:RUSTUP_UPDATE_ROOT = $oldRoot
                $env:RUSTUP_HOME = $oldRustupHome
                $env:CARGO_HOME = $oldCargoHome
            }
        } else {
            # First-time setup: run rustup-init WITHOUT mirror env vars.
            # rustup-init.exe respects RUSTUP_DIST_SERVER, and mirrors do NOT
            # host rustup-init.exe — always download from official source.
            # After init, subsequent toolchain installs use the mirror via Invoke-WithRustupEnv.
            Write-Host "First-time setup: running rustup-init for '$Toolchain'..." -ForegroundColor White
            $output = Invoke-WithRustupEnv {
                & (Get-RustupInitExePath) -y --no-modify-path --default-toolchain $Toolchain 2>&1
            }
            if ($output) { Write-Host "$output" }
            if ($LASTEXITCODE -eq 0) { return $true }
            Write-Color "rustup-init failed (exit $LASTEXITCODE)" "Red"
            return $false
        }
    }
    $result = _DoInstall
    if ($result -eq "METADATA_ERROR") {
        Write-Host ""
        Write-Color "⚠ Rustup metadata is corrupted (common after switching mirrors)." "Yellow"
        Write-Color "  Auto-clearing cache and retrying..." "Yellow"
        Clear-RustupCache
        $result = _DoInstall
    }
    if ($result -eq "MIRROR_404") {
        Write-Host ""
        Write-Color "⚠ Version '$Toolchain' not available on mirror '$mirrorName'." "Yellow"
        Write-Color "  Falling back to official source..." "Yellow"
        $result = _DoInstall -UseMirror:$false
    }
    if ($result -eq $true) {
        Write-Color "Toolchain '$Toolchain' installed!" "Green"
        if ((Get-RustupExePath) -and -not (Get-CurrentToolchain)) {
            Invoke-RvmUse $Toolchain
        }
    } elseif ($result -eq $false -or $result -eq "METADATA_ERROR") {
        Write-Host ""
        Write-Color "Install still failed after cache clear." "Red"
        Write-Color "Try: rvm repair  (full re-initialize, preserves toolchains)" "Yellow"
    }
}
function Invoke-RvmUse {
    param([string]$Toolchain)
    if (-not $Toolchain) { Write-Color "Usage: rvm use <toolchain>" "Yellow"; return }
    if (-not (Ensure-RustupInitialized)) { return }
    # Auto-install if not installed
    if (-not (Resolve-ToolchainDir $Toolchain)) {
        Write-Color "Toolchain '$Toolchain' not installed. Installing first..." "Yellow"
        Invoke-RvmInstall $Toolchain
        # Re-check after install
        if (-not (Resolve-ToolchainDir $Toolchain)) {
            Write-Color "Install failed. Aborting." "Red"
            return
        }
    }
    Write-Host "Switching to '$Toolchain' ..." -ForegroundColor White
    $ok = Invoke-WithRustupEnv {
        $output = & (Get-RustupExePath) default $Toolchain 2>&1
        if ($output) { Write-Host "$output" }
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-Color "Switch failed (exit $LASTEXITCODE). Is '$Toolchain' installed?" "Red"
        return $false
    }
    if (-not $ok) { return }
    Write-Color "Now using: $Toolchain" "Green"
    $cargoBin = Join-Path $script:CARGO_HOME_DIR "bin"
    if (Test-Path $cargoBin) {
        $env:PATH = "$cargoBin;" + (($env:PATH -split ";") | Where-Object { $_ -ne $cargoBin } | Where-Object { $_ } | Select-Object -Unique) -join ";"
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $newUser = @($cargoBin) + (($userPath -split ";") | Where-Object { $_ -notmatch [regex]::Escape($cargoBin) } | Where-Object { $_ })
        [Environment]::SetEnvironmentVariable("PATH", ($newUser -join ";"), "User")
        Write-Host "  PATH updated: $cargoBin" -ForegroundColor Gray
    }
    $env:RUSTUP_HOME = $script:RUSTUP_HOME_DIR
    $env:CARGO_HOME = $script:CARGO_HOME_DIR
    [Environment]::SetEnvironmentVariable("RUSTUP_HOME", $script:RUSTUP_HOME_DIR, "User")
    [Environment]::SetEnvironmentVariable("CARGO_HOME", $script:CARGO_HOME_DIR, "User")
    Write-Color "  RUSTUP_HOME=$($script:RUSTUP_HOME_DIR)" "Gray"
    Write-Color "  CARGO_HOME=$($script:CARGO_HOME_DIR)" "Gray"
}function Invoke-RvmList {
    param([switch]$Available)
    $installed = Get-InstalledToolchains
    if ($Available) {
        Write-Host ""; Write-Color "Fetching remote toolchain versions..." "White"
        $dists = Get-RemoteVersions
        Write-Host ""; Write-Color "Available toolchains:" "White"
        Write-Host ""
        foreach ($d in $dists) {
            $clr = switch ($d.Channel) { "stable" { "Green" } "beta" { "Yellow" } "nightly" { "Magenta" } default { "White" } }
            Write-Host ("  {0,-10} rust {1,-20} ({2})" -f $d.Channel, $d.Version, $d.Date) -ForegroundColor $clr
        }
        Write-Host ""
        Write-Host "  Specific version:  rvm install 1.75.0" -ForegroundColor Gray
        Write-Host "  See all releases:  https://github.com/rust-lang/rust/releases" -ForegroundColor Gray
        Write-Host ""
    }
    if (@($installed).Count -eq 0) {
        if (-not $Available) { Write-Color "No toolchains installed. Run 'rvm install stable'." "Yellow" }
    } else {
        if (-not $Available) { Write-Host "Installed toolchains:" -ForegroundColor White }
        else { Write-Host "Installed:" -ForegroundColor Gray }
        $current = Get-CurrentToolchain
        foreach ($t in $installed) {
            $mark = if ($t -eq $current) { " * " } else { "    " }
            $clr = if ($t -eq $current) { "Green" } else { "White" }
            $suffix = if ($t -eq $current) { " (active)" } else { "" }
            Write-Color "  $mark$t$suffix" $clr
        }
    }
}
function Invoke-RvmCurrent {
    $current = Get-CurrentToolchain
    if ($current) {
        Write-Color "Currently using: $current" "Green"
        $rustcPath = Join-Path $script:CARGO_HOME_DIR "bin\rustc.exe"
        if (Test-Path $rustcPath) {
            Invoke-WithRustupEnv { $v = & (Join-Path $script:CARGO_HOME_DIR "bin\rustc.exe") --version 2>&1; Write-Host "  $v" -ForegroundColor Cyan }
        }
    } else { Write-Color "No active toolchain." "Yellow" }
}
function Resolve-ToolchainDir {
    param([string]$Toolchain)
    $tcDir = Join-Path $script:RUSTUP_HOME_DIR "toolchains"
    if (-not (Test-Path $tcDir)) { return $null }
    $matches = Get-ChildItem $tcDir -Directory | Where-Object { $_.Name -like "$Toolchain*" }
    if ($matches) { return $matches[0].FullName }
    return $null
}
function Invoke-RvmUninstall {
    param([string]$Toolchain)
    if (-not $Toolchain) { Write-Color "Usage: rvm uninstall <toolchain>" "Yellow"; return }
    $fullName = Resolve-ToolchainDir $Toolchain
    if (-not $fullName) {
        Write-Color "Toolchain '$Toolchain' not found installed." "Red"
        return
    }
    $toolchainName = Split-Path $fullName -Leaf
    Write-Host "Removing '$Toolchain' ($toolchainName)..." -ForegroundColor White
    # Delete toolchain directory directly (rustup toolchain remove can hang on some systems)
    try {
        [System.IO.Directory]::Delete($fullName, $true)
        Write-Color "  Deleted: $fullName" "Gray"
    } catch {
        try {
            Write-Color "  .NET retrying..." "DarkYellow"
            [System.IO.Directory]::Delete($fullName, $true)
        } catch {
            Write-Color "  Failed to delete: $_" "Red"
            Write-Color "Try manually deleting: $fullName" "Yellow"
            return
        }
    }
    Write-Color "Toolchain '$Toolchain' removed." "Green"
    # If it was the default toolchain, warn the user
    $settingsFile = Join-Path $script:RUSTUP_HOME_DIR "settings.toml"
    if (Test-Path $settingsFile) {
        try {
            $content = Get-Content $settingsFile -Raw
            $defaultMatch = [regex]::Match($content, '(?m)^default_toolchain\s*=\s*"([^"]+)"')
            if ($defaultMatch.Success -and $defaultMatch.Groups[1].Value -eq $toolchainName) {
                Write-Color "  (was default — stale reference remains in settings.toml)" "Yellow"
                Write-Color "  Use 'rvm use <toolchain>' to set a new default." "Yellow"
            }
        } catch {
            # silently ignore
        }
    }
}
function Invoke-RvmDefault {
    param([string]$Toolchain)
    if (-not $Toolchain) {
        $c = Get-CurrentToolchain
        if ($c) { Write-Color "Default toolchain: $c" "Green" } else { Write-Color "No default set." "Yellow" }
        return
    }
    Invoke-RvmUse $Toolchain
}
function Invoke-RvmRoot {
    param([string]$NewPath)
    if (-not $NewPath) { Write-Host $script:RVM_HOME; return }
    $resolved = [System.IO.Path]::GetFullPath($NewPath)
    if ($script:RVM_HOME -eq $resolved) { Write-Color "RVM root already: $resolved" "Yellow"; return }
    Write-Host "Changing root to: $resolved" -ForegroundColor Cyan
    foreach ($d in @($resolved, (Join-Path $resolved "rustup"), (Join-Path $resolved "cargo"), (Join-Path $resolved "bin"))) {
        if (-not (Test-Path $d)) { New-Item $d -ItemType Directory -Force | Out-Null }
    }
    $oldR = $script:RUSTUP_HOME_DIR; $oldC = $script:CARGO_HOME_DIR
    # Copy contents without -Recurse to avoid nesting toolchains/toolchains/stable/...
    $newRustupDir = Join-Path $resolved "rustup"
    $newCargoDir  = Join-Path $resolved "cargo"
    if (Test-Path $oldR) {
        Get-ChildItem $oldR -Force | ForEach-Object {
            if ($_.PSIsContainer) { Copy-Item $_.FullName -Destination $newRustupDir -Recurse -Force -ErrorAction SilentlyContinue }
            else { Copy-Item $_.FullName -Destination $newRustupDir -Force -ErrorAction SilentlyContinue }
        }
    }
    if (Test-Path $oldC) {
        Get-ChildItem $oldC -Force | ForEach-Object {
            if ($_.PSIsContainer) { Copy-Item $_.FullName -Destination $newCargoDir -Recurse -Force -ErrorAction SilentlyContinue }
            else { Copy-Item $_.FullName -Destination $newCargoDir -Force -ErrorAction SilentlyContinue }
        }
    }
    $oldBinDir = Join-Path $script:RVM_HOME "bin"
    $newBinDir = Join-Path $resolved "bin"
    if (Test-Path $oldBinDir) {
        Get-ChildItem $oldBinDir -Force | ForEach-Object {
            if ($_.PSIsContainer) { Copy-Item $_.FullName -Destination $newBinDir -Recurse -Force -ErrorAction SilentlyContinue }
            else { Copy-Item $_.FullName -Destination $newBinDir -Force -ErrorAction SilentlyContinue }
        }
    }
    $s = Get-Settings; $s.root = $resolved; Save-Settings $s
    [Environment]::SetEnvironmentVariable("RVM_HOME", $resolved, "User")
    $env:RVM_HOME = $resolved; $script:RVM_HOME = $resolved
    $script:RUSTUP_HOME_DIR = Join-Path $resolved "rustup"
    $script:CARGO_HOME_DIR = Join-Path $resolved "cargo"
    $oldCb = Join-Path $oldC "bin"; $newCb = Join-Path $script:CARGO_HOME_DIR "bin"
    $up = [Environment]::GetEnvironmentVariable("PATH", "User")
    # Remove both old and new bin dirs from existing PATH, deduplicate, then prepend $newCb.
    $filtered = ($up -split ";") | Where-Object {
        $_ -and $_ -notmatch [regex]::Escape($oldCb) -and $_ -notmatch [regex]::Escape($newCb) -and $_ -notmatch [regex]::Escape($script:RVM_HOME)
    }
    $up = @($newCb) + @($filtered)
    [Environment]::SetEnvironmentVariable("PATH", ($up -join ";"), "User")
    Write-Color "Root changed to '$resolved'. Restart terminal." "Green"
}
# --- Main dispatcher ---
function Invoke-RvmVersion { Write-Color "RVM version $script:RVM_VERSION" 'Cyan' }
function Test-MirrorSpeed {
    param($Name, $DistServer, $UpdateRoot)
    $env:RUSTUP_HOME = $script:RUSTUP_HOME_DIR
    $env:CARGO_HOME  = $script:CARGO_HOME_DIR
    $env:RUSTUP_DIST_SERVER  = $DistServer
    $env:RUSTUP_UPDATE_ROOT  = $UpdateRoot
    $env:PATH = "$($script:CARGO_HOME_DIR)\bin;$env:PATH"
    try {
        $rustup = Join-Path $script:CARGO_HOME_DIR "bin\rustup.exe"
        if (-not (Test-Path $rustup)) { return @{ name=$Name; ok=$false; ms=$null; error="rustup not found" } }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ok = $false; $err = $null
        try {
            # Run rustup check in a background job so we can apply a 10-second timeout.
            # Without a timeout, a dead mirror hangs indefinitely.
            $job = Start-Job -ScriptBlock {
                param($R) & $R check 2>&1
            } -ArgumentList $rustup

            $completed = Wait-Job $job -Timeout 10
            if ($completed) {
                $out = Receive-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -Force
                $errOut = $out | Where-Object { $_ -match 'error[:]|404|timeout|reset|failed' -and $_ -notmatch 'update available|up to date' }
                $okOut  = $out | Where-Object { $_ -match 'stable|beta|nightly|up.to.date|update available' }
                if ($errOut -and -not $okOut) { $err = ($errOut[0] -split ':', 2)[-1].Trim() }
                else { $ok = $true }
            } else {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -Force
                $err = "timeout (10s)"
            }
        } catch { $err = $_.Exception.Message.Split("`n")[0].Trim() }
        $ms = $sw.ElapsedMilliseconds; $sw.Stop()
        return @{ name=$Name; ok=$ok; ms=$ms; error=$err }
    } finally {
        $env:RUSTUP_DIST_SERVER = $null
        $env:RUSTUP_UPDATE_ROOT = $null
        $env:RUSTUP_HOME = $null
        $env:CARGO_HOME = $null
        $prepend = "$($script:CARGO_HOME_DIR)\bin;"
        if ($env:PATH -and $env:PATH.StartsWith($prepend)) { $env:PATH = $env:PATH.Substring($prepend.Length) }
    }
}
# ---------- Custom Mirror Helpers ----------
function Get-CustomMirrors {
    $s = Get-Settings; $c = $null
    try { $c = $s.custom_mirrors } catch { }
    if (-not $c) { return @{} }
    if ($c -is [string]) { try { $c = $c | ConvertFrom-Json -AsHashtable } catch { return @{} } }
    if (-not ($c -is [hashtable] -or $c -is [System.Collections.Specialized.OrderedDictionary])) {
        # Handle PSCustomObject (from JSON round-trip in Save-Settings)
        $ht = @{}
        foreach ($k in @($c.PSObject.Properties | ForEach-Object Name)) {
            $v = $c.$k
            if ($v -is [PSCustomObject] -or $v -is [hashtable]) {
                # Convert nested mirror entry to hashtable
                $nh = @{}
                foreach ($pk in @($v.PSObject.Properties | ForEach-Object Name)) { $nh[$pk] = $v.$pk }
                $ht[$k] = $nh
            } else {
                $ht[$k] = $v
            }
        }
        return $ht
    }
    return $c
}
function Save-CustomMirrors($dict) {
    $s = Get-Settings
    $s | Add-Member -NotePropertyName "custom_mirrors" -NotePropertyValue $dict -Force -ErrorAction SilentlyContinue
    Save-Settings $s
}
function Get-AllMirrors {
    $r = @{}
    foreach ($k in $script:MIRRORS.Keys) { $r[$k] = $script:MIRRORS[$k] }
    foreach ($k in (Get-CustomMirrors).Keys) {
        if (-not $script:MIRRORS.ContainsKey($k)) { $r[$k] = (Get-CustomMirrors)[$k] }
    }
    return $r
}
function Invoke-RvmMirror {
    param([string]$Action, [string]$MirrorName, [string]$DistUrl, [string]$UpdUrl, [string]$CargoUrl)
    $cachedSettings = Get-Settings  # Cache to avoid multiple file reads
    # Resolve -d -u -c short flags
    $ra = @($script:REMAINING_ARGS)
    for ($i = 0; $i -lt $ra.Count; $i++) {
        $v = $ra[$i]
        if (($v -eq '-d' -or $v -eq '--dist') -and $i+1 -lt $ra.Count) { $DistUrl = $ra[$i+1]; $i++ }
        elseif (($v -eq '-u' -or $v -eq '--upd') -and $i+1 -lt $ra.Count) { $UpdUrl = $ra[$i+1]; $i++ }
        elseif (($v -eq '-c' -or $v -eq '--cargo') -and $i+1 -lt $ra.Count) { $CargoUrl = $ra[$i+1]; $i++ }
        elseif ($v -match '^--?d(?:ist)?=(.*)') { $DistUrl = $Matches[1] }
        elseif ($v -match '^--?u(?:pd)?=(.*)') { $UpdUrl = $Matches[1] }
        elseif ($v -match '^--?c(?:argo)?=(.*)') { $CargoUrl = $Matches[1] }
    }
    # ---- speed ----
    if ($Action -eq "speed") {
        Write-Host ""; Write-Color "Testing mirror speed (rustup check)..." "White"; Write-Host ""
        $allMirrors = @(@{ name="official"; dist=$null; upd=$null })
        foreach ($k in $script:MIRRORS.Keys | Where-Object { $_ -ne "official" }) {
            $m = $script:MIRRORS[$k]
            $allMirrors += @{ name=$k; dist=$m.rustup_dist_server; upd=$m.rustup_update_root }
        }
        foreach ($k in (Get-CustomMirrors).Keys) {
            $m = (Get-CustomMirrors)[$k]
            $allMirrors += @{ name=$k; dist=$m.rustup_dist_server; upd=$m.rustup_update_root }
        }
        $results = @(); $done = 0
        foreach ($m in $allMirrors) {
            $done++; $pct = [Math]::Round($done / $allMirrors.Count * 100)
            Write-Progress -Activity "Testing mirrors" -Status "  $($m.name)" -PercentComplete $pct
            $results += Test-MirrorSpeed $m.name $m.dist $m.upd
        }
        Write-Progress -Activity "Testing mirrors" -Completed
        $results = $results | Sort-Object { if ($_.ok) { $_.ms } else { [int]::MaxValue } }
        $s = $cachedSettings
        $activeName = if ($s.cargo_mirror_name) { $s.cargo_mirror_name } else { "official" }
        Write-Host "  Mirror          Latency   Status   Note" -ForegroundColor DarkGray
        Write-Host ("  " + ("-" * 55)) -ForegroundColor DarkGray
        $rank = 1
        foreach ($r in $results) {
            $mark = if ($r.name -eq $activeName) { "*" } else { " " }
            if ($r.ok) {
                $bar = [Math]::Min([Math]::Round($r.ms / 1500), 10)
                $spacer = [Math]::Max(0, 10 - $bar)
                $bars = ("=" * $bar) + ("-" * $spacer)
                $note = if ($r.name -eq "official") { "baseline" } else { "ok" }
                $line = "  " + $rank.ToString().PadRight(3) + " " + ($r.name + $mark).PadRight(15) + " " + ("{0,7} ms" -f $r.ms) + "  " + $bars + "  " + $note
                Write-Host $line -ForegroundColor Green; $rank++
            } else {
                $e = $r.error.Substring(0, [Math]::Min(28, $r.error.Length))
                Write-Host ("  " + $rank.ToString().PadRight(3) + " " + ($r.name + $mark).PadRight(15) + " FAILED   " + $e) -ForegroundColor Red; $rank++
            }
        }
        Write-Host ""; Write-Color "  * = current active mirror" "DarkGray"
        Write-Host "  Run 'rvm mirror set <name>' to switch." "DarkGray"
        return
    }
    # ---- show (default) ----
    if ((-not $Action) -or $Action -eq "show") {
        $s = $cachedSettings
        Write-Host ""; Write-Color "Mirror configuration:" "White"
        if ($s.rustup_dist_server) { Write-Host "  RUSTUP_DIST_SERVER: $($s.rustup_dist_server)" -ForegroundColor Cyan }
        else { Write-Host "  RUSTUP_DIST_SERVER: official" -ForegroundColor Cyan }
        Write-Host "  CARGO mirror:       $($s.cargo_mirror_name)" -ForegroundColor Cyan
        Write-Host ""; Write-Color "Available mirrors:" "White"
        $custom = Get-CustomMirrors
        foreach ($k in (Get-AllMirrors).Keys) {
            $isCustom = $custom.ContainsKey($k)
            $isActive = $s.cargo_mirror_name -eq $k
            $mk = if ($isActive) { " *" } else { "  " }
            $c = if ($isActive) { "Green" } else { "Gray" }
            $tag = if (-not $script:MIRRORS.ContainsKey($k)) { " [custom]" } else { "" }
            Write-Host "$mk $k$tag" -ForegroundColor $c
        }
        return
    }
    # ---- list ----
    if ($Action -eq "list") {
        $s = $cachedSettings
        $custom = Get-CustomMirrors
        Show-SectionHeader "Built-in mirrors:" "Cyan"
        foreach ($k in ($script:MIRRORS.Keys | Sort-Object)) {
            $m = $script:MIRRORS[$k]
            $mark = if ($s.cargo_mirror_name -eq $k -and -not $custom.ContainsKey($k)) { " *" } else { "  " }
            $c = if ($s.cargo_mirror_name -eq $k -and -not $custom.ContainsKey($k)) { "Green" } else { "White" }
            Write-Host ("  " + $mark + " " + $k.PadRight(16) + "  " + $m.rustup_dist_server) -ForegroundColor $c
        }
        if ($custom.Count -gt 0) {
        Show-SectionHeader "Custom mirrors:" "Yellow"
            foreach ($k in ($custom.Keys | Sort-Object)) {
                $m = $custom[$k]
                $mark = if ($s.cargo_mirror_name -eq $k) { " *" } else { "  " }
                $c = if ($s.cargo_mirror_name -eq $k) { "Green" } else { "Yellow" }
                Write-Host ("  " + $mark + " " + $k.PadRight(16) + "  " + $m.rustup_dist_server) -ForegroundColor $c
            }
        }
        return
    }
    # ---- set ----
    if ($Action -eq "set") {
        if (-not $MirrorName) { Write-Color "Usage: rvm mirror set <name>" "Yellow"; return }
        $n = $MirrorName.ToLower()
        $allM = Get-AllMirrors
        if (-not $allM.ContainsKey($n)) { Write-Color "Unknown mirror: $MirrorName" "Red"; return }
        $m = $allM[$n]; $s = Get-Settings
        $s.rustup_dist_server = $m.rustup_dist_server; $s.rustup_update_root = $m.rustup_update_root
        $s.cargo_mirror_name = $n; Save-Settings $s
        if ($m.cargo_registry) { Write-CargoConfig $m.cargo_registry; Write-Color "  Cargo config written." "Gray" }
        elseif ($n -eq "official") { $cp = Join-Path $script:CARGO_HOME_DIR "config.toml"; if (Test-Path $cp) { Remove-Item $cp -Force -ErrorAction SilentlyContinue } }
        Write-Color "Mirror set to: $MirrorName" "Green"; return
    }
    # ---- add ----
    if ($Action -eq "add") {
        if (-not $MirrorName) { Write-Color "Usage: rvm mirror add <name> [--dist|-d <url>] [--upd|-u <url>] [--cargo|-c <url>]" "Yellow"; return }
        $n = $MirrorName.ToLower()
        if ($script:MIRRORS.ContainsKey($n)) { Write-Color "Name '$MirrorName' is a built-in. Use 'mirror edit' to override." "Yellow"; return }
        $custom = Get-CustomMirrors
        if ($custom.ContainsKey($n)) { Write-Color "Mirror '$MirrorName' already exists. Use 'mirror edit' to update." "Yellow"; return }
        if (-not $DistUrl) { Write-Color "Error: --dist <url> is required." "Red"; return }
        $custom[$n] = @{ rustup_dist_server = $DistUrl; rustup_update_root = if ($UpdUrl) { $UpdUrl } else { $DistUrl.TrimEnd('/') + "/rustup" }; cargo_registry = if ($CargoUrl) { $CargoUrl } else { "https://rsproxy.cn/crates.io-index" } }
        Save-CustomMirrors $custom
        Write-Color "Mirror '$MirrorName' added." "Green"
        Write-Color "  dist: $($custom[$n].rustup_dist_server)" "Gray"
        Write-Color "  upd:  $($custom[$n].rustup_update_root)" "Gray"; return
    }
    # ---- edit ----
    if ($Action -eq "edit") {
        if (-not $MirrorName) { Write-Color "Usage: rvm mirror edit <name> [--dist|-d <url>] [--upd|-u <url>] [--cargo|-c <url>]" "Yellow"; return }
        $n = $MirrorName.ToLower()
        $custom = Get-CustomMirrors
        $isBuiltIn = $script:MIRRORS.ContainsKey($n)
        if (-not $isBuiltIn -and -not $custom.ContainsKey($n)) { Write-Color "Mirror '$MirrorName' not found." "Red"; return }
        # Fork: only copy from built-in if this name has NOT been customized yet.
        if ($isBuiltIn -and -not $custom.ContainsKey($n)) {
            $src = $script:MIRRORS[$n]
            $custom[$n] = @{ rustup_dist_server = $src.rustup_dist_server; rustup_update_root = $src.rustup_update_root; cargo_registry = $src.cargo_registry }
            Write-Color "Forking built-in '$MirrorName' to custom." "Yellow"
        }
        # Apply user-provided changes to whatever is currently stored (built-in fork or existing custom).
        if ($DistUrl) { $custom[$n].rustup_dist_server = $DistUrl }
        if ($UpdUrl) { $custom[$n].rustup_update_root = $UpdUrl }
        elseif (-not $UpdUrl -and $DistUrl) { $custom[$n].rustup_update_root = $DistUrl.TrimEnd('/') + "/rustup" }
        if ($CargoUrl) { $custom[$n].cargo_registry = $CargoUrl }
        Save-CustomMirrors $custom
        Write-Color "Mirror '$MirrorName' updated." "Green"; return
    }
    # ---- remove ----
    if ($Action -eq "remove") {
        if (-not $MirrorName) { Write-Color "Usage: rvm mirror remove <name>" "Yellow"; return }
        $n = $MirrorName.ToLower()
        $custom = Get-CustomMirrors
        if ($custom.ContainsKey($n)) {
            # Custom mirror (may have been forked from a built-in of the same name) — delete it.
            $custom.Remove($n); Save-CustomMirrors $custom
            $s = $cachedSettings
            if ($s.cargo_mirror_name -eq $n) {
                $s.cargo_mirror_name = "official"; $s.rustup_dist_server = $null; $s.rustup_update_root = $null; Save-Settings $s
                Write-Color "Mirror '$MirrorName' removed (was active - reset to official)." "Yellow"
            } else {
                Write-Color "Mirror '$MirrorName' removed." "Green"
            }
            return
        }
        if ($script:MIRRORS.ContainsKey($n)) { Write-Color "Cannot remove built-in mirror '$MirrorName'." "Yellow"; return }
        Write-Color "Mirror '$MirrorName' not found." "Red"; return
    }
    Write-Color "Usage: rvm mirror [list|show|set|add|edit|remove|speed]" "Yellow"
}
function Invoke-RvmHelp {
    $lines = @(
        ""
        "RVM - Rust Version Manager for Windows v$script:RVM_VERSION"
        ""
        "Commands:"
        "  install <toolchain>      Install a Rust toolchain"
        "  use <toolchain>          Switch to a toolchain"
        "  list                     List installed toolchains"
        "  list available           List available toolchains"
        "  current                  Show current toolchain"
        "  uninstall <toolchain>    Remove a toolchain"
        "  default [toolchain]      Show/set default toolchain"
        "  root [path]              Show/set RVM root directory"
        "  mirror [list|show|set|speed]   Manage mirror settings"
        "  repair                   Repair corrupted rustup metadata"
        "  doctor                   Diagnose rustup health"
        "  version                  Show RVM version"
        "  help                     Show this help"
        ""
        "Mirrors:"
        "  rvm mirror speed        # Speed test all mirrors"
        "  rvm mirror set rsproxy   # ByteDance (recommended)"
        "  rvm mirror set tuna      # Tsinghua TUNA"
        "  rvm mirror set official  # Reset"
        ""
        "Root:   $script:RVM_HOME"
        "Rustup: $script:RUSTUP_HOME_DIR"
        "Cargo:  $script:CARGO_HOME_DIR"
    )
    $lines -join "`n" | Write-Host
}
# Main dispatcher
if ([string]::IsNullOrWhiteSpace($Command)) { Invoke-RvmHelp; return }
switch ($Command.ToLower()) {
    "install"    { Invoke-RvmInstall $Arg1 }
    "use"        { Invoke-RvmUse $Arg1 }
    "list"       { if ($Arg1 -eq "available") { Invoke-RvmList -Available } else { Invoke-RvmList } }
    "current"    { Invoke-RvmCurrent }
    "uninstall"  { Invoke-RvmUninstall $Arg1 }
    "default"    { Invoke-RvmDefault $Arg1 }
    "root"       { Invoke-RvmRoot $Arg1 }
    "mirror"     { Invoke-RvmMirror $Arg1 $Arg2 }
    "repair"     { Repair-Rustup }
    "doctor"     { Invoke-RvmDoctor }
    "version"    { Invoke-RvmVersion }
    "help"       { Invoke-RvmHelp }
    "speed"     { Invoke-RvmMirror "speed" $null }
    default      { Write-Color "Unknown command: $Command. Try 'rvm help'." "Red" }
}

<#
.SYNOPSIS
    RVM Installer for Windows
.DESCRIPTION
    Install RVM (Rust Version Manager) and configure the system.
    Supports custom installation directory.
.NOTES
    Usage:
        powershell -ExecutionPolicy Bypass -File install.ps1
        powershell -ExecutionPolicy Bypass -File install.ps1 -InstallDir D:\rvm
#>

param(
    [string]$InstallDir,
    [switch]$Quiet,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RVM_VERSION = '0.1.0'
$DEFAULT_INSTALL = Join-Path $env:USERPROFILE '.rvm'
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# Banner
if (-not $Quiet) {
    Write-Host ''
    Write-Host '  ==============================================' -ForegroundColor Cyan
    Write-Host '  |                                            |' -ForegroundColor Cyan
    Write-Host "  |   RVM - Rust Version Manager v$RVM_VERSION      |" -ForegroundColor Cyan
    Write-Host '  |   For Windows                              |' -ForegroundColor Cyan
    Write-Host '  |                                            |' -ForegroundColor Cyan
    Write-Host '  ==============================================' -ForegroundColor Cyan
    Write-Host ''
}

# Determine Install Directory
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = $DEFAULT_INSTALL
}
$InstallDir = [Environment]::ExpandEnvironmentVariables($InstallDir)

# Check if RVM is already installed elsewhere
$existingRvmHome = [Environment]::GetEnvironmentVariable('RVM_HOME', 'User')
if (-not $existingRvmHome) {
    $defaultSettingsPath = Join-Path $DEFAULT_INSTALL 'settings.json'
    if (Test-Path $defaultSettingsPath) {
        try {
            $settings = Get-Content $defaultSettingsPath -Raw | ConvertFrom-Json
            if ($settings.root) { $existingRvmHome = $settings.root }
        } catch { }
    }
}

if ($existingRvmHome -and (Test-Path $existingRvmHome)) {
    if ($existingRvmHome -ne $InstallDir) {
        Write-Host ''
        Write-Host '  WARNING: RVM is already installed at:' -ForegroundColor Yellow
        Write-Host "    $existingRvmHome" -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Options:' -ForegroundColor Cyan
        Write-Host '    1. Continue: Install RVM to new location (two installations will exist)' -ForegroundColor White
        Write-Host '    2. Cancel: Press Ctrl+C to cancel' -ForegroundColor White
        Write-Host ''
        if (-not $Force) {
            $response = Read-Host '  Continue? (y/N)'
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Host '  Installation cancelled.' -ForegroundColor Yellow
                exit 0
            }
        }
    }
}

$binDir = Join-Path $InstallDir 'bin'
$rustupDir = Join-Path $InstallDir 'rustup'
$cargoDir = Join-Path $InstallDir 'cargo'

Write-Host "  Installing RVM to: $InstallDir" -ForegroundColor White
Write-Host ''

# Create all directories
foreach ($dir in @($InstallDir, $binDir, $rustupDir, $cargoDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  [OK] Created: $dir" -ForegroundColor Green
    } else {
        Write-Host "  [--] Exists:  $dir" -ForegroundColor Gray
    }
}

# Copy Script Files
$filesToCopy = @{
    'rvm.ps1'       = Join-Path $binDir 'rvm.ps1'
    'uninstall.ps1' = Join-Path $binDir 'uninstall.ps1'
}

foreach ($src in $filesToCopy.Keys) {
    $srcPath = Join-Path $SCRIPT_DIR $src
    $dstPath = $filesToCopy[$src]
    if (Test-Path $srcPath) {
        Copy-Item $srcPath $dstPath -Force
        Write-Host "  [OK] Installed: $src" -ForegroundColor Green
    } else {
        Write-Host "  [!!] Not found: $src (skipped)" -ForegroundColor Yellow
    }
}

# Create launcher batch file (uses %~dp0 to find rvm.ps1, no env var dependency)
$launcherContent = "@echo off`r`n"
$launcherContent += ":: RVM launcher - uses own directory to find rvm.ps1 (no env var dependency)`r`n"
$launcherContent += "set `"RVM_DIR=%~dp0`"`r`n"
$launcherContent += "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"%RVM_DIR%rvm.ps1`" %*`r`n"
$launcherContent += "if %errorlevel%==0 goto :refreshpath`r`n"
$launcherContent += "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%RVM_DIR%rvm.ps1`" %*`r`n"
$launcherContent += "if %errorlevel%==0 goto :refreshpath`r`n"
$launcherContent += "echo ERROR: PowerShell not found.`r`n"
$launcherContent += "exit /b 1`r`n"
$launcherContent += ":refreshpath`r`n"
$launcherContent += ":: Refresh PATH from registry so subsequent commands see latest user PATH`r`n"
$launcherContent += "for /f `"tokens=2* delims=`" %%A in ('reg query `"HKCU\Environment`" /v PATH 2^>nul ^| findstr REG_') do (`r`n"
$launcherContent += "    set `"PATH=%%B`"`r`n"
$launcherContent += ")"

$launcherPath = Join-Path $binDir 'rvm.bat'
$launcherContent | Set-Content $launcherPath -Encoding ASCII
Write-Host '  [OK] Created launcher: rvm.bat' -ForegroundColor Green

# Add bin to PATH
Write-Host ''
Write-Host '  Configuring PATH ...' -ForegroundColor Cyan

$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -split ';' -contains $binDir) {
    Write-Host "  [--] PATH already contains: $binDir" -ForegroundColor Gray
} else {
    $newPath = "$binDir;$userPath"
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Write-Host "  [OK] Added to user PATH: $binDir" -ForegroundColor Green
}

# Initialize settings.json
$settingsPath = Join-Path $InstallDir 'settings.json'
if (-not (Test-Path $settingsPath)) {
    $settings = [PSCustomObject]@{
        root               = $InstallDir
        rustup_dist_server = $null
        rustup_update_root = $null
        cargo_mirror_name  = "official"
    }
    $settings | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
    Write-Host '  [OK] Created settings.json' -ForegroundColor Green
} else {
    Write-Host '  [--] settings.json already exists' -ForegroundColor Gray
}

# Set RVM_HOME
[Environment]::SetEnvironmentVariable('RVM_HOME', $InstallDir, 'User')
Write-Host "  [OK] Set RVM_HOME=$InstallDir" -ForegroundColor Green

# Summary
Write-Host ''
Write-Host '  ==============================================' -ForegroundColor Green
Write-Host '  |        RVM installed successfully!         |' -ForegroundColor Green
Write-Host '  ==============================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Installation:  $InstallDir" -ForegroundColor White
Write-Host "  Binary:        $binDir" -ForegroundColor White
Write-Host "  Rustup data:   $rustupDir" -ForegroundColor White
Write-Host "  Cargo data:    $cargoDir" -ForegroundColor White
Write-Host ''
Write-Host '  Getting started:' -ForegroundColor Cyan
Write-Host '    1. Restart your terminal (or open a new one)' -ForegroundColor White
Write-Host '    2. Run: rvm help' -ForegroundColor White
Write-Host '    3. Install Rust: rvm install stable' -ForegroundColor White
Write-Host ''
Write-Host '  China users - set mirrors first:' -ForegroundColor Yellow
Write-Host '    rvm mirror set rsproxy' -ForegroundColor Gray
Write-Host '    (or: rvm mirror set tuna)' -ForegroundColor Gray
Write-Host ''
Write-Host '  To uninstall RVM:' -ForegroundColor Gray
Write-Host '    1. Remove installed toolchains: rvm uninstall <toolchain>' -ForegroundColor Gray
Write-Host "    2. Delete: $InstallDir" -ForegroundColor Gray
Write-Host "    3. Remove $binDir from PATH" -ForegroundColor Gray
Write-Host '    4. Remove RVM_HOME env var' -ForegroundColor Gray
Write-Host ''

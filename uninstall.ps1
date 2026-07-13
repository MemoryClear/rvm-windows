<#
.SYNOPSIS
    RVM Uninstaller for Windows
.DESCRIPTION
    Remove RVM and all its data from the system.
#>

param(
    [switch]$Force
)

Set-StrictMode -Version Latest

$RVM_HOME = if ($env:RVM_HOME) { $env:RVM_HOME } else { Join-Path $env:USERPROFILE ".rvm" }

Write-Host ""
Write-Host "  RVM Uninstaller" -ForegroundColor White
Write-Host ""

if (-not $Force) {
    Write-Host "  This will remove:" -ForegroundColor Yellow
    Write-Host "    - RVM scripts and configuration from: $RVM_HOME" -ForegroundColor White
    Write-Host "    - All installed Rust toolchains" -ForegroundColor White
    Write-Host "    - RVM_HOME, RUSTUP_HOME, CARGO_HOME and PATH entries" -ForegroundColor White
    Write-Host ""
    $confirm = Read-Host "  Are you sure? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "  Cancelled." -ForegroundColor Gray
        exit 0
    }
}

$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$cargoBin = Join-Path $RVM_HOME "cargo\bin"
$newPath = ($userPath -split ";" | Where-Object { $_ -ne "" -and $_ -ne $cargoBin }) -join ";"
[Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
Write-Host "  [OK] Removed cargo\bin from PATH" -ForegroundColor Green

[Environment]::SetEnvironmentVariable("RVM_HOME", $null, "User")
[Environment]::SetEnvironmentVariable("RUSTUP_HOME", $null, "User")
[Environment]::SetEnvironmentVariable("CARGO_HOME", $null, "User")
Write-Host "  [OK] Removed RVM_HOME, RUSTUP_HOME, CARGO_HOME" -ForegroundColor Green

$ri = Get-Command Rmove-Item
if (Test-Path $RVM_HOME) {
    & $ri $RVM_HOME -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $RVM_HOME)) {
        Write-Host "  [OK] Removed: $RVM_HOME" -ForegroundColor Green
    } else {
        Write-Host "  [!!] Directory not fully removed: $RVM_HOME" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [--] $RVM_HOME not found (already removed?)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  RVM has been uninstalled." -ForegroundColor Green
Write-Host "  Restart your terminal for changes to take effect." -ForegroundColor Yellow
Write-Host ""
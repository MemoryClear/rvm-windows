@echo off
:: RVM launcher - uses own directory to find rvm.ps1 (no env var dependency)
set "RVM_DIR=%~dp0"
set "PS_FILE=%RVM_DIR%rvm.ps1"
pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS_FILE:\=\\%' %*" 2>nul
if %errorlevel%==0 goto :refreshpath
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS_FILE:\=\\%' %*" 2>nul
if %errorlevel%==0 goto :refreshpath
echo ERROR: PowerShell not found. Check that PowerShell is installed.
exit /b 1
:refreshpath
:: Refresh PATH from registry so subsequent commands see latest user PATH
for /f "tokens=2* delims=" %%A in ('reg query "HKCU\Environment" /v PATH 2^>nul ^| findstr REG_') do (
    set "PATH=%%B"
)

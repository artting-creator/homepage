@echo off
chcp 65001 >nul
rem ---------------------------------------------------------------
rem  Git menu launcher.
rem  This file stays ASCII-only on purpose: cmd.exe misparses UTF-8
rem  batch files that contain non-ASCII text. All Chinese UI text
rem  lives in git-menu.ps1 instead.
rem ---------------------------------------------------------------

where pwsh >nul 2>&1
if not errorlevel 1 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0git-menu.ps1"
  goto :eof
)

where powershell >nul 2>&1
if not errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0git-menu.ps1"
  goto :eof
)

echo.
echo   PowerShell not found. Please run git-menu.ps1 manually.
echo.
pause

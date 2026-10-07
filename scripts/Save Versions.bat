@echo off
setlocal
cd /d "%~dp0"
title Save Versions

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo Node.js is not installed. Get it from https://nodejs.org then run this again.
  echo.
  pause
  exit /b 1
)

echo.
echo  =====  Save Versions  =====
echo.
echo  Before you continue, in Roblox Studio:
echo    1. Press "Save snapshot" in the Asset Versioning panel
echo    2. Save your place with Ctrl+S
echo.
set "MSG="
set /p "MSG= What did you change? (a few words, or press Enter to skip): "
set "MSG=%MSG:"='%"

set "EXTRA="
if "%MSG%"=="" goto run
set "PUSH="
set /p "PUSH= Send it to the team now? (y/N): "
if /i "%PUSH%"=="y" set "EXTRA=--push"

:run
node "tools\asset-versioning\save.js" --message "%MSG%" %EXTRA%
echo.
pause

@echo off
setlocal
cd /d "%~dp0"
title Asset Versioning setup

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo Node.js is not installed. Get it from https://nodejs.org then run this again.
  echo.
  pause
  exit /b 1
)

node scripts\setup.js %*
echo.
pause

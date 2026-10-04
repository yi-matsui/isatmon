@echo off
rem  Mock mode (no device needed): double-click to try the dashboard
cd /d "%~dp0"
start "" "%~dp0index.html"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Monitor.ps1" -Mock
pause

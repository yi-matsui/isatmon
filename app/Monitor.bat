@echo off
rem  Monitor.bat          -> real device
rem  Monitor.bat -Mock    -> mock data
cd /d "%~dp0"
start "" "%~dp0index.html"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Monitor.ps1" %*
pause

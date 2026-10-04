@echo off
rem  IsatIo.cs -> IsatIo.exe  (uses the csc.exe bundled with Windows .NET Framework 4.x)
cd /d "%~dp0"
set CSC=%windir%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%windir%\Microsoft.NET\Framework\v4.0.30319\csc.exe
"%CSC%" /nologo /target:exe /out:IsatIo.exe IsatIo.cs
if errorlevel 1 (echo BUILD FAILED) else (echo BUILD OK: IsatIo.exe)
pause

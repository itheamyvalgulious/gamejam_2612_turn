@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
set "cargo_exit=%errorlevel%"
if not %cargo_exit%==0 pause
exit /b %cargo_exit%

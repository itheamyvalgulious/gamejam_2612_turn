@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
set "level_exit=%errorlevel%"
if not %level_exit%==0 pause
exit /b %level_exit%

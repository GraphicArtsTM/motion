@echo off
rem Show whether the bot is running.
rem All messages are in Russian inside scripts\windows\local.ps1 (this file stays ASCII on purpose).
cd /d "%~dp0"
set "PSARGS="
if /i "%~1"=="silent" set "PSARGS=-Silent"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\local.ps1" -Action status %PSARGS%

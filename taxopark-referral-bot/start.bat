@echo off
rem Start the referral bot (no Docker). 'start.bat silent' - no window pause, used by autostart.
rem All messages are in Russian inside scripts\windows\local.ps1 (this file stays ASCII on purpose).
cd /d "%~dp0"
set "PSARGS="
if /i "%~1"=="silent" set "PSARGS=-Silent"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\local.ps1" -Action start %PSARGS%

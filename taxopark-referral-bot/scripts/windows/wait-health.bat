@echo off
rem Ждёт, пока веб-сервис ответит на /health (до 3 минут).
set /a HTRIES=0
:loop
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:8000/health; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 exit /b 0
set /a HTRIES+=1
if %HTRIES% geq 60 exit /b 1
timeout /t 3 /nobreak >nul
goto :loop

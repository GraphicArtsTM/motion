@echo off
rem Читает переменную из .env: call scripts\windows\read-env.bat ИМЯ  ->  %ENV_VALUE%
set "ENV_VALUE="
if not exist ".env" exit /b 0
for /f "usebackq eol=# tokens=1,* delims==" %%a in (".env") do (
  if /i "%%a"=="%~1" set "ENV_VALUE=%%~b"
)
exit /b 0

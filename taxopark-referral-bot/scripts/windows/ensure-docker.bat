@echo off
rem Проверяет, что Docker Desktop установлен и запущен; при необходимости запускает его и ждёт.
where docker >nul 2>&1
if errorlevel 1 goto :no_docker
docker info >nul 2>&1
if not errorlevel 1 exit /b 0
echo  Запускаю Docker Desktop, подождите...
if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
set /a DTRIES=0
:wait_docker
timeout /t 3 /nobreak >nul
docker info >nul 2>&1
if not errorlevel 1 exit /b 0
set /a DTRIES+=1
if %DTRIES% geq 80 goto :docker_timeout
goto :wait_docker

:no_docker
echo.
echo  Docker Desktop не установлен.
echo  1. Скачайте и установите его: https://www.docker.com/products/docker-desktop/
echo  2. Перезагрузите компьютер.
echo  3. Снова запустите start.bat
start "" https://www.docker.com/products/docker-desktop/
exit /b 1

:docker_timeout
echo  Docker не запустился за 4 минуты. Откройте Docker Desktop вручную и повторите.
exit /b 1

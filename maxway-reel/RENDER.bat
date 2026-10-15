@echo off
rem ============================================================
rem  MAXWAY reel - one-click render (Windows 10/11)
rem  1) installs Python if missing   2) downloads ffmpeg (with zscale)
rem  3) installs Python libraries    4) downloads sources from Google Drive
rem  5) renders 3 high-quality videos into the "out" folder
rem ============================================================
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
title MAXWAY reel render
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

echo.
echo  MAXWAY reel - render of 3 videos (1080x1920, 60 fps)
echo  -----------------------------------------------------
echo.

rem ---------- 1. Python ----------
set "PY="
py -3 -c "import sys; assert sys.version_info >= (3, 9)" >nul 2>nul && set "PY=py -3"
if not defined PY python -c "import sys; assert sys.version_info >= (3, 9)" >nul 2>nul && set "PY=python"
if not defined PY if exist "%LocalAppData%\Programs\Python\Python312\python.exe" set "PY="%LocalAppData%\Programs\Python\Python312\python.exe""
if not defined PY (
  echo [1/5] Python not found - installing Python 3.12 ...
  winget install -e --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements >nul 2>nul
  if not exist "%LocalAppData%\Programs\Python\Python312\python.exe" (
    echo       winget unavailable - downloading installer from python.org ...
    curl -L --fail -o "%TEMP%\python-3.12.7-amd64.exe" https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe || goto :fail
    "%TEMP%\python-3.12.7-amd64.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_test=0 || goto :fail
  )
  if exist "%LocalAppData%\Programs\Python\Python312\python.exe" set "PY="%LocalAppData%\Programs\Python\Python312\python.exe""
)
if not defined PY (
  echo ERROR: could not install Python. Install it from https://www.python.org and run this file again.
  goto :fail
)
echo [1/5] Python: OK

rem ---------- 2. ffmpeg (portable, with zscale for iPhone HDR) ----------
if not exist "tools\ffmpeg\bin\ffmpeg.exe" (
  echo [2/5] Downloading ffmpeg ...
  if not exist tools mkdir tools
  curl -L --fail -o "tools\ffmpeg.zip" https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip || goto :fail
  tar -xf "tools\ffmpeg.zip" -C tools || goto :fail
  for /d %%D in (tools\ffmpeg-*win64-gpl*) do move "%%D" "tools\ffmpeg" >nul
  del "tools\ffmpeg.zip"
)
if not exist "tools\ffmpeg\bin\ffmpeg.exe" (
  echo ERROR: ffmpeg was not unpacked.
  goto :fail
)
set "PATH=%~dp0tools\ffmpeg\bin;%PATH%"
echo [2/5] ffmpeg: OK

rem ---------- 3. Python libraries (local .venv) ----------
if not exist ".venv\Scripts\python.exe" (
  echo [3/5] Creating virtual environment ...
  %PY% -m venv .venv || goto :fail
)
".venv\Scripts\python.exe" -c "import numpy, cv2, PIL" >nul 2>nul
if errorlevel 1 (
  echo [3/5] Installing libraries: numpy, opencv, pillow ...
  ".venv\Scripts\python.exe" -m pip install --upgrade pip >nul
  ".venv\Scripts\python.exe" -m pip install -r requirements.txt || goto :fail
)
echo [3/5] Libraries: OK

rem ---------- 4-5. sources + render ----------
echo [4/5] Sources and render (this takes a while, see progress below) ...
".venv\Scripts\python.exe" render_all.py %* || goto :fail

echo.
echo [5/5] DONE! Videos are in the "out" folder:
dir /b out\MAXWAY_*.mp4
start "" "%~dp0out"
echo.
pause
exit /b 0

:fail
echo.
echo ===== ERROR: render stopped. Read the message above. =====
pause
exit /b 1

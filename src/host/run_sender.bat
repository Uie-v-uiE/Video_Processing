@echo off
setlocal
rem Resolve python: PATH first, then common local runtimes
set PY=
where python >nul 2>nul && set PY=python
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set PY="%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY if exist "D:\Software\Xiaomi_MiMo\XiaomiMiMo\Xiaomi MiMo\resources\runtimes\win32-x64\python\python.exe" set PY="D:\Software\Xiaomi_MiMo\XiaomiMiMo\Xiaomi MiMo\resources\runtimes\win32-x64\python\python.exe"
if not defined PY (
  echo [ERR] python not found. Install Python 3.10+ or edit this bat.
  exit /b 1
)

set HOSTDIR=%~dp0
set BOARD_IP=192.168.1.10
set PC_IP=192.168.1.100
if not "%~1"=="" set BOARD_IP=%~1
if not "%~2"=="" set PC_IP=%~2

echo [RUN] UDP %PC_IP% -^> %BOARD_IP%:5001  built-in anim @30fps
echo       Ctrl+C to stop
%PY% "%HOSTDIR%video_sender.py" --ip %BOARD_IP% --src %PC_IP% --fps 30 --anim
endlocal

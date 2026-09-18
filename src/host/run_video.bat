@echo off
setlocal
set PY=
where python >nul 2>nul && set PY=python
if not defined PY if exist "D:\Software\Xiaomi_MiMo\XiaomiMiMo\Xiaomi MiMo\resources\runtimes\win32-x64\python\python.exe" set PY="D:\Software\Xiaomi_MiMo\XiaomiMiMo\Xiaomi MiMo\resources\runtimes\win32-x64\python\python.exe"
if not defined PY (
  echo [ERR] python not found.
  exit /b 1
)

set HOSTDIR=%~dp0
set BOARD_IP=192.168.1.10
set PC_IP=192.168.1.100

if "%~1"=="" (
  echo Usage: run_video.bat path\to\video.mp4 [board_ip] [pc_ip]
  echo Example: run_video.bat D:\Videos\demo.mp4
  echo          run_video.bat demo.mjpeg
  exit /b 1
)
if not exist "%~1" (
  echo [ERR] file not found: %~1
  exit /b 1
)
if not "%~2"=="" set BOARD_IP=%~2
if not "%~3"=="" set PC_IP=%~3

echo [RUN] %1 -^> %BOARD_IP%:5001 @30fps
%PY% "%HOSTDIR%video_sender.py" --ip %BOARD_IP% --src %PC_IP% --video "%~1" --fps 30
endlocal

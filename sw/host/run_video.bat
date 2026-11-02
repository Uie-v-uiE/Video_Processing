@echo off
setlocal
set PY=D:\Software\Xiaomi_MiMo\XiaomiMiMo\Xiaomi MiMo\resources\runtimes\win32-x64\python\python.exe
set FF=D:\Software\Ghost\FFmpeg\ffmpeg.exe
set ROOT=%~dp0..\..
if "%~1"=="" (
  echo Usage: run_video.bat path\to\video.mp4
  echo Example: run_video.bat D:\Videos\demo.mp4
  exit /b 1
)
if not exist "%~1" (
  echo [ERR] file not found: %~1
  exit /b 1
)
pushd "%ROOT%"
"%PY%" "sw\host\video_sender.py" --ip 192.168.1.10 --src 192.168.1.100 --video "%~1" --fps 30
popd

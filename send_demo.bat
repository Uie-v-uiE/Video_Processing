@echo off
rem send_demo.bat - double-click demo: ping the board, then stream the built-in test video.
rem It needs only Python 3 (standard library). ffmpeg is optional: it is used only when
rem you pass your own video file with:  send_demo.bat my.mp4
setlocal
cd /d "%~dp0"
chcp 65001 >nul
where python >nul 2>&1
if errorlevel 1 (
  echo [ERR] python not found in PATH. Install Python 3 and open this file again.
  pause
  exit /b 1
)
if "%~1"=="" (
  echo [DEMO] ping board 192.168.1.10 then push built-in test pattern for 12 s
  python src\host\video_sender.py --demo
) else (
  echo [DEMO] pushing "%~1" - decoding needs ffmpeg
  python src\host\video_sender.py --input "%~1" --demo
)
echo.
echo [DONE] exit code %ERRORLEVEL%. Look at the screen: the moving white line and the
echo        red block prove frames are swapped atomically. Press any key.
pause >nul

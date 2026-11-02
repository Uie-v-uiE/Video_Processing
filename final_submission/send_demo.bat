@echo off
rem send_demo.bat - Purpose: double-click demo entry for the panel. Step 1 pings the board and
rem        leaves the normal ping output on screen; step 2 streams the BUILT-IN test pattern for
rem        DEMO_SECONDS (default 300 s = 5 minutes) so the picture can be watched and photographed
rem        without the clip ending mid-sentence. Tool behind it: src/host/video_sender.py --demo
rem        (Python 3 standard library only; ffmpeg is needed only for your own video file).
rem Usage: send_demo.bat            = ping + 300 s built-in pattern at 192.168.1.10:5001
rem        send_demo.bat my.mp4      = ping + stream your own file (needs ffmpeg)
rem        Change the length or the address by editing the two set lines below.
rem Exit code: whatever video_sender.py returns (0 = finished normally).
setlocal
cd /d "%~dp0"
chcp 65001 >nul
set BOARD_IP=192.168.1.10
set DEMO_SECONDS=300
where python >nul 2>&1
if errorlevel 1 (
  echo [ERR] python not found in PATH. Install Python 3 and open this file again.
  pause
  exit /b 1
)
echo [STEP 1] ping %BOARD_IP%
ping -n 4 %BOARD_IP%
echo.
if "%~1"=="" (
  echo [STEP 2] push the built-in test pattern for %DEMO_SECONDS% s
  python src\host\video_sender.py --demo --ip %BOARD_IP% --seconds %DEMO_SECONDS%
) else (
  echo [STEP 2] pushing "%~1" - decoding needs ffmpeg
  python src\host\video_sender.py --input "%~1" --demo --ip %BOARD_IP% --seconds %DEMO_SECONDS%
)
set RC=%ERRORLEVEL%
echo.
echo [DONE] exit code %RC%. On the panel the moving white line and the red block prove frames
echo        are swapped atomically; the counters behind it are readable over the serial port and
echo        by JTAG (see report/host_guide.md). Press any key.
pause >nul
exit /b %RC%

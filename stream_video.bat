@echo off
REM stream_video.bat -- double-click to push a REAL video to the board over the self-developed
REM UDP link. The panel path is 512x300 RGB565, so ffmpeg decodes + scales to exactly that and
REM pipes raw frames into src/host/video_sender.mjs (mode `--file -`).
REM
REM   usage:   stream_video.bat [video.mp4] [fps]
REM   default: video = D:\UserData\Downloads\a.mp4   fps = 30
REM
REM Notes worth keeping in mind (all are deliberate):
REM   * -re makes ffmpeg emit at real time, so the frame rate on the wire IS the number you pass.
REM     video_sender's own pacer still limits the intra-frame burst (15 MB/s) -- that guard is what
REM     keeps the board's input FIFO from overflowing (ISSUES: 221 packets at line rate blew it up).
REM   * scale=512:288 + pad to 512:300 keeps 16:9 instead of stretching it; the 6 black rows at
REM     top and bottom are the price, and the panel's 2x vertical stretch makes them visible but
REM     symmetric.
REM   * Exit with Ctrl+C. The board hands the picture back automatically (arbiter, ISSUES #53).
setlocal
set "VIDEO=%~1"
set "FPS=%~2"
if "%VIDEO%"=="" set "VIDEO=D:\UserData\Downloads\a.mp4"
if "%FPS%"=="" set "FPS=30"

cd /d "%~dp0"

where ffmpeg >nul 2>nul
if errorlevel 1 (
  echo [ERR] ffmpeg not found in PATH. Install it or put ffmpeg.exe next to this script.
  pause
  exit /b 1
)
where node >nul 2>nul
if errorlevel 1 (
  echo [ERR] node not found in PATH.
  pause
  exit /b 1
)
if not exist "%VIDEO%" (
  echo [ERR] video not found: "%VIDEO%"
  echo        drop a file on this .bat, or run: stream_video.bat D:\path\to\clip.mp4 30
  pause
  exit /b 1
)

echo [INFO] pushing "%VIDEO%" at %FPS% fps to 192.168.1.10:5001  (512x300 RGB565)
echo [INFO] stop with Ctrl+C.  Board side: MODE should show ETH while this runs.
echo.

ffmpeg -hide_banner -loglevel error -re -i "%VIDEO%" -vf "scale=512:288,pad=512:300:0:6" -pix_fmt rgb565le -f rawvideo - | node src\host\video_sender.mjs --file - --fps %FPS%

echo.
echo [INFO] sender finished.
pause
endlocal

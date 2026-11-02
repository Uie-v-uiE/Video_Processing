@echo off
rem run_test.bat - Purpose: double-click entry for the ONE-CLICK TEST tool, Node side:
rem        src/host/one_click_test.mjs  (4 steps: ping the board -> open the readback path ->
rem        push the built-in clip from data/ -> compare the counters).
rem        All paths are relative to this file's folder (the repo root); extra args are forwarded,
rem        e.g.  run_test.bat --dry-run        run_test.bat --ip 192.168.1.20 --frames 2
rem Exit code: 0 = all four steps PASS, 1 = any step FAIL, 2 = bad argument or missing clip file.
setlocal
cd /d "%~dp0"
chcp 65001 >nul
where node >nul 2>&1
if errorlevel 1 (
  echo [ERR] node not found in PATH. Install Node 24, or use run_test.sh which calls the Python side.
  pause
  exit /b 1
)
node src\host\one_click_test.mjs %*
set RC=%ERRORLEVEL%
echo.
echo [DONE] The four conclusion lines above are the readings; the verdict word is the last field
echo        of each line (PASS / FAIL / NOT_MEASURED). Exit code %RC%: 0 all PASS, 1 a step FAIL,
echo        2 argument or clip file problem.
if not "%RUN_TEST_NO_PAUSE%"=="" exit /b %RC%
pause >nul
exit /b %RC%

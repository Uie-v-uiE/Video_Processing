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
if "%~1"=="" (
  echo Usage: run_serial.bat COM5
  exit /b 1
)
%PY% "%HOSTDIR%serial_ctrl.py" --port %~1
endlocal

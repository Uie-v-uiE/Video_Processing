@echo off
setlocal
set PY=D:\Software\Xiaomi_MiMo\XiaomiMiMo\Xiaomi MiMo\resources\runtimes\win32-x64\python\python.exe
set ROOT=%~dp0..\..
pushd "%ROOT%"
"%PY%" "sw\host\video_sender.py" --ip 192.168.1.10 --src 192.168.1.100 --fps 30
popd

# 工程路径与复现步骤

## 1. 本机路径

| 用途 | 路径 |
|------|------|
| 仓库根目录 | `D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline` |
| Vivado 可执行文件 | `D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat` |
| Vitis | `D:\Software\Vivado\2025.2.1\Vitis` |
| 完整 FFmpeg | `C:\Users\wenqu\scoop\apps\ffmpeg\9.0.1\bin\ffmpeg.exe` |
| 上位机 Python | MiMo 运行时 Python 3.12（含 numpy/Pillow） |

## 2. Vivado 工程

| 项 | 位置 |
|----|------|
| 系统工程（PS+PL） | `vivado_system/zynq_video_sys.xpr` |
| 生成脚本 | `tcl/build_system_axigpio.tcl` |
| 管脚约束 | `constraints/rk_zynq7020.xdc` |
| 比特流输出 | `output/system.bit` |
| 硬件平台 XSA | `output/system.xsa` |
| 时序报告 | `output/timing_summary.rpt`（实现后导出） |

**从零生成：**

```bat
cd /d D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl
%VIVADO% -mode batch -source tcl\program_system.tcl
```

`vivado_system/` 在 `.gitignore` 中，不入库；用 TCL 可完全重建。

## 3. Vitis 工程

| 项 | 位置 |
|----|------|
| 工作区 | `vitis_udp/` |
| Platform | `vitis_udp/platform` |
| 应用 | `vitis_udp/app_component` |
| 应用源码 | `vitis_udp/app_component/src/main.c` |
| 与仓库同步的源码 | `sw/ps/main.c`（改代码请两处一致） |
| ELF | `vitis_udp/app_component/build/app_component.elf` |
| ps7_init | `vitis_udp/app_component/_ide/psinit/ps7_init.tcl` |
| Launch 用 bitstream | `vitis_udp/app_component/_ide/bitstream/system.bit` |

**改 RTL 后：** 先 Vivado 出新 bit，再把 `output/system.bit` 拷到  
`vitis_udp/app_component/_ide/bitstream/system.bit`，然后 Vitis Run。

**改 PS 代码后：** 同步 `sw/ps/main.c`，Build app_component，Run。

Platform 的 `libsrc` / `export` 不入库；需从 `output/system.xsa` 重建 Platform，并勾选 **lwip220**。

## 4. 上位机

| 项 | 位置 |
|----|------|
| 发送脚本 | `sw/host/video_sender.py` |
| 一键动画 | `sw/host/run_sender.bat` |
| 一键视频 | `sw/host/run_video.bat` |
| 依赖 | `sw/host/requirements.txt` |

```bat
sw\host\run_sender.bat
sw\host\run_video.bat D:\path\to\video.mp4
```

## 5. 仿真

```bat
%VIVADO% -mode batch -source sim\run_sim.tcl
```

金标图：

```bat
%PYTHON% scripts\golden_model.py
```

输出到 `sim_out/`。

## 6. 从零复现检查单

1. [ ] 安装 Vivado/Vitis 2025.2.1，许可证可用  
2. [ ] `tcl/build_system_axigpio.tcl` 生成 bit + xsa  
3. [ ] Vitis 从 xsa 建 Platform，启用 lwip220，链路 `CONFIG_LINKSPEED1000`  
4. [ ] 建 empty application，源码用 `sw/ps/main.c`  
5. [ ] Build Platform → Build app → Run  
6. [ ] PC 网卡 192.168.1.100/24，接 PS ETH  
7. [ ] `run_sender.bat` 或 `run_video.bat`  
8. [ ] 串口验证 `FILL` / `00111` / `STAT`  

## 7. 常用命令速查

| 目的 | 命令 |
|------|------|
| 全量实现 bit | `tcl/build_system_axigpio.tcl` |
| 下载 bit | `tcl/program_system.tcl` |
| 仿真 | `sim/run_sim.tcl` |
| 金标图 | `scripts/golden_model.py` |
| 动画推流 | `sw/host/run_sender.bat` |
| 视频推流 | `sw/host/run_video.bat <file>` |
| 串口效果 | `00111` / `00000` |
| 串口诊断 | `FILL` / `STAT` |

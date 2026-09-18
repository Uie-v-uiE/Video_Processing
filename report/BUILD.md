# 构建与上板（第三版）

## 1. 本机路径

| 用途 | 路径 |
|------|------|
| 仓库根 | `D:\Xilinx\Prj\ADD\Video_Pipeline-main\` |
| Vivado | `D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat` |
| Vitis | `D:\Software\Vivado\2025.2.1\Vitis\bin\vitis.bat` |
| Vivado 工程 | `vivado_system\zynq_video_sys.xpr`（已 gitignore，可用 TCL 重建） |
| 构建脚本 | `build\tcl\build_system_axigpio.tcl` |
| 下载脚本 | `build\tcl\program_system.tcl` |
| 上位机 | `src\host\` |
| PS 源码 | `src\ps\main.c` |
| Git | `D:\Git\Git\bin\git.exe`（若 PATH 无 git 用全路径） |

---

## 2. 常用命令

```bat
cd /d D:\Xilinx\Prj\ADD\Video_Pipeline-main
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat

:: 从零生成 bit + xsa
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl

:: 下载 bit
%VIVADO% -mode batch -source build\tcl\program_system.tcl

:: 仿真（含 zoom）
%VIVADO% -mode batch -source sim\run_sim.tcl
%VIVADO% -mode batch -source sim\run_zoom_only.tcl

:: 增量重跑（改 RTL/约束后）
%VIVADO% -mode batch -source build\tcl\rebuild_cdc_fix.tcl

:: 推流
cd src\host
run_sender.bat
run_video.bat D:\path\to\video.mp4
run_serial.bat COM5
```

产物：`build\system.bit`、`build\system.xsa`、`build\*.rpt`。

---

## 3. 上板顺序

1. 12V 电源、HDMI 1024×600、USB（JTAG+UART）
2. 网线接 **PL 网口**（非 PS 口）
3. 下载 bit
4. （串口需要）Vitis Run PS ELF——bit 会复位 PS
5. PC：`192.168.1.100/24`
6. `ping 192.168.1.10`
7. `run_sender.bat` 推流
8. HDMI：左原图 / 右缩放+效果；OSD 见 FPS/ANG/EN；右屏自动缩放循环

---

## 4. 网络参数

| 项 | 值 |
|----|-----|
| 板卡 PL IP | `192.168.1.10` |
| UDP 端口 | **5001** |
| BOARD_MAC | `00:11:22:33:44:55` |
| PC IP | `192.168.1.100/24` |

---

## 5. 串口命令摘要

| 命令 | 作用 |
|------|------|
| `00000` / `10000` / `01000` / `00111` | 效果位 |
| `SRC0` / `SRC1` | 彩条 / 视频 |
| `TH80` | 阈值 |
| `ZOOM0` / `ZOOM1` | 缩放关/开（PL 常开时 GPIO 预留） |
| `FILL` / `STAT` | 诊断 |

效果位：gray binary blur sobel invert（bit0 在左）。

---

## 6. 报告

实现后已导出：

- `build/timing_summary.rpt`
- `build/utilization.rpt`
- `build/power.rpt`
- `build/clock_util.rpt`

手工补报告：

```tcl
open_run impl_1
report_timing_summary -file build/timing_summary.rpt
report_power -file build/power.rpt
```

约束与脚本说明见仓库根 `README.md` 与 `docs/`（本地）。

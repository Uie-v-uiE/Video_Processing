# 构建与上板

> 版本注记：本文最早写于第三版，命令与脚本路径至今仍适用；**版本相关的数字**（哪块 bit、
> 门禁多少）不在这里，看 `report/DEMO_SCRIPT.md` §0 与 `report/OVERNIGHT_LOG.md` §9.5。

## 1. 本机路径

| 用途 | 路径 |
|------|------|
| 仓库根 | `D:\Xilinx\Prj\pro\Video_Processing\`（旧文档与一次性脚本里曾是**另一份工作副本**根 `D:\Xilinx\Prj\ADD\Video_Pipeline-main`；那棵树今天还在、停在 v3 时代（git HEAD `7cde28d`）⇒ 脚本指过去**不会报错，只会静默改错树**，比失败更坏；2026-09-23 已全部改成自适应路径） |
| Vivado | `D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat` |
| Vitis | `D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat`（批处理式跑法；无后缀的 `xsdb` 是 Linux 包装脚本，Git Bash 下会报 rlwrap 缺失） |
| Vivado 工程 | `vivado_system\zynq_video_sys.xpr`（已 gitignore，可用 TCL 重建） |
| 构建脚本 | `build\tcl\build_system_axigpio.tcl` |
| 下载脚本 | `build\tcl\program_system.tcl`；PS 起来用 `build\tcl\ps_jtag_boot.tcl`（会自动从 xsa 解出 `ps7_init.tcl`） |
| 第二块板 | `ku5p\build\tcl\ku5p_build.tcl`（`KU5P_SYNTH_ONLY=1` 只综合；正式产物在 `ku5p\build\`，实验跑法加 `KU5P_TAG=<名>` 落到 `ku5p\build\exp_<名>\` 不盖正式报告） |
| 上位机 | `src\host\`（推流 `video_sender.mjs`、健康读回 `health_read.mjs`、KU5P 遥测 `ku5p_stats.mjs`） |
| PS 源码 | `src\ps\main.c`（编译：`node build\ps_app.mjs`，需要 `PS_BSP`） |
| Git | `D:\Software\Git\Git\bin\git.exe`（**旧的 `D:\Git\Git\bin` 在这台机器上已不存在**；PATH 里也有 `git`） |

---

## 2. 常用命令

```bat
cd /d D:\Xilinx\Prj\pro\Video_Processing
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

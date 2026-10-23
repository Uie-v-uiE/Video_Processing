# 器件、工具链与第三方声明

## 1 器件与板卡

| 项 | 取值 |
|---|---|
| FPGA | `xc7z020clg484-2`（Zynq-7020，-2 速度等级） |
| 板卡 | `RK-ZYNQ7020-F` |
| 外部存储 | 板载 DDR3；QSPI NOR；microSD |
| 网络 | PL 侧 RJ45，RTL8211F-CG |
| 显示 | HDMI，1024×600 面板 |

## 2 工具链

| 工具 | 版本/用途 |
|---|---|
| Vivado | 2025.2.1，综合、实现、位流、XSA、时序/资源/CDC/功耗报告 |
| Vitis | 2025.2.1，平台与 FSBL 构建；PS 应用也由脚本直接编译 |
| 仿真 | Vivado xsim；ModelSim 作为可选快速回归 |
| 主机 | Python 3（标准库）、Node.js 18+、PowerShell 5+ |
| 可选 | ffmpeg，仅用于把 mp4 解成裸帧；内置测试图不需要 |

时序、资源、功耗数字都在上表工具版本和 `xc7z020clg484-2` 上测得；换工具版本或器件需要重跑，数字不能直接沿用。

## 3 第三方与自研边界

- 使用 Xilinx 提供的 PS7、AXI GPIO、AXI HP 等 IP 与 Vitis 运行库；这些组件的版权归各自权利人。
- RTL 视频通路、以太网协议栈、PS 裸机固件、上位机推流/遥测/自检工具由本项目编写；未使用第三方视频处理 IP。
- 仿真中的 PHY/AXI 从机模型在 `sim/prim/` 内，为本项目测试用模型，不声称是厂商模型。
- 本项目**不使用 PYNQ**。技能包里的 `frameworks/pynq-overlay-development` 是通用框架技能，作为独立技能提交，不声称在本项目上板验证。
- 技能包里的 Vivado/板卡框架卡是通用做法，具体到本项目的读数以 `build/reports/` 和 `board/measured/` 为准。

## 4 交付物来源

- `board/project/system.bit`、`system.xsa`、`ps_app.elf` 由本仓库的 `build/build.tcl`、`build/vitis/rebuild_vitis.py` 和 `build/ps/build_ps_app.py` 生成。
- `board/flash/BOOT.bin` 由 `board/scripts/make_boot_image.sh` 用包内 FSBL、位流和应用打包；三件套 MD5 在 `boot_manifest.txt`。
- `board/vivado` 是构建脚本生成并整理过的工程；`board/vitis` 是平台描述，实际平台由 `build/vitis/rebuild_vitis.py` 重建。
- 技术文档与海报是本地交付件，不在 GitHub；正文源在 `report/design-report.md`。

## 5 复现环境边界

- 网络地址：PC `192.168.1.100/24`，板卡 `192.168.1.10/24`；视频端口 `UDP 5001`，遥测端口 `UDP 1234`。
- 串口：`COM6`（按机器识别），115200 8N1。
- 工具路径通过环境变量传入：`VP_VIVADO_BIN`、`VP_XSDB`、`VP_VITIS_WS`、`PS_CC`、`PS_BSP`、`MSIM_BIN`；脚本不写死本机路径。
- 工具版本、器件型号和板卡型号只在本页与 README 的实现读数中定值；其他文档引用同一组值。

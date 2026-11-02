# 多源视频同帧对照处理系统

Zynq-7020 上的视频处理工程。系统从千兆网口接收 512×300、RGB565 视频，在 PL 内完成帧重组、DDR 乒乓缓存、缩放、旋转、双线性插值、六级效果、同帧左右对照和 OSD，最终输出 1024×600 HDMI。像素数据不经过 PS，PS 仅负责命令解析、状态回读和 SD 卡回放。

## 主要功能

- 网络视频接收：RGMII、MAC、UDP 过滤、按帧内偏移重组；整帧字节、行覆盖位图和坏包计数同时满足才提交。
- 显示与处理：缩放、任意角度旋转、双线性插值、六级效果处理；效果链延迟固定为 15 个像素时钟。
- 同帧对照：屏幕竖缝左侧为原图，右侧为同一帧的处理结果，两侧共用几何运算和源坐标。
- 状态监测：帧数、坏包、处理窗完整性、链路帧间隔和时延可通过串口、UDP 遥测和 AXI GPIO 读取。
- 启动与回放：QSPI 启动、SD 卡帧序列回放、三阶段链路故障注入自检。

## 目录

| 目录 | 内容 |
|---|---|
| `src/rtl/` | PL 源码：顶层、以太网、显示、几何、效果、AXI、HDMI |
| `src/ps/` | PS 裸机程序：`main.c`、`sd_play.c`、链接脚本 |
| `src/host/` | PC 侧工具：推流、遥测、链路自检、串口检查 |
| `src/constraints/` | 引脚、时钟组、CDC、RGMII/HDMI 约束 |
| `sim/` | 仿真台架、原语模型和判定结果 |
| `build/` | Vivado/Vitis 构建脚本、仿真入口、实现报告 |
| `board/` | Vivado/Vitis 工程、上板脚本、实测日志、QSPI 镜像、比对数据 |
| `data/` | 测试输入、参考图像、指标表 |
| `skill/` | 开发过程中整理的技能包，共 59 条 |
| `report/` | 设计报告、验证、优化、复现、协作记录和接口表 |
| `README.md` / `LICENSE` | 项目说明与 MIT 许可证 |

## 构建

完整的 PL 构建入口是 `build/build.tcl`：

```bash
vivado -mode batch -source build/build.tcl
```

该脚本调用 `build/tcl/build_system_axigpio.tcl`，完成建工程、块设计、综合、实现、位流、XSA 以及时序、资源、CDC、方法学和功耗报告。只建工程和块设计可使用：

```bash
vivado -mode batch -source build/build.tcl -tclargs bd_only
```

`build/tcl/stage_board_projects.tcl` 不是第二次综合或实现。它把已经生成的 Vivado 工程复制到 `board/vivado/`，并打开复制后的工程核对器件、约束和块设计文件是否齐全，属于上板工程整理与验证脚本。

PS 应用和启动镜像由独立脚本生成：

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<平台构建生成的 BSP 目录> PS_OUT=board/project/ps_app.elf \
python build/ps/build_ps_app.py

VP_VIVADO_BIN=<Vitis>/bin bash board/scripts/make_boot_image.sh
```

## 仿真

```bash
MSIM_BIN=<ModelSim>/win64 bash build/sim/run_msim.sh rows udp_reasm reasm_bounds \
    udp_telemetry eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
MSIM_BIN=<ModelSim>/win64 bash build/sim/run_msim.sh video_pipeline_top
```

每支台架末尾应出现 `RESULT ... PASS`。完整视频台架包含处理窗完整性、帧边界和显示链专项检查，判定结果在 `sim/results/`。

## 上板与测量

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat VP_VIVADO_BIN=<Vivado>/bin bash board/scripts/board_flash.sh
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
python src/host/link_selftest.py 192.168.1.10 6
node src/host/uart_cmd_check.mjs --port COM6
```

QSPI 固化使用 `board/scripts/make_boot_image.sh` 和 `board/tcl/flash_qspi.tcl`。JTAG 下载是易失的，断电后会回到 QSPI 镜像。完整步骤见 `report/reproduction.md`。

## 主要结果

| 项 | 读数 |
|---|---|
| 时序 | WNS 1.368 ns，WHS 0.048 ns，TNS = THS = 0，失败端点 0 |
| 资源 | LUT 14 965（28.13%），FF 9 097（8.55%），BRAM 98（70.00%），DSP 19（8.64%） |
| 连续流 | 241 帧 / 8.03 s = 30.01 fps（最终版位流，JTAG 下载） |
| 链路自检 | 22.2 / 0 / 18.9 fps，PASS |
| 效果链延迟 | 固定 15 个像素时钟；PL 内部帧时延 2–16 ms |
| 功耗（估算） | 2.407 W |

## 设计报告

GitHub 仓库中的最终报告位于 `report/design_report.pdf` 和 `report/design_report.docx`，正文 22 页，包含系统组成、软硬件划分、接口设计、时序与资源优化、实测结果、大模型协作记录、技能包提炼和复现说明。平台提交时设计报告单独上传，`源码.rar` 不重复包含这两个文件。Markdown 源稿在 `report/design-report.md`，验证、优化、复现和协作记录分别见 `report/` 下对应文件。

## 大模型协作

开发过程中使用大模型辅助代码检索、测试脚本编写、报告整理和问题定位。由人确定目标、架构和验收标准，模型负责提出候选修改和检查方案，所有结论均通过仿真、实现报告或板上日志复核。完整的会话卡、提示词和纠错轨迹在 `report/collaboration/`。

## 复现

器件为 `xc7z020clg484-2`，工具为 Vivado/Vitis 2025.2.1。PC 与板卡使用 `192.168.1.100/24` 和 `192.168.1.10/24` 直连，串口为 115200 8N1。具体命令、期望输出和常见问题见 `report/reproduction.md`。

## 许可证

MIT License，见 `LICENSE`。

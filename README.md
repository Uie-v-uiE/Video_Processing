# 多源视频流多效果变换处理系统

Zynq-7020 上的一条全硬件视频通路，加上一套能从网线和串口读回来的观测仪表。

上位机把 512×300、RGB565 的帧切成不超过 1392 字节的 UDP 报文发到 5001 端口。PL 从 RGMII 开始收包，经 MAC、UDP 过滤、按帧内偏移重组，写入 DDR 乒乓缓存；显示侧读回整帧，做缩放、任意角度旋转、双线性插值和六级效果处理，与 OSD 一起按 ×2 展开到 1024×600、59.5 Hz HDMI。像素通路不经过 PS。屏幕中间的竖缝左侧是原图、右侧是同一帧的处理图，两侧共用几何算子和固定 15 拍的效果链。

## 可复核的结果

| 结论 | 怎么看 | 读数 |
|---|---|---|
| 帧收满才提交 | 行覆盖位图、字节门与作废计数 | 8 秒推流 241 帧，29.95 fps；作废计数不随干净流增长 |
| 处理窗没有漏进原图 | 灰度单级 + split video 下的非灰像素计数 | 185°、30 fps 连续流下 `pane_bad=0`，计数有效 |
| 仪表能被打红 | 干净流 → 每 100 包丢 1 包 → 干净流 | 22.0 fps / 0 fps + 14.3 次作废每秒 / 18.9 fps，PASS |
| 效果链延迟不随配置变 | 完整视频台架的逐拍对齐与 OSD 时延 | 恒 15 个像素时钟；板上 PL 内部帧时延 2–16 ms |
| 帧间隔统计可读 | 串口 `link clr` → 推流 → 停流 → 重启 → `link` | 推流中 `gap_valid=1`；停流 `stall` 增长；重启后 `gap_max=22 061 ms` |
| QSPI 断电自启 | 写入、硬件回读、断电重上 | `DONE=1`、`EOS=1`、无 CRC/IDCODE 错误；`stat`/`link` 有回显 |

## 实现读数

器件 `xc7z020clg484-2`，工具 Vivado / Vitis 2025.2.1。

| 项 | 读数 |
|---|---|
| 时序 | WNS 1.341 ns，WHS 0.025 ns，TNS = THS = 0，失败端点 0 |
| 逐时钟 setup | `clk_fpga_0` 2.159 ns；`eth_rxc` 3.247 ns；`sys_clk` 14.797 ns；`clkout0_1` 3.264 ns；`clkout3` 1.727 ns |
| 资源 | LUT 14 967（28.13%），FF 9 095（8.55%），BRAM 98（70.00%），DSP 19（8.64%） |
| 仿真 | 19 支标准回归 `fail=0`；完整视频台架 C17/C25/C26 专项 PASS |
| 板上 | QSPI 冷启动、8 秒推流、遥测、三阶段自检、105 条串口电池、温度均通过 |

## 提交内容对照

| 赛题要求 | 本仓库 |
|---|---|
| 完整工程与源码（RTL、PS 软件） | `src/rtl/`、`src/ps/`、`src/constraints/` |
| 仿真/验证结果，说明功能正确性 | `sim/`、`sim/results/`、`build/reports/regression.txt`、`report/verification.md` |
| 综合与实现报告（资源、频率、性能） | `build/reports/` |
| 上板工程、运行脚本、实测输出与参考比对 | `board/vivado/`、`board/vitis/`、`board/project/`、`board/scripts/`、`board/tcl/`、`board/measured/`、`board/compare/` |
| 可复现构建脚本 | `build/build.tcl`、`build/tcl/`、`build/vitis/`、`build/ps/`、`build/sim/` |
| 技能包 | `skill/`，入口 `skill/README.md` |
| 设计报告七项 | `report/design-report.md`、`report/verification.md`、`report/optimization.md`、`report/collaboration/`、`report/skill-distillation.md`、`report/reproduction.md` |

`board/` 采用两个工程文件夹：`board/vivado/` 放 `.xpr` 与 `.srcs`，`board/vitis/` 放平台描述与 QEMU 参数；源码路径使用 `$PPRDIR/../../src/...`，工程内没有本机绝对路径。

## 构建与复现

```bash
# Vivado：建工程、块设计、综合、实现、位流、XSA、报告
vivado -mode batch -source build/build.tcl

# 台架
bash build/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
bash build/sim/run_msim.sh video_pipeline_top

# PS 应用
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<平台构建生成的 BSP 目录> \
PS_OUT=board/project/ps_app.elf \
python build/ps/build_ps_app.py

# Vitis 平台（可选）
VP_VITIS_WS=<工作目录> <Vitis>/bin/vitis.bat -s build/vitis/rebuild_vitis.py 8879

# 上板
VP_XSDB=<Vitis>/bin/xsdb.bat VP_VIVADO_BIN=<Vivado>/bin \
  bash board/scripts/board_flash.sh
VP_HW_URL=localhost:3121 vivado -mode batch -source board/tcl/flash_qspi.tcl

# 主机侧
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
python src/host/link_selftest.py 192.168.1.10 6
node src/host/uart_cmd_check.mjs --port COM6
```

完整步骤与每条命令的期望结果在 [`report/reproduction.md`](report/reproduction.md)。

## 目录

```text
src/rtl/            PL 源码：顶层、以太网、显示、几何、效果、AXI、HDMI
src/ps/             PS 裸机：main.c、sd_play.c、链接脚本
src/constraints/    引脚、时钟组、准静态 CDC、候选 IO 窗
src/host/           推流、遥测、仪表、自检、串口判据
sim/                88 支台架；sim/results/ 汇总最终判定
build/build.tcl     Vivado 主入口
build/tcl/          Vivado 构建与 board 工程 staging TCL
build/vitis/        Vitis 平台重建脚本
build/ps/           PS 应用直接编译脚本
build/sim/          xsim 运行入口
build/reports/      时序、资源、CDC、功耗、回归与完整视频台架
board/vivado/       Vivado 工程（.xpr + .srcs）
board/vitis/        Vitis 平台描述与 QEMU 参数
board/project/      位流、XSA、PS 应用
board/scripts/      上板、健康、UART、镜像打包
board/tcl/          JTAG、QSPI 单步脚本
board/measured/     一手实测日志
board/flash/        BOOT.bin 与打包日志
board/compare/      实测与参考结果的比对
data/inputs/        测试向量
data/golden/        人眼比对参考图
data/metrics.csv    指标表
skill/              与大模型协作提炼的技能包
report/             设计报告、验证、优化、复现、协作记录
deliverables/       技术文档与海报（仅本地，不进 GitHub）
```

## 边界

遥测时延只覆盖 PL 内部（帧提交到开始扫描），不是玻璃到玻璃。RGMII 发侧在 HR bank 上没有 ODELAYE2，0° 转发仍有约 0.845 ns 的 TskewT 保持缺口；90° 与 −45° 都被否决。BRAM 70% 由整帧缓存决定，512×300 以上画幅放不下。185° 细线已由 RTL 和台架闭环，人眼目视仍建议做一次。逐条说明在 [`report/limits.md`](report/limits.md)。

[English version](README_EN.md)

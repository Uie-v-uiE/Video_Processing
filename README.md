# Zynq 实时视频图像处理与逐像素对照显示

中文 · [English](README_EN.md)

## 1. 项目简介

上位机把 512×300 的 RGB565 帧切成 UDP 报文推到板卡的 5001 端口，每包不超过 1392 字节。这条链路上没有软件
逐像素参与：PL 里的以太网栈把 RGMII 还原成 GMII、重组以太网帧、按端口过滤，再由 PL 作 AXI 主设备把载荷写进
DDR 的乒乓帧缓存。显示侧把整帧读回来，先过缩放与旋转，再过六级效果链，最后与 OSD 一起经 ×2 展开驱动
1024×600 的 HDMI 屏。效果链由九位控制字逐位开关，六级流水在任何算法组合下的延迟都是 15 拍。

屏幕被一条竖缝分成两个窗，左窗是原图，右窗是同一坐标系下处理后的图，缝的位置是运行时参数，取值 0 到
100 %。这样安排不只是为了好看：错位、少列、越界填黑这类几何错误，在缝两侧当场就能看出来，同一帧就是
一台对照仪器。

片源有三路，网口的 UDP 视频流、SD 卡上的预转换帧序列、PL 自绘的测试图卡，由 `src_arb` 仲裁，长按按键切换；
只有 SD 那一路的像素由 PS 侧 DMA 写入。PL 内的 `link_monitor` 持续统计收包数、丢包数与帧间隔，同一组计数
既画在 OSD 上，也可以用串口命令读回和清零，还能经 AXI GPIO 用 xsdb 取到：GPIO_0 选要读哪一格，GPIO_1 取
那一格的值。RTL 与上位机之外，仓库里还有 83 支 testbench（`sim/tb_*.v`）和 49 条与本题解耦的做法条目
（`skill/`），下面这些命令能把工具报告全部重跑一遍。

## 目录导览

src/ —— `src/rtl/` 80 个 .v、`src/ps/` PS 侧 C、`src/constraints/` 9 份 .xdc（在用 2 份，其余 7 份是候选/实验件）、`src/host/` 26 支 .mjs 与 3 支 .py 上位机工具  
sim/ —— 顶层 84 份 .v（其中 83 支 `tb_*.v`），跑法见 `sim/README.md` 表格下方那一行  
build/ 与 board/ —— 7 份流程入口 TCL、检查器与 `build/report/` 下 7 份工具原始报告；上板工程、三步 JTAG 烧写脚本与实测输出（串口留档、板级校验读数）  
data/ —— 测试数据与参考结果：`data/inputs/` 8 份输入序列、`data/golden/` 参考图、`data/metrics.csv` 表头一行加 28 行指标  
skill/ 与 report/ —— 49 条 SKILL.md 技能条目（各写适用范围、使用方法、失效条件与复用结果）；设计报告、失败分析、复现说明与大模型协作记录  

## 从零复现

### 环境

器件是 `xc7z020clg484-2`，也就是板上那块 ZYNQ7020 CLG484 模块，速度等级 2，约束按这块板子的原理图给。工具是
Vivado / Vitis 2025.2.1、Node 24、Python 3.12（无第三方包，串口走 PowerShell），全部脚本都在这个版本下从零
重跑过；步骤记在 `report/build.md`，器件与版本的声明在 `report/declarations.md`。

### 构建

```bash
vivado -mode batch -source build/build.tcl          # 建工程 → 综合 → 实现 → 出位流
vivado -mode batch -source build/report.tcl         # 重出 build/report/ 下 7 份报告
vivado -mode batch -source build/gen_bit.tcl        # 位流与 .xsa 归档到 board/
```

分步入口是 `build/create_project.tcl`、`build/add_sources.tcl`、`build/synth.tcl`、`build/impl.tcl`。一次全流程实测 19 分 30 秒，综合 10 分 09 秒、实现含 `write_bitstream` 7 分 22 秒，日志 `build/r118_build_console.txt`。

### 上板与验证

```bash
bash build/board_verify.sh --geom --battery        # 几何检查 + 105 条串口命令回归测试，判定行在末尾
bash run_test.sh                                    # 一键测试：ping → 读回 → 发内置片源 → 计数对账
node src/host/video_sender.mjs --test bars          # 通用推流；任意片源用 src/host/video_sender.py --input
```

预期现象是屏上出现滚动条纹与右移的黄色方块，OSD 第 2 行的帧率格落到 29–30，`lane8` 的收包计数增量等于发出的
包数。JTAG 三步链的细节在 `board/README.md`。

## 关键数字与出处

板上这一版是 r132，位流身份 `build/system.bit md5=cb907d3e4898`，2026-10-17 11:35 产出，构建日志
`build/r132_streamwrap_build.log`；同一轮的 `build/utilization.rpt`、`build/timing_summary.rpt`、
`build/power.rpt` 都是 11:36 写的，下面每一格读数都出自这一次构建。

装法两条都留了痕。JTAG 是三步（`ps_jtag_boot`、`program_pl`、`ps_app_reload`），读数记在
`report/log/issues.md` #478。QSPI 写进去过一次，工具回了 `Verify Operation successful`，进盘镜像是 flash
目录里那份 `BOOT.bin`（不随包），md5 `acd8cdd5f060`，日志 `build/evidence/r132_flash_qspi_9_ok.log`；差的
是断电重上电那一度，串口文本还没存进 `board/measured/`，所以本页不写成"已固化自启"。

主时钟三条：显示像素钟 50 MHz 是 `clkout0_1`，H_TOTAL 1344、V_TOTAL 625，场频因此是 59.5 Hz；PL 逻辑钟
100 MHz 是 `clk_fpga_0`；以太网收包域 125 MHz 是 `eth_rxc`。约束在 `src/constraints/`。实现后全设计最差
setup 余量 0.687 ns，TNS 0 ns，setup 与 hold 的失败端点都是 0。

| 行名（会被机器读） | 读数 | 来源 |
| --- | --- | --- |
| 全设计 setup WNS | WNS **0.687 ns**、WHS **0.004 ns**，失败 setup 与 hold 端点 **0 / 51027** | `build/timing_summary.rpt`（Design Timing Summary）、`data/metrics.csv` 第 4-6 行 |
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **0.687 ns**，占它 8 ns 周期的 8.59 %，是全设计最紧的一格；100 MHz `clk_fpga_0` **1.571 ns**，占 15.71 %；50 MHz 显示域 `clkout0_1` **3.287 ns**，占 16.44 %；`sys_clk` **14.294 ns**，占 71.47 %，是最宽的一档 | `build/timing_summary.rpt`（Intra Clock Table 与 Clock Summary 两段） |
| 保持时间 | 全设计最差那一格在 `eth_rxc`，**0.004 ns**；逐时钟 WHS 依次是 `clk_fpga_0` **0.048 ns**、`clkout0_1` **0.067 ns**、`sys_clk` **0.121 ns**、`eth_rxc` **0.004 ns** | `build/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/hold_paths.rpt`、`build/clock_uncertainty.rpt` |
| BRAM / LUT / FF / DSP | BRAM **96 tile（68.57 %）**/ 140、LUT **14013（26.34 %）**、FF **8132（7.64 %）**、DSP **19（8.64 %）**/ 220 | `build/utilization.rpt`、`data/metrics.csv` 第 7-10 行 |
| 功耗 | 动态 **2.213 W**，片上合计 **2.390 W**；估算结温 **52.6 °C**，环境 25.0 °C、Effective TJA 11.5 °C/W、Max Ambient 57.4 °C；工具置信度 **Low**，所以这一格是估算值而不是实测 | `build/power.rpt`；`data/metrics.csv` 第 20-21 行 |
| 发布前检查 | 一键门禁 24 项 24 绿 / 0 红，末行 `GATES: ALL PASS（24 项全部判定）`；顶层整屏台架 **165 条判定 / 0 条 FAIL**，末行 `RESULT tb_v98_top_seam PASS`，件头部三枚指纹 `top_md5=c778dc4416b3 tb_md5=3975c335ab26 rtl_md5=93938780ccd6` 与现树同批 | `build/r132_gates.txt`、`build/tb_v98_report.txt`、`build/tb_edge_rim_r132.txt` |

这几格各有边界。本版不加载 RGMII 收口的输入窗，`eth_ctl` 与 `eth_rxd[3:0]` 这 5 个收端点因此不在时序检查的
覆盖范围内；hold 那一行只有 `eth_rxc` 带自加的 0.800 ns 不确定度（`src/constraints/rk_zynq7020.xdc:50`），
其余三个域没有这一行，那四个 WHS 数值只能在各自域内比大小，两处的展开写在 `report/08-limits.md` §4 与 §6。
门禁全绿的那一套是 r132，取 `build/r132_gates.txt`；这一轮中间红过两趟，那笔账在 `report/06-validation.md`。
上面这些报告由那三条命令重跑，`report.tcl` 的重跑产物与归档件只差 Date 与 `-file` 两行（细节与 SD 片源两个
滑窗的 29.956 / 29.815 fps 都写在 `report/build.md` 与 `report/06-validation.md`）。边界与限制的逐条登记在
`report/08-limits.md`，缺陷与有意保留的未通过项在 `report/known_issues.md`，未决项在 `report/90-open-items.md`。

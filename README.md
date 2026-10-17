# Zynq 实时视频图像处理与逐像素对照显示

中文 · [English](README_EN.md)

## 1. 项目简介（这个系统做什么）

上位机把 512×300 的 RGB565 帧切成每包不超过 1392 字节的 UDP 报文，发到板上的 5001 端口；收包不经过 PS——PL 里把
RGMII 还原成 GMII、重组以太网帧、按端口过滤，载荷由 PL 作 AXI 主设备写进 DDR 的乒乓帧缓存（SD 那一路才由 PS 的 DMA 写入），PL 再读回整帧，过按位开关的效果链（六级流水、九位控制字，一位一个算法）与缩放、旋转、分割混合，再经 ×2 展开驱动 1024×600 的 HDMI。
屏幕被一条竖缝分成两个窗：左窗是原图，右窗是同一坐标系下处理后的图，缝的位置由控制字给（0–100 %）。这条对照既是演示效果，也是一台仪器：错位、少列、越界填黑这类几何错误，在缝两侧当场就能看见。

片源有三路——网口的 UDP 视频流、SD 卡上的预转换帧序列、PL 自绘的测试图卡——由 `src_arb` 仲裁，长按按键切换。PL 内的 `link_monitor`
持续统计收包数、丢包数与帧间隔，同一组计数既画在 OSD 上，也能经 AXI GPIO 用 xsdb 读回（GPIO_0 选要读哪一格、GPIO_1 取那一格的值），还能用串口命令
清零。RTL 与上位机之外，仓库里还有 82 支 testbench（`sim/tb_*.v`）和 49 条与本题解耦的做法条目（`skills/`），工具报告全部可以用下面的命令重跑。

## 目录导览

src/ —— `src/rtl/` 80 个 .v、`src/ps/` PS 侧 C、`src/constraints/` 9 份 .xdc（在用 2 份，其余 7 份是候选/实验件）、`src/host/` 26 支 .mjs 与 3 支 .py 上位机工具  
sim/ —— 顶层 83 份 .v（其中 82 支 `tb_*.v`），跑法见 `sim/README.md` 表格下方那一行  
build/ —— 7 份流程入口 TCL、检查器与 `build/report/` 下 7 份工具原始报告  
board/ —— 上板工程、三步 JTAG 烧写脚本与实测输出（串口留档、板级校验读数）  
data/ —— 测试数据与参考结果：`data/inputs/` 8 份输入序列、`data/golden/` 参考图、`data/metrics.csv` 第 1 行是表头、往下 28 行指标  
skills/ —— 49 条 SKILL.md 技能条目，各写适用范围、使用方法、失效条件与已验证的复用结果  
report/ —— 设计报告、失败分析、复现说明与大模型协作记录  

## 从零复现

### 环境

器件是 `xc7z020clg484-2`，也就是板上那块 ZYNQ7020 CLG484 模块，速度等级 2；约束按这块板子的原理图给。工具 Vivado / Vitis 2025.2.1、
Node 24、Python 3.12（无第三方包，串口走 PowerShell），全部脚本都在这个版本下从零重跑过，步骤记在 `report/build.md`，器件与版本的
声明在 `report/declarations.md`。

### 构建

```bash
vivado -mode batch -source build/build.tcl          # 建工程 → 综合 → 实现 → 出位流
vivado -mode batch -source build/report.tcl         # 重出 build/report/ 下 7 份报告
vivado -mode batch -source build/gen_bit.tcl        # 位流与 .xsa 归档到 board/
```

分步入口是 `build/create_project.tcl` / `build/add_sources.tcl` / `build/synth.tcl` / `build/impl.tcl`。一次全流程实测约 20 分钟（19 分 30 秒），其中
综合 10 分 09 秒、实现含 `write_bitstream` 7 分 22 秒，日志在 `build/r118_build_console.txt`；另一次只走分步链、不含实现，建工程
63 秒、综合 10 分 53 秒、出报告 1 分 34 秒（`build/evidence/r121_c4_verify.txt`）。

### 上板与验证

```bash
bash build/board_verify.sh --geom --battery        # 几何检查 + 105 条串口命令回归测试，判定行在末尾
bash run_test.sh                                    # 一键测试：ping → 读回 → 发内置片源 → 计数对账
node src/host/video_sender.mjs --test bars          # 通用推流；任意片源用 src/host/video_sender.py --input
```

预期现象：屏上出现滚动条纹与右移的黄色方块，OSD 第 2 行的帧率格落到 29–30，`lane8` 的收包计数增量等于发出的包数（差额 0）。
JTAG 三步链见 `board/README.md`。

## 关键数字与出处

板上现在这一版是 r132，位流身份 `build/system.bit md5=cb907d3e4898`（2026-10-17 11:35 那一跑产出，构建日志 `build/r132_streamwrap_build.log`；同一轮读数件 `build/utilization.rpt` / `build/timing_summary.rpt` / `build/power.rpt` 都是 11:36）。下面每一格读数都来自这一块位流那一次构建。
装法两条都留了痕：JTAG 三步（`ps_jtag_boot` → `program_pl` → `ps_app_reload`）的读数在 `report/log/issues.md` #478；QSPI 固化写了一次并通过 `Verify Operation successful`（进盘镜像 `board/flash/BOOT.bin` md5 `acd8cdd5f060`，日志 `build/evidence/r132_flash_qspi_9_OK.log`），但**冷上电那一度还没验** ⇒ 本页不把它写成"已固化"，等读数回来再改。

主时钟三条：显示像素钟 50 MHz（`clkout0_1`，H_TOTAL 1344 / V_TOTAL 625 ⇒ 场频 59.5 Hz）、PL 逻辑钟 100 MHz（`clk_fpga_0`）、以太网
收包域 125 MHz（`eth_rxc`）；约束在 `src/constraints/`，含时钟、I/O 窗、时钟不确定度与异步组声明。实现后全设计最差 setup 余量
0.687 ns，失败 setup 与 hold 端点 0 / 51027，片内路径已收敛（WNS 0.687 ns / TNS 0 ns / 失败端点 0），两个方向都是 0。

| 行名（会被机器读） | 读数 | 来源 |
| --- | --- | --- |
| 全设计 setup WNS | WNS **0.687 ns**、WHS **0.004 ns**，失败 setup/hold 端点 **0 / 51027**（两个方向都是 0。本版不加载 RGMII 收口输入窗，`eth_rx_ctl` 与 `eth_rxd[3:0]` 这 5 个收端点因此不在时序检查的覆盖范围内，窗为何退回候选件见 `report/08-limits.md` §4） | `build/timing_summary.rpt`（Design Timing Summary）、`data/metrics.csv` 第 4-6 行 |
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **0.687 ns**（占它 8 ns 周期的 8.59 %，全设计最紧的一格）；100 MHz `clk_fpga_0` **1.571 ns**（占它 10 ns 周期的 15.71 %）；50 MHz 显示域 `clkout0_1` **3.287 ns**（占它 20 ns 周期的 16.44 %）；`sys_clk` **14.294 ns**（占它 20 ns 周期的 71.47 %，最宽的一档） | `build/timing_summary.rpt`（Intra Clock Table + Clock Summary 两段） |
| 保持时间 | 全设计最差那一格在 `eth_rxc`，**0.004 ns**；逐时钟 WHS：`clk_fpga_0` **0.048 ns**、`clkout0_1` **0.067 ns**、`sys_clk` **0.121 ns**、`eth_rxc` **0.004 ns**。警告：只有 `eth_rxc` 这一域带自加的 0.800 ns hold 不确定度（`src/constraints/rk_zynq7020.xdc:50`），其余三个域的报告里没有这一行 ⇒ 这四个数只能在同域内比大小，跨域比较要等不确定度补齐（`report/08-limits.md` §6） | `build/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/hold_paths.rpt`、`build/clock_uncertainty.rpt` |
| BRAM / LUT / FF / DSP | BRAM **96 tile（68.57 %）**/ 140、LUT **14013（26.34 %）**、FF **8132（7.64 %）**、DSP **19（8.64 %）**/ 220 | `build/utilization.rpt`、`data/metrics.csv` 第 7-10 行 |
| 功耗 | 动态 **2.213 W**（片上合计 **2.390 W**）、估算结温 **52.6 °C**（Ambient 25.0 °C、Effective TJA 11.5 °C/W、Max Ambient 57.4 °C），工具置信度 **Low** ⇒ **这是估算，不是实测** | `build/power.rpt`；`data/metrics.csv` 第 20-21 行 |
| 发布前检查 | 本页不作门禁全绿声明，以 `bash build/gates.sh` 打印的末行为准；**r132 这一轮的门禁还没跑**（#46 的规范通道整架正在跑：`build/sim/run_one.sh tb_v98_top_seam`），所以这一格只写"未跑"，不引用旧构建的读数。变化是正向的：长期红着的顶层判据 `C5c` 在 r132 翻绿（`report/log/issues.md` #478：两版树各一次整架 165 PASS / 0 FAIL，其中交付版就是这一行的 `STREAM_WRAP` 版） | `build/r132_streamwrap_build.log`、`report/log/issues.md` #478 |

这些报告可以由上面三条命令重跑：`report.tcl` 的重跑产物与归档件只差 Date 与 `-file` 两行，其余逐字节相同（`build/evidence/r121_note_c4.txt`、
`build/evidence/r121_report_archive.txt`）。SD 片源两个 100 帧滑窗的实测读数是 29.956 与 29.815 fps（`build/evidence/r87_boot_stat_drain.txt`），
`data/metrics.csv` 那一行把它取整写成 29.8 – 30.0；效果链那 9 个位开关与三路片源的逐格对照由 `sim/tb_*.v` 台架判。

边界与限制的逐条登记在 `report/known-limitations.md`（HDMI 源端的量测维度、PS 侧固件的重建与复验步骤、工具版本绑定），
缺陷与有意保留的未通过项在 `report/known_issues.md`，未决项集中表在 `report/90-open-items.md`。

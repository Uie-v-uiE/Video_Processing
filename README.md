# Zynq 实时视频图像处理与逐像素对照显示

中文 · [English](README_EN.md)

## 1. 项目简介（这个系统做什么）

上位机把 512×300 的 RGB565 帧切成每包不超过 1392 字节的 UDP 报文，发到板上的 5001 端口。收包不经过 PS：PL 里把 RGMII 还原成 GMII、
重组以太网帧、按端口过滤，载荷由 PL 作 AXI 主设备写进 DDR 的乒乓帧缓存（SD 那一路才由 PS 的 DMA 写入），PL 再读回整帧，过按位开关的效果链（六级流水、九位控制字，一位一个算法）与缩放、旋转、分割混合，再经 ×2 展开驱动 1024×600 的 HDMI。
一条竖缝把屏幕分成两个窗：左窗是原图，右窗是同一坐标系下处理后的图，缝的位置由控制字给（0–100 %）。这条缝除演示外还当量测用：错位、少列、越界填黑这类几何错误，缝两侧当场就能看见。

片源三路：网口的 UDP 视频流、SD 卡上的预转换帧序列、PL 自绘的测试图卡。`src_arb` 做仲裁，长按按键切换。`link_monitor` 在 PL 内统计
收包数、丢包数与帧间隔。这组计数画在 OSD 上，可以经 AXI GPIO 用 xsdb 读回（GPIO_0 选要读哪一格、GPIO_1 取那一格的值），串口命令能把它清零。
仓库里除 RTL 与上位机工具外还有 82 支 testbench（`sim/tb_*.v`）和 49 条与本题解耦的做法条目（`skills/`），工具报告用下面三条命令重跑。

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

分步入口是 `build/create_project.tcl` / `build/add_sources.tcl` / `build/synth.tcl` / `build/impl.tcl`。一次全流程实测约 20 分钟（19 分 30 秒）：
综合 10 分 09 秒，实现含 `write_bitstream` 7 分 22 秒，日志在 `build/r118_build_console.txt`。另一次只走分步链、不含实现，建工程 63 秒、
综合 10 分 53 秒、出报告 1 分 34 秒，读数取自 `build/evidence/r121_c4_verify.txt`。

### 上板与验证

```bash
bash build/board_verify.sh --geom --battery        # 几何检查 + 105 条串口命令回归测试，判定行在末尾
bash run_test.sh                                    # 一键测试：ping → 读回 → 发内置片源 → 计数对账
node src/host/video_sender.mjs --test bars          # 通用推流；任意片源用 src/host/video_sender.py --input
```

预期现象：屏上出现滚动条纹与右移的黄色方块，OSD 第 2 行的帧率格落到 29–30，`lane8` 的收包计数增量等于发出的包数（差额 0）。
JTAG 三步链见 `board/README.md`。

## 关键数字与出处

板上现在跑的是 r126，位流身份 `system.bit md5=cd04907e1369`（身份行由检查记录自己写出，`build/r126_gates.txt`；逐字节一致的存档件在
`build/r118_gates_final.txt` 与 `build/evidence/r118_board/`）。表内每一格读数都来自这一块位流的那一次构建。

主时钟三条：显示像素钟 50 MHz（`clkout0_1`，H_TOTAL 1344 / V_TOTAL 625，场频 59.5 Hz）、PL 逻辑钟 100 MHz（`clk_fpga_0`）、以太网
收包域 125 MHz（`eth_rxc`）。约束在 `src/constraints/`，写了时钟、I/O 窗、时钟不确定度与异步组声明。实现后全设计最差 setup 余量 0.739 ns，
失败 setup 与 hold 端点 0 / 51135，也就是 WNS 0.739 ns / TNS 0 ns / 失败端点 0，两个方向都是 0，片内路径收敛。

| 行名（会被机器读） | 读数 | 来源 |
| --- | --- | --- |
| 全设计 setup WNS | WNS **0.739 ns**、WHS **0.052 ns**，失败 setup/hold 端点 **0 / 51135**（两个方向都是 0。本版不加载 RGMII 收口输入窗，`eth_rx_ctl` 与 `eth_rxd[3:0]` 这 5 个收端点因此不在时序检查的覆盖范围内，窗为何退回候选件见 `report/08-limits.md` §4） | `build/report/timing_summary.rpt:151`、`data/metrics.csv` 第 4–6 行 |
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **0.739 ns**（占它 8 ns 周期的 9.24 %，全设计最紧的一格）；100 MHz `clk_fpga_0` **1.850 ns**（占它 10 ns 周期的 18.5 %）；50 MHz 显示域 `clkout0_1` **3.630 ns**（占它 20 ns 周期的 18.15 %）；`sys_clk` **14.876 ns**（占它 20 ns 周期的 74.38 %，最宽的一档） | `build/report/timing_summary.rpt`（Intra Clock Table + Clock Summary 两段） |
| 保持时间 | 全设计最差那一格在 `eth_rxc`，**0.052 ns**；逐时钟 WHS：`clk_fpga_0` **0.053 ns**、`clkout0_1` **0.059 ns**、`sys_clk` **0.222 ns**、`eth_rxc` **0.052 ns**。只有 `eth_rxc` 这一域带自加的 0.800 ns hold 不确定度（`src/constraints/rk_zynq7020.xdc:50`），其余三个域的报告里没有这一行 ⇒ 这四个数只能同域比大小，跨域比较要等不确定度补齐（`report/08-limits.md` §6） | `build/report/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/hold_paths.rpt`、`build/clock_uncertainty.rpt` |
| BRAM / LUT / FF / DSP | BRAM **95.5 tile（68.21 %）**/ 140、LUT **14154（26.61 %）**、FF **8188（7.70 %）**、DSP **19（8.64 %）**/ 220 | `build/report/utilization.rpt`、`data/metrics.csv` 第 7–10 行 |
| 功耗 | 动态 **2.213 W**（片上合计 2.391 W）、估算结温 **52.6 °C**，工具置信度 **Low** ⇒ 这是估算，不是实测 | `build/report/power.rpt`；`data/metrics.csv` 第 27–28 行 |
| 发布前检查 | 这里不作门禁全绿声明，以 `bash build/gates.sh` 打印的末行为准。板上这一版读数是「门禁 24 项 23 绿 / 1 红」，唯一未通过项 `C5c` 由顶层整屏仿真的测试例自己判出：帧头窗那一带的输出行带着上一帧的内容，本体行逐格全对。症状、已排除的解释与关闭条件在 `report/08-limits.md` §1；最新且全部通过的那一套归档属于更早的一次构建 `build/r75_gates.txt`，与板上这一版不是同一构建，两处读数不能混用 | `build/r118_gates.txt` |

这三条命令能重跑这些报告：`report.tcl` 的重跑产物与归档件只差 Date 与 `-file` 两行，其余逐字节相同，对照在 `build/evidence/r121_note_c4.txt` 与
`build/evidence/r121_report_archive.txt`。SD 片源两个 100 帧滑窗实测 29.956 与 29.815 fps（`build/evidence/r87_boot_stat_drain.txt`），
`data/metrics.csv` 那一行取整写成 29.8 – 30.0；效果链那 9 个位开关与三路片源的逐格对照由 `sim/tb_*.v` 那批测试例判。

边界与限制逐条登记在 限制清单（HDMI 源端的量测维度、PS 侧固件的重建与复验步骤、工具版本绑定），
缺陷与有意保留的未通过项在 问题清单，未决项收在 未决项集中表。

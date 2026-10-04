# Zynq 实时视频图像处理与逐像素对照显示

中文 · [English](README_EN.md)

## 1. 项目简介

上位机把 512×300 的 RGB565 帧切成 ≤1392 字节的 UDP 包（端口 5001）发到板上；PS 侧收包并写 DDR，
PL 侧从 DDR 读帧、按 9 级效果链（灰度、模糊、锐化、Sobel、形态学、gamma、缩放、旋转、分割混合）处理后
经 ×2 展开驱动 1024×600 HDMI，并把统计量画在 OSD 上；PL 内的 `link_monitor` 持续统计收包/丢包/帧间隔，
上位机用 xsdb 经 GPIO_0 选车道、GPIO_1 取值读回。除网片源外，板上还有 SD 预转换帧序列与自研测试图卡两个源，
三者由 `src_arb` 仲裁，长按按键切换。

### 亮点

- 0 / 51135：实现后 setup 与 hold 两个方向的失败端点都是 0，全设计最差 setup 余量 0.739 ns（`build/report/timing_summary.rpt`）。
- 29.8 – 30.0 fps：SD 片源在 512×300 预转换序列下的 100 帧滑窗实测帧率（`data/metrics.csv`，件 `build/evidence/r87_boot_stat_drain.txt`）。
- 9 级 × 512×300：一条可逐像素开关的处理链，同一屏左窗显示原图、右窗显示处理图，缝位置由控制字给（分割线 0–100 %）。
- 81 支 testbench：每个关键模块与易错点各有 `sim/tb_*.v` 台架，清单由 `node build/gen_sim_readme.mjs --apply` 从各文件头注释生成。
- 49 条技能条目：`skills/` 是与本题解耦的通用做法包，形状由 `node skills/_meta/check-skill-package.mjs` 判（现值 红=0）。

### 目录

src/ —— `src/rtl/` Verilog RTL、`src/ps/` PS 侧 C、`src/constraints/` 9 份 .xdc、`src/host/` 26 支 .mjs 与 3 支 .py 上位机工具  
sim/ —— 84 份 .v（其中 81 支 `tb_*.v`），跑法见 `sim/README.md` 表格下方那一行  
build/ —— 7 份流程入口 TCL、检查器与 `build/report/` 下 7 份工具原始报告  
board/ —— 上板工程、三步 JTAG 烧写脚本与实测输出（串口留档、板级校验读数）  
data/ —— 测试数据与参考结果：`data/inputs/` 8 份输入序列、`data/golden/` 参考图、`data/metrics.csv` 28 行指标  
skills/ —— 49 条 SKILL.md 技能包，README 写适用范围/使用方法/失效条件/已验证的复用结果  
report/ —— 设计报告、失败分析、复现说明与大模型协作记录  

## 2. 复现步骤

### 环境

器件 `xc7z020clg484-2`（板上 ZYNQ7020 CLG484 速度等级 2；选题指南给的初级组器件是 `xc7z020clg400-1`，
两者封装与管脚数不同，本工程按实际板子约束），工具 Vivado / Vitis 2025.2.1（指南推荐 2026.1，
本工程全部脚本在 2025.2.1 下从零复现），Node 24，Python 3.12（无第三方包，串口走 PowerShell）。

### 构建

```bash
vivado -mode batch -source build/build.tcl          # 建工程 → 综合 → 实现 → 出位流
vivado -mode batch -source build/report.tcl         # 重出 build/report/ 下 7 份报告
vivado -mode batch -source build/gen_bit.tcl        # 位流与 .xsa 归档到 board/
```

分步入口是 `build/create_project.tcl` / `add_sources.tcl` / `synth.tcl` / `impl.tcl`；
一次全流程实测约 2 小时（综合约 11 分钟，实现约 1.5–2 小时，计时见 `build/evidence/r121_c4_verify.txt`）。

### 上板与验证

```bash
bash build/board_verify.sh --geom --battery        # 几何判据 + 105 条串口命令电池，判定词在行尾
bash run_test.sh                                    # 一键测试：ping → 读回 → 发内置片源 → 计数对账
node src/host/video_sender.mjs --test bars          # 通用推流；任意片源用 src/host/video_sender.py --input
```

预期现象：屏幕出现滚动条纹与右移黄色方块，OSD 第 2 行帧率格落到 29–30，
`lane8` 收包计数增量等于发出的包数（差额 0）。JTAG 三步链见 `board/README.md`。

### 时序说明

主时钟：显示像素钟 50 MHz（`clkout0_1`，H_TOTAL 1344 / V_TOTAL 625 ⇒ 场频 59.5 Hz）、
PL 逻辑钟 100 MHz（`clk_fpga_0`）、以太网收包域 125 MHz（`eth_rxc`）。约束在 `src/constraints/`，
含时钟、I/O 窗、时钟不确定度与异步组声明。

| 行名（会被机器读） | 读数 | 来源 |
| --- | --- | --- |
| 全设计 setup WNS | WNS **0.739 ns**、WHS **0.052 ns**，失败 setup/hold 端点 **0 / 51135**（两个方向都是 0；本版不带 RGMII 收口输入窗 ⇒ 那 5 个 I/O 端点当前未检查，未检查不等于满足） | `build/timing_summary.rpt:151`（本会话打开核对）、`data/metrics.csv` 第 4–6 行 |
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **0.739 ns**（占它 8 ns 周期的 9.24 %，全设计最紧的一格）；100 MHz `clk_fpga_0` **1.850 ns**（占它 10 ns 周期的 18.5 %）；50 MHz 显示域 `clkout0_1` **3.630 ns**（占它 20 ns 周期的 18.15 %）；`sys_clk` **14.876 ns**（占它 20 ns 周期的 74.38 %，最宽的一档） | `build/timing_summary.rpt`（Intra Clock Table + Clock Summary 两段） |
| 保持时间 | 全设计最差那一格在 `eth_rxc`，**0.052 ns**；逐时钟 WHS：`clk_fpga_0` **0.053 ns**、`clkout0_1` **0.059 ns**、`sys_clk` **0.222 ns**、`eth_rxc` **0.052 ns**。⚠ 只有 `eth_rxc` 带着 r79 加严的 0.800 ns hold 不确定度，其余三个域的报告里没有那一行 ⇒ 这四个数只许两两比同域，跨域比"谁更薄"要等不确定度带补齐 | `build/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/hold_paths.rpt`、`build/clock_uncertainty.rpt` |
| BRAM / LUT / FF / DSP | BRAM **95.5 tile（68.21 %）**/ 140、LUT **14154（26.61 %）**、FF **8188（7.70 %）**、DSP **19（8.64 %）**/ 220 | `build/utilization.rpt`、`data/metrics.csv` 第 7–10 行 |
| 功耗 | 动态 **2.213 W**（片上合计 2.391 W）、估算结温 **52.6 °C**，工具置信度 **Low** ⇒ **这是估算，不是实测** | `build/power.rpt`；`data/metrics.csv` 第 20–21 行 |

结论：片内路径已收敛（WNS 0.739 ns / TNS 0 ns / 失败端点 0）；报告可由上面三条命令重跑复现，
`report.tcl` 重跑产物与 `build/*.rpt` 官方件只差 Date 与 `-file` 两行，其余逐字节相同
（凭据 `build/evidence/r121_c4_verify.txt`）。

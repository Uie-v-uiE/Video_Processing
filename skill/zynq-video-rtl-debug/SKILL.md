---
name: zynq-video-rtl-debug
description: Layered (L0–L4) RTL debug and single-variable fix protocol for this workspace's Zynq7020 UDP→DDR→HDMI video pipeline (src/rtl/**, sim/, build/tcl/, report/). Use when editing any .v under src/rtl, running xsim testbenches via sim/run_sim.tcl, rebuilding the bitstream with build/tcl/build_system_axigpio.tcl, or interpreting board results recorded in report/OVERNIGHT_LOG.md and data/measured/. Enforces production-geometry sims, report gates, and "no claim without a file+number".
---

# Zynq7020 视频流水线上板不亮 / 画面异常的分层定位

## 适用场景
- 本仓库（`Video_Processing/`）里任何一次「改 RTL → 上台架 → 出报告 → 上板」的闭环。
- 症状：拖影 / 黑横纹 / 卡死 / 左窗不跟随 / 画面 4 幅或窄条 / OSD 数字不对 / JTAG 找不到器件。
- 不适用：画质类判定的收敛（见失效条件 6）；非本布局的工程（见失效条件 1）。

## 使用方法
先读 `README.md` 与 `report/OVERNIGHT_LOG.md`（逐轮判据）、`report/ISSUES.md`（症状索引），再按层推进：

| 层 | 手段（本仓库真实入口） | 判据 |
|----|------------------------|------|
| L0 | 直读 RTL + `git diff --stat` + 逐行核对 | 端口/信号一一对应（R03 抽模块时就是这么核的） |
| L1 | `vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl`；单个台架 `SIM_TB=tb_v6_tail_bank …`；只编译 `SIM_ONLY=1`；plusargs `SIM_ARGS="+FULL +MISALIGN"` | 每个 TB 自己 `$display` 的 `RESULT <tb> PASS`；末行 `SIM DONE pass=N fail=0` |
| L2/L3 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` → 读 `build/timing_summary.rpt`、`utilization.rpt`、`power.rpt`、`route_status.rpt`、`methodology.rpt`、`cdc.rpt`；新模块预检 `OOC_ONLY=link_monitor vivado -mode batch -source build/tcl/ooc_newmods.tcl` | 门禁四项：WNS/WHS ≥0 且全约束 met、BRAM ≤97%、Slice ≤98%、功耗不明显恶化、Failed Nets=0、无新增 Critical |
| L4 | `xsdb.bat build/tcl/ps_jtag_boot.tcl <ps7_init.tcl>` → `vivado -mode batch -source build/tcl/program_pl.tcl` → `xsdb.bat build/tcl/set_src.tcl` → `node src/host/video_sender.mjs --test frameid …` → **停流**后 `node src/host/ddr_verify.mjs --frameid` / `ddr_stale.mjs`；链路计数 `node src/host/health_read.mjs --gapclr` | 每 bank 帧号跨度=1、逐 lane 命中率、六带丢字率、`hb_slow`/`frames_bad` |

（`<ps7_init.tcl>` 用构建产出的
`vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/ip/design_1_processing_system7_0_0/ps7_init.tcl`，
也可以直接从 `build/system.xsa` 里解出来用，`report/OVERNIGHT_LOG.md` §「L4 尝试」。）

四步纪律（都是踩出来的）：
1. **测量先于改动**：先跑判据矩阵再动代码 —— SRC0 无流（验 HDMI/时序本体）、SRC0 有流（验入包链
   是否干扰显示）、SRC1 正常流、**SRC1 停流冻结帧**（静态坏数据 vs 读写同址冲突）。
   「停流仍脏 ⇒ 是没被写过的 BRAM 字（值 0 = 黑），不是读写冲突」这条就是这么来的。
2. **一次构建只动一个架构变量**；allow 窗口 / 写引擎 / saver 三处永不捆绑改。
3. **仿真用生产几何**（512×300 源、1024×600 显示、H=1344 V=625 @50 MHz、1392 B 分包）。
   小几何台架会绿而板上失败（`sim/tb_timing.v:11` 是 16×8、`sim/tb_v6_pingpong.v:14` 是 512×60）。
4. **每一轮把假设/改动/仿真结果/板级结果/是否回退写进 `report/`**，并给文件+数字。

## 已验证效果
- 该分层在本仓库 R01–R13 逐轮里给出了结论（`report/OVERNIGHT_LOG.md` §3、§5 门禁表、§6 bit 表）：
  L1 从基线 **28/28** 涨到 **34/34**（`sim/results/regression_v77_r13.txt`）；
  门禁从「BRAM 98.93% + Slice 99.92% 两项不合格」做到
  **BRAM 64.64% / Slice 18.03% / Reg 4.08% / WNS +0.499**（R05），
  R06 把 `frame_reasm` 的 24 位进位链换成「饱和累加 + 等值比较」后
  WNS **+0.499 → +0.974**、Dynamic 2.338 → 2.176 W。
- 板级结论在同一套流程下拿到：15/30/60 fps 与 120 fps（实测 116 fps ≈36 MB/s、900 帧）
  四档激励下「每 bank 恰好一帧、逐 lane 100.0%、连续丢字带 0 字」
  （`report/OVERNIGHT_LOG.md` §「L4 执行」，明细 `data/measured/board_measure_r06_r07.md`）。
- 「禁止无新证据就采纳」这条路有正例：R03 帧尾修复坚持**双向判据**（旧逻辑必须能复现坏、
  新逻辑必须完整）——`tb_v6_tail_bank` 给出 `frame1 old=7/8 (first_bad_word=7) / new=8/8`
  且 `commits old=2 new=2`（没有过度延迟换页）。同时如实降级：板上 6+2 轮 A/B **无区分力**
  ⇒ 证据等级只到「机理 + 仿真」，没被写成板级战果。
- 环境事实表（本机可复现，`report/OVERNIGHT_LOG.md` §0）：Vivado/Vitis **2025.2.1** 在
  `D:\Software\Vivado\2025.2.1\`；器件 `xc7z020clg484-2`；`xvlog/xelab/xsim` 只在
  `vivado.bat -mode batch -source` 里可用；批处理一律带 `-nojournal -log <路径>`，
  否则 `vivado.jou`/`vivado.log` 落在当前目录。

## 失效条件
1. **本目录 `scripts/run_sim.tcl` 在本布局下跑不起来**（未改，保留给交接）：它硬要
   `rtl_base/` + `rtl_fix/` 两个目录并 `FATAL missing` 退出，而本仓库只有 `src/rtl/`。
   它的「把 `rtl_fix` 覆盖 base 同名模块」规则也随布局消失了
   （`sim/run_sim.tcl` 头部注释：这一版没有 filter，那些文件本身就是修好的）。
2. 因此本 skill 原文里的这些路径**在本仓库不存在**，不要照抄：`rtl/top/…`、`rtl_fix/`、
   `build_tcl/`、`docs/LEARNINGS.md`、`sim/run_sim_v5.tcl`、`.qoder/skills/…`，以及旧的仓库根
   `D:/Xilinx/Prj/ADD/Video_Pipeline-main`（**真实仓库根是 `D:/Xilinx/Prj/pro/Video_Processing`**；
   2026-09-23 已把 5 个还硬编码旧根的 tcl 改成 `[file dirname [info script]]` 自适应）。
   真实路径是 `src/rtl/…`、`build/tcl/…`、`report/…`。
   命令侧：推流用 `node src/host/video_sender.mjs …`（本机也有 python 3.12，但**交付件不依赖它**，
   判据工具一律零依赖，见 `src/host/HOST_GUIDE.md`）。
3. **换工具版本 ⇒ 全部门禁数字作废**：BD、`ps7_init.tcl`、xsa、实现策略都是 2025.2.1 验的；
   已记录的两个版本事实就够说明脆弱度——`report_timing_summary -check_summary_only`
   在 2025.2.1 不是合法选项，`Flow_PerfOptimized_high` 等策略名不被支持（R06）。
4. **换器件 ⇒ 原语层失效**：`IDDR/IDELAYE2/IDELAYCTRL`（`src/rtl/eth/rgmii_rx.v`）、
   `OSERDESE2`（`src/rtl/hdmi/tmds_serializer.v`）、`MMCME2_BASE`（`src/rtl/clocks/clk_gen.v:15`）
   在 UltraScale+ 上不存在。
5. **台架资源**：`hw_server` 一次只能看到一块板（两颗 FT2232 共用序列号 `0ABC01`，
   `report/OVERNIGHT_LOG.md` §11）；同一进程连跑三次 `synth_design` 会撞 Windows `.Xil` 目录锁
   并**静默跳过后面的模块**（`build/tcl/ooc_newmods.tcl` 头注，故有 `OOC_ONLY=`）。
   批处理失败先 `tasklist`/free RAM（`ERROR: [Common 17-217] Failed to load feature 'core'`
   是内存问题不是 RTL 问题，`report/ISSUES.md` 快速对照）。
6. 画质类（缩放走样、色彩、抖动）不能用这套判据收敛；停流回读会把 A9 停在复位态，
   之后必须重跑 L4 三件套，否则量的是「PS 不跑」的工况。
7. 「禁止清单」（无新证据不得采纳）仍然有效且**未被本轮推翻**：V-blank-only allow 当主修、
   mute 当主修、burst saver、双显示 BRAM（`report/OVERNIGHT_LOG.md` U3：整帧拷贝要吸收的窗口需
   ≈84 个 BRAM tile 而全片只有 140 ⇒ 加深缓冲结构上不可行）。

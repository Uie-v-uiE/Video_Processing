---
name: zynq-video-rtl-debug
description: Layered (L0-L4) RTL debug and single-variable fix protocol for this workspace's Zynq7020 UDP-to-DDR-to-HDMI video pipeline (src/rtl/**, sim/, build/tcl/, report/). Use when editing any .v under src/rtl, running xsim testbenches via sim/run_sim.tcl or sim/run_one.sh, rebuilding the bitstream with build/tcl/build_system_axigpio.tcl, or interpreting board results recorded in report/OVERNIGHT_LOG.md and data/measured/. Enforces production-geometry sims, report gates, and "no claim without a file+number".
---

# S8 · 上板不亮 / 画面异常时的分层定位（L0–L4）

条目索引与其余各条在 [../README.md](../README.md)；工作纪律与提示词模板在 [../SKILL.md](../SKILL.md)。
本文件只管一件事：**症状出来之后按什么顺序往下剥，每一层用什么命令、判据是什么。**

## 适用场景
本仓库里任何一次"改 RTL → 上台架 → 出报告 → 上板"的闭环。
症状：拖影 / 黑横纹 / 卡死 / 左窗不跟随 / 画面 4 幅或窄条 / OSD 数字不对 / JTAG 找不到器件 / ping 不通。
不适用：画质类判定的收敛（缩放走样、色彩、抖动只能靠眼睛，见 `report/AI_COLLABORATION.md` §6）；
布局不是 `src/rtl + sim + build/tcl` 的工程（下面每条路径都是仓库根相对路径，换布局就要全部重指）。

## 脚本在哪（本目录不放副本）

`scripts/` 原来那份 `run_sim.tcl` 已删除：它是 `sim/run_sim.tcl` 的旧拷贝，
还按 V5 时代的 `rtl_base/ + rtl_fix/` 目录找文件，在本仓库布局下会 `FATAL missing` 退出——
**技能包里带一份会引导别人跑错的脚本，比不带更糟**。仓库根那一份才是真的：

| 要跑什么 | 用哪个文件 |
|----------|------------|
| 全量台架（一次跑完所有 `sim/tb_*.v`） | [`../../sim/run_sim.tcl`](../../sim/run_sim.tcl) |
| 单个台架快速迭代（只编要编的文件） | [`../../sim/run_one.sh`](../../sim/run_one.sh) |
| 建工程 + BD + 综合实现 + bit + xsa | [`../../build/tcl/build_system_axigpio.tcl`](../../build/tcl/build_system_axigpio.tcl) |
| 新模块上全流程前的结构预检 | [`../../build/tcl/ooc_newmods.tcl`](../../build/tcl/ooc_newmods.tcl)（`OOC_ONLY=<模块名>` 一次一个；它的数字**不是门禁**，对输入一律加 3 ns） |
| 下 bit / 起 PS / 选显示源 | `build/tcl/{program_pl,program_system,ps_jtag_boot,set_src,scan_jtag}.tcl` |
| 门禁复核 | `bash ../../build/gates.sh`（它检查什么、红了先看哪里，见 README 的 C 表） |

## 使用方法：按层推进，每层都要留下一条能复跑的判据

| 层 | 手段 | 判据 |
|----|------|------|
| **L0 读码** | 直读 RTL + `git diff --stat`；端口/信号逐个对（R03 抽模块就是这么核的） | 每一条"应该连上"的线都能说出两侧模块与位宽；说不出就加观测口，别继续推 |
| **L1 仿真** | `vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl`；单个 `bash sim/run_one.sh tb_xxx`；只编译 `SIM_ONLY=1`；plusargs `SIM_ARGS="+FULL +MISALIGN"` | 每个 TB 自己打 `RESULT <tb> PASS`，末行 `SIM DONE pass=N fail=0`。**一个断言都没有的 TB 计 FAIL**（`NO_ASSERT` 不当绿） |
| **L2/L3 出报告** | `build/tcl/build_system_axigpio.tcl` → 读 `build/{timing_summary,utilization,power,route_status,methodology,cdc}.rpt` | 时序两项 ≥0 且失败端点 0、BRAM/Slice 不越阈值、功耗不明显恶化、CDC 配对不新增、无新增 Critical。红项照实写进报告，不改阈值 |
| **L4 上板** | `xsdb.bat build/tcl/ps_jtag_boot.tcl <ps7_init.tcl>` → `program_pl.tcl` → `set_src.tcl` → `node src/host/video_sender.mjs --test frameid …` → **停流**后 `node src/host/ddr_verify.mjs --frameid` / `ddr_stale.mjs`；链路计数 `node src/host/health_read.mjs --gapclr` | 每 bank 帧号跨度 = 1、逐 lane 命中率、包内分带丢字率、`hb_slow`/`frames_bad`。回读会把 PS 停住：复测前必须重跑三件套 |

`<ps7_init.tcl>` 用构建产出的
`vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/ip/design_1_processing_system7_0_0/ps7_init.tcl`，
或直接从 `build/system.xsa` 里解出来。

## 四步纪律（都是踩出来的，一条都不要省）

1. **测量先于改动**：先跑判据矩阵再动代码 —— SRC0 无流（验 HDMI/时序本体）、SRC0 有流（验入包链是否
   干扰显示）、SRC1 正常流、**SRC1 停流冻结帧**（区分"静态坏数据"与"读写同址冲突"）。
   "停流仍脏 ⇒ 是没被写过的 BRAM 字（值 0 = 黑），不是读写冲突"这条就是这么量出来的。
2. **一次构建只动一个架构变量**；allow 窗口 / 写引擎 / saver 三处永不捆绑改。
3. **仿真用生产几何**：512×300 源、1024×600 显示、H=1344 V=625 @50 MHz、1392 B 分包。
   小几何会绿而板上失败——`sim/tb_timing.v` 是 16×8、`sim/tb_v6_pingpong.v` 是 512×60，
   它们的绝对数值只能当"机理形状"用。
4. **每一轮把假设/改动/仿真结果/板级结果/是否回退写进 `report/`**，每条说法给出文件与数字；
   没验的写"没验"。判据级别要如实降级：板上 A/B 没有区分力时，证据只能写到"机理 + 仿真"为止。

## 失效条件（这几条不要在本文件里再抄一遍，指向它的唯一住处）

- **换工具版本 / 换器件 / 两套 FT2232 撞号 / 参数三处写死 / 时钟比例一改整张槽位表作废 /
  没核 md5 就下板** → 见 [../README.md](../README.md) 的 D1、D3 与
  [S10](../derived_clock_port_mux.md)、[S15](../artifact_freeze_and_freshness.md)、
  [S7](../board_eth_uart.md)；本目录不再各写一遍。
- **禁止清单仍然有效**（无新证据不得采纳）：V-blank-only allow 当主修、mute 当主修、burst saver、
  双显示 BRAM（`report/OVERNIGHT_LOG.md` U3：整帧拷贝要吸收的窗口需 ≈84 个 BRAM tile 而全片只有 140
  ⇒ 加深缓冲结构上不可行）。
- **同一进程连跑三次 `synth_design`** 会撞 Windows `.Xil` 目录锁并**静默跳过后面的模块**；
  `ERROR: [Common 17-217] Failed to load feature 'core'` 是内存不足，不是 RTL 问题
  （`report/ISSUES.md` 快速对照）。

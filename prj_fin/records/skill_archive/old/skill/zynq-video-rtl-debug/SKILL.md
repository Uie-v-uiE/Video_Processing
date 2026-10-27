---
name: zynq-video-rtl-debug
description: Layered (L0-L4) RTL debug and single-variable fix protocol for this workspace's Zynq7020 UDP-to-DDR-to-HDMI video pipeline (src/rtl/**, sim/, build/tcl/, report/). Use when editing any .v under src/rtl, running xsim testbenches via sim/run_sim.tcl or sim/run_one.sh, rebuilding the bitstream with build/tcl/build_system_axigpio.tcl, or interpreting board results recorded in report/log/OVERNIGHT_LOG.md and data/measured/. Enforces production-geometry sims, report gates, and "no claim without a file+number".
---

# S8 · 上板不亮 / 画面异常时的分层定位（L0–L4）

条目索引与其余各条在 [../README.md](../README.md)；工作纪律与提示词模板在 [../SKILL.md](../prompts/round-work-loop/SKILL.md)。
本文件只管一件事：**症状出来之后按什么顺序往下剥，每一层用什么命令、判据是什么。**

## 1. 一句话用途
上板不亮或画面异常时，按 L0→L4 一层一层往下判，每层留一条能复跑的判据。
## 2. 适用场景
本仓库里任何一次"改 RTL → 上台架 → 出报告 → 上板"的闭环。
症状：拖影 / 黑横纹 / 卡死 / 左窗不跟随 / 画面 4 幅或窄条 / OSD 数字不对 / JTAG 找不到器件 / ping 不通。
不适用：画质类判定的收敛（缩放走样、色彩、抖动只能靠眼睛，见 `report/AI_COLLABORATION.md` §6）；
布局不是 `src/rtl + sim + build/tcl` 的工程（下面每条路径都是仓库根相对路径，换布局就要全部重指）。

## 3. 不适用 / 失效条件

- **换工具版本 / 换器件 / 两套 FT2232 撞号 / 参数三处写死 / 时钟比例一改整张槽位表作废 /
  没核 md5 就下板** → 见 [../README.md](../README.md) 的 D1、D3 与
  [S10](../pitfalls/derived-clock-port-mux/SKILL.md)、[S15](../pitfalls/artifact-freeze-and-freshness/SKILL.md)、
  [S7](../runtime/board-eth-uart/SKILL.md)；本目录不再各写一遍。
- **禁止清单仍然有效**（无新证据不得采纳）：V-blank-only allow 当主修、mute 当主修、burst saver、
  双显示 BRAM（`report/log/OVERNIGHT_LOG.md` U3：整帧拷贝要吸收的窗口需 ≈84 个 BRAM tile 而全片只有 140
  ⇒ 加深缓冲结构上不可行）。
- **同一进程连跑三次 `synth_design`** 会撞 Windows `.Xil` 目录锁并**静默跳过后面的模块**；
  `ERROR: [Common 17-217] Failed to load feature 'core'` 是内存不足，不是 RTL 问题
  （`report/log/ISSUES.md` 快速对照）。
## 4. 前置条件

`scripts/` 原来那份 `run_sim.tcl` 已删除：它是 `sim/run_sim.tcl` 的旧拷贝，
还按 V5 时代的 `rtl_base/ + rtl_fix/` 目录找文件，在本仓库布局下会 `FATAL missing` 退出——
**技能包里带一份会引导别人跑错的脚本，比不带更糟**。仓库根那一份才是真的：

| 要跑什么 | 用哪个文件 |
|----------|------------|
| 全量台架（一次跑完所有 `sim/tb_*.v`） | [`../../sim/run_sim.tcl`](../../sim/run_sim.tcl) |
| 单个台架快速迭代（只编要编的文件） | [`../../sim/run_one.sh`](../../sim/run_one.sh) |
| 建工程 + BD + 综合实现 + bit + xsa | [`../../build/tcl/build_system_axigpio.tcl`](../../build/tcl/build_system_axigpio.tcl) |
| 新模块上全流程前的结构预检 | [`../../build/tcl/ooc_newmods.tcl`](../../build/tcl/ooc_newmods.tcl)（`OOC_ONLY=<模块名>` 一次一个；它的数字**不是门禁**，对输入一律加 3 ns） |
| 下 bit / 起 PS / 选显示源 | 三件套 `build/tcl/{ps_jtag_boot,program_pl,ps_app_reload}.tcl`；选源是 `build/tcl/set_src.tcl`；链上有没有器件是 `scan_jtag.tcl` |
| 门禁复核 | `bash ../../build/gates.sh`（它检查什么、红了先看哪里，见 README 的 C 表） |

## 5. 使用方法

| 层 | 手段 | 判据 |
|----|------|------|
| **L0 读码** | 直读 RTL + `git diff --stat`；端口/信号逐个对（R03 抽模块就是这么核的） | 每一条"应该连上"的线都能说出两侧模块与位宽；说不出就加观测口，别继续推 |
| **L1 仿真** | `vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl`；单个 `bash sim/run_one.sh tb_xxx`；只编译 `SIM_ONLY=1`；plusargs `SIM_ARGS="+FULL +MISALIGN"` | 每个 TB 自己打 `RESULT <tb> PASS`，末行 `SIM DONE pass=N fail=0`。**一个断言都没有的 TB 计 FAIL**（`NO_ASSERT` 不当绿） |
| **L2/L3 出报告** | `build/tcl/build_system_axigpio.tcl` → 读 `build/{timing_summary,utilization,power,route_status,methodology,cdc}.rpt` | 时序两项 ≥0 且失败端点 0、BRAM/Slice 不越阈值、功耗不明显恶化、CDC 配对不新增、无新增 Critical。红项照实写进报告，不改阈值 |
| **L4 上板** | `xsdb.bat build/tcl/ps_jtag_boot.tcl <ps7_init.tcl>` → `program_pl.tcl` → `set_src.tcl` → `node src/host/video_sender.mjs --test frameid …` → **停流**后 `node src/host/ddr_verify.mjs --frameid` / `ddr_stale.mjs`；链路计数 `node src/host/health_read.mjs --gapclr` | 每 bank 帧号跨度 = 1、逐 lane 命中率、包内分带丢字率、`hb_slow`/`frames_bad`。回读会把 PS 停住：复测前必须重跑三件套 |

`<ps7_init.tcl>` 用构建产出的
`vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/ip/design_1_processing_system7_0_0/ps7_init.tcl`，
或直接从 `build/system.xsa` 里解出来。


### 四步纪律（都是踩出来的，一条都不要省）


1. **测量先于改动**：先跑判据矩阵再动代码 —— SRC0 无流（验 HDMI/时序本体）、SRC0 有流（验入包链是否
   干扰显示）、SRC1 正常流、**SRC1 停流冻结帧**（区分"静态坏数据"与"读写同址冲突"）。
   "停流仍脏 ⇒ 是没被写过的 BRAM 字（值 0 = 黑），不是读写冲突"这条就是这么量出来的。
2. **一次构建只动一个架构变量**；allow 窗口 / 写引擎 / saver 三处永不捆绑改。
3. **仿真用生产几何**：512×300 源、1024×600 显示、H=1344 V=625 @50 MHz、1392 B 分包。
   小几何会绿而板上失败——`sim/tb_timing.v` 是 16×8、`sim/tb_v6_pingpong.v` 是 512×60，
   它们的绝对数值只能当"机理形状"用。
4. **每一轮把假设/改动/仿真结果/板级结果/是否回退写进 `report/`**，每条说法给出文件与数字；
   没验的写"没验"。判据级别要如实降级：板上 A/B 没有区分力时，证据只能写到"机理 + 仿真"为止。

## 6. 判读与失败分叉
| 这一层的动作 | 通过 | 失败 | 读不到输入 |
| --- | --- | --- | --- |
| L0 上电与 JTAG 链 | 链子在，继续 L1 | 链空 ⇒ 先分清是板子没上电还是线缆/hw_server，不许直接改 RTL | `NOT_MEASURED`：这一层没读数，别当通过 |
| L1 位流是否配进去 | DONE=1 且读回一致 ⇒ 进 L2 | 没配上 ⇒ 重跑 `program_pl.tcl` 那一步，仍然失败就查 DONE/供电 | `NOT_MEASURED`：读不到 DONE 状态就是没测 |
| L2 PS 是否起来 | DDR 自检回读到写入值 ⇒ 进 L3 | 起不来 ⇒ 按 `build/tcl/ps_jtag_boot.tcl` 的顺序复位重来，AP 不可达只能断电重上 | `NOT_MEASURED`：串口/hw_server 被别的进程占用时不算失败也不算过 |
| L3 数据通路计数 | 计数与流量同向增长 ⇒ 进 L4 | 计数不动 ⇒ 查片源与使能链，不改判据 | `NOT_MEASURED` |
| L4 屏上现象与人眼判据 | 现象与 OSD 读数一致 ⇒ 结案 | 不一致 ⇒ 回 L3 找是哪一段说谎，最后一条永远是人眼那格 | `NOT_MEASURED`：没人看屏就不能写"已验证" |
## 7. 已验证的效果

- **L4 的第一格就是被它救回来的**：`ping` 发送=3 / 接收=3 / 丢失=0 与 `DDR_ECHO`、`PROGRAMMED xc7z020_1`
  三行连起来读，才把"没画面"从"网口坏了"改成"PS 没重起"（`report/log/OVERNIGHT_LOG.md` §「L4 执行」）。
- **L1 的一条"没有断言就不算绿"**把整类假绿堵住了：`sim/run_sim.tcl` 不再把 `NO_ASSERT` 计为 pass
  （`report/log/OVERNIGHT_LOG.md` R13 第 3 条）——起因是一个什么都不断言的台架可以永远绿。
- **机器那一半跑通、并且说得清是谁跑的**：`bash build/board_verify.sh --battery --geom` 退出码 **0**
  （串口电池 99/99、`geom_check ok=8 fail=0`，`build/evidence/verify_0927_2309*.txt`），
  同一轮的位流身份是**它的 md5**而不是文件名（每次上板生成的 flash 日志是工具输出，不入库，所以能带走的是那串 md5）。
- **它救过最贵的一次是反着用的**：门禁全绿而唯一例化顶层的台架连着红了好几版，因为门禁当时不跑它
  （`report/log/ISSUES.md` #88/#78）⇒ "分层"不是走过场，每一层都得有一条真的会红的判据。

## 8. 提炼来源与边界
- 来源证据：`report/log/OVERNIGHT_LOG.md` 的分层记录与 `report/log/ISSUES.md` 里板级那一族（含 `#216`/`#218` 那两条：应答器几分钟后再 ping 就不回、0 长度载荷把收包机楔死）。
- 不再适用：非 Zynq 裸机流程（带 FSBL/FreeRTOS/PYNQ 的工程），或板上没有可读回的计数寄存器时——L3 那一层直接失能，只能退到示波器/抓包。
- 迁移要改的三处：位流加载脚本的名字、DDR 自检地址、以及 L4 那一格由谁看（屏上 OSD 还是串口回显）。

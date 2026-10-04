# `build/` —— 一条命令复现这一版，外加综合与实现报告

这里只有两类东西：**能跑的构建脚本**与**这一版跑出来的报告**。报告是 Vivado 自己产出的原文，
不做二次加工；脚本按下面三步走就能得到同一块位流。工具版本：Vivado / Vitis 2025.2.1，
器件 `xc7z020clg484-2`。

这个目录里具体有什么：

| 路径 | 是什么 |
|---|---|
| `tcl/` | 构建与查询脚本，入口是 `tcl/build_system_axigpio.tcl` |
| `reports/` | 综合与实现报告（时序汇总、资源、功耗、布线状态、方法论、CDC…）+ 随包的判据报告 |
| `build_ps_app.py` | 不开 IDE 也把 `src/ps` 编成 ELF，并对成品做自检 |
| `gates.sh`、`board_verify.sh` | 门禁与上板回读（复现的第二、三步） |
| `check_ports.py`、`check_skill_cards.py`、`freeze_evidence.sh`、`tb98_report.sh` | 上面两个脚本自己要调的辅助脚本 |

位流、XSA 与固件在仓库里就落在 `build/system.bit` / `build/system.xsa` / `build/ps_app.elf`
（这三个是构建输出，不进 git）；**提交包里**它们与上板要用的 tcl、串口脚本、实测输出一起放到
`board/` 那一边（`board/project/`、`board/tcl/`、`board/scripts/`、`board/output/`），
因为评委在板级目录要找的就是"往板上放什么、怎么放、放完读回来是什么"。
仓库里那一堆逐轮留档（`build/evidence*/`、`build/frozen*/`、`*_rNN.txt`、探针与扫描的 console）
都不随包 —— 它们是作者的时间轴；文档里点到它们的地方已改成"仓库留档 <名>（不随包）"，不留假链接。

仓库里还有一批开发工具（滚一轮对照、注释手术、孤儿 RTL 扫描等）**不随包**：它们不在复现链上，
文档里提到它们的地方已改成"仓库里的某某（工具，不随包）"，不留假链接。


## 复现（唯一入口）

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
```

它做四件事：建工程 → 收 RTL/约束/BD（清单在 `build/tcl/set_src.tcl`）→ 综合 → 实现并出位流。
跑完的产物：`build/system.bit`、`build/system.xsa`、`build/ps_app.elf`，以及
`build/reports/` 里的 `timing_summary.rpt`、`utilization.rpt`、`power.rpt`、
`route_status.rpt`、`methodology.rpt`、`cdc.rpt`。中途任何一步失败，脚本会打印它停在哪一步，
不会带着半套产物退出。

```bash
bash build/gates.sh                 # 门禁：时序/资源/端口/CDC/文档一致性（项数以脚本打印的那行为准）
VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom   # 上板回读与串口命令电池
```

门禁里任何一项判红，这一版就**不采纳**、不冻结；脚本自己会念"有红项"还是"全部判定"。

## `tcl/` 里各脚本干什么

| 脚本 | 用途 |
|---|---|
| `build_system_axigpio.tcl` | **入口**，上面那条命令跑的就是它 |
| `set_src.tcl` | 文件清单：哪些 RTL/约束/BD 进这一版位流，只在这里决定 |
| `create_project.tcl`、`build_system.tcl`、`build_bitstream.tcl`、`build_pl_full.tcl`、`synth_pl_only.tcl` | 入口调用的分段步骤，单独跑是给调试用 |
| `crit_path.tcl`、`hold_paths.tcl` | 只读查询：关键路径逐条（逻辑级数 / 布线占比）、保持时间最差路径 |
| `report_mem_hier.tcl`、`cdc_who.tcl` | 只读查询：BRAM 按模块归属、CDC 发射端清单 |
| `sweep_impl_strategy.tcl`、`read_run_result.tcl` | 实现策略扫描与读数（时序采纳就是拿这两条比） |
| `ooc_newmods.tcl` | 新模块 out-of-context 快速综合，先看资源再谈集成 |
| `scan_jtag.tcl` | JTAG 链诊断（跑法是 `vivado -mode batch -source`，不是 xsdb） |
| `ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl` | 上板三件套：PS 起来 → 烧 PL → 重载应用。**全程只走 JTAG，本工程的脚本从不向 QSPI/SPI flash 写入** |

## 报告怎么读

- `reports/timing_summary.rpt` 的第一段 Design Timing Summary 给 WNS / TNS / 失败端点数；
   slack 的绝对值在相邻两版之间会摆零点几 ns（放置运气），所以判断"有没有变好"要同口径复跑，
  不看单个 WNS。
- `reports/utilization.rpt` 给 Block RAM Tile、LUT、FF、DSP；BRAM 要分清是
  `RAMB36/FIFO*` 的**单元数**还是 `Block RAM Tile` 的**瓦片数**，两个数不一样。
- `reports/power.rpt` 是**估算**（没有仿真活动文件、没有实测），引用时必须说"估算"。

---

# P15a 增补（2026-10-04）：入口、落点、耗时、失败指路、自探测清单

这一节是**追加**的，上面原文一行没删（`build/README.md` 是已入库文件，且 `report/log/ISSUES.md` 按行号
指过它）。**先说清一处与本节冲突的旧句**：上面写的 `build/reports/`（以及"产物落在 `build/reports/`"）
描述的其实是**导出包里的布局**，不是构建落点 —— 本仓当前**没有** `build/reports/` 目录
（本次实跑 `[ -d build/reports ]` → NO），`build/reports/` 只由 `build/make_submission.sh` 在打包时
`mkdir -p`（该文件 `:224`、`:333`、`:371` 的展平段）并把 `build/**.rpt|txt` 复制进去。
构建自己写报告的位置见下面第 3 节。

## 1. "一条命令"到底是哪一条（逐字）

分两层，**别把它们混成一条**：

**A. 只出硬件产物（位流 + XSA + 7 份报告）** —— 从**仓库根**起：

```bash
"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl
```

入口脚本内部的实际调用序列（逐条按脚本行号读出来的，不按记忆重排）：
`create_project -force`（`:9`）→ 收 RTL glob 十个目录 + 两个顶层（`:13-18`）→
加 `rk_zynq7020.xdc`（`:19`）→ 加 `clock_groups_impl.xdc` 并设 `used_in_synthesis false` /
`used_in_implementation true`（`:24-26`）→ **两档默认关的候选约束**按环境变量加载（`:45-52`、`:63-70`）→
`create_bd_design` / PS7 + 3×axi_gpio + 2×interconnect / 连线 / `make_bd_intf_pins_external`
（`:72-224`）→ 端口改名用"前后集合 diff"而不是返回值（`:205-223`）→ `assign_bd_address` + 三个基址钉死 +
逐段回读 `ADDR_LOG`（`:227-262`）→ `validate_bd_design` → `save_bd_design`（`:261-263`）→
（可选 `-tclargs bd_only` 在此早退，`:266`）→ `make_wrapper` + `add_files`（`:267-272`）→
`set_property top system_top` + `update_compile_order`（`:276-277`）→ `launch_runs synth_1 -jobs 4` +
`wait_on_run` + `PROGRESS != 100%` 则 `exit 1`（`:287-292`）→ 三个旋钮（`:298-333`）→
`launch_runs impl_1 -to_step write_bitstream -jobs 4` + `wait_on_run`（`:334-335`）→
`file copy -force` 位流（`:341`）→ `open_run` 后连出 7 份报告（`:342-351`）→
`write_hw_platform -fixed -include_bit -force`（`:352`）→ 扫各 run 的 `runme.log` 数
`Synth 8-689` 与 multi-driven 并落两份凭据（`:365-390`）→ `puts "SYSTEM BUILD DONE"`（`:392`）。

**B. 一整轮（指纹→构建→名册→判读→门禁两跑→采纳/回刷→上板）** —— 每一轮有一份同名链脚本，
r118 用的就是这一份，从**仓库根**起：

```bash
export VP_VIVADO_BIN=<Vivado>/bin          # 必须显式给，见下面第 2 节
export VP_XSDB=<Vitis>/bin/xsdb.bat        # 必须显式给
unset IMPL_POST_PLACE_HOOK VP_R116_IO_WINDOW
bash build/r118_chain.sh
```

它逐字做：`cd "$(dirname "$0")/.."`（`:20`，所以**从哪个终端起都一样**）→ 要求两个环境变量
（`:22-23`）→ 清掉两个旋钮（`:24`）→ **先采指纹**（`:27`，P15a 铁律 1）→ 跑 A 那条 Vivado（`:30`）→
`[ -s 位流 ]` 否则 `exit 2`（`:35`）→ 位流 md5 前 12（`:36`）→ 名册探针 `probe_timing_roster.tcl`（`:38`）→
两套差分尺子（`:42` 与内嵌 python 的严格口径 `:45-71`）→ 改前/改后读数（`:73`）→ 写 `r118_verdict.txt`（`:75-82`）→
门禁两跑并 `cmp` 是否逐字节一致（`:84-88`）→ 采纳则 `build/evidence/r118_bit/` + 刷板，
否则回刷上一版（`:93-102`）→ `board_verify.sh`（`:103`）→ 写 `BOARD_NOW.txt`（`:104-108`）。

**C. PS 侧固件**（不在 A/B 里，必须单独一条）：

```bash
node build/ps_app.mjs          # 需要 PS_CC / PS_BSP，默认平台在仓库内 vitis/platform/…（ps_app.mjs:26-29）
```

## 2. 需要的环境变量（以及一处会让人误会的写法）

| 变量 | 谁读它 | 不给会怎样 |
|---|---|---|
| `VP_VIVADO_BIN` | 各链脚本与门禁辅助脚本 | `build/r118_chain.sh:22` 用 `${VP_VIVADO_BIN:?…}` 直接中止。**注意**：同一脚本 `:21` 写的 `V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}` 那个默认值在 `:22` 面前是**死代码** —— 变量没给就中止、给了就用给的，永远轮不到默认值。照抄这份链做新脚本时要么删掉 `:21` 的默认，要么把 `:22` 改成给默认（现状是"看着有兜底、其实没有"） |
| `VP_XSDB` | 上板侧（如 `build/board_verify.sh:114` 会 `[ -f "$VP_XSDB" ]` 判存在） | `exit 2`，写明"找不到 xsdb" |
| `IMPL_STRATEGY` | 入口 `:298-304` | 不设 = 工程默认；设了会把名字打进日志（`BUILD_STRATEGY …`），拒绝则 `exit 1` |
| `IMPL_POST_PLACE_HOOK` | 入口 `:309-317` | 不设 = `BUILD_POST_PLACE_HOOK none` |
| `IMPL_PRPO` | 入口 `:322-333` | 不设 = `BUILD_PRPO off` |
| `VP_R116_IO_WINDOW` / `VP_R119_TMDS_WINDOW` | 入口 `:45-52` / `:63-70` | 都不设 = 两个候选约束不加载；日志会各念一行 `off` |
| `FP_ROOT` | `build/rtl_fingerprint.sh:25` | 默认取脚本所在目录的上一层（=仓库根），一般不用给 |
| `KX_RUN_DIR` | `build/freeze_evidence.sh:24` | 默认 `/tmp/kx`（沙箱自测要用它隔开真机凭据） |
| `VP_LABEL` / `VP_N` | 名册探针调用（`build/r118_chain.sh:38`） | 决定名册件前缀与探针路数 |

## 3. 产物落在哪（真实路径，非导出包路径）

| 类别 | 路径 |
|---|---|
| 位流 / 平台 | `build/system.bit`、`build/system.xsa` |
| 固件 | `build/ps_app.elf`（**只有跑过 C 那条才更新**） |
| 报告 | `build/timing_summary.rpt`、`build/utilization.rpt`、`build/cdc.rpt`、`build/methodology.rpt`、`build/power.rpt`、`build/route_status.rpt`、`build/clock_util.rpt` |
| 门禁凭据 | `build/width_warnings.txt`、`build/multi_driven.txt` |
| 工程与中间件 | `vivado_system/zynq_video_sys.runs/{synth_1,impl_1,…}/`（整目录被 `.gitignore:2` 忽略） |
| 检查点（P15a 铁律 4，本仓是 Vivado 自动落的 dcp，不是脚本落的） | `…/runs/synth_1/system_top.dcp`、`…/impl_1/system_top_opt.dcp`、`_placed.dcp`、`_physopt.dcp`、`_routed.dcp` |
| 采纳副本 | `build/evidence/rNN_bit/system.bit` + 同目录 `md5.txt`（`build/r118_chain.sh:94-95`） |

检查点能干什么（**只写用途，不在此设计复算逻辑，那是 P15c**）：开只读探针拿布局后/布线后的数
（`open_checkpoint`/`open_run` 一条命令，不重跑 RTL），或低成本复算物理结果；
台账 `report/log/ISSUES.md` #310 记着"在已布线 DCP 上改 `IDELAY_VALUE` 有效 ⇒ 扫档位不必重跑构建"，
就是这一类用法的实例。r118 的五个 dcp 落盘时刻（盘上 mtime）：synth 04:29、opt 04:30:54、
placed 04:32:31、physopt 04:32:41、routed 04:36:27。

归档命名规则与"规则 vs 现状"的对照在 `build/artifacts/README.md`；本轮成品的来源卡是
`build/provenance.md`；残留进程防护的实况与配方在 `build/probe-guard.md`。

## 4. 分阶段耗时（只从已有日志时间戳算，出处都点名）

算式：起讫取 `build/r118_build_console.txt` 里 Vivado 自己打的 `[Sun Oct 4 …]` 行与
`build/r118_console.txt` 的链时间戳；步内耗时取该日志里的 `…: Time (s): … elapsed = …` 行。
**不预测重建会花多久**（同一台机器、同一份 RTL 也不能保证逐位相同，见 `provenance.md` 第 3 节"无 seed"）。

| 阶段 | 起 → 止 | 墙钟 | 出处（行号） |
|---|---|---|---|
| 源码指纹 | 04:18:25 | <1 s | `build/r118_console.txt:1` |
| 建工程 + 收文件 + 建 BD + 地址 + wrapper | 04:18:27 → 04:19:26 | **59 s** | 会话横幅 `:6` → `Launched synth_1` `:283`；其中 `create_project` 自身 elapsed 9 s（`:18`） |
| `synth_1`（含 6 个 OOC IP 并行） | 04:19:26 → 04:29:35 | **10 min 09 s** | `:283` → `:1743`；`wait_on_runs … elapsed = 00:10:09`（`:1744`） |
| └ 其中 `synth_design` 本体 | — | 6 min 30 s | `:1738` |
| `impl_1` 总 | 04:29:37 → 04:36:59 | **7 min 22 s** | `:1781` → `:2619` |
| └ `opt_design` | — | 27 s | `:2030` |
| └ `place_design` | — | 1 min 32 s | `:2290` |
| └ `phys_opt_design` | — | 7 s | `:2324` |
| └ `route_design` | — | 3 min 10 s | `:2543` |
| └ `write_bitstream` | 04:36:27 → 04:36:57 | 29 s | `:2617` + `impl_1/.write_bitstream.{begin,end}.rst` 的 mtime |
| 出 7 份报告 + XSA + 两份凭据 | 04:36:59 → 04:37:57 | **58 s** | `:2619` → 末行 `Exiting Vivado at … 04:37:57`；各文件 mtime 04:37:30…04:37:57 |
| **构建合计** | 04:18:27 → 04:37:57 | **19 min 30 s** | 同上 |
| 名册 + 差分 + 读数 + 判读 | 04:37:58 → 04:41:01 | 3 min 03 s | `build/r118_console.txt:3,11` |
| 门禁两跑 | 04:41:01 → 04:42:27 | 1 min 26 s | 同文件 `:11-12` |
| 刷板一轮（JTAG 复位→boot→program→读回） | 04:45:26 → 04:47:07 | 1 min 41 s | `build/evidence/r118_board/bitcycle_console.txt` 首末行 |
| PS 固件单独编译 | 【待实测】 | 【待实测】 | 本轮没有跑 `node build/ps_app.mjs`，现有日志里也没有它的时间戳 ⇒ 不给估计 |

可中断点：`-tclargs bd_only`（入口 `:266`）在 BD 建完就 `exit 0`，脚本注释自己写明理由 ——
"BD 配置写错本来 3 分钟就能验出来，不必等 20 分钟的综合+实现"（`:264-265`）。

## 5. 失败先看哪个日志（按顺序，不要先看退出码）

1. **`build/rNN_build_console.txt`**（A 那条命令的 stdout）。先 grep 这几个 token，命中哪个就是哪一步停的：
   `SYNTH FAILED`、`ADDRESS PINNING FAILED`、`PORT_LOOKUP_FAILED`、`BUILD_STRATEGY_REJECTED`、
   `BUILD_HOOK_REJECTED`、`BUILD_PRPO_REJECTED`；全都没有而缺末行 `SYSTEM BUILD DONE` ⇒ 中断在工具侧。
2. `vivado_system/zynq_video_sys.runs/synth_1/runme.log` —— 综合报错与 `Synth 8-689` / `8-6859` 原文在这里
   （入口 `:365-376` 数的就是它）。
3. `…/runs/impl_1/runme.log` —— DRC / 布局 / 布线 / `Route 35-57` 那行 Estimated Timing Summary 在这里。
4. `build/*.rpt` 与 `build/{width_warnings,multi_driven}.txt` 的 mtime —— 判断"报告是不是这一版的"。
5. 上板失败：`build/evidence/rNN_board/bitcycle_console.txt` → 同目录 `board_verify_console.txt` → `BOARD_NOW.txt`。
6. 门禁红：`build/rNN_gates.txt`（跑法必须两步，**不要把 stdout 直接重定向进它自己要读的凭据文件**，
   该脚本文件头 `:12-19` 记着这个自伤）。

**为什么"不要先看退出码"**：`build/tcl/README.md:19-23` 明写同级两个脚本 `add_files` 指向错根、
**报错之后仍然 exit 0**，并要求"跑完必须自己去 `build/` 里核对报告的时间戳，不要相信退出码"。

## 6. 入口差异：两个同级脚本按不同根解析（教训的实形）

本次用一条 grep 把根解析形状全数出来（这就是台账 #41 教的"按缺陷类别扫"的签名）：

```bash
grep -n "file dirname \[info script\]" build/tcl/build_system*.tcl build/tcl/create_project.tcl build/tcl/synth_pl_only.tcl build/tcl/build_bitstream.tcl
```

| 脚本:行 | 写法 | 归一化后的 `root` |
|---|---|---|
| `build/tcl/build_system_axigpio.tcl:2` | `… [file dirname [info script]] .. ..` | **仓库根（正确）** |
| `build/tcl/build_system.tcl:2` | `… ..`（一级） | `build/` |
| `build/tcl/build_pl_full.tcl:2` | `… ..` | `build/` |
| `build/tcl/create_project.tcl:9` | `… ..` | `build/` |
| `build/tcl/synth_pl_only.tcl:3` | `… ..` | `build/` |
| `build/tcl/build_bitstream.tcl:8` | `… ..` | `build/` |

后果（逐条有实体，不是我推的）：`add_files` 指向 `build/src/…`（不存在）；
`file mkdir $outdir` 会凭空造出 `build/build/`（**这个空目录现在还在盘上**，本次 `ls -la build/build/`
只有 `.` 与 `..`，mtime 2026-09-26 02:54）；`build_system.tcl` 那一份还会去找 `build/build/system.bit`。
台账 `report/log/ISSUES.md` 把这一族记在 **#22**，并把"扫描要按类别而不是按我今天看到的那串字符"
记在 **#41**（#41 同时修掉了 3 支**下板**脚本，构建侧这几支**故意留着不动**，因为
`report/log/CHANGELOG_V7.md` 与 ISSUES 若干条目按名字指它们 —— 见 `build/tcl/README.md:3-6`）。
另一层差异：`create_project.tcl` 的用法注释写的是 `-source tcl/create_project.tcl`（`:2-6`），
即**假定 cwd = `build/`**；而 `build_system_axigpio.tcl` 因为用 `.. ..`，
从仓库根（`-source build/tcl/…`）或从 `build/`（`-source tcl/…`）起都能归一到仓库根。
⇒ **规矩只有一条：构建只认 `build_system_axigpio.tcl`，并且从仓库根起；其余同级脚本是历史分段步骤。**

## 7. 脚本开工前的自探测清单（可核对，逐条对回现有脚本实际做了什么）

判定口径：`有`= 现行入口或现行链里真有这一行；`部分`= 只在某些历史轮脚本里有；`缺`= 没有。
"缺，导致"那一栏只写能判定的后果，不写"可能会有问题"。

| # | 该探的 | 现有脚本做了吗（对回行号） | 缺，导致 |
|---|---|---|---|
| P1 | 工具是否存在 | **有**（但不是入口本身）：`build/r116_chain.sh:18`、`build/check_powup_init.sh:83` 都是 `[ -f "$V/vivado.bat" ] || exit 2`；`build/board_verify.sh:114` 探 `VP_XSDB`。链脚本 `:21-22` 只探"变量给没给"，**不探那个路径下真有 vivado.bat** | 变量给错（少一层、Windows 斜杠方向）时报的是"命令找不到"，而不是"工具不在"，新人会去查 PATH 而不是查变量 |
| P2 | 版本**等于**声明值 | **缺**。全仓没有任何一处做等值断言；版本串只是 Vivado 自己打进横幅（`build/r118_build_console.txt:1-4`）。`build/freeze_evidence.sh:118` 那句 `2025.2.1` 是**文案**不是断言 | 换版本后照跑、照覆盖已采纳产物，只有事后读报告才发现工具不是那一版 ⇒ 来源卡的版本只能靠"当时留了日志"，见 `probe-guard.md` 第 3 节 |
| P3 | 器件是否在设备库 | **缺**（靠 `create_project -part` 自己报错）。手工核对办法本次验过：`grep -o "xc7z020[a-z0-9]*" <Vivado>/data/parts/installed_devices.txt` 回 `xc7z020` / `xc7z020clg484` / `xc7z020i` | 报错形状像"工程打不开"而不是"器件缺"，多花一轮排查 |
| P4 | 磁盘余量 | **缺**（`grep -rnE "df -|Avail" build/*.sh` 无相关命中）。本次实测当前盘：330G 总 / 113G 可用 / 66% 已用 | 写满盘 ⇒ 位流半截、报告 0 字节，门禁读成解析失败；0 字节日志也不证明"还没开始"（P23 第 5 节） |
| P5 | 有没有同名进程正在写目标目录 | **部分**：进程名探测有 10 处（`build/r108_stage2.sh:13`、`r109_stage2.sh:16`、`r110_apply_cuts.sh:35-36`、`r113_chain2.sh:18`、`r113_roster_refanout.sh:22,25`、`r113_step5_rotate.sh:18`、`r114_replication_ab.sh:65`、`r115_c2_verdict.sh:22`、`r115_fanout_ab.sh:43`），**但**（i）**现行 r118 形链一处都没有**（`grep -nE "tasklist\|pgrep" build/r118_chain.sh` 无命中），（ii）全都只看进程名、不看它的工作目录/命令行 | 详见 `build/probe-guard.md` 第 3 节。直接后果：并发跑两条链会互相 `-force` 拆工程、并写同一份 `rNN_build_console.txt` |
| P6 | 源码指纹先于编译 | **有**：`build/r118_chain.sh:27` 在 `:30` 之前；r118 日志里两处时间戳能证（04:18:25 vs 04:18:27）。空指纹 REFUSE 只在 `build/r116_chain.sh:23`，**r118 形链没有** | 尺子坏（`src/rtl` 改名等）时 r118 形链会带空指纹跑完 19 分钟，事后 provenance 无法自证 |
| P7 | 产物不覆盖 / 归档不重名 | **缺**：`file copy -force`（入口 `:341`）、`write_hw_platform -force`（`:352`）、`create_project -force`（`:9`），无任何目录名比较 | 见 `build/artifacts/README.md` 第 4 节 A2/A3；**已采纳产物会被下一轮换掉**，这就是本轮不许跑构建的原因 |
| P8 | 脏树检查（改过源才允许重跑） | **部分**：`build/r110_apply_cuts.sh:38` 探 `git status --porcelain` 指定 RTL；门禁另有"有 RTL 比 bit 新就 WARN"（`build/gates.sh` 新鲜度段） | 入口与链没有脏树判定 ⇒ 拿未提交的源生成的位流与已提交的位流同名 |
| P9 | 退出码 0/1/2/3 口径 | **不统一**（`exit 1` 红、`exit 2` 既当缺前置又当缺报告、`exit 3` 只散见）；门禁 `build/gates.sh:582-586` 用 0/1 且把 PARTIAL 也判 1 | 外层按码分支会判错。本轮只登记，不改脚本 |
| P10 | 门禁两跑一致 | **有**：`build/r118_chain.sh:84-88` 两次跑 `cmp -s`，不一致就念"文档或产物在动"（r118 那一跑 04:42 真的念了这条，见 `build/r118_console.txt:12`） | — |

一句话总结这张表：**指纹、时间戳、两跑一致性这三件事现有脚本真的在做；版本、器件、磁盘、并发进程、
不覆盖这五件事现行入口没在做**（并发进程只在部分历史轮脚本里做过）。
需要补的话，补在链脚本而不是补在 `build_system_axigpio.tcl` 里 —— 后者是工具侧脚本，
把它变成"检查+构建"复合体会让它失去单独复用的价值；本轮按边界不改任何脚本。

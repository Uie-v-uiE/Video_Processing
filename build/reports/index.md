# 原件目录索引（P15b · `build/reports/`）

**这里不放大报告本身。** 原件一律留在它们本来的位置（`build/`、`build/evidence/`、`docs/timing/`、
`src/constraints/`），本文件只做三件事：① 给出每个原件的**真实路径**与**它属于哪一轮**；
② 用命令（不是手打）摘出每份的**头几行**（工具版本 / 日期 / 设计名）；③ 声明配对规矩。

> **配对规矩（P15b 铁律 5，与 P15a `build/provenance.md` 第 6 节同一条）**
> 一份原件必须与它的解析件（`build/parsed/*.json`）或名册行（`build/roster/*.tsv`）**成对**出现，
> 并且能用 `build/provenance.md` 第 5 节的指纹核上。
> **只有一份时另一份不可信**：有解析件却没有原件（或原件指纹与卡上不符）⇒ 解析件里的数字全部作废；
> 有原件却没有解析件 ⇒ 那份原件没人读过，不许引用来支持任何结论。
> 机器检法：`python build/p15b_parse_reports.py --check` 的 `GATE J5` 行（本轮读数：相符 9、
> 找不到对应原件的解析件 0、指纹不符 0、缺解析件的原件 0 ⇒ 判定 PASS）。

## 0. 本轮（r118）= 被解析的 9 份原件

取头几行用的命令（逐字可复跑）：

```bash
sed -n '1,11p' build/timing_summary.rpt          # 其余 6 份 .rpt 同理；route_status.rpt 没有这段头
md5sum build/*.rpt | cut -c1-12                  # 与 build/provenance.md 第 5 节逐行对
```

| 原件路径 | 哪一轮 | 头几行取到的东西（工具版本 / 日期 / 设计名 / 器件） | 解析件 | 入库 |
|---|---|---|---|---|
| `build/timing_summary.rpt` | r118（provenance 第 138 行，md5 `8ff1201d17ae`） | 行 3 `Tool Version : Vivado v.2025.2.1 (win64) Build 6403652 Thu Mar 19 19:48:24 GMT 2026`；行 4 `Date : Sun Oct 4 04:37:30 2026`；行 6 `Command : report_timing_summary -file …`；行 7 `Design : system_top`；行 8 `Device : 7z020-clg484`；行 10 `Design State : Routed` | `build/parsed/parsed_timing_summary.rpt.json` | 是 |
| `build/utilization.rpt` | r118（行 139，md5 `7dd1932b2d2a`） | 行 3 同上版本串；行 4 `Date : Sun Oct 4 04:37:30 2026`；行 6 `Command : report_utilization -file …`；行 7 `Design : system_top`；行 8 `Device : xc7z020clg484-2`；行 11 `Design State : Routed` | `parsed_utilization.rpt.json` | 是 |
| `build/methodology.rpt` | r118（行 141，md5 `645029c4dafe`） | 行 3 同上；行 4 `Date : Sun Oct 4 04:37:40 2026`；行 6 `report_methodology -file …`；行 11 `Design State : Fully Routed` | `parsed_methodology.rpt.json` | 是 |
| `build/cdc.rpt` | r118（行 140，md5 `443785a20f42`） | 行 3 同上；行 4 `Date : Sun Oct 4 04:37:32 2026`；行 6 `report_cdc -file …`；行 10 `Design State : Routed` | `parsed_cdc.rpt.json` | 是 |
| `build/power.rpt` | r118（行 142，md5 `e7be51c9e05b`） | 行 3 同上；行 4 `Date : Sun Oct 4 04:37:48 2026`；行 6 `report_power -file …`；行 9-12 `Design State : routed` / `Grade : commercial` / `Process : typical` / `Characterization : Production` | `parsed_power.rpt.json` | 是（**估算**，无仿真活动文件 ⇒ 见 `docs/build-notes.md`） |
| `build/route_status.rpt` | r118（行 143，md5 `a6d3822c92d7`） | **原件没有版本头**：行 1 直接是 `Design Route Status` ⇒ `banner.*` 11 个字段全部 `NOT_MEASURED`（不是空、不是 0） | `parsed_route_status.rpt.json` | 是 |
| `build/clock_util.rpt` | r118（行 144，md5 `22ce2506d78d`） | 行 3 同上；行 4 `Date : Sun Oct 4 04:37:49 2026`；行 6 `report_clock_utilization -file …`；行 10 `Design State : Routed` | `parsed_clock_util.rpt.json` | 是 |
| `build/width_warnings.txt` | r118（行 145，md5 `21438ef4b9ad`） | 非工具报告，无版本头；整个文件一个字符 `0`（`Synth 8-689` 计数） | `parsed_width_warnings.txt.json` | 是 |
| `build/multi_driven.txt` | r118（行 146，md5 `21438ef4b9ad`） | 同上，一个字符 `0`。**与上一行同指纹是因为两份都只装一个 `0`**，不是「同一份内容被复制」⇒ 区分要看字节以外的含义（provenance 行 146 已声明） | `parsed_multi_driven.txt.json` | 是 |

## 1. 名册与逐时钟原件（`build/roster/` 用的就是这些）

| 原件路径 | 哪一轮 | 头几行 / 形状（命令取的） | 谁在引用 | 入库 |
|---|---|---|---|---|
| `build/evidence/r118_after_roster_probefmt.txt` | r118（链脚本 04:38 那一趟） | 行 1 起就是 `ROSTER|setup|clk=clk_fpga_0|period=10.000|slack=1.850ns …`；**无版本头**，版本靠同目录 `build/evidence/r118_after.txt:1-3` 的 `# 改前/改后读数 r118_after 生成 2026-10-04 04:38:55 / DCP … mtime=2026-10-04 04:36:27 / 位流身份：cd04907e1369` 三行绑定 | `build/roster/roster_r118_probe.tsv` | 是 |
| `build/evidence/r118_after.txt` | r118 | 行 1-3 同上（生成时刻 / DCP / 位流 md5 前 12 位 `cd04907e1369` = provenance 第 134 行） | 逐时钟 `Slack/Logic Levels/route%` 的原文落点 | 是 |
| `build/roster_r118_after_<clk>_setup.rpt` × 8、`…_hold.rpt` × 8 | r118 | 行 3 `Tool Version : Vivado v.2025.2.1 (win64) Build 6403652 …`；行 4 `Date : Sun Oct 4 04:38:39 2026`（各钟同一分钟）；行 6 `Command : report_timing -delay_type min -nworst 1 -max_paths 4 -from eth_rxc -to eth_rxc -file …`；行 10 `Design State : Routed` | `build/coverage.md` 的「每路钟到底被检查了什么」——不确定度那一行只在这些件里逐钟可见 | 是 |
| `build/roster_r118_after_fanout.rpt` | r118 | `report_high_fanout_nets` 的表（`FANOUT` 段的原文） | 探针名册 `FANOUT|` 行；差分尺子 `timing_roster_diff.sh` 的 D6 | 是 |

## 2. 既有尺子的名册件（**上一轮/基线，不是 r118**）

这些件只用来**对齐口径**，不许当本轮读数引用（P23：跑不到的数字一律 `【待实测】`）。

| 原件路径 | 哪一轮 | 头一行（原文） | 用法边界 |
|---|---|---|---|
| `docs/timing/roster_baseline.tsv` | B3 冻结基线（生成 2026-10-03 22:45:09，来源件 r115_base 那两份） | `# label=baseline built=2026-10-03 22:45:09 src_reports=build/evidence/r115_base/timing_summary.txt,build/evidence/r115_base/check_timing_verbose.txt` | 13+1 列**口径的出处**；本轮 `roster_r118.tsv` 的列名/列序/单位与它逐字相同 |
| `docs/timing/roster_round115.tsv` | r115 轮（A=baseline，B=r115 滚） | `# r115 轮名册（E1）。差值列 = B − A，两端同 DCP（H3 合法）；噪声底 noise_ns=0.000（B4…）` | 差分形态的参照；数字**不是** r118 |
| `docs/timing/roster_round116.tsv` | r116 轮 | 同上第一行（文件头写的是 r115 轮的模板文字，与文件名不一致 ⇒ 这一条已登记进 `docs/build-notes.md` 的疑点，不替它解释） | 同上 |
| `build/evidence/r116_roster_e1.tsv` | r116（`# label=r116 built=2026-10-04 03:27:56 src_reports=build/evidence/r116/r116_timing_summary.txt,build/evidence/r116/r116_check_timing.txt`） | 同左 | r116 的 B 侧读数 |
| `build/evidence/r118_roster_diff_vs_r114.txt` | r118 vs r114（探针尺子的差分结果件） | 行 1 起是 `ROSTERDIFF-ROW clk_fpga_0/setup slack 1.850ns …->1.850ns …` | `ROSTERDIFF-SUMMARY … judged=6 pairs=16 result=GREEN` 是**既有尺子**自己算的，本条任务不重跑它、只指路 |
| `build/evidence/r115_base/timing_summary.txt` + `check_timing_verbose.txt` | 基线（`| Date : Sat Oct 3 22:30:38 2026` / `22:21:17 2026`） | 同左 | 13+1 列口径原来吃的**那两份**输入；本轮 r118 没有独立的 check_timing 件（见下节） |
| `build/evidence/r116/r116_timing_summary.txt` + `r116_check_timing.txt` | r116（`| Date : Sun Oct 4 01:35:11 2026` / `01:35:08 2026`） | 同左 | 同上 |
| `build/check_timing_verbose.rpt` | **不是 r118**：`| Date : Sat Oct 3 15:32:44 2026` | 同左 | 所以本轮名册的 `unconstrained_endpoints / io_unconstrained_ports` 两列**改用 r118 原件内嵌的 check_timing 段**（`build/timing_summary.rpt` 行 58-140），行号见 `docs/build-notes.md` 的字段位置表 |

## 3. 约束原件（`build/coverage.md` 的出处）

| 原件路径 | 本轮（r118）是否加载 | 由谁决定 |
|---|---|---|
| `src/constraints/rk_zynq7020.xdc` | **是**（综合 + 实现） | `build/tcl/build_system_axigpio.tcl:19` |
| `src/constraints/clock_groups_impl.xdc` | **是**（只实现） | 同文件 `:24-26`（`used_in_synthesis false`） |
| `src/constraints/r116_rgmii_input_window.xdc` | 否（`VP_R116_IO_WINDOW` 未设） | 同文件 `:45-52`；r118 日志念的是 `off` 那一条（provenance 第 3 节） |
| `src/constraints/r119_hdmi_source_window.xdc` | 否（`VP_R119_TMDS_WINDOW` 未设） | 同文件 `:63-70` |
| `src/constraints/r114_io_async.xdc`、`r114_io_variantA_rise_only.xdc`、`r114_io_variantB_phy_delay.xdc`、`r115_io_window_candidate.xdc`、`r119b_hdmi_tp1_pinclk.xdc` | **发布流程里没有任何一处挂载**（`grep -c` 在 `build/tcl/*.tcl` 只命中探针/实验脚本） | 见 `build/coverage.md` 第 4 节 |

## 4. 本目录不列的东西（免得读者以为漏了）

- 构建日志 `build/r118_build_console.txt`、门禁件 `build/r118_gates_final.txt`：**盘上有但未入库**，
  这是 provenance 第 6 节缺口 G3 的内容，本索引不重复登记，也不替它补配对状态。
- `build/sweep_*_timing.rpt`、`build/r8[78]_*.rpt`、`build/v64_repro_*.rpt`、`build/probe_*.rpt`、
  `build/roster_r11[34]rf_*.rpt`、`build/roster_roster_*.rpt`：都不是 r118，本轮**不解析、不引用其数字**；
  要读它们请先按同一规矩配 provenance 指纹（没有卡 ⇒ 按「未配对」处理）。
- 资源**按模块**归属需要的 `Utilization by Hierarchy`：r118 的 `build/utilization.rpt` 里**没有这一节**
  （`grep -n 'Utilization by Hierarchy' build/utilization.rpt` 无命中），仓里 `build/util_hier.rpt`
  的日期是 9 月 25 日 ⇒ 本轮该维度 `NOT_MEASURED`，见 `docs/build-notes.md`。

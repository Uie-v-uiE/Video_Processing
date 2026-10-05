# 读数说明与字段位置表（P15b · `report/build-notes.md`）

口径：**读数基准 = r118**（`build/provenance.md:1`；位流 `cd04907e1369`，`build/provenance.md:134`）。
本文配在每一份表旁边说四件事：**它能证明什么、不能证明什么、告警条数该怎么读、字段在原件的第几行第几列**
（P15b 铁律 4 + 铁律 1）。与 `build/reports/index.md`（原件索引）、`build/coverage.md`（约束覆盖面）互引，不重复维护。
所有行/列是 2026-10-04 用 `grep -n` / `sed -n` / `awk` **现取**的，没有一处按记忆写列序；
机器版全表 = `python build/p15b_parse_reports.py --fieldmap`（269 行，逐条带定位串；2026-10-05 由 `--check` 的 J1 分母复核仍是 269）。

## 1. 每份表能证明什么、不能证明什么

| 表 | 能证明 | 不能证明 |
|---|---|---|
| `build/parsed/parsed_timing_summary.rpt.json` + `build/roster/roster_r118.tsv` | 8 路域各自的 setup/hold 最差值、失败端点数、端点总数（分母）、脉宽检查数 | 不能证明"设计整体时序收敛"：I/O 口没有窗（`build/coverage.md` C5/M6），且 4 路域在原件 Intra 表里只有名字（`build/timing_summary.rpt:184,185,187,188` ⇒ 名册写 `NA`，不是 0） |
| `build/roster/roster_r118_probe.tsv` | 逐钟最差路径的 slack/逻辑级数/布线占比/终点名（探针尺子） | 与上一行是**两把尺子、两种单位**：`rel_margin_*` 是比值（0.185000），本表 `margin_pct` 是百分数（18.50）。裁决 G1/G2 只用比值那张；本表 `NOWRITE` = 该域没有可读路径，**不是 0** |
| `build/parsed/parsed_utilization.rpt.json` | 器件级资源用量（如 `Slice LUTs 14154 / 26.61%`，`build/utilization.rpt:35`） | **不能按模块归属**：r118 件里没有 `Utilization by Hierarchy` 一节（`grep -n 'Utilization by Hierarchy' build/utilization.rpt` 0 命中 ⇒ 解析件写 `utilization_by_hierarchy_present = NOT_MEASURED`）；仓里 `build/util_hier.rpt` 的日期是 9 月 25 日，不是 r118 ⇒ 该维度 `NOT_MEASURED`（铁律 6：不许把隔离统计当整体增量） |
| `build/parsed/parsed_methodology.rpt.json` | 方法学检查的**条数**与规则号 | 见第 2 节：条数是代价不是错误，本表不带判定列 |
| `build/parsed/parsed_cdc.rpt.json` | 9 行跨域统计的原文（`sections.table.rows[]`） | `field_positions[]` 里 `cdc[…].Endpoints/Safe/Unsafe` 的**字段名与值不同义**（见第 4 节缺陷 D-1）⇒ 只用 `sections.table.rows[].cells.col11..col15` |
| `build/parsed/parsed_power.rpt.json` | 工具**估算**功率/结温（`build/power.rpt:33` = 2.391 W） | 原件 `:43` 的 `Simulation Activity File` = `---` ⇒ 无仿真活动文件；`Confidence Level = Low`（`:41`）。任何"实测功耗"的说法都不成立（provenance:142 同一口径） |
| `build/parsed/parsed_route_status.rpt.json` | 网络数与 `# of nets with routing errors = 0`（`:10`） | 该件**没有版本头** ⇒ 11 个 `banner.*` 全部 `NOT_MEASURED`；它的"出自哪一版"只能靠 provenance 第 5 节的指纹（`:143`） |
| `build/parsed/parsed_clock_util.rpt.json` | 每路钟的 Global/Source Id、驱动脚、网名（`:59-66`、`:78-85`） | 不能证明时钟树的"意图"；`build/coverage.md` 第 2 节的名字对照才是覆盖面用的 |
| `build/parsed/parsed_width_warnings.txt.json`、`parsed_multi_driven.txt.json` | 各是一个计数器读数 `0`（`sed -n '1p'`） | 两份**同指纹**（`21438ef4b9ad`）只因为都只装一个字符 `0`（provenance:145-146 已声明），不等于内容相同；`0` 也不等于"没有位宽问题"，它只是该入口统计的那一类（`build/tcl/build_system_axigpio.tcl:379-388`） |
| `build/check_timing_verbose.rpt` | 未约束口的**名字**（`:57-61`、`:73-78`） | **不是 r118**：`:4` `Date : Sat Oct 3 15:32:44 2026`。名字只当参照；r118 名册 `unconstrained_endpoints`/`io_unconstrained_ports` 两列改吃 r118 原件内嵌段（`build/timing_summary.rpt:65-67`、`:90-110`），那张表只有计数没有名字 |
| `build/clock_uncertainty.rpt` | `set_clock_uncertainty -hold 0.800` 的**生效形状**（`:107` 带 `+ UU`） | **不是 r118**：`:9` `Date : Wed Sep 30 06:19:21 2026`；也不能反推 setup 侧（该件两段都是 `-delay_type min`） |
| `build/evidence/r119_ser_clock_probe.txt` | TMDS 串行寄存器由 `clkout1_1` 驱动（`:49-52`）、`u_pl/hb_reg[22]` 由 `sys_clk` 驱动（`:53`） | 打开的是 `system_top_opt.dcp`（`:11`），时刻 10-04 09:11（`:8` session 行）⇒ 是 r118 之后的**优化后网表探针**，不是 r118 位流的路由态 |

## 2. 方法学告警怎么读：条数是代价，不是错误

- `build/methodology.rpt:26` `Checks found: 446`；规则行 `:30-36` 的计数相加 = 2+1+336+98+1+1+7 = **446**（逐行 `grep -n` 复核，行数相加与总数相符 ⇒ 没有漏行）。
- 全部 7 条规则的 Severity 都是 `Warning`（`build/methodology.rpt:30-36` 第 2 个竖线单元格），原件里**没有判定列** ⇒ 「446」是一个**代价数**：`SYNTH-5 336`（`Mapped onto distributed RAM because of timing constraints`）读作"为了把 BRAM 用满而接受的分布式 RAM 推断条数"，读作"错误"就是误读。
- **只计数不断言的检查器不能当结论**：`check_timing`（r118 内嵌段 `build/timing_summary.rpt:57-140`）输出的是 `no_clock (0) … latch_loops (0)` 这类分级计数，`HIGH/MEDIUM` 是分级不是判定；`report_cdc`（`build/cdc.rpt:15-25`）给 `Safe/Unsafe/Unknown` 三列计数，同样不判定。这两类的任何"通过"必须由**外部判据**（门禁/名册 G1G2）说话，解析件不许自己写 PASS。
- **某类告警清零可能只是被豁免**：`no_output_delay` 的 12 = HIGH 6（`:106`）+ MEDIUM 6（`:108`），后者之所以降到 MEDIUM 是因为 `rk_zynq7020.xdc:55-58` 写了 `set_false_path`。同理 `no_input_delay` 的 2 个 MEDIUM 来自 `:59-60`。⇒ "这一类清零"必须先问"是不是有 false_path 把它拿掉了"，`build/coverage.md` M6 就是这条。

## 3. 字段位置表（原件 + 行 + 列 + 现取命令）

三类定位族，列的语义不同，混用会读错：**S**=空格切列（`awk '{print $N}'`）、**P**=竖线切单元格（`awk -F('|') '{print $N+1}'`，下表列号 = 单元格序号）、**C**=冒号分栏（`route_status`）。
`NOT_MEASURED` 出现在**列槽**只表示"这一行不是空格表、列号不适用"，与"值没取到"是两件事（值的缺失见第 4 节计数）。

| 字段 | 原件 | 行 | 列 | 取到的值 | 族 / 现取命令 |
|---|---|---|---|---|---|
| `design_timing_summary.WNS(ns)` | `build/timing_summary.rpt` | 151 | 1 | `0.739` | S ｜`grep -n -m1 'WNS(ns)'`→表头 149；`sed -n '151p' \| awk '{print $1}'` |
| `…TNS Failing Endpoints` / `…TNS Total Endpoints` | 同上 | 151 | 3 / 4 | `0` / `51135` | S ｜同行 `$3`、`$4` |
| `…WHS(ns)` / `…TPWS Total Endpoints` | 同上 | 151 | 5 / 12 | `0.052` / `12634` | S ｜同行 `$5`、`$12` |
| `clock_summary[clkout1_1].Period/Freq` | 同上 | 170 | 4 / 5 | `4.000` / `250.000` | S ｜`sed -n '170p'`（Clock Summary 数据行 = 164-171，表头 162） |
| `intra_clock[clkout0_1].WNS / TNS Total Endpoints / TPWS Total Endpoints` | 同上 | 186 | 2 / 5 / 13 | `3.630` / `30179` / `5508` | S ｜表头 179；`sed -n '186p' \| awk '{print $2,$5,$13}'` |
| `intra_clock[…]` 的 4 个 NA 域 | 同上 | 184,185,187,188 | 2/5/8 **无值** | `NOT_MEASURED`（不是 0） | S ｜那四行 setup/hold 列位置是空格，只有脉宽列有数 |
| Inter Clock 行（覆盖面佐证） | 同上 | 198-199 | 1..3 | `clkout0_1 sys_clk 14.757` | S ｜表头 196 |
| `check_timing` 内嵌计数 | 同上 | 65-67 / 99 / 106 | —— | `no_input_delay (7)`、`5 … (HIGH)`、`6 … (HIGH)` | 文本行 ｜`grep -n 'checking no_input_delay'` |
| `table[1 Slice Logic].Slice LUTs.Used / Util%` | `build/utilization.rpt` | 35 | 2 / 6 | `14154` / `26.61` | P ｜`sed -n '35p' \| awk -F'\|' '{print $3,$7}'` |
| `utilization_by_hierarchy_present` | 同上 | `NOT_MEASURED` | `NOT_MEASURED` | `NOT_MEASURED` | C ｜`grep -n 'Utilization by Hierarchy'` → **0 命中** |
| `checks_found` | `build/methodology.rpt` | 26 | —— | `446` | `grep -n 'Checks found:'` |
| `rule[SYNTH-5].Checks` | 同上 | 32 | 4（P 第 5 格） | `336` | P ｜`sed -n '32p' \| awk -F'\|' '{print $5}'` |
| `summary[Total On-Chip Power (W)]` | `build/power.rpt` | 33 | 2 | `2.391` | P ｜`grep -n 'Total On-Chip Power'` |
| `summary[Simulation Activity File]` / `Confidence Level` | 同上 | 43 / 41 | 2 | `---` / `Low` | P ｜同一张表 |
| `route_status[# of nets with routing errors]` | `build/route_status.rpt` | 10 | `NOT_MEASURED` | `0` | C ｜`grep -n '# of nets with routing errors'`；`:4-10` 是 7 个计数行 |
| `clock_resources[clkout1_1].Period/Loads/Driver/Net` | `build/clock_util.rpt` | 63 | 10 / 8 / 12 / 13 | `4.000` / `8` / `u_pl/u_clk/u_bufg_5x/O` / `u_pl/u_clk/clk_pix5x` | P ｜表头 57 |
| `clock_source[clkout1_1].Source Clock Period` | 同上 | 82 | 10 | `4.000` | P ｜表头 76；驱动 `u_pl/u_clk/u_mmcm/CLKOUT1` |
| `cdc[sys_clk>clkout0_1]` 行 | `build/cdc.rpt` | 24 | 表 token 6 | `Safely Timed`/`None`/`231`（**注意 D-1**） | S ｜表头 15，数据行 17-25 |
| `counter_value` | `build/width_warnings.txt`、`build/multi_driven.txt` | 1 | 1 | `0` / `0` | `sed -n '1p'`（整文件一个字符） |
| 逐钟不确定度（覆盖面用） | `build/roster_r118_after_*.rpt` | 29（首处） | —— | `eth_rxc` hold `0.800 …+ UU`；`clkout1_1` 等 4 路该行**不存在** | `grep -c 'Clock Uncertainty:'` + `grep -n -m1` |
| 逐钟空路径标记 | `build/roster_r118_after_clkout1_1_setup.rpt` | 15 | —— | `No timing paths found.` | `sed -n '15p'`（8 个域 × setup/hold 共 16 份件） |

## 4. 配对与 FAIL 登记（P15b 铁律 5：原件与解析结果必须成对，只有一份时另一份不可信）

`build/parsed/` 现有 **9** 份解析件、`build/roster/` 现有 **2** 份名册。逐条对回原件与 `build/provenance.md` 第 5 节（`:134-149`）指纹：

| # | 解析产物 | 原件 | 原件在 provenance 第 5 节？ | 配对判定 |
|---|---|---|---|---|
| 1-9 | `parsed_{timing_summary,utilization,cdc,methodology,power,route_status,clock_util}.rpt.json`、`parsed_width_warnings.txt.json`、`parsed_multi_driven.txt.json` | 9 份 `build/*` 原件，**盘上都在** | 是（`:138-146`）；独立重算 `md5sum` 前 12 位与卡上逐字节相符（2026-10-05 复跑：`8ff1201d17ae`/`22ce2506d78d`/`21438ef4b9ad`） | **PASS**（脚本 J5：相符 9、无原件 0、指纹不符 0、缺解析件 0） |
| 10 | `build/roster/roster_r118_probe.tsv` | `build/evidence/r118_after_roster_probefmt.txt`（盘上在、已入库） | **否**：`grep -n 'probefmt\|r118_after' build/provenance.md` **0 命中** ⇒ 该原件没有指纹行 | **FAIL**（缺 `provenance.md` 第 5 节的一行；按铁律 5 这份名册的数字暂不可引用） |
| 11 | `build/coverage.md` 第 3 节点名的 `build/roster_r118_after_<clk>_{setup,hold}.rpt` 一族（2026-10-04 记 16 份、`git ls-files` 计 17） | 2026-10-05 复核：盘上 7 份、`git ls-files build/roster_r118_after_*.rpt` 计 7 ⇒ 现存的那 7 份全在库内 | **否**：`grep -n r118_after build/provenance.md` 仍 0 命中 ⇒ 无 md5/sha256 可核 | **FAIL**（provenance 第 5 节缺这一族的指纹行，一份都没有） |
| 12 | `build/roster/roster_r118.tsv` 的 `unconstrained_endpoints`/`io_unconstrained_ports` 两列 | r118 原件内嵌 `check_timing` 段（`build/timing_summary.rpt:65-67,90-110`，**无端口名字**） | 是（同一份原件 `:138`） | **PASS**，但名字必须去 `build/check_timing_verbose.rpt`（非 r118）取 ⇒ 引用端口名字的句子按第 1 节口径降级 |
| 13 | 承载配对的 `build/provenance.md`、尺子 `build/p15b_parse_reports.py`、`build/parsed/`、`build/roster/` | —— | —— | 2026-10-04 记 **FAIL**：那四件 `git ls-files` 全部**未跟踪** ⇒ clone 之后"成对"不成立（provenance 第 6 节缺口 G3 的同一形状，只是范围更大）。2026-10-05 复核 `git ls-files build/parsed build/roster build/provenance.md build/p15b_parse_reports.py` = 9/2/1/1，`git status` 那一族 `??` 已不见 ⇒ 未跟踪那一半由入库闭合。剩下的只有形状：`.gitignore:26` 写 `build/reports/*`、`:27` 给 `!build/reports/index.md` 开了例外 ⇒ clone 拿得到索引与解析件，拿不到 `build/reports/` 里的原件副本 |

缺陷（不是配对问题，但会让引用出错）：
- **D-1**：`parsed_cdc.rpt.json` 的 `field_positions[].field` 里 `cdc[…].Endpoints/.Safe/.Unsafe` 的值与名字不同义 ——
  原件 `build/cdc.rpt:15` 表头有 14 个 token（`No ASYNC_REG` 被空格切成两格），数据行 17 切成 15 个 token（`No Common Primary Clock` 占 4 格），
  于是"第 6 列"实际落在 CDC Type 上（`Primary`）。真值在 `sections.table.rows[].cells.col11..col15`（`build/cdc.rpt:17` → 103/102/1/0/2）。
  影响面：`parsed_cdc.rpt.json` 的 18 个 `cdc[…]` 命名字段。**门神抓不到它**：J1 只验"记录的行/列能重取出记录的值"（自洽即 PASS），不验"字段名与值同义"。
- **D-2**：`report/timing/roster_round116.tsv:1` 的文件头写的是「r115 轮名册（E1）」，与文件名不一致 ⇒ 引用前先按文件名定轮次、正文头只当模板残留（`build/reports/index.md:53` 同一条，此处登记）。

## 5. 门禁实跑读数（判定放最后一个字段，打印分母）

```
GATE J1 parsed 数字逐字段回原件定位    verified=229 mismatch=0 not_measured=40 total_fields=269   判定=PASS
GATE J2 名册逐域覆盖                  域数 8 = Clock Summary 8，缺口 0；约束点名 3/8（详见 coverage.md C2） 判定=PASS
GATE J3 读不到→NOT_MEASURED            触发 40 个字段：route_status 11 / timing_summary 15 / utilization 4 / cdc 3 / clock_util 3 / methodology 3 / power 1；反向违规 0 判定=PASS
GATE J4 每条判据自带反例且只染红该条    --check 模式不跑；`--self` 实跑：反例 7 条各自独占红 ⇒ 判定=PASS（本轮补测）
GATE J5 parsed/ ↔ provenance 一一对应  相符 9 / 无原件 0 / 指纹不符 0 / 缺解析件 0                    判定=PASS（但见第 4 节 #10 #11 #13 三条 FAIL）
GATE J6 同一输入跑两次逐字节一致        比对 11 个文件，不一致 0                                     判定=PASS
GATE-SUMMARY judged=6 PASS=5 FAIL=0 NOT_MEASURED=1   分母：J1=269 J2=8 J3=40 J4=6 J5=9 J6=11
```
`--check` 里 J4 记 `NOT_MEASURED` 是因为该模式按设计不跑反例；`python build/p15b_parse_reports.py --self`
（只写系统临时目录，不动 `build/` 任何真件）2026-10-05 复跑得 `GATE-SELF judged=6 分母=反例 7 条 … 判定=PASS` 与 `SELFRESULT GREEN` ⇒ 补测判定 `PASS`，两处的原始行都留在本节。

## 6. 明写的 `NOT_MEASURED`（要重跑构建/只读探针才能拿到的数，留给后一轮）

| 项 | 状态 | 缺的具体是哪一次运行 |
|---|---|---|
| 资源**按模块**归属（铁律 6） | `NOT_MEASURED` | 缺一次实现后只读 `report_utilization -hierarchy`（r118 件里没有该节；`build/util_hier.rpt` 是 9 月 25 日的） |
| `clkfbout/clkfbout_1/clkout1_1/clkout2` 的时钟组归属 | `NOT_MEASURED` | 缺一次只读 `open_checkpoint` + `report_clock_groups`/`get_clocks` 探针（r118 四路 `No timing paths found.`，从时序件反推不出来） |
| 挂上 `r119_hdmi_source_window.xdc` 之后 TMDS 输出口的时序 | `NOT_MEASURED` | 缺一次 `VP_R119_TMDS_WINDOW=1` 的构建（`build/tcl/build_system_axigpio.tcl:63-70`） |
| 挂上 `r119b_hdmi_tp1_pinclk.xdc` 后的域数（8→9） | `NOT_MEASURED` | 缺一次挂载 + 重建名册；当前只有约束文件自身（`:24-26`） |
| 板上实测吞吐/帧率/带宽（"关键性能指标"的非时序部分） | `NOT_MEASURED` | 板子与人手不在只读复核边界内；r118 那批件（`build/r118_*`、`report/timing/round_r118.md`）没有配对的解析件 |
| 同一命令两次运行逐位相同（构建层，不是解析层） | `FAIL`（既有结论，非新测） | 见 `build/provenance.md:192`：入口对 `system.bit` 用 `file copy -force` ⇒ 原地覆盖 |

## 7. 复跑（全部只读）

```bash
python build/p15b_parse_reports.py --check      # 六条判据 + 两把尺子的单位核对
python build/p15b_parse_reports.py --fieldmap   # 269 行字段位置表（本文第 3 节的机器版）
python build/p15b_parse_reports.py --self       # 7 支反例，只写系统临时目录
md5sum build/timing_summary.rpt | cut -c1-12    # 对 build/provenance.md:138
git ls-files build/parsed build/roster build/provenance.md   # 空 = 未入库（第 4 节 #13）
```

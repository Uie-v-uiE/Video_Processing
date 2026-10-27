# 时序类字段速查（本文件的上一级是 `SKILL.md`）

范围：`build/timing_summary.rpt` 一份件里的时序读数形状。
所有行号与原文都来自 2026-10-04 对该件的直读；件头 `Tool Version` 行把版本钉死（见本表 V 组）。
**本层不是判据**：这里的行号只说明"去哪一格读"，结论要由 `evals/` 记录或实测输出给。
复算方法在 `SKILL.md` §5 步骤 2–4。

## 目录

- V 组：件头身份（版本 / 时间 / 命令 / 器件）
- D 组：Design Timing Summary 那一条数据行
- C 组：Clock Summary
- I 组：Intra Clock Table（逐时钟）
- X 组：Inter Clock Table（跨时钟）
- O 组：Other Path Groups Table
- M 组：内嵌 Report Methodology 表
- P 组：Timing Details 的分组标题（Setup/Hold 归属）
- R 组：解析口径（`build/gates.sh` 用的列号）

## V 组：件头身份

| 要取的事 | 文件:行 | 列/字段位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 工具版本串 | `build/timing_summary.rpt:3` | `| Tool Version :` 之后的整串 | `Vivado v.2025.2.1 (win64) Build 6403652 Thu Mar 19 19:48:24 GMT 2026` | 件 | 2026-10-04 | tool-version-drift |
| 生成时刻 | `:4` | `| Date :` | `Sun Oct  4 04:37:30 2026` | 件 | 2026-10-04 | who-else-writes-this-artifact |
| 生成命令 | `:6` | `| Command :` | `report_timing_summary -file D:/Xilinx/Prj/pro/Video_Processing/build/timing_summary.rpt` | 件 | 2026-10-04 | build-report-field-map |
<!-- 本仓示例取值 --> | 设计 / 器件 / 速度文件 | `:7` `:8` `:9` | 各自 `| … :` | `system_top` / `7z020-clg484` / `-2  PRODUCTION 1.12 2019-11-22` | 件 | 2026-10-04 | tool-version-drift |
| 设计状态 | `:10` | `| Design State :` | `Routed` | 件 | 2026-10-04 | build-report-field-map |

⚠ 器件写法在这一份里是 `7z020-clg484`（`report_timing_summary` 的输出），
而 `build/utilization.rpt:8` 写的是 `xc7z020clg484-2`——同一版构建的两种拼法，比对时要按件自取。

## D 组：Design Timing Summary

| 要取的事 | 文件:行 | 字段下标 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 段落锚点 | `build/timing_summary.rpt:145` | 行首 `\| Design Timing Summary` | 命中 1 行 | 件 | 2026-10-04 | build-report-field-map |
| 列名行 | `:149` | — | `WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) THS(ns) THS Failing Endpoints THS Total Endpoints WPWS(ns) TPWS(ns) TPWS Failing Endpoints TPWS Total Endpoints` | 件 | 2026-10-04 | report-field-parse-breaks |
| 数据行 | `:151` | $1=WNS $2=TNS $3=TNS Failing EP $4=TNS Total EP | `0.739 0.000 0 51135` | 件 | 2026-10-04 | checker-ran-on-nothing |
| 同上 | `:151` | $5=WHS $6=THS $7=THS Failing EP $8=THS Total EP | `0.052 0.000 0 51135` | 件 | 2026-10-04 | report-field-parse-breaks |
| 同上（脉宽组） | `:151` | $9=WPWS $10=TPWS $11=TPWS Failing EP $12=TPWS Total EP | `0.264 0.000 0 12634` | 件 | 2026-10-04 | build-report-field-map |
| 全约束是否满足那句 | `:154` | 整行 | `All user specified timing constraints are met.` | 件 | 2026-10-04 | checker-ran-on-nothing |

## C 组：Clock Summary

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 表头 | `build/timing_summary.rpt:162` | — | `Clock  Waveform(ns)  Period(ns)  Frequency(MHz)` | 件 | 2026-10-04 | build-report-field-map |
| 顶层输入钟 | `:164-166` | $1 名 $2 波形 $3 周期 $4 频率 | `clk_fpga_0 {0.000 5.000} 10.000 100.000`；`eth_rxc {0.000 4.000} 8.000 125.000`；`sys_clk {0.000 10.000} 20.000 50.000` | 件 | 2026-10-04 | build-report-field-map |
| 派生钟 | `:167-171` | 行首有两个空格 | `clkfbout` `clkfbout_1` `clkout0_1` 20.000/50.000；`clkout1_1` 4.000/250.000；`clkout2` 5.000/200.000 | 件 | 2026-10-04 | checker-ran-on-nothing |

## I 组：Intra Clock Table（逐时钟）

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 表头 | `build/timing_summary.rpt:179` | 与 D 组列名同序 | `Clock  WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) …` | 件 | 2026-10-04 | build-report-field-map |
| `clk_fpga_0` 行 | `:181` | $1 名 $2 WNS $3 TNS $4 失败EP $5 总EP $6 WHS | `clk_fpga_0 1.850 0.000 0 15721 0.053` | 件 | 2026-10-04 | report-field-parse-breaks |
| `eth_rxc` 行 | `:182` | 同上 | `eth_rxc 0.739 0.000 0 4835 0.052` | 件 | 2026-10-04 | checker-ran-on-nothing |
| `sys_clk` 行 | `:183` | 同上 | `sys_clk 14.876 0.000 0 323 0.222` | 件 | 2026-10-04 | build-report-field-map |
| 空行（无自身端点） | `:184-185`、`:187-188` | 只有钟名 | `clkfbout` / `clkfbout_1` / `clkout1_1` / `clkout2` 四行数值列为空 | 件 | 2026-10-04 | report-field-parse-breaks |
| `clkout0_1` 行 | `:186` | 同上 | `clkout0_1 3.630 0.000 0 30179 0.059` | 件 | 2026-10-04 | build-report-field-map |

## X 组：Inter Clock Table（跨时钟）

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 表头 | `build/timing_summary.rpt:196` | `From Clock To Clock WNS …` | 命中 1 行 | 件 | 2026-10-04 | build-report-field-map |
| 两行跨组 | `:198-199` | $1 From $2 To $3 WNS $4 TNS $5 失败EP | `clkout0_1 sys_clk 14.757 0.000 0`；`sys_clk clkout0_1 3.695 0.000 0` | 件 | 2026-10-04 | wns-lever 类（`skill/` 里那条按逻辑/布线分配选的条目，本包只指路） |

## O 组：Other Path Groups Table

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 表头 | `build/timing_summary.rpt:207` | — | `Path Group From Clock To Clock WNS(ns) TNS(ns) TNS Failing Endpoints` | 件 | 2026-10-04 | build-report-field-map |
| 数据行 | `:209` 之后 | — | 本次这份件里**为空**（没有其它路径组） | 件 | 2026-10-04 | checker-ran-on-nothing |

⚠ 这一组为空不代表"没有跨组路径"，只代表这张表按组归类时没有条目；判"没有"要另找凭据。

## M 组：内嵌 Report Methodology 表

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 段落 | `build/timing_summary.rpt:40` | 行首 `\| Report Methodology` | 命中 1 行 | 件 | 2026-10-04 | build-report-field-map |
| 列名 | `:44` | — | `Rule  Severity  Description  Violations` | 件 | 2026-10-04 | build-report-field-map |
| 计数行 | `:46-52` | $1 规则名 $2 严重度 $…$ 末列计数 | `DPIR-1 2`、`LUTAR-1 1`、`SYNTH-5 336`、`SYNTH-6 98`、`TIMING-9 1`、`TIMING-10 1`、`TIMING-18 7` | 件 | 2026-10-04 | report-field-parse-breaks |
| 陈旧提示 | `:54` | 整行 | `Note: This report is based on the most recent report_methodology run and may not be up-to-date. …` | 件 | 2026-10-04 | who-else-writes-this-artifact |

## P 组：Timing Details 的分组标题

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| From/To 组 | `build/timing_summary.rpt:218-219` | $3 是钟名 | `From Clock:  clk_fpga_0` / `  To Clock:  clk_fpga_0` | 件 | 2026-10-04 | report-field-parse-breaks |
| 该组 Setup 行 | `:221` | $3=失败端点数 $8=Worst Slack（冒号是独立字段） | `Setup : 0 Failing Endpoints, Worst Slack 1.850ns, Total Violation 0.000ns` | 件 | 2026-10-04 | build-report-field-map |
| 该组 Hold 行 | `:222` | 同上 | `Hold  : 0 … 0.053ns …` | 件 | 2026-10-04 | report-field-parse-breaks |
| 最差归属组（本例与全设计 WNS 相同） | `:354-358` | 同上 | `eth_rxc` setup `0.739ns`、hold `0.052ns` | 件 | 2026-10-04 | checker-ran-on-nothing |
| 另一组 | `:533-537` | 同上 | `sys_clk` setup `14.876ns`、hold `0.222ns` | 件 | 2026-10-04 | build-report-field-map |

## R 组：解析口径（与代码同行）

| 结论（口径，不是判据） | 出处 | 核对日期 | 支撑的条目 |
|---|---|---|---|
| 取 Design Timing Summary 那一行用"六个带符号小数的形状"匹配，命中第一条即停（不按段落数） | 代码 `build/gates.sh:68-70`（本次打开），件 `build/timing_summary.rpt:151` | 2026-10-04 | report-field-parse-breaks |
| 分组那层：`/^Setup :/` 时冒号自成一字段，所以取 `$8`；钟名取 `$3` | 代码 `build/gates.sh:279-284`；本次实跑得 `clk_fpga_0\|1.850\|0\|setup` 等 6 条数值行 + 4 条 `NA` 行 | 2026-10-04 | report-field-parse-breaks |
| 那 4 条 `NA` 对应 I 组里的空行（`:184-185`、`:187-188`），成因本轮未查，只登记读数 | 件 `build/timing_summary.rpt:184-188` | 2026-10-04 | checker-ran-on-nothing |
| 读不到 timing 行时把最像的三行原样打出来再 exit 2 | 代码 `build/gates.sh:71-75` | 2026-10-04 | checker-ran-on-nothing |

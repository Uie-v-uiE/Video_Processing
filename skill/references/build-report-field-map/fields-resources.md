# 资源·功耗·时钟·CDC·布线状态字段速查（上一级是 `SKILL.md`）

范围：`build/utilization.rpt`、`build/power.rpt`、`build/cdc.rpt`、`build/route_status.rpt`、`build/clock_util.rpt`、`build/methodology.rpt`。
所有行号与原文来自 2026-10-04 对这些件的直读；件头 `Tool Version` 与 `build/timing_summary.rpt:3` 同一版构建。
**本层不是判据**：结论要由 `evals/` 记录或实测输出给；本页只回答"这一格在哪、怎么复算"。

## 目录

- U 组：`utilization.rpt`（LUT / 寄存器 / BRAM / DSP）
- W 组：`power.rpt`（动态功耗 / 结温 / 置信度）
- S 组：`route_status.rpt`（路由错误网线）
- C 组：`cdc.rpt`（Critical 配对与末五列）
- K 组：`clock_util.rpt`（全局时钟资源用量）
- M 组：`methodology.rpt`（规则计数与 Critical 计数）
- R 组：解析口径（与代码同行）

## U 组：`build/utilization.rpt`

| 要取的事 | 文件:行 | 列位置（`-F'|'`） | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 表头（列序权威） | `:33` | $2 Site Type / $3 Used / $4 Fixed / $5 Prohibited / $6 Available / $7 Util% | `\| Site Type \| Used \| Fixed \| Prohibited \| Available \| Util% \|` | 件 | 2026-10-04 | report-field-parse-breaks |
| Slice LUTs（Logic+Memory 之和） | `:35` | $3 与 $7 | `14154` / `26.61` | 件 | 2026-10-04 | build-report-field-map |
| 其中 LUT as Logic / as Memory | `:36`、`:37` | 同上 | `9969 18.74` / `4185 24.05` | 件 | 2026-10-04 | build-report-field-map |
| 分布式 RAM / 移位寄存器 | `:38`、`:39` | 只有 Used | `4044` / `141` | 件 | 2026-10-04 | checker-ran-on-nothing |
| Slice Registers | `:40` | $3 与 $7 | `8188` / `7.70` | 件 | 2026-10-04 | build-report-field-map |
| Block RAM Tile | `:106` | $3 与 $7 | `95.5` / `68.21`（Available 140） | 件 | 2026-10-04 | report-field-parse-breaks |
| RAMB36/FIFO* 与 RAMB18 | `:107`、`:109` | $3 与 $7 | `93 / 66.43`、`5 / 1.79` | 件 | 2026-10-04 | build-report-field-map |
| DSPs | `:121` | $3 与 $7 | `19` / `8.64`（Available 220） | 件 | 2026-10-04 | build-report-field-map |
| `DSP48E1 only` 明细行 | `:122` | 只有 $3 | `19`（该行**没有** Util%） | 件 | 2026-10-04 | report-field-parse-breaks |

⚠ 名字行与缩进的明细行同形（都含 `|`），所以取数用"匹配名字 + `exit`"而不是数行号
（本仓口径见 `build/gates.sh:78-82`）。

## W 组：`build/power.rpt`

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 片上合计 | `:33` | `\| Total On-Chip Power (W) \|` 之后 | `2.391` | 件 | 2026-10-04 | build-report-field-map |
| 动态功耗（门禁取的那一格） | `:36` | `\| Dynamic (W) \|` 之后 | `2.213` | 件 | 2026-10-04 | report-field-parse-breaks |
| 结温估算 | `:40` | `\| Junction Temperature (C) \|` | `52.6` | 件 | 2026-10-04 | build-report-field-map |
| 工具置信度 | `:41` | `\| Confidence Level \|` | `Low` | 件 | 2026-10-04 | checker-ran-on-nothing |
| 环境温度假定 | `:127` | `\| Ambient Temp (C) \|` | `25.0` | 件 | 2026-10-04 | build-report-field-map |

## S 组：`build/route_status.rpt`

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 逻辑网总数 | `:4` | 冒号分隔的中间列 | `# of logical nets.......................... : 32330 :` | 件 | 2026-10-04 | build-report-field-map |
| 全路由完成数 | `:9` | 同上 | `# of fully routed nets............. : 20882 :` | 件 | 2026-10-04 | build-report-field-map |
| 有路由错误的网线数（门禁项） | `:10` | **最后一个纯数字**字段 | `# of nets with routing errors.......... : 0 :` | 件 | 2026-10-04 | report-field-parse-breaks |

## C 组：`build/cdc.rpt`

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 列名行 | `:15` | — | `Severity Source Clock Destination Clock CDC Type Exceptions Endpoints Safe Unsafe Unknown No ASYNC_REG` | 件 | 2026-10-04 | build-report-field-map |
| Critical 行 1 | `:17` | $2>$3 配对，$(NF-4) 端点数，$(NF-2) unsafe | `Critical clk_fpga_0 clkout0_1 No Common Primary Clock Asynch Clock Groups 103 102 1 0 2` | 件 | 2026-10-04 | report-field-parse-breaks |
| Critical 行 2 | `:18` | 同上 | `Critical sys_clk eth_rxc … 1968 1436 2 530 0` | 件 | 2026-10-04 | checker-ran-on-nothing |
| CDC Type 的 token 数会变 | `:17` vs `:24` | 前者 `No Common Primary Clock`（4 token），后者 `Safely Timed`（2 token） | `Info sys_clk clkout0_1 Safely Timed None 231 231 0 0 0` | 件 | 2026-10-04 | report-field-parse-breaks |
| 本次复算结果 | — | `awk '/^Critical/{print $2">"$3, $(NF-4), $(NF-2)}'` | 两行：`clk_fpga_0>clkout0_1 103 1`、`sys_clk>eth_rxc 1968 2` | 件+实跑 | 2026-10-04 | checker-ran-on-nothing |

## K 组：`build/clock_util.rpt`

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 表头 | `:41` | $2 Used $3 Available $4 LOC $5 Clock Region $6 Pblock | `\| Type \| Used \| Available \| LOC \| Clock Region \| Pblock \|` | 件 | 2026-10-04 | build-report-field-map |
| BUFGCTRL 用量 | `:43` | $2 | `8`（Available 32） | 件 | 2026-10-04 | build-report-field-map |
| BUFIO 用量（那条结构判据读的就是它） | `:45` | $2 | `0`（Available 16） | 件 | 2026-10-04 | checker-ran-on-nothing |
| MMCM / PLL | `:48`、`:49` | $2 | `2` / `0` | 件 | 2026-10-04 | build-report-field-map |
| 全局时钟资源段标题 | `:53` | 行首 `2. Global Clock Resources` | 命中 1 行 | 件 | 2026-10-04 | build-report-field-map |

## M 组：`build/methodology.rpt`

| 要取的事 | 文件:行 | 列位置 | 本次实跑的原文读数 | 来源类型 | 核对日期 | 支撑的条目 |
|---|---|---|---|---|---|---|
| 检查总数 | `:26` | `Checks found:` 之后 | `446` | 件 | 2026-10-04 | build-report-field-map |
| 列名行 | `:28` | `-F'|'` 下 $2 规则 $3 严重度 $5 计数 | `\| Rule \| Severity \| Description \| Checks \|` | 件 | 2026-10-04 | report-field-parse-breaks |
| 规则计数行 | `:30-36` | 同上 | `DPIR-1 2`、`LUTAR-1 1`、`SYNTH-5 336`、`SYNTH-6 98`、`TIMING-9 1`、`TIMING-10 1`、`TIMING-18 7` | 件 | 2026-10-04 | build-report-field-map |
| 门禁那一项读的是 CRITICAL WARNING 行数 | `:30-36` 全表 | `grep -ac "CRITICAL WARNING"` | 本次实测 `0`（这份件里七条全是 Warning） | 实跑 | 2026-10-04 | checker-ran-on-nothing |

⚠ 上一行是"该格现在读什么"的形状说明；把 `0` 当"通过"要按 `checker-ran-on-nothing` 的口径判（该项在 `build/gates.sh:193` 是 `== 0` 判据，且件缺席时走 `n/a`）。

## R 组：解析口径（与代码同行）

| 结论（口径，不是判据） | 出处 | 核对日期 | 支撑的条目 |
|---|---|---|---|
| utilization 的列序在 `-F'|'` 下行首有空字段（$2=名字、$3=Used、$7=Util%），代码注释就写明这点 | 代码 `build/gates.sh:76-82`（本次打开） | 2026-10-04 | report-field-parse-breaks |
| 路由错误取"最后一个纯数字字段"而不是固定列 | 代码 `build/gates.sh:87-88`；件 `build/route_status.rpt:10` | 2026-10-04 | report-field-parse-breaks |
| CDC 端点/unsafe 从尾巴数（`$(NF-4)`、`$(NF-2)`），因为 CDC Type 的 token 数会变 | 代码 `build/gates.sh:97-100`；件 `build/cdc.rpt:15-24` | 2026-10-04 | report-field-parse-breaks |
| 解析不出来的变量一律 `FATAL … exit 2`，不拿空值当 0 | 代码 `build/gates.sh:162-166` | 2026-10-04 | checker-ran-on-nothing |
| 缺哪个报告就 `FATAL 缺报告：<路径> exit 2`；冻结目录缺文件会回落到 `build/` | 代码 `build/gates.sh:26`、`:31-33` | 2026-10-04 | who-else-writes-this-artifact |

---
name: build-report-field-map
description: 查"某个数字在工具报告的哪一行哪一列"的速查表：当解析脚本读不到值、需要为新写的检查器定列位、需要核对 data/metrics.csv 或 README 里某个数点名的凭据文件、或需要确认 timing_summary.rpt / utilization.rpt / power.rpt / cdc.rpt / route_status.rpt / clock_util.rpt 各自的表头形状时使用。
---

## 1. 一句话用途

报告字段 → 行号与列号，逐行有出处。

## 2. 适用场景

- 当你要新写或修一支读 `.rpt` 的解析脚本，需要一份"哪一行第几列"的对照时。
- 当 `build/gates.sh` 打印 `FATAL 读不到 …`，你要先确认那一行现在长什么样时。
- 当 `data/metrics.csv` 或首页表格里某行点名的凭据文件与你手上的读数对不上，需要回到那份件核对时。
- 当换了 Vivado 版本或报告命令，表头/列序可能平移，需要重取列位时。
- 当评审问"这个 WNS 是从报告的哪一格读的"时。

## 3. 不适用 / 失效条件

- **本层不是判据**：任何结论都不能靠本页自称成立，只能靠 `evals/` 的记录或实测输出；本页只回答"是什么、去哪确认"。
- 不适用：行号是本次构建产物的行号（工具版本见 `skill/references/tool-version-drift/SKILL.md`）；换版本后必须重取，不许套用。
- 不适用：本包没有收录的报告类型（如 `report_io`、`report_cips`、综合 utilization 的 `hst/` 文件）。
- 不适用：`build/roster_*.rpt`、`build/probe_*.rpt` 这类每轮命名的实验件——它们的形状随生成脚本变，按本轮件自取。
- 不许越界：本页不给出"该加哪条约束/该改哪个阈值"。

## 4. 前置条件

- 下面这些件在盘上（本仓路径为示例取值，需按自身工程替换同名报告）：
  `build/timing_summary.rpt`、`build/utilization.rpt`、`build/power.rpt`、`build/cdc.rpt`、
  `build/route_status.rpt`、`build/clock_util.rpt`、`build/methodology.rpt`。
- 能跑 `grep -n` / `awk`；字段表复算命令在本页 §5 给出。
- 核对日期 2026-10-04，来源类型全部为"件"（我本次打开过这些文件并读到引用行）。

## 5. 使用方法

1. 先看目录，再按"要取的事"选行：
   - 时序类（WNS/TNS/失败端点/逐时钟/Clock Summary）→ `fields-timing.md`
   - 资源·功耗·时钟·CDC·布线状态类 → `fields-resources.md`
2. 用一条命令复算列位，不要抄列号：
   `awk 'NR==151{for(i=1;i<=NF;i++) printf "%d=[%s] ",i,$i; print ""}' build/timing_summary.rpt`
   完成后应看到：一份带下标的字段表（本次实测输出 `wns=0.739 whs=0.052 tnsfail=0 whsfail=0 eps=51135` 的同一行）。
3. 表格式件用 `-F'|'` 复算：
   `awk -F'|' 'NR==35{for(i=1;i<=NF;i++) printf "%d=[%s] ",i,$i; print ""}' build/utilization.rpt`
   完成后应看到：行首是空字段，所以名字在 $2、Used 在 $3、Util% 在 $7。
4. 找段落起点用行号 + 标题双锚：`grep -n "Design Timing Summary" build/timing_summary.rpt`（本次实测第 145 行）。
5. 把取到的数写进任何对外文档时，同一行点名"文件 + 那次构建的时间戳/md5"
   （`build/timing_summary.rpt:4` 的 `Date` 行、`build/tb_v98_report.txt` 头部的 provenance 行是两种现成形状）。

## 6. 判读与失败分叉

- 步骤 2：
  通过 = 打出的字段数 ≥ 12 且 $1 是带符号小数。
  失败 = 打出的行里没有小数（读到的是表头）⇒ `FAIL`，段落行号变了，回步骤 4 重取。
  读不到输入 = 没有输出 ⇒ `NOT_MEASURED`，先确认那份报告是否 0 字节。
- 步骤 3：
  通过 = $3 是整数/小数、$7 是百分数。
  失败 = $3 为空 ⇒ 该行不是数据行，或 `-F'|'` 忘了加 ⇒ 重来。
  读不到输入 = 行号超范围 ⇒ `NOT_MEASURED`，报告可能来自别的工具版本。
- 步骤 4：
  通过 = 只命中 1 行。
  失败 = 命中多行 ⇒ `FAIL`，用更长的锚串（例如 `| Design Timing Summary`）。
  读不到输入 = 命中 0 行 ⇒ `NOT_MEASURED`，这份件可能不是 `report_timing_summary` 生成的。
- 步骤 5：
  通过 = 文档那格点的件与你读的那一份同一枚 md5/时间戳。
  失败 = 不同 ⇒ `FAIL`，按 `skill/pitfalls/who-else-writes-this-artifact/SKILL.md` 走身份核对。
  读不到输入 = 件不在盘上 ⇒ `NOT_MEASURED`，不许把该格当已验证念出。

## 7. 已验证的效果

- 本次直读并复算的行（2026-10-04，全部为打开该文件后取到的原文行号）：
  `build/timing_summary.rpt:3`（Tool Version 行）、`:145`（段落标题）、`:149`（列名行）、`:151`（数据行）、
  `:218-222 / :354-358 / :533-537`（逐时钟 Setup/Hold）、`:44-52`（内嵌 Report Methodology 表）；
  `build/utilization.rpt:33-40`（Slice LUTs / Registers）、`:106`（Block RAM Tile）、`:122`（DSP48E1 only）；
  `build/power.rpt:33 / :36 / :40 / :41 / :127`；`build/cdc.rpt:15-18`；`build/route_status.rpt:10`；
  `build/clock_util.rpt:43-49`；`build/methodology.rpt:28-36`。
- 本次实跑的复算命令与输出摘要（写进了两个 pitfalls 条目）：
  `awk` 取 timing 行 ⇒ `wns=0.739 whs=0.052 tnsfail=0 whsfail=0 eps=51135`；
  `rows` 式子作用于 `build/cdc.rpt` ⇒ 两条 Critical 配对；
  `grep -a "nets with routing errors" build/route_status.rpt | grep -oE '[0-9]+' | tail -1` ⇒ `0`。
- 一致性核对：上述读数与 `data/metrics.csv` 第 5–7 行（WNS 0.739 / WHS 0.052 / 0 个失败端点 / 总端点 51135）一致（同日直读）。
- 未覆盖部分：`build/*.rpt` 的其余章节（IO、Clocking 细目、Registers by Type 等）未逐行核对 ⇒ 那些行留空并标 `【未核实】`。

## 8. 提炼来源与边界

- 来源：本仓 `build/` 下上述真实件 + 解析它们的代码 `build/gates.sh:68-100,279-292`（列位口径的唯一住处）。
- 相互引用：`skill/pitfalls/report-field-parse-breaks/SKILL.md` §7 的实跑输出就是本页列位的凭据；两者互相指回。
- 候选来源行清单在 `skill/references/_proposed-sources.md`。
- 边界：换 Vivado 主版本、换报告命令（如加了 `-file`/`-min_passing_endpoints` 之类选项）、或换器件家族时，行号会整片平移；
  本页的**方法**（先 `grep -n` 定段、再 `awk` 打字段表、最后取列）仍然可用，具体行号需要重取。
- 平台相关行已在 `fields-timing.md`、`fields-resources.md` 里用"来源类型"列标出。

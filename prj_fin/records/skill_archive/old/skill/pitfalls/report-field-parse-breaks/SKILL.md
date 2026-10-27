---
name: report-field-parse-breaks
description: 处理"工具报告没变坏、解析器先失灵"这一类：当脚本报 FATAL 读不到某一行、或把负数读成空值/把别的列读成目标列时用它；触发信号是 build/timing_summary.rpt 里出现负 slack 后门禁仍说读不到、CDC 行字段数变化导致计数为 0、台架日志里的缩进 FAIL 行不被计数、以及 build/route_status.rpt 那一行末尾的数值被固定列号读错。
---

## 1. 一句话用途

报告形状变了，先修解析器再说结论。

## 2. 适用场景

- 当解析脚本打印"读不到 / FATAL / KeyError"，而你手上有那份报告且肉眼能看见那个数时。
- 当设计第一次出现**负** slack（WNS/WHS/TNS 为负）之后，原本工作的取数式突然返回空值或 null。
- 当同一份报告里同类行的**字段个数不同**（本仓 CDC 行：`No Common Primary Clock` 占 4 个 token，`Safely Timed` 占 2 个），而解析用的是固定列号。
- 当计数结果为 0，但你 `grep` 得到匹配行（本仓形状：台架把每条判据打成 `  FAIL <名字>`，前面有缩进）。
- 当你换了一个 Vivado/Vitis 版本、换了一个报告命令（如 `report_timing_summary` 的选项）、或换了器件家族之后，之前能读的字段读不到了。

## 3. 不适用 / 失效条件

- 不适用：报告确实没生成（文件不存在/0 字节）——那是产物缺失，见 `who-else-writes-this-artifact` 与本条步骤 1 的读不到输入分支。
- 不适用：数值本身违例（读得到且为负）——那是设计问题，不要用本条去"修数字"。
- 失效：解析器由工具官方 API 提供（例如直接读 JSON/对象属性而不是解析文本），本条的列位与正则部分不适用；仍适用的是"必须允许符号位"这一半。
- 失效：你已经把形状定义抽成一份**单一来源**并对真实工件跑过对照（本仓做法是 `build/rtl_fingerprint.sh` 那种"定义只有一处"），此时应改判为"报告变了"而不是"解析器坏了"。
- 不许越界：本条不给"该把阈值改成多少"的建议。

## 4. 前置条件

- 真实样例报告在盘上（本仓：`build/timing_summary.rpt`、`build/cdc.rpt`、`build/route_status.rpt`、`build/utilization.rpt`、`build/power.rpt`、`build/methodology.rpt`、`build/clock_util.rpt`）。
- `awk` / `grep` / `sed`；Windows 上用 Git Bash（MSYS），本仓所有解析式都在 MSYS 下写。
- 一份该报告字段位置速查表：`skill/references/build-report-field-map/SKILL.md`（本包内，行号取自上面那批真实文件）。
- 只读权限即可；不需要重跑构建。

## 5. 使用方法

1. 先确认"报告存在且非空"：`ls -la build/timing_summary.rpt`（示例取值）。
   完成后应看到：文件大小 > 0 且时间戳属于你要读的那一次构建。
2. 用肉眼定位那一行，把行号写下来：`grep -n "Design Timing Summary" build/timing_summary.rpt`，然后看它下面第一条数据行。
   完成后应看到：形如 `0.739 0.000 0 51135 0.052 0.000 0 51135 0.264 …` 的一行（本仓实测在第 151 行）。
3. 打印字段表，确认列位而不是猜：`awk 'NR==151{for(i=1;i<=NF;i++) printf "%d=[%s] ",i,$i; print ""}' build/timing_summary.rpt`。
   完成后应看到：$1=WNS、$3=TNS Failing Endpoints、$5=WHS、$7=THS Failing Endpoints、$8=THS Total Endpoints（本仓实测）。
4. 让正则**允许符号位**再重跑取数式（本仓形状：`build/gates.sh:69` 的四列数字都写成 `[-+]?[0-9]+\.[0-9]+`）。
   完成后应看到：负 slack 被读出为负数，而不是"读不到"。
5. 字段数会变的行改"从尾巴数列"：本仓 `build/gates.sh:100` 的 `$(NF-4)`（Endpoints）与 `$(NF-2)`（Unsafe）。
   完成后应看到：`awk '/^Critical/{print $2">"$3, $(NF-4), $(NF-2)}' build/cdc.rpt | sort`
   打出两行配对（本仓实测 `clk_fpga_0>clkout0_1 103 1` 与 `sys_clk>eth_rxc 1968 2`）。
6. 计数类判据要容忍缩进：用 `^ *FAIL( |$)` 而不是 `^FAIL`（本仓 `sim/run_one.sh:32-34`）。
   完成后应看到：`FAIL 行数` 与肉眼数到的缩进 FAIL 行数一致。
7. 末列取数用 `$NF`/`tail -1` 而不是固定列号（本仓两处真实写法：`build/gates.sh:88` 取路由错误数的最后一个纯数字、`build/rim_gate_ce.sh:57` 的 `awk 'NF{print $NF}'`）。
   完成后应看到：换一版报告加了尾部空格/列宽后仍能取到同一个数。
8. 读不到时**把候选行原样打出来**（本仓形状：`build/gates.sh:73`），再改解析式；不要只留"读不到"三个字。
   完成后应看到：错误输出里带 1–3 行报告原文，可以直接判"是我正则错了还是报告真没有"。

## 6. 判读与失败分叉

- 步骤 1：
  通过 = 文件存在且非空。
  失败 = 存在但 0 字节 ⇒ `FAIL`，去看是哪一步没跑完（不要在本条里绕）。
  读不到输入 = 文件不存在 ⇒ `NOT_MEASURED`，改跑 `bash build/gates.sh <某个冻结目录>` 指定一套完整件。
- 步骤 2：
  通过 = 找到 `Design Timing Summary` 且下方有数据行。
  失败 = 段落名换了（工具版本差异）⇒ 按你版本重取段落名，并重做步骤 3 的字段表。
  读不到输入 = 报告是别的工具的格式 ⇒ `NOT_MEASURED`，本条步骤 3 之后不适用，改为你那格式的列定义。
- 步骤 3：
  通过 = 你能说出每个要用的数的列号，且与速查表一致。
  失败 = 列号与表不一致 ⇒ 说明这份报告与表里那份不是同一次/同版本构建产出，先绑定版本再改表。
  读不到输入 = awk 无输出（行号写错）⇒ `NOT_MEASURED`，回到步骤 2。
- 步骤 4：
  通过 = 负数被读出。
  失败 = 仍读不到 ⇒ 检查文档里用的是 U+2212 减号还是 ASCII 连字符
  （本仓形状：`src/host/metric_recheck.mjs:46` 的 `sgn()` 先把 U+2212 折成 `-` 再 `Number()`；事故记录 `report/log/ISSUES.md` #321）。
  读不到输入 = 你手上没有任何负数样本 ⇒ `NOT_MEASURED`：造一份合成日志喂给 `--verdict` 类离线分支再判。
- 步骤 5：
  通过 = 输出行数 = 报告里 `Critical` 行数。
  失败 = 少行/多行 ⇒ 你的锚定词（`/^Critical/`）不唯一，换更具体的行首形状。
  读不到输入 = 输出为空 ⇒ 该报告这一版没有 Critical 行，这是**结论**不是失败，但要按"空集不许通过"处理（见 `checker-ran-on-nothing`）。
- 步骤 6：
  通过 = 计数 > 0 且与肉眼一致。
  失败 = 计数为 0 而报告里明明有 `  FAIL …` ⇒ 判定与计数不同源，改解析式。
  读不到输入 = 日志里没有判定行 ⇒ 走 `NO-VERDICT-LINE` 分支（rc=4），不是"没有 FAIL 所以过"。
- 步骤 7：
  通过 = 取到最后一个数字字段。
  失败 = 取到的是行号/时间戳 ⇒ 该行末尾有别的数字，改锚定到具体标签后再取值。
  读不到输入 = 整行缺失 ⇒ `NOT_MEASURED`，不要默认成 0。
- 步骤 8：
  通过 = 候选行打印出来，能一眼判正则错还是报告错。
  失败 = 打印的三行里没有目标数据 ⇒ 你的候选正则太宽，先收窄再判。
  读不到输入 = 没有任何候选行 ⇒ `NOT_MEASURED`，报告可能整段没生成，回到步骤 1。

## 7. 已验证的效果

- 基线（修复前，历史件）：`report/log/ISSUES.md` 记载 r60 那次 TNS 为负（−6.457）时，
  旧解析式只给 WNS/WHS 留符号位 ⇒ 脚本打印 `FATAL 读不到 timing summary` 并 `exit 2`，
  把最该看见的两个数（WNS −0.482 / 19 个失败端点）换成了"读不到"这句话；
  代码里的这段说明在 `build/gates.sh:62-67`。本轮**未重跑那一次构建的现场**，故"负 TNS 现在能被读出"的当次数值记 `【未实测】`。
- 用它之后（本轮实跑，2026-10-04，命令与输出原样）：
  `awk '/^[ ]*[-+]?[0-9]+\.[0-9]+…（同 build/gates.sh:69 的形状）/' build/timing_summary.rpt`
  → `wns=0.739 whs=0.052 tnsfail=0 whsfail=0 eps=51135`；
  与 `data/metrics.csv` 第 5–7 行的读数（0.739 / 0.052 / 0 / 51135）一致（该 csv 行点名 `build/timing_summary.rpt`）。
- CDC 尾巴数列（本轮实跑 2026-10-04）：`build/gates.sh:100` 的 `rows` 式子作用于 `build/cdc.rpt` 得
  `clk_fpga_0>clkout0_1 103 1`、`sys_clk>eth_rxc 1968 2`；同文件第 17–18 行是这两条 Critical 原始行。
- 分组取的字段（本轮实跑 2026-10-04）：`build/gates.sh:279-284` 的分组 awk 对 `build/timing_summary.rpt` 产出
  `clk_fpga_0|1.850|0|setup`、`eth_rxc|0.739|0|setup`、`sys_clk|14.876|0|setup`（及各自 hold 行），
  另有 `clkfbout`、`clkfbout_1`、`clkout1_1`、`clkout2` 四组打出 `NA`——这四组的成因本轮未查，只登记读数。
- 缩进 FAIL 计数：`bash sim/run_one.sh --verdict tb_v98_top_seam build/tb_v98_report.txt` 打出 `FAIL 行数=1 || PASS 行数=161`（2026-10-04 实跑）；
  同一份文件用严格 `^PASS` 也是 161（本轮 `grep -ac '^PASS'` 实测），
  而 `data/metrics.csv` 第 15 行写的是 140/1 且点名另一枚 `top_md5=2bf2ceeede07`；当前盘上这份报告的头行是 `top_md5=56c269602e18`（两份不是同一次跑，属同名覆盖，见 `who-else-writes-this-artifact`）。

## 8. 提炼来源与边界

- 证据：`report/log/ISSUES.md` #321（读不出负数 ⇒ 写对也红、写错也红，射程为零）、#166（缩进 FAIL 不被计数，红被念成"没数"）、
  #280 末尾（判据脚本 fixture 写成 `HOLDWorst|tap=13|…` 而真件是 `HOLDWorst|13|…` ⇒ 对着 fixture 全绿、第一份真件 `KeyError: 'tap'`）；
  代码形状 `build/gates.sh:62-73`、`build/gates.sh:88`、`build/gates.sh:100`、`build/gates.sh:279-284`、`sim/run_one.sh:32-34`、`build/rim_gate_ce.sh:57`。
- 工具行为断言的来源行见 `skill/pitfalls/_proposed-sources.md`。
- 停止适用的条件：你改用工具的对象/属性查询（`get_property`、结构化输出）而不是文本解析时，列位与正则那一半作废；
  符号位与"读不到必须说读不到"仍然适用。
- 迁移到新题目/新板卡要改的地方：
  1. 段落名与行号：本文行号取自本仓 `build/*.rpt`（Vivado 2025.2.1，器件 `xc7z020clg484-2`，见 `skill/references/tool-version-drift/SKILL.md`），换版本必须重取；
  2. 字段语义表：`build/cdc.rpt` 末五列（Endpoints / Safe / Unsafe / Unknown / No-ASYNC_REG）是本仓从这份文件里数出来的，别的 CDC 报告列不同；
  3. 判定 token：`FAIL`/`PASS`/`RESULT`/`VERDICT` 是本仓台架自己印的字符串，换工程就换成你的收尾词；
  4. 7 系列 ↔ UltraScale+ ↔ Versal：`report_cdc` / `report_methodology` 的报告表头列名可能变，本条只保证"从尾巴数列 + 允许符号位"这个做法可迁移。

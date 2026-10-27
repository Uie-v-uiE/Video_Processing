---
name: report_metrics
description: 从真实 Vivado 报告文本里按"表头右对齐到列末"取 WNS/TNS/失败端点/WHS/THS/脉宽与 LUT/FF/BRAM/DSP 与其 Available/Util%，落一份带来源行号的 CSV 与 Markdown，并给出八条自洽判据（部分与整体、印值与复算值、全局最差值与时钟族归属、阈值上下界、与上一版的双向漂移）。当症状是"报告里有数但抄进表格时串了列""负数把 awk 打回一句读不到""要证明某个百分比是印出来的还是算出来的"时使用。不跑 Vivado、不改报告、不比对两张任意外部表（那是 golden_compare）。
---

## 1. 一句话用途

把 Vivado 时序与资源报告读数成带出处的指标表。

## 2. 适用场景

- 报告已经生成（`report_timing_summary` / `report_utilization` 的落盘件），要把读数变成机器可核对的 key/value + 来源文件 + 来源行号时。
- 怀疑取值串列：值行与表头行不是按空格数对齐（负号、宽数字、`RAMB36/FIFO*` 这类含空白的 Site Type）时——本脚本按"右端对齐到表头字段末列"取。
- 需要"部分与整体"自洽：`LUT as Logic + LUT as Memory == Slice LUTs`、`FF + Latch == Slice Registers`、`RAMB36 <= Block RAM Tile <= RAMB36 + RAMB18`（R3）。
- 需要复算印值：用同一行 `Used/Available` 反算 Util%，容差只到"报告只印两位小数"（R4）。
- 需要归属而不只是绝对值：全局 WNS 的数必须等于某个时钟族的 WNS，且该族失败端点数与符号自洽（R5）。
- 与上一版对账：给 `--baseline` + `--max-drift-pct` 做双向漂移，并念出新增键/消失键（R7）。

## 3. 不适用 / 失效条件

- 报告还没生成：本脚本不调 Vivado（不探针工具，只读文件里的 `| Tool Version :` / `| Date :` 行），也不该被用来"顺手跑一次报告"。
- 想要的是"两张任意外部表逐键比对"：那是 `golden_compare`；这里的字段名与列位是按 Vivado 报告形状写死的。
- 换工具版本/换报告模板后列位漂了：R1 会把取不到的字段点名并整条 `NOT_MEASURED`，但**不会**替你改列位——先按第 8 节重测形状再改。
- `X` / 空 / 非数一律 `null`（`num()` 里 `/^x/i` 也算读不到），绝不默认 0；所以"综合刚跑完、报告还没更新"的时段里 R2/R5 会是 `NOT_MEASURED`，不要当通过。
- 阈值只给一侧（只给 `--max-pct` 不给 `--min-pct`）⇒ R6 `NOT_MEASURED`，不默认放行；同理只给 `--baseline` 不给 `--max-drift-pct` ⇒ R7 `NOT_MEASURED`。
- 想把 CSV/MD 写进工程目录：`--out-dir` 落在 `src/`、`sim/`、`build/`、`board/`、`data/`、`report/`、`docs/` ⇒ exit 3 拒绝，且不产出半截文件。

## 4. 前置条件

- 工具探针：**无外部探针**。版本与时间是"从报告文件头读出来的文本"（`Tool Version`、`Date`、`Design`、`Device` 被抄进产出的 `.md`），因此本脚本能跑不代表 Vivado 能跑；解释器版本由 `skill/scripts/selftest/run_all.sh` 念出（本会话实测 `node=v24.21.0`）。
- 输入三件：`--timing`（report_timing_summary 落盘件）、`--utilization`（report_utilization 落盘件）、`--out-dir`（可写、非工程目录）。本仓示例取值：`build/timing_summary.rpt` 与 `build/utilization.rpt`，需按自身工程替换。
- 缺输入的行为：缺任一必需参数 ⇒ `METRICS 前置不满足 缺 --xxx NOT_MEASURED` + `METRICS 前置不满足 判 0 项 FAIL`（exit **3**）；文件不存在/空文件 ⇒ `METRICS 读不到输入 … NOT_MEASURED` + `判 0 项 NOT_MEASURED`（exit **2**）；无法识别的参数只打一行（无分母行）后 exit 3。
- 可选旋钮：`--prefix`（默认 `metrics`）、`--max-pct FIELD=NUM`/`--min-pct FIELD=NUM`（可重复或逗号分隔）、`--baseline CSV`、`--max-drift-pct NUM`。
- 报告形状前提（本仓实测）：`| Design Timing Summary` 段标题 + 含 `WNS(ns)` 的表头行 + 虚线分隔行 + 值行；利用率表按 `^| Site Type |` 逐行匹配，同一个 Site Type 允许出现两次但两处 `Used` 必须一致。

## 5. 使用方法

1. 取数（本仓示例取值，需按自身工程替换）：
   ```bash
   node skill/scripts/report_metrics/report_metrics.mjs \
     --timing build/timing_summary.rpt --utilization build/utilization.rpt \
     --out-dir <临时产物目录> [--prefix metrics]
   ```
   完成后应看到八行 `R1_field_shape … R8_provenance_per_row …`（每行 `判 N 项`），末行
   `METRICS <csv> <md> 取到字段=N 判 N 项 未判 K 项 红 M 项 <判定>`。没给阈值/baseline 时末行是 `NOT_MEASURED`（exit 2），这是设计行为。
2. 全判（R6/R7 也要判过才许念绿）：
   ```bash
   node ... --out-dir <目录1> --max-pct <字段>=<上界> --min-pct <字段>=<下界>          # 先产一份 csv
   node ... --out-dir <目录2> --max-pct … --min-pct … --baseline <目录1>/metrics.csv --max-drift-pct 0
   ```
   完成后应看到：`R6_threshold_band 判 2 项 …  PASS`、`R7_baseline_drift 判 42 项 容许=0% 增=0 减=0 破限=0 新增键=0 消失键=0 PASS`，末行 `红 0 项 PASS`（exit 0）。
3. 反例自证（本仓 fixture，示例取值）：`--timing`/`--utilization` 换成 `skill/scripts/selftest/fixtures/report_metrics_negative/` 里那两件 ⇒ R3 必须红（部分之和与整体差 1）。
4. 台账用法：把 `<目录>/metrics.csv` 存成下一轮的 `--baseline`；`metrics.md` 每行都带来源文件与行号，引用读数时念这份 md，别念屏上的中文细节。

## 6. 判读与失败分叉

| 判据 | 通过 | 失败（红） | 读不到输入 |
| --- | --- | --- | --- |
| R1 字段形状 | `取不到=0 命中多次=0`（分母=请求字段数 22） | `命中多次=N` ⇒ 同一 Site Type 两处 `Used` 不一致或有一处为空 ⇒ 报告自己漂了或解析串列，**不许**"取第一条" | `取不到=N 例:…` ⇒ 段标题/表头/行形状与脚本假设不符，或值是 `X`/空 ⇒ `NOT_MEASURED` |
| R2 符号 vs 失败端点数 | `… 同向`（WNS≥0 配 0 个失败端点；负 WNS 配 >0 个） | `… 但 … （方向与端点数不自洽）` ⇒ 报告被截断或取错行；先确认这份报告是不是同一套产物 | 任一侧读不到 ⇒ `NOT_MEASURED`（`读不到=1`） |
| R3 整体与部分 | `lut 14154==14154 reg 8188==8188 bram 93<=95.5<=98`（夹逼两侧各算一次比较） | `… == … 不成立(got vs want)` 或夹逼破了（念出是小侧还是大侧） ⇒ 报告内部不一致，或该表被人为改过 | 总数或部分读不到 ⇒ `NOT_MEASURED` |
| R4 Util% 复算 | 每个 `_util_pct` 与 `Used/Available*100` 差 ≤0.005 | `印X 算Y` ⇒ 印值与算值不符（列串了、或 Available 取错） | Available 为空/0 ⇒ `读不到=N` ⇒ `NOT_MEASURED` |
| R5 全局 WNS 归属 | `全局 WNS=… 最差族=… 值等=yes … 与符号自洽=yes 参比族=N` | 值不等或端点与符号不符 ⇒ 全局最差值不来自任何时钟族（分层时钟/被约束掉的族），先查报告再查脚本 | 读不到 Intra Clock Table 或全局 WNS ⇒ `NOT_MEASURED`；"只有脉宽列没有 setup 列"的族会被念出来且不参比 |
| R6 阈值带 | 上下界都给且值在带内（两侧各算一次比较） | `上界N 破` / `下界N 破` ⇒ 这是结论，回到设计侧；**不要**为了让它绿而挪阈值 | 没给阈值、或只给一侧、或字段名对不上 ⇒ `判 0 项 NOT_MEASURED` |
| R7 baseline 漂移 | `破限=0`，且 `增/减`、`新增键/消失键` 都念出来 | `例:key:old->new(Δx%)` ⇒ 与上一版差过限；先确认两份件是不是同一次构建 | 没给 `--baseline` 或没给 `--max-drift-pct` ⇒ `NOT_MEASURED`；baseline 文件不存在 ⇒ exit 2 |
| R8 逐行出处 | 每行都有 `source_file`（且文件在盘上）与 `source_line`（正整数，可为逗号列表） | `缺出处的=N` ⇒ 有读数没来源，产出的表不能引用 | — |
| 产物 | `<前缀>.csv` 与 `<前缀>.md` 都在盘上（判读要数文件，不能只信 stdout 那行） | 只有一件 ⇒ 写入被打断，删掉目录重跑 | 目录被守卫拒绝 ⇒ exit 3 |

## 7. 已验证的效果

本会话（2026-10-04）在仓库根实跑；两份报告是本仓示例取值，需按自身工程替换。

- 只取数（不给阈值/baseline）：`METRICS …/metrics.csv …/metrics.md 取到字段=42 判 82 项 未判 2 项 红 0 项 NOT_MEASURED`（exit 2），其中
  `R1_field_shape 判 22 项 请求字段=22 取到=42 取不到=0 命中多次=0 PASS`、`R3_whole_vs_parts 判 4 项 lut 14154==14154 reg 8188==8188 bram 93<=95.5<=98 PASS`、
  `R4_percent_recheck 判 10 项 … 一致 PASS`、`R5_wns_ownership 判 2 项 全局 WNS=0.739 最差族=eth_rxc(行 182) 值等=yes 该族失败端点=0 与符号自洽=yes 参比族=4 PASS`、`R8_provenance_per_row 判 42 项 行=42 缺出处的=0 PASS`。
- 全判（阈值 + 上一份 csv 当 baseline + 容差 0）：`R6_threshold_band 判 2 项 lut_slice=26.61 上界40 下界10 PASS`、
  `R7_baseline_drift 判 42 项 容许=0% 增=0 减=0 破限=0 新增键=0 消失键=0 PASS`，末行 `取到字段=42 判 126 项 未判 0 项 红 0 项 PASS`（exit 0），产物两件都在盘上。
  ⚠ 如实说明：这一条的 baseline 是同一份输入的上一次产出（零漂移是构造出来的），它的意义是"R7 的通路被跑通过、且它能为红"，不是"设计没有漂移"——真实漂移要用上一轮留档的 csv 当 baseline（第 5 节第 4 步）。
- 反例（负向 fixture，两份报告的部分之和与整体各差 1）：`R3_whole_vs_parts 判 4 项 lut LUT as Logic + LUT as Memory == Slice LUTs 不成立(14154 vs 14155) reg FF + Latch == Slice Registers 不成立(8188 vs 8189) bram 93<=95.5<=98 FAIL`，末行 `判 82 项 未判 2 项 红 1 项 FAIL`（exit 1）。
- 阈值越界：`R6_threshold_band 判 2 项 lut_slice=26.61 上界1 破 下界0 FAIL`（exit 1）。
- baseline 被改动（把 `reg_slice` 那一行改成 7000 的临时副本）：`R7_baseline_drift 判 42 项 容许=0% 增=1 减=0 破限=1 新增键=0 消失键=0 例:reg_slice:7000->8188(Δ16.97%) FAIL`（exit 1）。
- 守卫与缺输入：`--out-dir build/_selftest_scratch` ⇒ `METRICS 前置不满足 --out-dir 指向工程目录 build/_selftest_scratch NOT_MEASURED` + `判 0 项 FAIL`（exit 3，目录没被创建）；`--timing no_such.rpt` ⇒ `METRICS 读不到输入 --timing no_such.rpt 不存在 NOT_MEASURED`（exit 2）。
- 串跑：`skill/scripts/selftest/run_all.sh` 的 `METRIC report_metrics 判 9 项 no_baseline=ok pos=ok pos_art=ok negR7=ok negR6=ok guard=ok guard_no_write=ok negR3=ok missing=ok PASS`。
- `--prefix` 改名、`--max-pct` 一次给多个 `FIELD=NUM` 逗号串、报告头四行缺失时的行为、同一 Site Type 两处不一致（`命中多次>0` 那一支）：`【未实测】`（本会话的真件里"两处一致"是成立的，没造过不一致的件）。

## 8. 提炼来源与边界

- 来源证据：下面这些列位假设不是按记忆写的，而是从 `build/timing_summary.rpt` 与 `build/utilization.rpt`（本仓示例取值，需按自身工程替换）逐列打印出来的结果：段标题 `| Design Timing Summary`、表头 12 列、`Intra Clock Table` 的连续行形状、`report_utilization` 里同一 Site Type 出现两行（两处 `Used` 必须一致）；
  形状漂移的历史事故记在 `report/log/ISSUES.md`（串列与"读不到当 0"两族）。
- 边界：只处理这两份 Vivado 报告；功耗、DRC、CDC 读数各有自己的抽取件，不塞进这里（塞进来就会把列位假设变成两处硬编码）。
- 迁移要改五处：① `TKEY`/`UNAME`/`UKEY` 三张表（换成你的报告字段名）；② 表头定位用的段标题正则；③ 右对齐取值（如果你的报告值行不是右对齐到表头末列）；
  ④ `PROTECTED` 守卫表；⑤ 反例件（必须造"部分≠整体"的一份，且改动只红 R3 一条）。
- 不再适用：报告改成 JSON 输出（`report_timing_summary -json`）时，本脚本的整层"按列位取值"应换成按键取值，R1 的分母语义随之变化。

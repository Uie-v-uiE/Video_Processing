---
name: golden_compare
description: 把黄金参考表与实际产出表做逐键、逐值、带绝对容差的三态比对：键集合双向覆盖（少一行与多一行都判红）、增减分开计数、最差值必须属于黄金参考并能被黄金值夹住、两张表的解析面各自打印行数与坏值数。当症状是"这轮产出与上一轮/与冻结基线差了一点，但不确定是哪一个键哪一列"、或需要把 CDC/时序/资源读数钉在一份基线件上时使用。不解释报告语义（那是 report_metrics），不校验寄存器契约（那是 regmap_check）；两边没有共有键时它只会 NOT_MEASURED，不会替你编结论。
---

## 1. 一句话用途

黄金参考表与实际产出表的逐键逐值三态比对。

## 2. 适用场景

- 有一份"冻结下来的参考读数"和一份"这一轮的实际读数"，要证明两边同一个键上的同一列没漂（含容差）时。
- 差值必须分方向看（变大与变小是不同的处置），而手抄 grep 只看绝对值时。
- 报告是空白分列或 CSV，键需要由第几列拼出来（`$2>$3` 这种模板）时。
- 怀疑"产出多出一行"或"基线里的一行这次没产出"——两种都必须判红，只数共有键的比对器看不出。
- 要把比对结果落一份 CSV 台账（`--out-dir`）供逐键复核时。

## 3. 不适用 / 失效条件

- 读数本身还没被解析出来：先跑 `report_metrics` 或该报告的专用抽取脚本；本脚本只吃"已经是表"的东西。
- 两张表没有任何共有键 ⇒ C2/C3 空集合 `NOT_MEASURED`（本脚本**不会**替你推断它们等价），别把这种状态念成"通过"。
- 想要相对百分比容差：本脚本的 `--tolerance` 是**绝对偏差**，两侧同一容差；跨量级的列要分别给容差或分次跑。
- 键是浮点或含空白的列：kv 模式按空白分列，含空白的字段会被拆错（CSV 模式按引号处理，见第 7 节【未实测】条）。
- 要把结果写回工程目录：`--out-dir` 落在 `src/`、`sim/`、`build/`、`board/`、`data/`、`report/`、`docs/` 之下 ⇒ 直接拒绝（exit 3），一条判据都不打印。
- 判"哪一侧是真相"：本脚本只做对账，黄金参考错了它照样绿。

## 4. 前置条件

- 工具探针：本脚本**不探针外部工具**，只用 `node:fs` 读两个输入文件；没有网络、没有子进程。解释器版本由 `skill/scripts/selftest/run_all.sh` 的汇总行念出（本会话实测 `node=v24.21.0`）。
- 输入两件都必须显式给：缺 `--golden` 或 `--produced` ⇒ `GOLDEN 前置不满足 缺 --golden NOT_MEASURED` + `GOLDEN 前置不满足 判 0 项 FAIL`，exit **3**。
- 文件不存在或为空文件 ⇒ `GOLDEN 读不到输入 --golden … 不存在/是空文件 NOT_MEASURED` + `GOLDEN 读不到输入 判 0 项 NOT_MEASURED`，exit **2**。
- 每边必须给 `--values`（至少一个数值列），否则解析器抛 `没给 --values` ⇒ exit 3（走 `表头/表达式解析失败`）。
- `--tolerance` 不是数 ⇒ exit 3；不给默认 0。
- kv 模式：默认注释符 `#`（行首），空行跳过；CSV 模式第一行当表头。

## 5. 使用方法

1. 最小形式（kv，两边列位相同）：
   ```bash
   node <技能包>/skill/scripts/golden_compare/golden_compare.mjs \
     --golden <黄金表>.tsv --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' \
     --produced <产出表>.tsv --produced-key '$1' --produced-values 'endpoints=@2,unsafe=@1' \
     --tolerance 0 [--out-dir <临时目录>]
   ```
   完成后应看到：`C1_key_coverage / C2_value_vs_tolerance / C3_worst_row_membership / C4_parse_surface_nonempty` 四行，
   每行带 `判 N 项`，末行 `GOLDEN <黄金件> vs <产出件> 判 N 项 未判 K 项 红 M 项 PASS|FAIL|NOT_MEASURED`（最后一字段才是判定）。
2. 两边列位不同 + 行过滤（本仓示例取值，需按自身工程替换：CDC 基线 vs 冻结的 CDC 报告）：
   ```bash
   node ... --golden build/CDC_BASELINE.txt --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' \
     --produced build/frozen_r23_srcseen/cdc.rpt --produced-key '$2>$3' \
     --produced-values 'endpoints=@5,unsafe=@3' --produced-where '$1=Critical' --tolerance 0
   ```
   完成后应看到：末行 `GOLDEN CDC_BASELINE.txt vs cdc.rpt 判 18 项 未判 0 项 红 0 项 PASS`。
3. 落台账：加 `--out-dir <临时目录>` ⇒ 生成 `golden_diff.csv`（列 `key,value,golden,produced,delta,within_tolerance`，末行是 `verdict,…,judged,…,not_measured,…,fail,…` 汇总行）。
   ⚠ 判读只看末行的最后一个字段：随后打印的 `GOLDEN 写出 … 判 N 行 PASS` 那行说的是"写文件这件事"，**不反映比对结论**。
4. 反例自证（本仓 fixture，示例取值）：把 `--produced` 换成 `skill/scripts/selftest/fixtures/golden_compare_negative/produced.tsv` ⇒ C2 必须红，且增/减两侧都非零。

## 6. 判读与失败分叉

| 命令 | 通过 | 失败 | 读不到输入 |
| --- | --- | --- | --- |
| 整体 exit 码 | 0 可比对且全绿 | 1 = 有红项（结论） | 2 = 读不到/解析不到/空集（不是结论）；3 = 前置不满足（缺参、坏容差、`--out-dir` 指工程目录） |
| `C1_key_coverage` | `产出缺=0 产出不明=0`，分母=两边键的并集数 | `产出缺=N` = 基线里有 N 个键这次没产出；`产出不明=N` = 产出里有 N 个键基线不认识。两种都要回到生成侧，不许改键表达式糊过去 | 分母 0（两张表都没数据行）⇒ `NOT_MEASURED` |
| `C2_value_vs_tolerance` | `超上=0`（超上限的键值对数），且 `键值增/键值减` 与你的预期一致 | `超上=N 例:key.col:g->p(Δ±d)` ⇒ 逐键回到两份原始报告；只判一侧（只看增或只看减）是半成品，本脚本两个方向都数 | 值格为空/非数 ⇒ 计入 `值不可解析` 并整条 `NOT_MEASURED`；无共有键 ⇒ `判 0 项 NOT_MEASURED` |
| `C3_worst_row_membership` | 每个被比列的最差行"属于黄金=yes 不比黄金差=yes" | 任一 no ⇒ 产出里冒出一个基线没有的更差行（归属与取值两维同条判，不会只报一半） | 取不到可比的最差行 ⇒ `NOT_MEASURED`（两维一起判不了才算没判） |
| `C4_parse_surface_nonempty` | 两边行数都 >0，并念出各自的空/坏值数 | — （这条只负责"读到了东西"） | 任一边行数为 0 ⇒ `NOT_MEASURED`，等价"这条判据今天没被喂料" |
| `--out-dir` 台账 | `golden_diff.csv` 出现且末行 `verdict` 与屏上一致 | 末行 verdict 与屏上不符 ⇒ 是台账生成侧的问题，别信 CSV | 目录被守卫拒绝 ⇒ exit 3，屏上只有两行前置不满足 |

## 7. 已验证的效果

本会话（2026-10-04）实跑，均在仓库根；命令里的表是本仓示例取值，需按自身工程替换。

- 正例（`fixtures/golden_compare_positive/golden.tsv` vs 同目录 `produced.tsv`，`--golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1'`）：
  `GOLDEN golden.tsv vs produced.tsv 判 18 项 未判 0 项 红 0 项 PASS`（exit 0），四行分别 `C1 判 4 / C2 判 8 / C3 判 4 / C4 判 2` 全 PASS。
- 反例（换成 `fixtures/golden_compare_negative/produced.tsv`）：
  `C2_value_vs_tolerance 判 8 项 容差=0 超上=2 键值增=1 键值减=1 值不可解析=0 例:clk_b>clk_a.endpoints:20->21(Δ+1) clk_d>clk_a.endpoints:12->11(Δ-1) FAIL`，
  末行 `判 18 项 未判 0 项 红 1 项 FAIL`（exit 1）——一增一减各抓到一条，正是这条判据要的"两个方向都能判"。
- 真件对账（基线件 vs 冻结报告，上面第 2 步那条命令）：`GOLDEN CDC_BASELINE.txt vs cdc.rpt 判 18 项 未判 0 项 红 0 项 PASS`（exit 0）。
- 空集对照（`--produced` 换成只有 `#` 表头行的文件）：`C1_key_coverage 判 4 项 黄金=4 产出=0 共有=0 产出缺=4 产出不明=0 FAIL`，
  `C2`/`C3` 打 `判 0 项 …（空集合不算通过）NOT_MEASURED`，末行 `判 6 项 未判 3 项 红 1 项 FAIL`（exit 1）⇒ 读不到东西没有伪装成绿。
- 守卫与缺输入：`--out-dir build/_selftest_scratch` ⇒ `GOLDEN 前置不满足 --out-dir 指向工程目录 … NOT_MEASURED` + `判 0 项 FAIL`（exit 3）；
  `--golden no_such_a.tsv` ⇒ `GOLDEN 读不到输入 --golden no_such_a.tsv 不存在 NOT_MEASURED`（exit 2）。
- 以上由 `skill/scripts/selftest/run_all.sh` 串成一行：`GCMP golden_compare 判 7 项 pos=ok pos_art=ok guard=ok empty_set=ok negC2=ok missing=ok real_pair=ok PASS`。
- `--golden-format csv` / `--produced-format csv`、`--comment` 改注释符、`--golden-where`（只过滤黄金侧）、非零 `--tolerance`：`【未实测】`
  ——本会话只跑了 kv 与 `--produced-where`，CSV 分支需要一个带表头的 CSV 件才测得到。

## 8. 提炼来源与边界

- 来源证据：`skill/scripts/golden_compare/golden_compare.mjs` 的 C1–C4 实现（键覆盖、带方向的容差比对、最差行归属、解析面）与文件头"判定 token 一律放在每行最后一个字段"；
  反例件 `skill/scripts/selftest/fixtures/golden_compare_negative/produced.tsv`（同键同列改一个 +1、一个 −1）。
- 边界：本条目只做"两张表的差"，不做"一张表内部的自洽"（那是 `report_metrics` 的 R3/R4）、不做逐轮趋势（那需要 baseline 语义，见 `report_metrics` 的 R7）。
- 迁移要改四处：① 键/值表达式（`$N`/`@N`/模板）按你的报告列位重配；② `--*-where` 的过滤字面量（本仓示例 `$1=Critical`）；
  ③ `PROTECTED` 守卫表；④ 反例件（必须一增一减两条，否则只测到半个方向）。
- 不再适用：需要按相对百分比判漂、或两边键不同源（要先做名称归一）时——那一步必须在外面完成，本脚本的键比较是逐字符相等。

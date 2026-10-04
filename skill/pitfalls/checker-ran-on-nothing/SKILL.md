---
name: checker-ran-on-nothing
description: 让"判据其实没执行"这件事可判：当聚合结论（如 `GATES: ALL PASS`、`RESULT … PASS`、`violations=0`、`drop_words=0`）出现，而它的输入文件缺席、集合为空、样本数为 0、或计数器对不上时，用它把"通过"降级为"未判"并定位是哪一项没跑；触发物是 build/gates.sh 的 n/a 行、build/ports_check.txt 里 instances=0 却绿、data/metrics.csv 里 0 值行、以及仿真日志里找不到判定行。
---

## 1. 一句话用途

把"没判"从"通过"里分出来。

## 2. 适用场景

- 当聚合脚本打印 `ALL PASS` / `PASS`，而其中某几项的输入文件在你选的目录里不存在时
  （本仓形状：`bash build/gates.sh <冻结目录>` 报 `n/a` 行）。
- 当你新写一把检查器，**第一跑就绿**，且你无法说出它这次读了哪几行、判了几个数时。
- 当某个"计数器 = 0"就是判据本身（`violations=0`、`FAIL 行数=0`、`drop_words=0`），而样本总体可能是空的。
- 当一份报告同时有 `RESULT … FAIL` 与 `FAIL 行数=0` 这类自相矛盾的读数（红与"没数"长得一样）。
- 当有人把一项判据改成"读不到就跳过"，绿项数随之上升时。

## 3. 不适用 / 失效条件

- 不适用：判据已经打印了**分母**（例如结论行自带"判定 N 项 / 未判 M 项"，且 M>0 时退出码非 0）——本条只补没分母的场合。
- 不适用：你手里根本没有可执行的判据（没有脚本、只有肉眼观察）——那属于测量方法缺失，不是本条。
- 失效：换一个不打印 `n/a`/`NO-VERDICT-LINE` 这类词的工具或脚本，本条给的 grep 词表要换成你那把尺子的三态 token（`skill/references/checker-convention-shapes/SKILL.md` 那张表按你的脚本重写）。
- 失效：被聚合的判据本身是外部工具的退出码（你无法要求它区分"没判"与"判过"）——只能在外层包一层计数。
- 不适用：硬件/工具明确报错并停住的场合（那是失败，不是未判）。

## 4. 前置条件

- 一个能一条命令跑出聚合结论的脚本；本仓示例是 `build/gates.sh`、`sim/run_one.sh`、`build/board_verify.sh`（示例取值，需按自身工程替换）。
- 该脚本的**输入报告目录**可选（`gates.sh` 的第 1 个参数）。
- `bash` + `grep` + `awk`；只读操作，不需要 Vivado/Vitis，也不需要连板子。
- 一份"应当有 N 项"的清单来源（本仓做法：以脚本里 `say` 的调用次数为准，见 `build/gates.sh:184`），不许抄文档里的数字。

## 5. 使用方法

1. 跑聚合判据，把输出落盘而不是只看屏幕：`bash build/gates.sh > /tmp/kx/g.txt 2>&1`。
   完成后应看到：一份文件，末行是三态之一（`GATES: 有红项…` / `GATES: PARTIAL …` / `GATES: ALL PASS（N 项全部判定）`）。
   ⚠ 不要把 stdout 直接重定向进它自己要读的凭据文件（`build/rNN_gates.txt`），那会先截空再判。
2. 数"未判"：`grep -c '^ *n/a' /tmp/kx/g.txt`。
   完成后应看到：一个整数；非 0 时末行必须是 PARTIAL 而不是 ALL PASS。
3. 数分母：`grep -c '^  ' /tmp/kx/g.txt` 与 `grep 'GATES:' /tmp/kx/g.txt` 里的"判定 N 项"对照。
   完成后应看到：结论行里的 N 与"绿 + 红"的行数一致；不一致就是有一行既没算绿也没算红。
4. 对每一个"=0 就是过"的项，单独验它的总体不是空的：
   本仓形状 `python build/check_ports.py --dup > /tmp/kx/p.txt` 后读末行 `violations=0` 之外的 **instances/scanned 计数**
   （示例取值，需按自身工程替换；`build/gates.sh:257` 调的 `build/ports_floor.sh` 就是这条地板）。
   完成后应看到：总体数 ≥ 你自己那条下限；否则该项按 `NOT_MEASURED` 记。
5. 对仿真/台架类结论，用同一把解析器的离线分支复算一遍判定与计数：
   `bash sim/run_one.sh --verdict <tb名> <那份 run.log 或报告>`（本仓 `sim/run_one.sh:14` 的分支，纯文本工作、不起仿真）。
   完成后应看到：一行 `VERDICT <tb>: …` 与 `FAIL 行数=` / `PASS 行数=`，退出码 0/3/4 三档之一。
6. 把本轮"未判"的项名与缺失的输入文件路径登记下来（写进你工程的日志文件），不许靠删掉该项来消除 n/a。

## 6. 判读与失败分叉

- 步骤 1：
  通过 = 末行三态之一且 rc 与之对应（本仓：`ALL PASS` ⇒ rc=0；PARTIAL 或有红项 ⇒ rc=1）。
  失败 = 末行是 `GATES: ALL PASS` 但步骤 2 数出 n/a>0 ⇒ 结论行没带范围，按 `FAIL`，回到步骤 3 之前先补分母打印。
  读不到输入 = 脚本报 `FATAL 缺报告：<路径>`（本仓 `build/gates.sh:32`）⇒ `NOT_MEASURED`，先确认你选的目录里有哪些工件，不要改成"跳过这一项"。
- 步骤 2：
  通过 = 计数与结论行里的"未判 M 项"相等。
  失败 = 计数 > 0 而结论行写 ALL PASS ⇒ 判据静默不执行这一类，先修结论行生成处。
  读不到输入 = 文件不存在或 0 字节 ⇒ `NOT_MEASURED`，重跑步骤 1（若是后台跑，先排除并发写：见 `who-else-writes-this-artifact`）。
- 步骤 3：
  通过 = N = 绿数 + 红数。
  失败 = 对不上 ⇒ 有一项既没进 pass 也没进 fail 的计数；去数 `say` 的调用点与 `n/a` 打印点（本仓分别是 `build/gates.sh:175` 与 `build/gates.sh:180`）。
  读不到输入 = 结论行没有数字 ⇒ `NOT_MEASURED`，本条判据对你不成立，先给结论行加分母。
- 步骤 4：
  通过 = 总体数 ≥ 下限且 violations=0。
  失败 = 总体数为 0 而该项报绿 ⇒ 空集通过，判 `FAIL`，把该项改成"读不到总体即判红"。
  读不到输入 = 拿不到总体数（脚本没打印）⇒ `NOT_MEASURED`，先给尺子加一行射程打印。
- 步骤 5：
  通过 = 打出 `VERDICT <tb>: <判定>` 且 rc 与判定一致（0 绿 / 3 判红 / 4 认不出判定）。
  失败 = 打出 `NO-VERDICT-LINE` ⇒ 这支台架一条判定都没打，判 `FAIL` 而不是"没有 FAIL 所以过"。
  读不到输入 = 报 `CE-FATAL 读不到 <log>`（rc=2）⇒ `NOT_MEASURED`，先确认那份日志来自哪一跑。

## 7. 已验证的效果

- 基线（不用本条）：同一份 `build/tb_v98_report.txt` 里既有 `RESULT tb_v98_top_seam FAIL nfail=1` 又有 161 行 PASS；
  只看"有没有 FAIL 行"或只看汇总行都可能把这一跑念成"没数"。实测命令
  `bash sim/run_one.sh --verdict tb_v98_top_seam build/tb_v98_report.txt`
  输出 `VERDICT tb_v98_top_seam: RESULT tb_v98_top_seam FAIL nfail=1 || FAIL 行数=1 || PASS 行数=161`，`rc=3`（2026-10-04 本机实跑）。
- 负对照（同一把尺子必须拒"别人的日志替这支台架答复"）：
  `bash sim/run_one.sh --verdict tb_notthere build/tb_v98_report.txt`
  输出 `VERDICT tb_notthere: NO-VERDICT-LINE（这支台架一条判定都没打，去数判据条数） || FAIL 行数=1 || PASS 行数=161`，`rc=4`（2026-10-04 本机实跑）。
- 用它之后的差别（"未判"被念出来）：`report/log/ISSUES.md` #333 记的同一轮门禁，
  件 `build/evidence/r118_board/g1b.txt`（23 绿/1 红）→ 出现新红后 `21 绿/3 红`，随后定版两跑回到 `23 绿/1 红`
  （件 `build/evidence/r118_board/gatesc_summary.txt`）；这三份件是仓库里已有的历史读数，本轮**未重跑门禁**（重跑会写 `build/ports_check.txt`），
  所以"本轮重跑能复现 23/1"这一条记 `【待验证】`。
- 空集通过的历史基线：`report/log/ISSUES.md` #316（2026-10-04 02:14 前后）——`board_verify` 打印 `drop_words → 0` 的那一刻 `eth_live=0`，
  这个 0 属"没流量所以不可能丢"；带流重测后才有 `eth_live=1 … drop_words=0` 两次一致。修法是判据里加同一份读数的 `eth_live=1`。
- 计数对不上时的分母形状：本仓 `build/gates.sh:357` 那条 `[ "$NJ" = "3" ]` 地板（少一枚指纹判定就判红），
  它对应的事故是 `report/log/ISSUES.md` #203（`set -u` 下函数少传一个参数，命令替换只让**子 shell** 退出，本项照报 PASS）。

## 8. 提炼来源与边界

- 证据：`report/log/ISSUES.md` #164 / #166 / #194 / #203 / #316 / #333（本文按编号引用，未逐条抄写原文）；
  代码形状 `build/gates.sh:32`（缺报告 FATAL）、`build/gates.sh:164`（读不到就 exit 2，不拿空值当 0）、
  `build/gates.sh:180`（`naa()` 计数）、`build/gates.sh:586`（ALL PASS 的生成条件）、`build/gates.sh:285`（读不到分组行 ⇒ 未验）、
  `sim/run_one.sh:36`（NO-VERDICT-LINE）、`sim/run_one.sh:113`（退出码分档 0/1/2/3/4）；
  台账件 `build/evidence/r118_board/g1b.txt`、`build/evidence/r118_board/gatesc_summary.txt`。
- 工具行为断言与来源行见 `skill/pitfalls/_proposed-sources.md`（本目录不写 `_meta/`）。
- 停止适用的条件：你的聚合判据已经强制打印分母且退出码在未判时非 0；那时本条只剩"每加一项就检查分母是否同步"这一半价值。
- 迁移到新题目/新板卡要改的地方：
  1. 三态 token 词表（`ALL PASS`/`PARTIAL`/`n/a`/`NO-VERDICT-LINE`/`REFUSE` 是本仓脚本自己印的）——换成你脚本的字符串；
  2. 退出码表（本仓 `sim/run_one.sh` 是 0/1/2/3/4）；
  3. "0 就是过"的具体计数器名（本仓例 `violations=0`、`drop_words=0`、`FAIL 行数=0`）；
  4. 冻结目录参数化（本仓 `build/gates.sh <目录>` 缺文件会回落到 `build/`，见 `pick` 的定义 `build/gates.sh:26`）——若你的工具不回落，步骤 1 的读不到输入分支要改成硬失败。
- 平台相关：本条只读文本产物，与 7 系列 / UltraScale+ / Versal 无关；与 Vivado 版本无关。

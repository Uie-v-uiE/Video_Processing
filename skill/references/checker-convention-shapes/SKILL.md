---
name: checker-convention-shapes
description: 查本仓库判据的"形状约定"：写新检查器或改现有判据时，用它对齐三态 token（PASS/FAIL/n-a、ADOPT/DECLINE/NOT_MEASURED、REFUSE、MECHANISM_INERT）、退出码（0/1/2/3/4）、结论行必须携带的分母（判定 N 项、判 N 个数、八条对照）、末列取值写法（$NF、$(NF-4)）与反例脚本入口；触发场景是门禁打印与你的预期不一致、或某项红了却说不清是设计红还是尺子红。
---

## 1. 一句话用途

判据的形状约定，一张表查完。

## 2. 适用场景

- 当你要新写一支判据脚本，需要与本仓已有脚本对齐 token、退出码与分母写法时。
- 当某项"红了"，而你要先分清是设计红、凭据缺失（未判）、还是尺子自己断了时。
- 当聚合结论只有两态（绿/红），而你需要的第三态（读不到输入）已经在本仓别的脚本里有现成 token 时。
- 当你要给一条新判据配反例（变异对照），需要参照"反例跑的是同一份代码而不是另抄一份"这条现成做法时。
- 当你要解析一行的最后一列，而列数随内容变时。

## 3. 不适用 / 失效条件

- **本层不是判据**：任何结论都不能靠本页自称成立，只能靠 `evals/` 的记录或实测输出；本页写的是"本仓脚本现在怎么印"，不是"你该怎么判"。
- 不适用：官方工具的退出码语义（Vivado/xsim/xsdb 的 rc）——那类要按版本绑定，见 `skill/references/tool-version-drift/SKILL.md`。
- 不适用：外队工程——本表的 token 与文件名是本仓约定（示例取值，需按自身工程替换），迁移时要整列重写。
- 失效：脚本改了措辞（例如把 `n/a` 换成别的词）而不带对照，本页那一行随之作废；核对日期 2026-10-04。
- 不许越界：本页不给出"该把阈值改成多少"。

## 4. 前置条件

- 仓库根能跑 `bash`、`node`、`python`（本表里的脚本分别用这三种）。
- 打开过的脚本：`build/gates.sh`、`sim/run_one.sh`、`build/board_verify.sh`、`build/ports_floor.sh`、
  `build/gates_cdc_test.sh`、`build/run_one_ce.sh`、`build/rim_gate_ce.sh`、`build/r95_timing_round.sh`、
  `build/r115_fanout_ab.sh`、`src/host/line_cite_check.mjs`（本次全部直读过相关行）。
- 一份"被读的报告目录"参数习惯：`bash build/gates.sh [冻结目录]`。

## 5. 使用方法

1. 先查主表 `tokens-and-exit-codes.md`（按脚本名列 token、退出码、分母、反例入口）。
   完成后应看到：你手上那支脚本对应的一行；对不上就是新脚本，按下述四条约定补齐。
2. 写结论行时把**分母**一起印出来（照本仓形状：`判定 $NSAY 项`、`判 N 个数`、`八条对照`），
   并且"未判"要有独立计数与独立措辞。
   完成后应看到：末行有三种之一——有红项 / PARTIAL（判定 N 全过，但有 M 项未判）/ ALL PASS（N 项全部判定）。
3. 读不到输入时不要复用"红"：给一个 `n/a` 或 `NOT_MEASURED` 档，并让退出码与"红"不同档
   （本仓形状：`sim/run_one.sh` 把 rc=3（判红）与 rc=4（认不出判定）分开）。
4. 末列取值用 `$NF` 系列而不是固定列号（本仓三种真实写法：`awk 'NF{print $NF}'`、`$(NF-4)`/`$(NF-2)`、`-F'\t' '$NF=="RED"'`）。
   完成后应看到：同一份件在列宽变化后仍取到同一个值。
5. 新判据必须配一支"跑同一份代码"的反例脚本（本仓形状：`build/ports_floor.sh` + `build/ports_floor_ce.sh`、`build/gates_cdc_test.sh` 五个 case）。
   完成后应看到：反例脚本自己打印 `SELF PASS …` 且退出码 0；不红不绿都算失败。
6. 判据的健康度要绑在它支撑的那一项上（本仓形状：门禁第 15 项在判定前先跑 `build/run_one_ce.sh`，不过就把该项判红）。
   完成后应看到：尺子坏的时候，被它支撑的那一项也红。

## 6. 判读与失败分叉

- 步骤 1：
  通过 = 主表里有你脚本那一行，且 token 与你看到的一致。
  失败 = 对不上 ⇒ `FAIL`，说明文档漂了或脚本改了措辞；回 §4 的那支脚本直读，更新主表行。
  读不到输入 = 脚本不在这台机器上（新克隆/新工程）⇒ `NOT_MEASURED`，本表对你不适用。
- 步骤 2：
  通过 = 末行带"判定 N 项"，且 N = 绿+红行数。
  失败 = 末行只有 PASS/FAIL ⇒ `FAIL`（有 n/a 时会被念成 ALL PASS，这是本仓 #141 那一族的形状）。
  读不到输入 = 末行没有数字 ⇒ `NOT_MEASURED`，先补分母打印再谈结论。
- 步骤 3：
  通过 = 三档退出码可区分（0 / 判红 / 读不到）。
  失败 = 判红与"没数"同码 ⇒ `FAIL`，链里 `… || die` 会把"没跑"读成"过了"。
  读不到输入 = 你的调用方式把 rc 吞了（管道右侧）⇒ `NOT_MEASURED`，先落盘再读。
- 步骤 4：
  通过 = 取到的值与肉眼一致。
  失败 = 取到行号/时间戳 ⇒ `FAIL`，锚定标签后再取值。
  读不到输入 = 取到空串 ⇒ `NOT_MEASURED`，本仓做法是判红或 `n/a`，**不**默认 0（`build/gates.sh:162-166`）。
- 步骤 5：
  通过 = 该红的能红、该绿的能绿，且反例覆盖"基线坏了"这一类。
  失败 = 反例一条都不红 ⇒ `FAIL`：判据没牙（本仓 `build/gates_cdc_test.sh` 的 T1–T5 就是为此写的）。
  读不到输入 = 反例需要的输入件不在盘上 ⇒ `NOT_MEASURED`，别把"跑不了"写成"过了"。
- 步骤 6：
  通过 = 尺子不健康时被支撑项红。
  失败 = 尺子坏了但被支撑项绿 ⇒ `FAIL`，把健康度检查放进那一项的判定里。
  读不到输入 = 反例脚本自身无法运行 ⇒ `NOT_MEASURED`，先修反例。

## 7. 已验证的效果

- 本次直读的形状（2026-10-04，逐条打开文件核对）：
  `build/gates.sh:173-183`（`NSAY`/`NNA` 与 `say`/`naa` 两个计数器）、`build/gates.sh:581-586`（三态结论行与退出码 1/1/0）、
  `build/gates.sh:32`（缺报告 FATAL exit 2）、`build/gates.sh:164`（解析不到变量即 exit 2）；
  `sim/run_one.sh:36-44`（`NO-VERDICT-LINE` + rc=4；rc=3 判红；rc=0 绿）、`sim/run_one.sh:58-60`（`REFUSE …` exit 3）、
  `sim/run_one.sh:16`（`CE-FATAL 读不到 …` exit 2）；
  `build/board_verify.sh:263`/`:265`（`RESULT board_verify PASS（判红的步骤：0）` exit 0 / `FAIL nred=N` exit 1）、`:114`（`REFUSE: 找不到 xsdb` exit 2）；
  `build/ports_floor.sh:15-25`（`FLOOR BAD` exit 1 / `FLOOR OK instances=… width_compared=…` exit 0，地板 `FLOOR_I=100`、`FLOOR_W=280`）；
  `build/run_one_ce.sh:71-72`（`SELF PASS run_one --verdict（八条对照都按期望动）` exit 0 / `SELF FAIL …（$BAD 条不符）` exit 1）；
  `build/gates_cdc_test.sh:12-20`（五个 case T1–T5，"全部符合预期才 0"）；
  `build/r95_timing_round.sh:113`（`word()`：0→ADOPT、2→NOT_MEASURED、其余→DECLINE）；
  `build/r115_fanout_ab.sh:41`（`line …` 只有第 4 个参数等于 `RED` 才置 R=1，`GREEN`/`INFO` 不置）。
- 本次实跑（2026-10-04）：`node src/host/line_cite_check.mjs` 打印
  `D5: CLEAN（退出码只由硬错决定；soft 158 条是给人排队的候选…）`，rc=0；
  同轮 `bash sim/run_one.sh --verdict …` 得 rc=3 与 rc=4 各一次（见 `checker-ran-on-nothing` §7）。
- 未实测：`build/ports_floor.sh`、`build/gates_cdc_test.sh`、`build/run_one_ce.sh` 本轮**没有真的执行**
  （`gates_cdc_test` 会拷基线、`run_one_ce` 会喂合成日志；本轮只直读代码），三态与退出码因此记 `【待验证】`。

## 8. 提炼来源与边界

- 来源：上一节列出的脚本行（本次全部打开过）；台账动机 `report/log/ISSUES.md` #141（结论行必须带范围）、
  #163/#164/#166（红/没数/没跑必须长得不一样）、#194（只看退出码 ⇒ instances=0 也绿）、#203（`set -u` 下子 shell 退出而本项报 PASS）、
  #209（要两把尺子：手写基线 + 上一版采纳件）。
- 现有条目引用关系：`skill/pitfalls/checker-ran-on-nothing/SKILL.md` §3、`skill/pitfalls/report-field-parse-breaks/SKILL.md` §8、
  `skill/pitfalls/exit-zero-nothing-written/SKILL.md` §6；技能包同族主条目在 `skill/S30`（`skill/references/verdict-line-must-print-scope/SKILL.md`）与
  `skill/pitfalls/criterion-blind-spot/SKILL.md`（S21）、`skill/references/bench-self-inflicted-reds/SKILL.md`（S20）——本页不复制它们的清单，只给形状对照。
- 候选来源行在 `skill/references/_proposed-sources.md`。
- 边界：本表是"本仓约定"的快照；换团队/换语言时整表重写，但 §5 步骤 2–6 那四条约定（带分母、三档退出码、末列取值、反例同码）
  与工具链无关，可直接搬。

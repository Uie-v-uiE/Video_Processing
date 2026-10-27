# 三态 token × 退出码 × 分母 对照表（上一级是 `SKILL.md`）

核对日期 2026-10-04；来源类型统一为"代码"（本次逐行打开过的脚本）。
表里所有字符串都是脚本里**会原样打印**的文本（不翻译、不改写），`grep -a` 可以按它们匹配。
**本表不是判据**：要证明某项通过，靠实测输出或 `evals/` 记录。

## 目录

- T1 聚合门禁与收尾结论
- T2 单台架/解析类
- T3 板级
- T4 尺子健康度与反例（"跑同一份代码"那一族）
- T5 实验轮次的判定词（ADOPT/DECLINE/NOT_MEASURED/MECHANISM_INERT）
- T6 末列取值的三种真实写法
- T7 分母写法清单（哪些结论行自带 N）

## T1 聚合门禁与收尾结论

| 脚本 | token（原样） | 退出码 | 含义 | 出处行 | 来源类型 | 核对日期 |
|---|---|---|---|---|---|---|
| `build/gates.sh` | `GATES: 有红项（判定 $NSAY 项）—— 不采纳，保留上一版` | 1 | 有红 | `build/gates.sh:582` | 代码 | 2026-10-04 |
| `build/gates.sh` | `GATES: PARTIAL —— 判定 $NSAY 项全过，但有 $NNA 项因缺凭据未判（见上面 n/a 行），这一版不作"过门禁"` | 1 | 全过但有未判 | `build/gates.sh:584` | 代码 | 2026-10-04 |
| `build/gates.sh` | `GATES: ALL PASS（$NSAY 项全部判定）` | 0 | 全过且无未判 | `build/gates.sh:586` | 代码 | 2026-10-04 |
| `build/gates.sh` | `  n/a  <说明>`（由 `naa()` 打印，同时 `NNA+1`） | 不改退出码 | 该项今天没判 | `build/gates.sh:180-183` | 代码 | 2026-10-04 |
| `build/gates.sh` | `FATAL 缺报告：$f` | 2 | 输入件缺席 | `build/gates.sh:32` | 代码 | 2026-10-04 |
| `build/gates.sh` | `FATAL 解析不到 $v —— 报告格式变了？不要拿空值当 0 判绿` | 2 | 尺子读不到 | `build/gates.sh:164` | 代码 | 2026-10-04 |
| `build/gates.sh` | `FATAL 读不到 timing summary 的那一行数字。报告里最像的三行是：` | 2 | 同上（带候选行） | `build/gates.sh:72-74` | 代码 | 2026-10-04 |
| `build/gates.sh` | `        FATAL … 有行不是『配对 端点数 unsafe』三列 ⇒ 这一项不敢判绿` | — | 基线坏了 → 该项判红 | `build/gates.sh:110` | 代码 | 2026-10-04 |
| `build/gates.sh` | `        WARN 没有 … —— CDC 这项退化成"只把数字摆出来"，不比等于没门禁` | — | 无基线 → 判红 | `build/gates.sh:129` | 代码 | 2026-10-04 |
| `build/gates.sh` | `NOLOG` / `无凭据=未验` | 计入红 | 凭据缺失（不是空值 0） | `build/gates.sh:212`、`:232` | 代码 | 2026-10-04 |

## T2 单台架/解析类

| 脚本 | token（原样） | 退出码 | 含义 | 出处行 | 来源类型 | 核对日期 |
|---|---|---|---|---|---|---|
| `sim/run_one.sh --verdict` | `VERDICT <tb>: RESULT <tb> …  || FAIL 行数=N || PASS 行数=M` | 0 | 判绿且无 FAIL 行 | `sim/run_one.sh:39-44` | 代码 | 2026-10-04 |
| `sim/run_one.sh --verdict` | 同上，判定串里含 `FAIL` | 3 | 判红（结论） | `sim/run_one.sh:42-43` | 代码 | 2026-10-04 |
| `sim/run_one.sh --verdict` | `VERDICT <tb>: NO-VERDICT-LINE（这支台架一条判定都没打，去数判据条数） \|\| FAIL 行数=0 \|\| PASS 行数=M` | 4 | 认不出判定（不是"过了"） | `sim/run_one.sh:36-37` | 代码 | 2026-10-04 |
| `sim/run_one.sh --verdict` | `CE-FATAL 读不到 <LOG>` | 2 | 输入日志不存在 | `sim/run_one.sh:16` | 代码 | 2026-10-04 |
| `sim/run_one.sh` | `REFUSE: 找不到 xvlog（当前 …）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（report/BUILD.md）` | 2 | 前置条件不满足 | `sim/run_one.sh:47` | 代码 | 2026-10-04 |
| `sim/run_one.sh` | `REFUSE: 已经有 xsim 在跑（它会把行写进同一份 run.log）。先看是谁的：…` | 3 | 并发写者挡住（不是设计红） | `sim/run_one.sh:58-60` | 代码 | 2026-10-04 |
| `sim/run_one.sh` | `XVLOG FAILED` / `XELAB FAILED` | 1 | 编译/例化失败 | `sim/run_one.sh:97`、`:100` | 代码 | 2026-10-04 |
| 台架侧收尾词 | `RESULT <tb> PASS` / `RESULT <tb> FAIL …` / `TB RESULT PASS\|FAIL` / `PASS <tb> ALL` | — | 被 `--verdict` 认的四种形状 | `sim/run_one.sh:17-31` | 代码 | 2026-10-04 |

## T3 板级

| 脚本 | token（原样） | 退出码 | 含义 | 出处行 | 来源类型 | 核对日期 |
|---|---|---|---|---|---|---|
| `build/board_verify.sh` | `RESULT board_verify PASS（判红的步骤：0）` | 0 | 机器那一半全绿 | `build/board_verify.sh:263` | 代码 | 2026-10-04 |
| `build/board_verify.sh` | `RESULT board_verify FAIL nred=$NRED ⇒ 这一版不能采纳` | 1 | 有红步骤 | `build/board_verify.sh:265` | 代码 | 2026-10-04 |
| `build/board_verify.sh` | `REFUSE: 找不到 xsdb（当前 $VP_XSDB）。设 VP_XSDB=<Vitis>/bin/xsdb.bat 再跑（report/BUILD.md）` | 2 | 前置条件不满足 | `build/board_verify.sh:114` | 代码 | 2026-10-04 |
| 子判据 | `RESULT PASS geom_check（ok=8 fail=0）` / `RESULT PASS uart_cmd_check（105 条命令, 97.7 s）` | — | 被 `grep -a "RESULT PASS …"` 二次确认（命令 rc + stdout 两重） | `build/board_verify.sh:244`、`:252-256` | 代码 | 2026-10-04 |

## T4 尺子健康度与反例

| 脚本 | token（原样） | 退出码 | 含义 | 出处行 | 来源类型 | 核对日期 |
|---|---|---|---|---|---|---|
| `build/ports_floor.sh` | `FLOOR OK instances=$PCI width_compared=$PCW（地板 $FLOOR_I/$FLOOR_W）` | 0 | 扫描面没塌 | `build/ports_floor.sh:24-25` | 代码 | 2026-10-04 |
| `build/ports_floor.sh` | `FLOOR BAD 汇总行里取不到 instances/width_compared（这一项什么都没查）：[…]` | 1 | 读不到总体 | `build/ports_floor.sh:15-18` | 代码 | 2026-10-04 |
| `build/ports_floor.sh` | `FLOOR BAD instances=… width_compared=… 低于地板 … ⇒ violations=0 可能是没看而不是没违规` | 1 | 射程塌了 | `build/ports_floor.sh:20-22` | 代码 | 2026-10-04 |
| `build/run_one_ce.sh` | `SELF PASS run_one --verdict（八条对照都按期望动）` | 0 | 解析器自己的八条对照成立 | `build/run_one_ce.sh:71` | 代码 | 2026-10-04 |
| `build/run_one_ce.sh` | `SELF FAIL run_one --verdict（$BAD 条不符）` | 1 | 尺子没牙 | `build/run_one_ce.sh:72` | 代码 | 2026-10-04 |
| `build/gates_cdc_test.sh` | T1 必须红 / T2 必须绿 / T3 必须红 / T4 必须红 / T5 必须红 | 0 仅当五个 case 全合期望 | 门禁第 6 项的判据 | `build/gates_cdc_test.sh:12-20`、`:65` | 代码 | 2026-10-04 |
| `src/host/line_cite_check.mjs` | `D5: CLEAN（退出码只由硬错决定；soft N 条是给人排队的候选…）` | 0（有硬错则非 0） | 硬错只四类：文件不在树里 / 行号越过文件末尾 / D5b 例化者列 / D5d 回声对不上 | `src/host/line_cite_check.mjs:21-22`、`:160-215` | 代码 | 2026-10-04 |
| `build/gates.sh` | 第 15 项判定前先跑 `bash build/run_one_ce.sh`，不过则 `WHY="$WHY判定解析器自己的对照不过(#166…)"` | — | 尺子健康度绑在被它支撑的那一项上 | `build/gates.sh:327-329` | 代码 | 2026-10-04 |

## T5 实验轮次的判定词

| 脚本 | token（原样） | 触发条件 | 出处行 | 来源类型 | 核对日期 |
|---|---|---|---|---|---|
| `build/r95_timing_round.sh` | `word()`：`0) echo ADOPT;; 2) echo NOT_MEASURED;; *) echo DECLINE;;` | 读不出报告 ≠ 否决 | `build/r95_timing_round.sh:113` | 代码 | 2026-10-04 |
| `build/r95_timing_round.sh` | `say "各滚结束：$WORDS（NOT_MEASURED=报告没读出来，不是否决）"` | 汇总说明 | `build/r95_timing_round.sh:121` | 代码 | 2026-10-04 |
| `build/r115_fanout_ab.sh` | `line F3_mechanism … "读数缺失=尺子断了" RED` | 读数缺失一律红 | `build/r115_fanout_ab.sh:85` | 代码 | 2026-10-04 |
| `build/r115_fanout_ab.sh` | `MECHANISM_INERT 不许写成没有收益`（`INFO` 档，不置 R=1） | 机制没动 ≠ 无收益 | `build/r115_fanout_ab.sh:41`、`:89` | 代码 | 2026-10-04 |
| `build/r117_chain.sh` | `不满足就是 MECHANISM_INERT（机制没动不许汇报成"没有收益"…）` | 预登记判据 | `build/r117_chain.sh:12` | 代码 | 2026-10-04 |
| `build/r90_phase2.sh` | `变异对照没红 ⇒ 这条判据没有牙（D 判不了东西）` | 变异对照即尺子的牙 | `build/r90_phase2.sh:52` | 代码 | 2026-10-04 |

## T6 末列取值的三种真实写法

| 写法 | 用在什么形状的行 | 出处 | 本次是否实跑 | 核对日期 |
|---|---|---|---|---|
| `awk 'NF{print $NF}'`（取最后一个非空字段） | 每行末列是判定词的输出 | `build/rim_gate_ce.sh:57` | 否，只直读 ⇒ `【待验证】` | 2026-10-04 |
| `awk '/^Critical/{print $2">"$3, $(NF-4), $(NF-2)}'`（从尾巴数，因 CDC Type token 数会变） | `report_cdc` 的行 | `build/gates.sh:100` | **是**，对 `build/cdc.rpt` 得 2 行 | 2026-10-04 |
| `awk -F'\t' '$NF=="RED" && $2!="presence"{n++} END{print n+0}'`（末列等值判定 + 空则 0） | 制表符名册差分 | `build/r115_c2_verdict.sh:79` | 否，只直读 ⇒ `【待验证】` | 2026-10-04 |
| `grep -a "nets with routing errors" … \| grep -oE '[0-9]+' \| tail -1`（最后一个纯数字） | `report_route_status` | `build/gates.sh:87-88` | **是**，得 `0` | 2026-10-04 |

## T7 分母写法清单

| 结论行 | 分母来自哪 | 出处 | 核对日期 |
|---|---|---|---|
| `GATES: ALL PASS（$NSAY 项全部判定）` | `say` 被调用的次数（不抄文档数字） | `build/gates.sh:177`、`:184` | 2026-10-04 |
| `门禁当前绿=$G 红=$GBAD（判定 $NSAY 项）…` | 绿+红相加 | `build/adopt_after_chain.sh:64-65` | 2026-10-04 |
| `D5 引用核对：扫 128 份交付文档 … 硬错 0 条 … soft 158 条` | 扫描集大小与命中数自报 | 本次实跑 `node src/host/line_cite_check.mjs` | 2026-10-04 |
| `FLOOR OK instances=… width_compared=…（地板 100/280）` | 总体数与地板并排 | `build/ports_floor.sh:13-14`、`:24` | 2026-10-04 |
| `八条对照都按期望动` | 反例条数自报 | `build/run_one_ce.sh:71` | 2026-10-04 |

⚠ 本表所有"N"都是脚本自己印出来的数；抄进文档就会漂。引用时点名那一次运行输出，而不是抄数字。

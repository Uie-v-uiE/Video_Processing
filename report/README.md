# `report/` 文档地图（先在这里挑，再进具体那一份）

> 这一页只管一件事：**22 份文档各自是什么、什么时候该读、哪些是"当前口径"哪些是"历史账本"**。
> 具体数字与技术内容不在这页上抄一遍——抄了就一定会出现"两处各说各话"（这一天真的发生过，
> 见 `ISSUES.md` #88 与 `PERF_REPORT.md` §3 开头那段）。

## 一、给人看的（评审、演示前自己再过一遍）

| 文件 | 是什么 | 注意 |
|---|---|---|
| `DEMO_SCRIPT.md` | **演示清单**：功能名单（名字/效果/第几幕/怎么展示/凭据）+ 九幕脚本（第 9 幕"拔卡"排在收尾 `stat` 之后，因为 `sd remount` 在同一次上电里救不回回放） | 命令是从这份文件的代码块里**抽出来上板验过**的（`src/host/demo_cmds.mjs`），不要手抄进别的文档 |
| `PERF_REPORT.md` | 全部**量化指标**（吞吐/时延/资源/时序/功耗） | 铁规矩：**数字成套地念**——念哪一版就念它自己那一份 `rNN_gates.txt` + `evidence_rNN/` |
| `ARCHITECTURE.md` / `MODULES.md` | 数据流与模块清单 | 与 RTL 同名的模块才在这两份里 |
| `PS_VS_PL.md` | 为什么控制面在 PS、数据面在 PL | 答辩常问 |
| `BACKGROUND_AND_NOVELTY.md` / `CONTEST_CHECKLIST.md` | 立项背景、新颖性、赛题对照（含**偏差清单**） | OSD 格式对不齐的地方，偏差清单那节是唯一出处 |
| `COMMANDS.md` + `../src/host/HOST_GUIDE.md` | 串口/上位机命令的**口径**（含 `pipe` 九位、`gamma auto` 的 γ×100 单位） | 与固件不一致就是缺陷，按 #67 那一族处理 |
| `BUILD.md` / `BOARD_PINS.md` / `../build/tcl/README.md` | 怎么构建、引脚、跑哪几条脚本 | 刷板是**三条**命令不是一条（见 `build/tcl/README.md` §2） |
| `AI_COLLABORATION.md` | 人机协作方式与提交物四要素 | 赛题 §3.3 要求的那一份 |
| `../board/HANDS_ON.md` | **亲手把每个功能过一遍**的清单：每条命令 + 串口该回什么 + 屏上该看到什么 + 看到的若是别的对应哪条已知问题 | 与 `DEMO_SCRIPT.md` 的分工：那份是"演给人看"的顺序，这份是"自己把功能用一遍"。命令逐字取自 `board/cmd_battery_v81.txt`（当前 elf 上 99/99 PASS）与 `COMMANDS.md` |

> **只有一小时读文档的话，按这个顺序读这四份就够**：`BACKGROUND_AND_NOVELTY.md`（做了什么、别人做过什么）
> → `ARCHITECTURE.md`（怎么分的）→ `PERF_REPORT.md`（数字，成套念）→ `CONTEST_CHECKLIST.md`（赛题逐条对照，
> 含**没做到的那一节**）。其余都是证据与日记：`ISSUES.md`/`OVERNIGHT_LOG.md` 是过程账，`MODULES.md` 是查表，
> 不需要顺序读。这一句是 2026-09-27 加的，因为"22 份文档"本身会被当成"没有主线"。

## 二、判据与凭据在什么地方（要复核任何一个数，先来这里）

- **门禁 20 项**：`bash build/gates.sh`（反例对照：`build/tb98_gate_ce.sh` 七条 + `build/rim_gate_ce.sh` 六条）→ 输出 `build/rNN_gates.txt`。
  ⚠ 别把 gates 的输出直接重定向进它自己要读的 `rNN_gates.txt`（`build/gates.sh` 头部第 9-16 行讲这件事）。
- **冻结一套**：`bash build/freeze_evidence.sh <NN>` → `build/evidence_rNN/`（含 `MANIFEST.md5` 三件套指纹）。
  认 md5 不认文件名；`evidence_r*/` 与 `frozen_r*/` **不是垃圾，不许清**。
- **台架**：`bash sim/run_one.sh <tb名>`（单条，编译前记 `top_md5`/`tb_md5`/`rtl_md5`）；
  `sim/run_sim.tcl` 是 L1 全量。`build/l1_rNN.txt` 是那一次的 console。
- **板级机器验收**：`bash build/board_verify.sh --battery --geom`（串口电池 97 条 + 几何最后一跳）。
- **静态判据**：`python build/check_ports.py`（接线/位宽）、`node src/host/{ps_hb_check,doc_enc_check,
  doc_currency_check,pipe_len_check,uart_cmd_check}.mjs`。每一个都带自己的反例/变异对照。

## 三、账本与日记（不要按顺序读，追因时才查）

| 文件 | 是什么 | 怎么查 |
|---|---|---|
| `ISSUES.md`（344 KB） | **缺陷账本**，编号 #NN 一条一节：症状/假设/量出来的数/为什么这样修/还欠什么 | 认准编号引用；"已修"那一行必须带着凭据文件名 |
| `OVERNIGHT_LOG.md`（433 KB） | **时间线**，§NN 一轮一节：那天晚上按时间发生了什么、决策的现场理由 | 想知道"为什么是现在这样"读它；想知道"现在是什么"读第一节 |
| `CHANGELOG_V6.md` / `CHANGELOG_V7.md` / `V6_ROOT_CAUSE.md` / `V6_BOARD_MEASUREMENT.md` | V6/V7 时代的历史 | 只作对照，不当现状 |
| `VERSION_LINEAGE.md` | rNN 谱系（每一版改了什么、门禁与冻结在不在） | 追某个数出自哪一版 |
| `OPTIMIZATION_LOG.md` | 时序/资源/功耗的优化实验账（含**没采纳**的那些） | §5 采纳规则、§8 不采纳的结论 |
| `PLAN_V8_SPEC.md` | V8/V9 的原始设计与位段表 | 位段以 `main.c` + `effect_ctrl.v` 为准 |
| `ETH_BRINGUP.md` / `ROTATION_AND_EFFECTS.md` | 两个专题的小账 | 各 2 KB |

## 四、明天要做"蜕变"时，可以先定的三刀（**未动手**，等具体口径）

先给体量一个数（2026-09-27 `wc -l report/*.md` 全树 **13719 行**）：
`OVERNIGHT_LOG.md` **5078** + `ISSUES.md` **3905** = **8983 行 = 65 %**，
而这两份按规矩**不重写**（它们是历史，改了就不是凭据了）。
⇒ **"冗长"这一半不是编辑问题，是结构问题**：真正的活文档只有约 4700 行 / 15 份，
其中被门禁当"活口径"扫的只有 **9 份**（`src/host/doc_currency_check.mjs` 里的 `SCOPE_DOCS`）。
所以刀要砍在"谁该被天天读"上，不是砍字数。

1. `ISSUES.md` 与 `OVERNIGHT_LOG.md` 各留"当前仍开着的 + 最近十轮"，更早的整段挪进
   `report/archive/`（编号 #NN/§NN **不许重编号**，否则历史引用全断）。
   **挪之前要知道的代价（已量）**：根目录两份首页里硬写着 `report/xxx.md` 链接
   **README.md 49 处 / README.en.md 37 处**（`grep -o "report/[A-Za-z0-9_]*\.md" | wc -l`），
   `doc_currency_check` 用固定清单不受影响、`doc_enc_check` 走 glob 也不受影响
   ⇒ 要改的就是那两份首页的链接与 D2 那一条。
   ⚠ 比赛 §3.3 要求提交物里有"协作记录"，挪进子目录可以，**挪出仓库不行**。
2. V6 那四份（`CHANGELOG_V6` + `CHANGELOG_V7` + 两份 `V6_*`）合成一份 `V6_HISTORY.md`
   ——它们只作对照，没人顺序读。（这四份实测 **251+733+329+178 = 1491 行 = 全树的 10.9 %**。）
3. 数字只留**一张表**（`PERF_REPORT.md`），其余文档一律改成指路而不是复制数字；
   `doc_currency_check.mjs`（门禁第 18 项）已经能抓住"把旧构建念成当前"，可以放心收。
   现在**同时提到板子版本/门禁项数**的活文档有 4 份（`ARCHITECTURE`/`DEMO_SCRIPT`/`PERF_REPORT`/`README`，
   另两份是日记）⇒ 这一刀最省事的做法是"版本与项数只许出现在 `PERF_REPORT` 与首页"，
   其余改成指路；今天 `CONTEST_CHECKLIST` 那个"17 项"就是这一刀没砍的代价（实物已经 21 项）。

4. **（第四刀，2026-09-27 05:5x 现成的审计结果）对外念的每个数，检查它引用的报告是不是当前那一版。**
   今晚已经抓到并改掉一处：`CONTEST_CHECKLIST` 的"BRAM 65.71 %"是 **r57** 的数（`frozen_r57_remap`），
   而 `H_ACTIVE` 512→1024 之后板上 r75 是 **97.5/140 = 69.64 %** —— 门禁第 18 项管不到资源行。
   还剩这些**待你判定**（同一条命令可复跑：`grep -rnoE "build/(frozen|evidence|failed)_r[0-9]+[a-z_]*/?[A-Za-z0-9_.]*" <活文档> | awk -F'_r' '$2+0<74'`）：
   `README.md:22` 与 `README.en.md:29`、`PERF_REPORT.md:207,223`、`PLAN_V8_SPEC.md:13,58,86`、
   `board/README.md:143`、`COMMANDS.md:4`、`CONTEST_CHECKLIST.md:50,56,59,65`。
   判定只有两种，且不能混：**① 它是"那一次测到的历史"** ⇒ 保留，但句子要写成"rNN 那天测得"；
   **② 它是"我们现在是"** ⇒ 必须换成当前冻结件（或重测）。第 18 项只能看句式，看不出这两种语义。

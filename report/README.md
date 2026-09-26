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

## 二、判据与凭据在什么地方（要复核任何一个数，先来这里）

- **门禁 19 项**：`bash build/gates.sh`（`--self` 反例：`build/tb98_gate_ce.sh`）→ 输出 `build/rNN_gates.txt`。
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

1. `ISSUES.md` 与 `OVERNIGHT_LOG.md` 各留"当前仍开着的 + 最近十轮"，更早的整段挪进
   `report/archive/`（编号 #NN/§NN **不许重编号**，否则历史引用全断）。
2. V6 那四份（两份 CHANGELOG + 两份 V6_*）合成一份 `V6_HISTORY.md`——它们只作对照，没人顺序读。
3. 数字只留**一张表**（`PERF_REPORT.md`），其余文档一律改成指路而不是复制数字；
   `doc_currency_check.mjs`（门禁第 18 项）已经能抓住"把旧构建念成当前"，可以放心收。

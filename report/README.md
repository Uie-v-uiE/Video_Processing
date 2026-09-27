# `report/` 文档地图

这一页只管一件事：**每份文档是什么、什么时候该读、哪些是"当前口径"哪些是"历史账本"**。
数字和技术内容不在这页抄一遍——抄了就一定会出现"两处各说各话"（这一天真的发生过，
见 `ISSUES.md` #88 与 `PERF_REPORT.md` 开头那段）。

## 一、给人看的

| 文件 | 是什么 | 注意 |
|---|---|---|
| `PROJECT_BRIEF.md` | 500 字以内的项目简介（做了什么、特点在哪） | 只念已实测的能力，数字不写进简介 |
| `BACKGROUND_AND_NOVELTY.md` | 立项背景、创新点、前人工作（含**明确不做的那几条**） | 每条创新后面跟着一个可自证的凭据；"前人"那一节是公开通报，不是综述 |
| `ARCHITECTURE.md` / `MODULES.md` | 数据流框图与模块清单 | 只写当前顶层真实例化的东西；**未被例化的 RTL 在 MODULES 里如实标注"仅台架"** |
| `PS_VS_PL.md` | 为什么控制面在 PS、数据面在 PL | 答辩常问 |
| `DEMO_SCRIPT.md` | 演示动线：每一步敲什么、看见什么算过 | 命令是被 `src/host/demo_cmds.mjs` 从这份文件的代码块里**抽出来上板验过**的，不要手抄进别处 |
| `../board/HANDS_ON.md` | 自己把每个功能过一遍的清单（每条一个四要素配方） | 与 `DEMO_SCRIPT` 的分工：那份是演给别人看的顺序，这份是自己逐个用一遍 |
| `PERF_REPORT.md` | 全部量化指标（吞吐/时延/资源/时序/功耗），**唯一一张数字表** | 铁规矩：念哪一版就念它自己那一份 `rNN_gates.txt` + `evidence_rNN/`，不要跨版拼数 |
| `OPTIMIZATION_LOG.md` | 时序/资源/功耗的优化实验账，含**没采纳**的那些 | 采纳/不采纳的判据各有一节 |
| `COMMANDS.md` + `../src/host/HOST_GUIDE.md` | 串口与上位机命令口径（九位 `pipe`、`Pipe:` 五位成对编码、γ×100 单位） | 与固件不一致就是缺陷，`uart_cmd_check.mjs` 会抓 |
| `BUILD.md` / `BOARD_PINS.md` / `../build/tcl/README.md` / `../sim/README.md` | 怎么构建、引脚、跑哪几条脚本、台架怎么跑 | 刷板是三条命令不是一条；构建入口只有一个 |
| `AI_COLLABORATION.md` | 人机协作记录：约束怎么给、模型怎么跑偏、用什么读数判掉 | 只写有出处的往来，不写台词 |
| `../skill/README.md` | 技能包索引（每一项四段：适用场景 / 使用方法 / 已验证效果（从哪次失败来）/ 失效条件） | 与本页分工：这里是项目文档，那里是**别人换题目也能用**的方法 |
| `CONTEST_CHECKLIST.md` | 提交物逐条对照（含"没做到的那一节"） | 里面的"门禁几项"这类数会漂，念之前先跑一遍 gates |

**只有一小时**：`PROJECT_BRIEF.md` → `BACKGROUND_AND_NOVELTY.md` → `ARCHITECTURE.md` →
`PERF_REPORT.md` → `CONTEST_CHECKLIST.md`。其余是证据与日记，按需查，不必顺序读。

## 二、判据与凭据在哪（要复核任何一个数，先来这里）

- **门禁**：`bash build/gates.sh` → 输出 `build/rNN_gates.txt`。反例对照 `build/tb98_gate_ce.sh`、
  `build/rim_gate_ce.sh`。⚠ 不要把 gates 的输出直接重定向进它自己要读的 `rNN_gates.txt`
  （`build/gates.sh` 头部讲的就是这件事）。
- **冻结一套**：`bash build/freeze_evidence.sh <NN>` → `build/evidence_rNN/`（含三件套指纹）。
  认 md5 不认文件名；`evidence_r*/` 与 `frozen_r*/` 不是垃圾，不许清。
- **台架**：`bash sim/run_one.sh <tb名>`（编译前盖 `top_md5`/`tb_md5`/`rtl_md5`），全量在 `sim/run_sim.tcl`。
  哪两个被门禁钉住、哪些测的是未例化的老 RTL：见 `../sim/README.md`。
- **板级机器验收**：`bash build/board_verify.sh --battery --geom`。
- **静态判据**：`python build/check_ports.py`、`node src/host/{ps_hb_check,doc_enc_check,
  doc_currency_check,pipe_len_check,uart_cmd_check}.mjs`——每个都带自己的反例/变异对照。
- **提交包**：`bash build/make_submission.sh` → 仓库外一份以 `git archive HEAD` 为唯一入口的导出，
  剪掉的东西与理由写在脚本里。

## 三、账本与日记（追因时才查，别当现状读）

| 文件 | 是什么 |
|---|---|
| `ISSUES.md` | 缺陷账本，`#NN` 一条一节：症状/假设/量出来的数/为什么这样修/还欠什么。**追加式，不重写** |
| `OVERNIGHT_LOG.md` | 时间线，`§NN` 一轮一节：那晚按时间发生了什么、决策的现场理由。同上 |
| `CHANGELOG_V6/V7.md`、`V6_ROOT_CAUSE.md`、`V6_BOARD_MEASUREMENT.md`、`VERSION_LINEAGE.md` | 版本史与谱系：想知道"这个数出自哪一版"来查；**不是现状** |
| `PLAN_V8_SPEC.md` | V8/V9 的原始设计与位段表（位段以 `main.c` + `effect_ctrl.v` 为准） |
| `ETH_BRINGUP.md`、`ROTATION_AND_EFFECTS.md` | 两个专题的小账 |

## 四、文档口径的两条规矩（为什么要这么分）

1. **版本、门禁项数、板子上是哪一版，只许出现在 `PERF_REPORT.md` 与仓库根首页。**
   其余文档一律指路，不复制数字——复制过一次，就会有两处各说各话（`doc_currency_check.mjs`
   只认句式，认不出"这句讲的是历史还是现状"）。
2. **历史句子必须写成"rNN 那天测得 X"**，现状句子必须能指到当前冻结件。
   同一条命令可以自查：
   `grep -rnoE "build/(frozen|evidence|failed)_r[0-9]+[a-z_]*/?[A-Za-z0-9_.]*" report/ board/ | awk -F'_r' '$2+0<74'`

（2026-09-28 02:0x 把上面第 2 条对全树跑了一遍，判定结果记在这里，省得明天重跑：
现存 sub-r75 的引用**全部属"那一次测到的历史"**——`frozen_r32_sdfix` 是 SD 热点与仲裁交接那两天的凭据、
`PLAN_V8_SPEC` 是原始设计、`OPTIMIZATION_LOG` 的 r62–r65 是实现策略 A/B 的账（含没采纳的）、
`board/README` 那条指 #50 的结案段 ⇒ **一个都不改**。唯一要留神的是念"交接多少毫秒"时：
`build/frozen_r54_readback/arb_handover_r54.json` 与 `build/frozen_r55_deadcdc/arb_handover_r55.json`
是**换过 bit 之后仍复现**的那两组，要念这两组，不是 r32 那一组。）


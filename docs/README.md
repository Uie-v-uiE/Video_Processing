# 文档地图

这个目录里只有三类东西，分法就是"谁在什么时候该读哪一份"：

| 位置 | 是什么 | 该不该读 |
|---|---|---|
| `docs/` | **交付物**：简介、背景与创新、架构与模块、软硬件划分、优化过程与前后对比、量化指标、命令表与上位机用法、构建与上板、演示脚本、人机协作记录、提交物对照 | 给评审读的就是这一层 |
| `docs/log/` | **工作记录**：缺陷账本 `ISSUES.md`、时间线 `OVERNIGHT_LOG.md`、版本谱系与两个专题小账 | 追因时才查；**按定义会过期**，别当现状读 |
| `docs/study/` | **学习型/资料型**：从零讲起的原理与工具（含 Tcl 入门） | 本地留存，不进 git、不进提交包 |

仓库根的 `README.md` 是项目总览与复现步骤；`skill/` 是提炼出来的方法包（换题目也能用的那一层）；
`board/` 留的是"跟那几条脚本在一起"的两份上板操作卡（`README.md` 与 `HANDS_ON.md`），搬走反而指不到东西。

本页只说每份文档是什么、什么时候读。**数字与技术内容不在这里抄一遍**——抄了就一定会出现
"两处各说各话"，这一天真的发生过（见 `log/ISSUES.md` #88 与 `PERF_REPORT.md` 开头那段）。

## 一、交付物

| 文件 | 是什么 | 注意 |
|---|---|---|
| `PROJECT_BRIEF.md` | 500 字以内的项目简介 | 只念已实测的能力，数字不写进简介 |
| `BACKGROUND_AND_NOVELTY.md` | 立项背景、创新点、前人做过什么（含**明确不做的那几条**） | 每条创新后面跟一个可自证的凭据 |
| `ARCHITECTURE.md` / `MODULES.md` | 数据流框图与模块清单 | 只写当前顶层真实例化的东西；未被例化的如实标注"仅台架" |
| `PS_VS_PL.md` | 为什么控制面在 PS、数据面在 PL | 软硬件划分的依据都在这份里 |
| `ROTATION_AND_EFFECTS.md` | 几何（旋转/缩放）与效果链的设计原理 | |
| `PERF_REPORT.md` | 全部量化指标（吞吐/时延/资源/时序/功耗），**唯一一张数字表** | 铁规矩：念哪一版就念它自己那一份 `rNN_gates.txt` + `evidence_rNN/`，不许跨版拼数 |
| `OPTIMIZATION_LOG.md` | 时序/资源/功耗的优化实验账，含**没采纳**的那些与前后对比 | 采纳与不采纳的判据各有一节 |
| `COMMANDS.md` | 串口命令口径（动词、参数、回声、拒收条件） | 与固件不一致就是缺陷，`uart_cmd_check.mjs` 会抓 |
| `COMMAND_PRECEDENCE.md` | 命令之间的**覆盖关系**：哪些组合会静默无效 | 被问"命令冲突"念这份 |
| `DEFAULTS.md` | 上电默认档是什么、为什么是这一套、怎么自己验（三条独立证据） | 被问"开机画面/默认状态"念这份；行号会漂，先重 grep |
| `HOST_GUIDE.md` | 上位机：推流、串口、判据工具各用什么 | 只有 Node 与 PowerShell，不需要 Python |
| `BUILD.md` / `BOARD_PINS.md` | 怎么构建、怎么刷板、引脚与极性 | 刷板是三条命令不是一条；构建入口只有一个 |
| `DEMO_SCRIPT.md` | 演示动线：每一步敲什么、看见什么算过 | 里面的命令由 `src/host/demo_cmds.mjs` 抽出来逐条上过板，别手抄进别处 |
| `AI_COLLABORATION.md` | 人机协作记录：约束怎么给、模型怎么跑偏、用什么读数判掉 | 只写有出处的往来，不写台词 |
| `../skill/README.md` | 技能包索引（每项四段：适用场景 / 使用方法 / 从哪次失败来 / 失效条件） | 与本页分工：这里是本项目，那里是**别人换题目也能用**的方法 |
| `../board/HANDS_ON.md` | 自己把每个功能过一遍的清单（每条一个四要素配方） | 与 `DEMO_SCRIPT` 的分工：那份是演给别人看的顺序 |

**只有一小时**：`PROJECT_BRIEF.md` → `BACKGROUND_AND_NOVELTY.md` → `ARCHITECTURE.md` →
`PERF_REPORT.md` → `../skill/README.md`。其余按需查，不必顺序读。

## 二、判据与凭据在哪（要复核任何一个数，先来这里）

- **门禁**：`bash build/gates.sh` → 输出 `build/rNN_gates.txt`。⚠ 不要把 gates 的输出直接重定向进
  它自己要读的 `rNN_gates.txt`（`build/gates.sh` 头部讲的就是这件事）。
- **冻结一套**：`bash build/freeze_evidence.sh <NN>` → `build/evidence_rNN/`（含三件套指纹）。
  认 md5 不认文件名；`evidence_r*/` 与 `frozen_r*/` 不是垃圾，不许清。
- **台架**：`bash sim/run_one.sh <tb名>`（编译前盖 `top_md5`/`tb_md5`/`rtl_md5`），全量在 `sim/run_sim.tcl`。
- **板级机器验收**：`bash build/board_verify.sh --battery --geom`。
- **静态判据**：`python build/check_ports.py`、`python build/trim_comments.py --check`、
  `node src/host/{ps_hb_check,doc_enc_check,doc_currency_check,pipe_len_check}.mjs`——
  每个都带自己的反例或变异对照，红的都是**文档或脚本**，不是板子。

## 三、工作记录（`docs/log/`，追因时才查）

| 文件 | 是什么 |
|---|---|
| `log/ISSUES.md` | 缺陷账本，`#NN` 一条一节：症状 / 假设 / 量出来的数 / 为什么这样修 / 还欠什么。**追加式，不重写** |
| `log/OVERNIGHT_LOG.md` | 时间线，`§NN` 一轮一节：那一轮按时间发生了什么、决策的现场理由。同上 |
| `log/CHANGELOG_V6.md`、`log/CHANGELOG_V7.md`、`log/VERSION_LINEAGE.md` | 版本史与谱系：想知道"这个数出自哪一版"来查；**不是现状** |
| `log/V6_ROOT_CAUSE.md`、`log/V6_BOARD_MEASUREMENT.md` | 第 6 版那两次根因分析与板级实测（今天的数字以 `PERF_REPORT.md` 为准） |
| `log/ETH_BRINGUP.md` | ETH 收包链的分步点亮记录（今天怎么跑见 `BUILD.md`） |
| `log/PLAN_V8_SPEC.md` | V8/V9 的原始设计与位段表（位段以 `src/ps/main.c` + `src/rtl/process/proc_pipeline.v` 为准） |
| `log/CONTEST_CHECKLIST.md` | 提交物逐条对照，含"没做到的那一节" |

## 四、文档口径的两条规矩

1. **版本号、门禁项数、板子上是哪一版，只许出现在 `PERF_REPORT.md` 与仓库根首页。**
   其余文档一律指路，不复制数字。
2. **历史句子必须写成"rNN 那天测得 X"**，现状句子必须能指到当前冻结件。
   这两条由 `src/host/doc_currency_check.mjs` 把关：D1 旧构建号不许念成"当前默认"、
   D2 点名的冻结目录必须盘上真有、D3 首页念的那一套必须是最新且全绿的那一套、
   D4 点名的文档路径必须存在且不许再指已经删掉的旧目录。

# `report/` —— 报告导航（赛题 §3.3.5.3 的七条，逐条钉到此刻真实存在的文件）

这一层是**交付文档**：说清楚这颗板子做了什么、为什么这样设计、怎么复现、跑出了什么数、哪里还不行。
本页只做两件事：① 把赛题 §3.3.5.3 点名的每一格指到**落点文件**；② 指不到的，写成**缺口 + 谁负责**。

口径（三条，先读）：

- **只指此刻在盘上的文件**。下面每一条在写之前都跑过 `test -e`（核对时刻 `2026-10-04 12:44`，最后一节给可重跑的命令）；
  **不引用"稍后会创建"的文件**——那正是 P21 的 C3 抓的死引用（本轮实跑 `12:29` = 64 条、`12:46/12:50` = 66 条，
  见 `90-open-items.md` 编号 6 与第 5 节）。
  这 66 里有 **2 条是本页故意点名的缺口**（第 1 节第 3 行的那个 P18a 契约件，与第 2 节最后一条那个 `data` 层的说明件）：
  写全路径 = 让这条洞继续被 C3 数着，装配收口时要么把文件补出来、要么把指路改成已存在的落点；
  写成裸文件名或"某份说明"就会从尺子上消失。这一条取舍与那两行的归属都登记在 `90-open-items.md` 编号 6。
- **七项的原文名单**取自本仓库里我已打开的那份核对件：`log/contest_checklist.md` §4.3
  「设计报告必答七项（§3.3.5.3），逐条钉落点」（第 106 行起）。
  该节 §4.5 又把"失败分析：哪些场景仍然做不好，原因是什么"（口径参照 §3.2.5.4）列为**必答项**
  ⇒ 所以本页在七行之外补一行"失败分析"，不是我自己加的。
- **文件号（10/20/30/40/50/60/70/90）是写作分工，不是赛题要求**。
  缺某个号不等于缺那一格的答案：例如"设计原理"这一格此刻由 `architecture.md` 承担，
  `20-principle.md` 只是尚未落地的**装配位**。缺号与缺内容分两列写，别混。

## 1. 赛题 §3.3.5.3 的七条 → 落点

| # | 指南要的那一格 | 此刻负责它的文件（都在盘上）| 仍缺的那一半（谁负责）|
|---|---|---|---|
| 1 | 选题背景与创新点（解决什么实际问题、**前人做过什么**）| `background_and_novelty.md`（同类题目的公开通报坐标系 + "这不是文献综述"的边界声明）| `10-background.md`、`prior-art-search.md`、`novelty-claims.md` **三份都不在盘上** ⇒ 归 **P19（进行中）**。硬条件：`report/questions-for-team.md:12,13` 的 Q-P19-1（真实出发点，只能队伍口述）与 Q-P19-2（主张强度定到哪一档）未答 ⇒ 无人值守下**禁止出现"首次/首创/领先/唯一"**（P23 §0）|
| 2 | 设计原理与功能框图 | `architecture.md`（文字版数据流框图 + 逐模块职责 + 延迟账本）、`modules.md`（端口/时序假设/例化关系）、`rotation_and_effects.md`（定点算术与窗口卷积）、`figures/fig-01-system-level.txt` + `figures/fig-02-module-level.txt` + `figures/legend.md`（两级框图的文本原件与图例）| 缺的是**能贴进 PPT 的位图/SVG**，不是缺框图；`20-principle.md` 这个装配位归 **P18a（待开）**。3.3.5.4 推荐结构里的"设计报告"整份由 `../report/02-architecture.md`、`../report/03-algorithm.md` 承担 |
| 3 | 软硬件划分依据与接口设计 | `ps_vs_pl.md`（划分原则与两处接口）、`architecture.md`、`../report/interface-table.md`（接口表）、`../src/host/ps/main.c`（PS 侧实物）、`commands.md` + `command_precedence.md` + `defaults.md`（命令/寄存器/默认档三条口径）| `30-partition-if.md` 装配位归 **P18a（待开）**；`report/claims-vs-evidence.md`（P18a 点名的"主张↔证据"对照件）**不在盘上**，同样归 P18a |
| 4 | 优化过程，含**优化前后的性能与资源对比表** | `40-optimization.md`（P18b 的分章版）、`optimization_log.md`（逐轮"基线 → 措施 → 实测" + 末尾「跨全期累计对照」）、`perf_report.md`（读数与版本对比，**表头声明"不要当当前值引用"**）、`comparison-notes.md`（对比表的读法与不可读成收益的那几条）、`timing_global.md`、`../data/metrics.csv` | 对比表本身齐；缺的是**指标表四处与现件不同源**（`metrics.csv` 第 14/15/25/27–28 行），逐条已核并登记在 `90-open-items.md` 第 2C 节（编号 17–20）⇒ 需要一次指标重算或一句"改哪一侧"的裁决 |
| 5 | 大模型协作记录（提示词、模型回答、**自我纠错轨迹**、智能体工作流设计）| `ai_collaboration.md`（约束怎么给、模型怎么跑偏）、`llm_collab.md`（四个案例 + §5 智能体工作流）、`collaboration/prompts-used.md`（用过的提示词原文）、`collaboration/corrections.md`（被证伪与更正的轨迹）、`collaboration/sessions/`（逐会话档案）| 原料是追加式日记 `log/issues.md`、`log/overnight_log.md`（**只作过程留痕，不当结论引用**）。缺的是"哪些交互可公开"的对外口径（P10 第 2 步第 1 问），需队伍点头 |
| 6 | 技能包的提炼过程（从哪些失败总结、**如何验证有效**、边界如何确定）| `../skills/README.md`（索引与逐条验证状态）、`../skills/_meta/sources.md`（每条断言的出处）、`../skills/_meta/naming-and-format.md`（外壳与命名规矩）、`../skills/evals/records/`（评测记录）、`../skills/pitfalls/`（未升格为通用技能的事故记录）、`llm_collab.md` §5| "如何验证有效"仍薄：本轮 C12 实跑 `绿=7 红=4 未测=1`，其中 G11 selftest 未落地、26 张平铺卡未迁移 ⇒ 归 **P04/P09/P11 队列**（`90-open-items.md` 编号 7）。B13 那条"基线 vs 用它之后"的效果对比需要会话预算（编号 128）|
| 7 | 复现说明：一份可供他人从零开始完整执行的操作步骤 | `70-reproduce.md`（环境自检 → 构建 → 仿真 → 上板 → 结果比对，逐命令带执行目录/shell/外部设备状态与"完成后应看到什么"）、`build.md`、`../build/README.md`、`../build/tcl/README.md`、`../sim/README.md`、`../board/README.md`、`../board/HANDS_ON.md（不随包）`、`../board/hardware_setup.md`、`../README.md` §5–§7（环境自检块与 A/B/C 三条路径）、`../report/repro-check.md`（演练读数）、`../submit/reproduce/`（包内那一版）| 两处仍欠：① `70-reproduce.md` §6 那 **5 条与既有文档的冲突**一条都没改（改的是别人的文件），逐条动作在 `90-open-items.md` 第 2D 节（编号 21–25）；② **第三方视角的一次干净复现演练**没做过 ⇒ 需要队伍批时间窗（只读自检八步不需要，构建与上板需要）|
| +1 | 失败分析：哪些场景仍然做不好，原因是什么（§3.2.5.4 口径，§4.5 列为必答）| `60-failure-analysis.md`（A 组"未解决"15 条 / B 组"未测试"16 条，每条四件：现象含证据 · 可判别的假设 · 判别方法 · 计划与成本；另含"未观察到失败"的取样依据一节）、`known_issues.md`（未修缺陷与"看着像问题其实是有意的"）、`../board/acceptance.md` 与 `../board/signoff.md`（逐格签收状态）| **本轮没有对这两份做任何审计**（见本页最后一节）；A/B 31 条的动作与成本已集中登记在 `90-open-items.md` 第 2F 节（编号 101–131）|
| +2 | 未决项集中管理（P18c 铁律 5，供 §3.3.5.5 的"文档质量"一格使用）| `90-open-items.md`（现算计数：md 口径 898 处 + 非 md 167 处 = **1065 处，七类逐类都有行认领**；漏项数 = 0 的成立时刻写在它第 1 节）| 它是一张**快照**：同伴轮次并发写入使数字只增（实测同一分钟内 879 → 898）⇒ P21 终审必须整表重跑（编号 10）。本轮写完它之后 `node build/checks/check_repo_consistency.mjs` 的 C8 行**从改前的 `FAIL` 变成 `PASS`**（`汇总表行=267`、`未认领的标记类=0`），其余红项与未测项一条没少 ⇒ 整把尺子仍是 `FAIL`，两趟原始读数贴在 `90-open-items.md` 第 5 节 |

## 2. 本目录与 §3.3.5.4 推荐结构的对照（**不在这里重抄那张表**）

§3.3.5.4 末句是"上表为推荐结构，非强制。采用其他组织方式的队伍须在 `README.md` 中给出目录对照说明"。
这条**已经在两处落了**，本目录是第三处、且只做 `report/` 内部这一层：

- **包的阅读路径对照（权威）**：`../report/README.md` 的「目录对照（推荐结构 → 本仓库位置）」一节
  （实读第 17–29 行，八行映射：项目简介/设计报告、工程本体、指标与读数、凭据、技能包、复现说明、
  协作与提炼、读懂工程本身）。**要看推荐结构 ↔ 本仓库的完整对应，看那份，别看这里。**
- **仓库总览对照**：`../README.md` §3「目录结构与赛题 §3.3.5.4 对照表」（含 3.3 条文依据、3.4 包里能直接跑的尺子）。
- **本目录（`report/`）内部的分层**：`10–90` 是"按写作任务分的装配位"，其余大写文件是"按主题分的原件"；
  两者关系即上面第 1 节的第 3–4 列——**每一格都有落点，部分格子的装配位号还没落盘**。
- 一处已知死指路（如实念）：`../report/README.md` 第 23 行把理由指到 `../../data/README.md`，
  **该文件此刻不存在**（`test -e data/README.md` = 无）⇒ 已登记在 `90-open-items.md` 编号 6/26，
  修法是把那行改指到已存在的 `../data/metrics.csv` 与 `../build/provenance.md`，不是"等它被创建"。

## 3. 索引（按"我想看什么"翻）

### 项目是什么

| 文档 | 回答的问题 |
|---|---|
| `../README.md` | 总体功能、特点、复现三步、仓库每个目录做什么（**先读这页**）；`../README_EN.md` 是英文版 |
| `background_and_novelty.md` | 为什么做"同帧逐像素对照"这种形态，以及与常见做法的差别在哪 |
| `architecture.md` | 数据通路与控制通路的分层：三路片源 → 跨时钟域缓冲 → 几何 → 效果链 → 对照合成 → OSD/HDMI |
| `modules.md` | 每个 RTL 模块的端口、时序假设、被谁例化 |
| `ps_vs_pl.md` | 同一件事为什么放在 PS 或 PL（划分原则与两处接口） |
| `rotation_and_effects.md` | 旋转与五级效果的算术（定点、象限折叠、窗口卷积） |
| `figures/` | 两级框图的文本原件（`fig-01-system-level.txt`、`fig-02-module-level.txt`）与图例 |

### 怎么复现

| 文档 | 回答的问题 |
|---|---|
| `70-reproduce.md` | 他人从零开始的逐命令步骤（含平台差异与"不可复现清单"）|
| `build.md` | 工具版本、环境变量、一条命令建工程出位流；失败时先看哪份日志 |
| `../build/README.md`、`../build/tcl/README.md` | `build/` 里每个脚本与报告是什么、报告怎么读、TCL 链怎么跑 |
| `../sim/README.md`、`../build/sim/names.md` | 台架与判据结果；台架新旧名字对照（仓库名 ↔ 包内名）|
| `../board/README.md`、`../board/HANDS_ON.md（不随包）`、`../board/hardware_setup.md` | 上板工程 / 运行脚本 / 实测输出三块；动手步骤；接线与供电 |
| `commands.md`、`command_precedence.md`、`defaults.md` | 串口/网络命令表与寄存器映射、命令优先级裁决、上电默认档 |
| `host_guide.md` | PC 侧上位机：推任意视频、双击跑自带演示（`../send_demo.bat`）、读回寄存器 |
| `board_pins.md` | 板级引脚、时钟来源与约束文件的对应关系 |

### 跑出了什么数

| 文档 | 回答的问题 |
|---|---|
| `50-results.md` | 结果与指标表（P18b 的分章版）|
| `perf_report.md` | 时序、资源、功耗、帧率与丢包的读数，每个数点名它出自哪份报告（**表头声明：走势表不要当当前值引用**）|
| `optimization_log.md`、`40-optimization.md`、`comparison-notes.md` | 优化过程与取舍：哪些刀落地了、哪些被证据否掉、为什么；对比表怎么读 |
| `timing_global.md` | 全局时序的逐轮账与"哪一格还没检查" |
| `../data/metrics.csv` | 唯一那张数字表（一行一个指标，带单位、判据与凭据路径）|
| `../build/`（`.rpt` **平铺**在这里，共 179 份）、`../build/evidence/` | Vivado 原文报告与被点名的逐轮凭据。`../build/reports/index.md` 只是**原件目录索引**，那里不放报告本身 |
| `io/`（本目录内）| HDMI 源端窗口与 TP1 量测两份专件（`io/hdmi_tp1_sdc_measurement.md`、`io/hdmi_cts_source_window.md`）|

### 哪里还不行、以及未决项

| 文档 | 回答的问题 |
|---|---|
| `60-failure-analysis.md` | 未解决（A 组）与未测试（B 组）分开列，每条四件齐全 |
| `known_issues.md` | 目前还没修的、以及"看着像问题其实是有意的"清单 |
| `90-open-items.md` | **所有未决项的集中表**：现算计数 + 每一类都有行认领 + 需要谁做什么 |
| `../board/acceptance.md`、`../board/signoff.md`、`../board/raw-vs-golden.md` | 逐格验收状态、需要人眼的签收、原图与金标的比对 |
| `demo_script.md`、`study/demo_plan.md` | 演示动线与讲稿，每一步该看到什么、看不到时先看哪一格 |

### 大模型协作与技能包

| 文档 | 回答的问题 |
|---|---|
| `ai_collaboration.md`、`llm_collab.md` | 协作过程与几个具体案例（含被证伪的判断）与工作流设计 |
| `collaboration/` | 用过的提示词原文（`prompts-used.md`）、更正轨迹（`corrections.md`）、逐会话档案（`sessions/`）|
| `../skills/`（索引 `../skills/README.md`）| 沉淀的技能卡（每张八节外壳）；出处登记在 `../skills/_meta/entry-map.md`（每条写明它长自哪一类观察；旧名 `sources.md` 在 2026-10-04 c7b325f 重建后**现不存在**），事故记录在 `../skills/pitfalls/` |
| `log/` | 追加式工作记录（问题账 `issues.md`、过夜流水 `overnight_log.md`、版本谱系 `version_lineage.md`、赛题核对表 `contest_checklist.md`）。**只作过程留痕，不当结论引用** |
| `study/` | 面向接手人的学习文档与英文海报占位。**本地留档，不随包**（见 `../.gitignore` 与 `../report/README.md` 最后一行）|

## 4. 只有十分钟

1. `../README.md` —— 项目做什么、特点、三步复现；
2. `../data/metrics.csv` —— 所有对外承诺的数字与其凭据（**同时读 `90-open-items.md` 第 2C 节**：四处与现件不同源已逐条标出）；
3. `perf_report.md` 的时序/资源两节 —— 优化到了什么程度；
4. `../board/README.md` 的"实测输出"表 + `../board/acceptance.md` —— 板子上真的跑起来了、哪几格还需要人；
5. `60-failure-analysis.md` 与 `90-open-items.md` —— 这两份列出哪里还不行、每一条欠什么。

## 5. 这一页的核对命令（谁都能重跑，别信我手打）

```bash
cd <仓库根>
# ① 本页点名的落点是否真在盘上（把上一节表里的路径逐个塞进这个循环）
for f in report/{10-background,20-principle,30-partition-if,40-optimization,50-results,\
60-failure-analysis,70-reproduce,90-open-items,README,ARCHITECTURE,MODULES,PS_VS_PL,\
BACKGROUND_AND_NOVELTY,BUILD,PERF_REPORT,OPTIMIZATION_LOG,KNOWN_ISSUES,TIMING_GLOBAL,\
comparison-notes,COMMANDS,COMMAND_PRECEDENCE,DEFAULTS,HOST_GUIDE,BOARD_PINS,DEMO_SCRIPT,\
AI_COLLABORATION,LLM_COLLAB}.md \
 report/interface-table.md report/repro-check.md \
 data/README.md data/metrics.csv build/reports/index.md build/sim/names.md \
 board/{README,HANDS_ON,hardware_setup,ACCEPTANCE,signoff,raw-vs-golden}.md \
 report/README.md skills/README.md skills/_meta/entry-map.md README.md README_EN.md; do
  test -e "$f" && echo "EXISTS $f" || echo "ABSENT $f"
done
# ② 未决项计数是否与本导航/90 一致（逐类现算，口径见 90-open-items.md 第 1 节）
for p in "【待验证】" "【未核实】" "【未实测】" "【队伍未确认】" "【待你补】" "NOT_MEASURED" "【填入】"; do
  echo "$p $(grep -rho --exclude=90-open-items.md -- "$p" report/ docs/ submit/ board/ skills/ README.md | wc -l)"
done
# ③ 那条尺子怎么说（只读；C3 管死引用、C8 管未决项认领）
node build/checks/check_repo_consistency.mjs
```

## 6. 本轮没做的事（为什么 + 需要什么）

本轮按队伍的收窄指令**只交两份**：`90-open-items.md` 与本页 `README.md`。其余如实列出：

1. **`60-failure-analysis.md`、`70-reproduce.md`：本轮没有撰写，也没有审计。**
   它们**此刻在盘上**（`test -e` 通过；60 = 538 行、70 = 210 行，A1–A15/B1–B16、§6 冲突表、§9 实跑摘要都在），
   是并发的那一轮 P18c 落的盘——任务描述里"四份交付物都没写"只对了一半：
   **真正缺的是 `90-open-items.md` 里能被 C8 认出的编号与收口段**（旧 90 存在但被截断，且用 `OI-161` 这种
   前缀行号，匹配不上 `check_repo_consistency.mjs:139` 的 `/^\|\s*\d+\s*\|/` ⇒ 改前实跑 `汇总表行=0`、判 **FAIL**）。
   我没有改那两份的一个字（禁区）。下一轮要做的三件审计动作与各自需要的条件，逐条写在
   `90-open-items.md` 第 6 节，简言之：铁律 1 的四件套抽查、`70` 第 9 节 37 条命令里 17 条 `NOT_MEASURED` 的
   "禁跑 / 缺料"分诊、以及 §6 那 5 条冲突的**修改授权**（改的是 `build.md`/`known_issues.md`/`build/README.md`/`board/README.md`/`src/host/metric_recheck.mjs`）。
2. **没有跑构建、仿真台架、上板与串口**（本轮禁区）⇒ 本页与 `90` 里所有"需要一次构建/上板"的行都停在
   `需批准 + 跑一条命令` / `需实测（仪器或板）`，**没有一条被写成"已验证"**。
3. **没有改 `docs/`、`submit/`、`board/acceptance.md`、根 `README.md`、`src/`–`data/`**（禁区）⇒
   本页第 1 节里指出的缺口（问题清单缺那一行、指标表四处不同源、五条文档冲突）都**如实保留**。
4. **没有 commit / push**（禁区）⇒ 这两份文件停在未跟踪状态。
   P23 第 6 节的运行台账 `RUN_REPORT.md`、`UNATTENDED.md` **此刻在仓库根不存在**（我 `test -e` 过），
   队列状态件 `report/run-queue.md` 与 `report/unattended.md` 是禁区且由同伴轮次维护 ⇒ 本轮的"做了什么"就写在
   本页第 6 节与 `90-open-items.md` 第 6/7 节，谁补进正式台账需要队伍定一句。

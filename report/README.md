# `report/` —— 报告导航（赛题 §3.3.5.3 的七条，逐条钉到此刻真实存在的文件）

这一层是**交付文档**：说清楚这颗板子做了什么、为什么这样设计、怎么复现、跑出了什么数、哪里还不行。
本页只做两件事：① 把赛题 §3.3.5.3 点名的每一格指到**落点文件**；② 指不到的，写成**缺口 + 谁负责**。

口径（三条，先读）：

- **只指此刻在盘上的文件**：下面每条落点写之前都跑过 `test -e`（核对时刻 `2026-10-04 12:44`，可重跑的命令在第 5 节）；不引用"稍后会创建"的文件——那正是终审尺子 C3 抓的死引用形态。缺口写成完整路径而不是裸文件名：C3 只认带目录前缀的串，抹成描述等于把洞藏起来。
- **七项的原文名单**取自已入库的核对件 `log/contest_checklist.md` §4.3「设计报告必答七项（§3.3.5.3），逐条钉落点」（第 106 行起）；同文件 §4.5（第 127 行起）又把"失败分析：哪些场景仍然做不好，原因是什么"（口径参照 §3.2.5.4）列为必答 ⇒ 表内在七行之外多一行。
- **文件号（10/20/30/40/50/60/70/90）是写作分工，不是赛题要求**：缺某个号不等于缺那一格的答案——"设计原理"这一格此刻由 `architecture.md` 承担，`20-principle.md` 只是尚未落地的**装配位**。缺号与缺内容分两列写，别混。

## 1. 赛题 §3.3.5.3 的七条 → 落点

| # | 指南要的那一格 | 此刻负责它的文件（都在盘上）| 仍缺的那一半（谁负责）|
|---|---|---|---|
| 1 | 选题背景与创新点（解决什么实际问题、**前人做过什么**）| `background_and_novelty.md`（同类题目的公开通报坐标系 + "这不是文献综述"的边界声明）| `10-background.md`、`prior-art-search.md`、`novelty-claims.md` **三份都不在盘上** ⇒ 归 **P19（进行中）**。硬条件：`report/questions-for-team.md:12,13` 的 Q-P19-1（真实出发点，只能队伍口述）与 Q-P19-2（主张强度定到哪一档）未答 ⇒ 无人值守下**禁止出现"首次/首创/领先/唯一"**（P23 §0）|
| 2 | 设计原理与功能框图 | `architecture.md`（文字版数据流框图 + 逐模块职责 + 延迟账本）、`modules.md`（端口/时序假设/例化关系）、`rotation_and_effects.md`（定点算术与窗口卷积）、`figures/fig-01-system-level.txt` + `figures/fig-02-module-level.txt` + `figures/legend.md`（两级框图的文本原件与图例）| 缺的是**能贴进 PPT 的位图/SVG**，不是缺框图；`20-principle.md` 这个装配位归 **P18a（待开）**。§3.3.5.4 推荐结构里的"设计报告"整份由 `02-architecture.md`、`03-algorithm.md` 承担 |
| 3 | 软硬件划分依据与接口设计 | `ps_vs_pl.md`（划分原则与两处接口）、`architecture.md`、`interface-table.md`（接口表）、`../src/host/ps/main.c`（PS 侧实物）、`commands.md` + `command_precedence.md` + `defaults.md`（命令/寄存器/默认档三条口径）| `30-partition-if.md` 装配位归 **P18a（待开）**；P18a 点名的"主张↔证据"对照件 `claims-vs-evidence.md` **此刻在盘上**（早前登记的"不在盘上"已不成立，收口时以本页第 5 节 ① 的现跑为准）|
| 4 | 优化过程，含**优化前后的性能与资源对比表** | `40-optimization.md`（P18b 的分章版）、`optimization_log.md`（逐轮"基线 → 措施 → 实测" + 末尾「跨全期累计对照」）、`perf_report.md`（读数与版本对比，**表头声明"不要当当前值引用"**）、`comparison-notes.md`（对比表的读法与不可读成收益的那几条）、`timing_global.md`、`../data/metrics.csv` | 对比表本身齐；缺的是**指标表四处与现件不同源**（`metrics.csv` 第 14/15/25/27–28 行），逐条已核并登记在 `90-open-items.md` 第 2C 节（编号 17–20）⇒ 需要一次指标重算或一句"改哪一侧"的裁决 |
| 5 | 大模型协作记录（提示词、模型回答、**自我纠错轨迹**、智能体工作流设计）| `ai_collaboration.md`（约束怎么给、模型怎么跑偏）、`llm_collab.md`（四个案例 + §5 智能体工作流）、`collaboration/prompts-used.md`（用过的提示词原文）、`collaboration/corrections.md`（被证伪与更正的轨迹）、`collaboration/sessions/`（逐会话档案）| 原料是追加式日记 `log/issues.md`、`log/overnight_log.md`（**只作过程留痕，不当结论引用**）。缺的是"哪些交互可公开"的对外口径（P10 第 2 步第 1 问），需队伍点头 |
| 6 | 技能包的提炼过程（从哪些失败总结、**如何验证有效**、边界如何确定）| `../skills/README.md`（总索引，由 `../skills/_meta/build-index.mjs` 从条目现算）、`../skills/_meta/distillation-process.md`（提炼过程：从哪些失败或观察、如何验证有效、边界如何确定）、`../skills/_meta/validation.md`（本包自测读数与复跑命令）、`../skills/_meta/check-skill-package.mjs` + `../skills/_meta/check-selftest.mjs`（机器判据与那把尺子自己的能红对照）、`../skills/_meta/entry-map.md`（条目地图：每条技能长自哪一类观察，也是"提炼过程"的证据；旧名 `_meta/sources.md` 在 c7b325f 重建后**现不存在**，entry-map.md 是它的落点）、`../skills/pitfalls/`（未升格为通用技能的事故记录）、`llm_collab.md` §5| 旧名 `skills/evals/records/` 与 `skills/scripts/check/gates.mjs` 在 c7b325f 重建后**现不存在**，评测记录的落点是 `_meta/validation.md`。仍欠的那一条是 B13"基线 vs 用它之后"的效果对比，需要会话预算 ⇒ `90-open-items.md` 第 2F 节（编号 128）；技能包门禁那条队列登记在同一文件编号 7，**该行的读数写于重建之前**，重跑以 `_meta/validation.md` 为准 |
| 7 | 复现说明：一份可供他人从零开始完整执行的操作步骤 | `70-reproduce.md`（环境自检 → 构建 → 仿真 → 上板 → 结果比对，逐命令带执行目录/shell/外部设备状态与"完成后应看到什么"）、`build.md`、`../build/README.md`、`../build/tcl/README.md`、`../sim/README.md`、`../board/README.md`、`../board/HANDS_ON.md（不随包）`、`../board/hardware_setup.md`、`../README.md` §2「复现步骤」（器件与工具版本、三条构建命令）、`repro-check.md`（演练读数）、`reproduce/README.md`（提交包那一版的复现说明）| 两处仍欠：① `70-reproduce.md` §6 那 **5 条与既有文档的冲突**一条都没改（改的是别人的文件），逐条动作在 `90-open-items.md` 第 2D 节（编号 21–25）；② **第三方视角的一次干净复现演练**没做过 ⇒ 需要队伍批时间窗（只读自检八步不需要，构建与上板需要）|
| +1 | 失败分析：哪些场景仍然做不好，原因是什么（§3.2.5.4 口径，§4.5 列为必答）| `60-failure-analysis.md`（A 组"未解决"15 条 / B 组"未测试"16 条，每条四件：现象含证据 · 可判别的假设 · 判别方法 · 计划与成本；另含"未观察到失败"的取样依据一节）、`known_issues.md`（未修缺陷与"看着像问题其实是有意的"）、`../board/acceptance.md` 与 `../board/signoff.md`（逐格签收状态）| **本轮没有对这两份做任何审计**（见本页第 6 节）；A/B 31 条的动作与成本已集中登记在 `90-open-items.md` 第 2F 节（编号 101–131）|
| +2 | 未决项集中管理（P18c 铁律 5，供 §3.3.5.5 的"文档质量"一格使用）| `90-open-items.md`（未决项的唯一汇总处：口径在第 0 节、现算命令与两个数字在第 1 节、与 C8 的改前/改后对账在第 5 节；本页第 5 节 ② 就是那套命令的缩略版）| 它是一张**快照**：同伴轮次并发写入使数字只增 ⇒ P21 终审必须整表重跑（编号 10）。第 5 节 ② 的命令扫的是 `report/`（含本页），所以本页不写死任何计数：复述进来的数字下一分钟就会与第 1 节对不上 |

## 2. 本目录与 §3.3.5.4 推荐结构的对照（**不在这里重抄那张表**）

§3.3.5.4 末句是"上表为推荐结构，非强制。采用其他组织方式的队伍须在 `README.md` 中给出目录对照说明"。那份对照说明的正文在 `submission-package.md`「目录对照（推荐结构 → 本仓库位置）」一节；本页早期版本把它指到本页自己的同名小节——那一小节**现不存在**，`submission-package.md` 是它的落点。**要看完整对应看那份，别看这里。**

- **本目录（`report/`）内部只有一层分工**：`10–90` 是"按写作任务分的装配位"，其余小写文件名是"按主题分的原件"；两者关系即第 1 节表里的第 3–4 列——**每一格都有落点，部分装配位号还没落盘**。

## 3. 索引（按"我想看什么"翻）

### 项目是什么

| 文档 | 回答的问题 |
|---|---|
| `../README.md` | 总体功能、特点、复现三步、仓库每个目录做什么（**先读这页**）；`../README_EN.md` 是英文版 |
| `01-overview.md` … `08-limits.md` | 八章分章版（导读、架构、算法、资源、时序、验证、技能提炼、限制），每章末尾点名它依据的文件 |
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
| `reproduce/README.md` | 提交包那一版的复现说明：四条命令从构建到上板，每条写明"跑完应看到什么" |
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
| `timing_global.md`、`timing/` | 全局时序的逐轮账与"哪一格还没检查"；逐时钟名册与逐轮台账 |
| `../data/metrics.csv` | 唯一那张数字表（一行一个指标，带单位、判据与凭据路径）；理由与取舍写在 `../data/README.md` |
| `../build/`（`.rpt` **平铺**在这里，共 179 份）、`../build/evidence/` | Vivado 原文报告与被点名的逐轮凭据。`../build/reports/index.md` 只是**原件目录索引**，那里不放报告本身 |
| `io/`（本目录内）| HDMI 源端窗口与 TP1 量测两份专件（`io/hdmi_tp1_sdc_measurement.md`、`io/hdmi_cts_source_window.md`）|

### 哪里还不行、以及未决项

| 文档 | 回答的问题 |
|---|---|
| `60-failure-analysis.md` | 未解决（A 组）与未测试（B 组）分开列，每条四件齐全 |
| `known_issues.md`、`known-limitations.md` | 目前还没修的、以及"看着像问题其实是有意的"清单；边界与限制的分章版 |
| `90-open-items.md` | **所有未决项的集中表**：现算计数 + 每一类都有行认领 + 需要谁做什么 |
| `../board/acceptance.md`、`../board/signoff.md`、`../board/raw-vs-golden.md` | 逐格验收状态、需要人眼的签收、原图与金标的比对 |
| `demo_script.md` | 演示动线与讲稿，每一步该看到什么、看不到时先看哪一格；`study/demo_plan.md` 是同一件事的本地版（`study/` 不随包）|

### 大模型协作与技能包

| 文档 | 回答的问题 |
|---|---|
| `ai_collaboration.md`、`llm_collab.md` | 协作过程与几个具体案例（含被证伪的判断）与工作流设计 |
| `collaboration/` | 用过的提示词原文（`prompts-used.md`）、更正轨迹（`corrections.md`）、逐会话档案（`sessions/`）|
| `../skills/`（索引 `../skills/README.md`）| 沉淀的技能条目（每条 `_meta/authoring-standard.md` 规定的五节外壳）；条目地图与出处在 `../skills/_meta/entry-map.md`（旧名 `_meta/sources.md` 在 c7b325f 重建后**现不存在**），提炼过程与验证读数在 `_meta/distillation-process.md` 与 `_meta/validation.md`，事故记录在 `../skills/pitfalls/` |
| `log/` | 追加式工作记录（问题账 `issues.md`、过夜流水 `overnight_log.md`、版本谱系 `version_lineage.md`、赛题核对表 `contest_checklist.md`）。**只作过程留痕，不当结论引用** |
| `study/` | 面向接手人的学习文档与英文海报稿。**本地留档，不随包**（排除规则写在 `../.gitignore` 第 107 行）|

## 4. 只有十分钟

1. `../README.md` —— 项目做什么、特点、三步复现；两级阅读路径的第一级（包级给"是什么 + 怎么跑"，本页给"哪一格落在哪个文件"）；
2. `../data/metrics.csv` —— 所有对外承诺的数字与其凭据（**同时读 `90-open-items.md` 第 2C 节**：四处与现件不同源已逐条标出）；
3. `perf_report.md` 的时序/资源两节 —— 优化到了什么程度；
4. `../board/README.md` 的"实测输出"表 + `../board/acceptance.md` —— 板子上真的跑起来了、哪几格还需要人；
5. `60-failure-analysis.md` 与 `90-open-items.md` —— 这两份列出哪里还不行、每一条欠什么。

## 5. 这一页的核对命令（谁都能重跑，只读）

```bash
cd <仓库根>
# ① 本页点名的落点是否真在盘上（路径就是第 3 节表里那些；还欠的装配位见第 1 节第 1–3 行的第 4 列）
for f in report/{README,background_and_novelty,architecture,modules,ps_vs_pl,rotation_and_effects,\
40-optimization,50-results,60-failure-analysis,70-reproduce,90-open-items,optimization_log,perf_report,\
comparison-notes,timing_global,known_issues,known-limitations,build,commands,command_precedence,defaults,\
host_guide,board_pins,demo_script,ai_collaboration,llm_collab,interface-table,repro-check,claims-vs-evidence,\
submission-package,questions-for-team}.md \
 report/0{1,2,3,4,5,6,7,8}-*.md \
 report/figures/{fig-01-system-level.txt,fig-02-module-level.txt,legend.md} \
 report/io/hdmi_tp1_sdc_measurement.md report/collaboration/{prompts-used,corrections}.md \
 report/log/{issues,overnight_log,version_lineage,contest_checklist}.md \
 data/metrics.csv data/README.md build/README.md build/tcl/README.md build/sim/names.md \
 build/provenance.md build/reports/index.md sim/README.md \
 board/{README,hardware_setup,acceptance,signoff,raw-vs-golden}.md \
 skills/README.md skills/_meta/{entry-map,validation,distillation-process}.md \
 skills/pitfalls README.md README_EN.md send_demo.bat; do
  test -e "$f" && echo "EXISTS $f" || echo "ABSENT $f"
done
# ② 未决项计数是否与本导航/90 一致（逐类现算；口径与分母只在 90-open-items.md 第 0–1 节定义，本页不复述数字）
for p in "【待验证】" "【未核实】" "【未实测】" "【队伍未确认】" "【待你补】" "NOT_MEASURED" "【填入】"; do
  echo "$p $(grep -rho --exclude=90-open-items.md -- "$p" report/ docs/ submit/ board/ skills/ README.md | wc -l)"
done
# ③ 那条尺子怎么说（只读；C3 管死引用、C8 管未决项认领）
node build/checks/check_repo_consistency.mjs
```

## 6. 本轮没做的事（为什么 + 需要什么）

收窄指令下本轮**只交两份**：`90-open-items.md` 与本页 `README.md`。其余如实列出：

1. **`60-failure-analysis.md`、`70-reproduce.md`：本轮没有撰写，也没有审计。** 两份**此刻在盘上**（第 5 节 ① 会逐个打印 `EXISTS`），是并发的那一轮 P18c 落的盘；本轮没改那两份的一个字（禁区）。下一轮的三件审计动作与各自需要的条件逐条写在 `90-open-items.md` 第 6 节：四件套抽查、`70` 第 9 节命令里 `NOT_MEASURED` 条目的"禁跑 / 缺料"分诊、以及 §6 那 5 条冲突的**修改授权**（改的是 `build.md`/`known_issues.md`/`../build/README.md`/`../board/README.md`/`../src/host/metric_recheck.mjs`）。
2. **没有跑构建、仿真台架、上板与串口**（禁区）⇒ 本页与 `90` 里所有"需要一次构建/上板"的行都停在 `需批准 + 跑一条命令` 或 `需实测（仪器或板）`，**没有一条被写成"已验证"**。
3. **没有改 `docs/`、`submit/`、`board/acceptance.md`、根 `README.md`、`src/`–`data/`**（禁区）⇒ 第 1 节点出的缺口（问题清单缺那一行、指标表四处不同源、五条文档冲突）都**如实保留**。
4. **早期版本里此刻不成立的指路与状态句已删，而不是改指到别处**：那条把 §3.3.5.4 对照表指到根 README 的某节（根 README 只有 §1/§2 两节）、那条把包内复现说明指到未跟踪的包目录、以及"`data/README.md` 此刻不存在"与"`claims-vs-evidence.md` 不在盘上"两句——这两份**现在都在盘上**，第 1 节第 3 行已按现状写。
5. **运行台账**：P23 第 6 节的 `RUN_REPORT.md`、`UNATTENDED.md` **此刻在仓库根不存在**（`test -e` 过）；队列状态件 `run-queue.md`、`unattended.md` 由同伴轮次维护、本轮不动 ⇒ 本轮"做了什么"就写在第 6 节与 `90-open-items.md` 第 6/7 节，谁补进正式台账需要队伍定一句。

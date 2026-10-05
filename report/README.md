# `report/` —— 报告导航

这一层回答四件事：这颗板子做了什么、为什么这样搭、别人怎么从零复现、跑出了哪些数以及哪里还不行。
本页只做两件事：把交付要回答的每一格指到**盘上存在的文件**；指不到的，写成缺口并说明还欠什么。
与指南条目的逐条对照只在 `report/submission-checklist.md`，本页不重抄那份表。

三条读法约定：

- 本页点名的每个路径都先用 `test -e` 复算过；复算命令集中在第 5 节，任何人可重跑。
- `01` 至 `08` 是**分章版**（导读、架构、算法、资源、时序、验证、技能提炼、限制），
  小写文件名是**按主题的原件**。同一话题两处都有时，以主题原件为准，分章版当作导读。
- 缺口写成完整路径而不是裸文件名：一句"见某某报告"如果落不到文件，就等于没写。

## 1. 交付要回答的每一格 → 由哪份文件负责

下面八行的**行序就是赛题 §3.3.5.3 那七条的顺序**（每条已把条款号写在第一格），最后一格是本仓库自加的。
这样排的目的只有一个：拿官方条款当检查表的人，逐条都能指到盘上一份文件，不需要在目录里翻。

| 要回答什么 | 负责它的文件（都在盘上） | 仍然欠的部分 |
|---|---|---|
| §3.3.5.3 第 1 条·选题背景与创新点：解决什么实际问题、前人做过什么 | `background_and_novelty.md`（同类题目的公开通报坐标系，并声明它不是文献综述） | 真实的出发点与主张强度需要队伍自己定；对外不写"首次／首创／领先／唯一"，公开对照只到"同类做法存在、本项目形态不同"这一档 |
| §3.3.5.3 第 2 条·设计原理与功能框图 | `architecture.md`（文字版数据流框图＋逐模块职责＋延迟账本）、`modules.md`（端口／时序假设／例化关系）、`rotation_and_effects.md`（定点算术与窗口卷积）、`figures/fig-01-system-level.txt`＋`figures/fig-02-module-level.txt`＋`figures/legend.md` | 两级框图目前是文本原件，缺的是能直接贴进演示稿的位图或矢量图 |
| §3.3.5.3 第 3 条·软硬件划分依据与接口设计 | `ps_vs_pl.md`（划分原则与两处接口）、`interface-table.md`（机器可读的寄存器与地址表）、`commands.md`＋`command_precedence.md`＋`defaults.md`（命令表、命令优先级裁决、上电默认档）、`../src/ps/main.c`（PS 侧实物） | 主张与证据的对照在 `claims-vs-evidence.md`；接口表与人读版说明若有冲突，以机器可读表为准 |
| §3.3.5.3 第 4 条（也是 §3.3.4 第 1、2 条）·优化过程，含优化前后的性能与资源对比 | `40-optimization.md`、`optimization_log.md`（逐轮"基线 → 措施 → 实测"，末尾有跨全期累计对照）、`comparison-notes.md`（对比表怎么读、哪些差值不能算收益）、`perf_report.md`、`timing_global.md`、`../data/metrics.csv` | `data/metrics.csv` 有四行与现件不同源（第 14、15、25、27–28 行），逐条登记在 `90-open-items.md` 第 2C 节；要么重算指标，要么改文档一侧，需要一次裁决。`perf_report.md` 的表头声明了"走势表不要当当前值引用" |
| §3.3.5.2 与 §3.3.5.3 第 5 条·大模型协作记录：提示词、模型回答、自我纠错轨迹、智能体工作流 | `ai_collaboration.md`（约束怎么给、模型怎么跑偏）、`llm_collab.md`（四个案例与工作流设计）、`collaboration/prompts-used.md`（提示词原文）、`collaboration/corrections.md`（被证伪与更正的轨迹）、`collaboration/sessions/`（逐会话档案） | 追加式工作记录在 `log/issues.md` 与 `log/overnight_log.md`，只作过程留痕，不当结论引用；"哪些交互可以公开"还没有对外口径 |
| §3.3.5.2 与 §3.3.5.3 第 6 条·技能包的提炼过程：从哪些失败总结、如何验证有效、边界在哪 | `../skills/README.md`（总索引，由 `../skills/_meta/build-index.mjs` 现算）、`../skills/_meta/distillation-process.md`（提炼过程）、`../skills/_meta/validation.md`（本包自测读数与复跑命令）、`../skills/_meta/entry-map.md`（每条技能长自哪一类观察）、`../skills/_meta/check-skill-package.mjs`（形状判据） | 还欠一条"基线 vs 用它之后"的效果对比，登记在 `90-open-items.md` 第 2F 节 |
| §3.3.5.3 第 7 条（也是 §3.3.4 第 4 条）·复现说明：他人可从零执行的步骤 | `70-reproduce.md`（环境自检 → 构建 → 仿真 → 上板 → 结果比对，逐命令写明执行目录、shell、外部设备状态与完成后应看到什么）、`reproduce/README.md`（提交包那一版）、`build.md`、`../build/README.md`、`../build/tcl/README.md`、`../sim/README.md`、`../board/README.md`、`../board/HANDS_ON.md（不随包）`、`../board/hardware_setup.md`、`../README.md` 的复现小节、`repro-check.md`（演练读数） | 两处欠：`70-reproduce.md` 第 6 节点出的与其它文档冲突的五处尚未改（逐条动作在 `90-open-items.md` 第 2D 节）；还没有第三方视角的一次干净复现演练，构建与上板那半需要一段可用时间 |
| 失败分析（本仓库自加的一格，对应 §3.3.4 第 5 条"稳定性与可演示性"）：哪些场景仍然做不好、原因是什么 | `60-failure-analysis.md`（未解决与未测试分两组，每条四件：现象含证据、可判别的假设、判别方法、计划与成本）、`known_issues.md`（未修缺陷，以及"看着像问题其实是有意的"）、`known-limitations.md`、`../board/acceptance.md` 与 `../board/signoff.md`（逐格签收状态） | 未决项的集中登记在 `90-open-items.md`；那份表是快照，会随后续实测变动，以重跑第 5 节的命令为准 |

## 2. 与 §3.3.5.4 推荐结构的对照

那份对照说明的正文在 `submission-package.md` 的「目录对照（推荐结构 → 本仓库位置）」一节，本页不重抄。

## 3. 按"我想看什么"翻

### 项目是什么

| 文档 | 回答的问题 |
|---|---|
| `../README.md` | 总体功能、特点、三步复现、每个目录做什么（先读这页）；`../README_EN.md` 是英文版 |
| `01-overview.md` 至 `08-limits.md` | 八章分章版：导读、架构、算法、资源、时序、验证、技能提炼、限制；每章末尾点名它依据的文件 |
| `background_and_novelty.md` | 为什么做"同一帧逐像素对照"这种形态，与常见做法差在哪 |
| `architecture.md` | 数据通路与控制通路的分层：三路片源 → 跨时钟域缓冲 → 几何 → 效果链 → 对照合成 → OSD 与 HDMI |
| `modules.md` | 每个 RTL 模块的端口、时序假设、被谁例化 |
| `ps_vs_pl.md` | 同一件事为什么放在 PS 或放在 PL |
| `rotation_and_effects.md` | 旋转与各级效果的算术：定点、象限折叠、窗口卷积 |
| `figures/` | 两级框图的文本原件与图例 |

### 怎么复现

| 文档 | 回答的问题 |
|---|---|
| `70-reproduce.md` | 从零开始的逐命令步骤，含平台差异与"不可复现清单" |
| `reproduce/README.md` | 提交包那一版的复现说明：四条命令从构建到上板，每条写明跑完应看到什么 |
| `build.md` | 工具版本、环境变量、一条命令建工程出位流；失败时先看哪份日志 |
| `../build/README.md`、`../build/tcl/README.md` | `build/` 里每个脚本与报告是什么、报告怎么读、TCL 链怎么跑 |
| `../sim/README.md`、`../build/sim/names.md` | 台架与判据结果；台架的仓库名与包内名对照 |
| `../board/README.md`、`../board/HANDS_ON.md（不随包）`、`../board/hardware_setup.md` | 上板工程、运行脚本与实测输出；动手步骤；接线与供电 |
| `commands.md`、`command_precedence.md`、`defaults.md` | 串口与网络命令表、寄存器映射、命令优先级、上电默认档 |
| `host_guide.md` | PC 侧上位机：推任意视频、双击跑自带演示（`../send_demo.bat`）、读回寄存器 |
| `board_pins.md` | 板级引脚、时钟来源与约束文件的对应关系 |
| `acceptance-recipes.md` | 需要人眼判的验收项：每条给命令、前置条件，以及"看到什么算通过" |

### 跑出了什么数

| 文档 | 回答的问题 |
|---|---|
| `50-results.md` | 结果与指标表 |
| `perf_report.md` | 时序、资源、功耗、帧率与丢包的读数，每个数点名出处；表头声明走势不当作当前值引用 |
| `measurements.md`、`optimization_log.md`、`comparison-notes.md` | 优化过程与取舍：哪些改动落地、哪些被证据否掉、对比表怎么读 |
| `timing_global.md`、`timing/` | 逐时钟名册与逐轮账，含"哪一格还没被检查" |
| `bench_mutation.md` | 台架判据自身的能红对照（判据不只会绿，也能红） |
| `../data/metrics.csv` | 唯一那张数字表：一行一个指标，带单位、判据与凭据路径；取舍理由在 `../data/README.md` |
| `../build/` 下的 `.rpt` 原件、`../build/evidence/` | Vivado 原文报告与被点名的逐轮凭据；`../build/reports/index.md` 只是原件索引，报告不在那里 |
| `io/` | HDMI 源端窗口与 TP1 量测两份专件 |

### 哪里还不行

| 文档 | 回答的问题 |
|---|---|
| `60-failure-analysis.md` | 未解决与未测试分两组列出，每条四件齐全 |
| `known_issues.md`、`known-limitations.md`、`08-limits.md` | 还没修的、看着像问题其实是有意的、边界与限制 |
| `90-open-items.md` | 所有未决项的集中表：现算计数、每一类都有行认领、需要谁做什么 |
| `../board/acceptance.md`、`../board/signoff.md`、`../board/raw-vs-golden.md` | 逐格验收状态、需要人眼判的签收、原图与金标的比对 |
| `demo_script.md` | 演示动线与讲稿：每步该看到什么、看不到时先看哪一格；本地版在 `study/demo_plan.md（不随包）` |
| `final-gate.md`、`declarations.md` | 发布前检查项的读法，以及对外声明的口径边界 |

### 判断依据（只判断、不动手的那两件）

| 文档 | 它替谁把账算清楚 | 结论落在哪 |
|---|---|---|
| `timing/eth_rxc_partition_options.md` | 收侧那条 0.739 ns 的 `eth_rxc` 路：还想买到余量，四条候选各值多少 | 四条逐一给判定（A 前提为假、B 要一整轮、C 先量才能判、D 不买余量但不补就是失实）；第 6 节把 D1 那一轮的逐时钟名册差分记成 `result=RED`（窗本身管用、代价在别的域），并说明为什么"没量过"不等于"到极限" |
| `timing/eth_tx_decoupling_inventory.md` | 发侧要不要从 125 MHz 域里独立出来：这是唯一还可能买到余量的结构性改法 | 前置清单 **35 条** RX↔TX 信号级跨域、其中 **33 条完全没有同步器** ⇒ 判定"这是一整轮，不是半轮"，收益**未量**，立案与否交回给人 |

§3.3.4 第 4 条要的是"判断依据看得见"。这两件没有写 RTL、没有跑构建，它们的用处是让下一轮不重复试错；
读它们时注意：没量到的地方都明写着没量到（后一件的第 9 节是"读出来的 / 没量到的"自审清单，
前一件对每条候选的收益都写了"未量"或"先量才能判"），结论里没有把未量写成结果。

### 大模型协作与技能包

| 文档 | 回答的问题 |
|---|---|
| `ai_collaboration.md`、`llm_collab.md` | 协作过程、具体案例（含被证伪的判断）、智能体工作流设计 |
| `collaboration/` | 提示词原文、更正轨迹、逐会话档案 |
| `../skills/` | 通用做法条目（索引在 `../skills/README.md`）；条目地图在 `../skills/_meta/entry-map.md`，提炼过程与验证读数在 `_meta/distillation-process.md` 与 `_meta/validation.md`，未升格为通用技能的经验记录在 `../skills/pitfalls/` |
| `log/` | 追加式工作记录（问题账 `issues.md`、流水 `overnight_log.md`、版本谱系 `version_lineage.md`、赛题核对表 `contest_checklist.md`）；只作过程留痕，不当结论引用 |
| `study/` | 面向接手人的学习文档与英文海报稿；本地留档不随包（排除规则在 `../.gitignore`） |

## 4. 只有十分钟

1. `../README.md` —— 这个项目做什么、怎么跑起来。
2. `../data/metrics.csv` —— 所有对外承诺的数字与其凭据（同时看 `90-open-items.md` 第 2C 节：四处与现件不同源已逐条标出）。
3. `perf_report.md` 的时序与资源两节 —— 优化到了什么程度。
4. `../board/README.md` 的实测输出表加 `../board/acceptance.md` —— 板上确实跑起来了，哪几格还需要人。
5. `60-failure-analysis.md` 与 `90-open-items.md` —— 哪里还不行，每一条欠什么。

## 5. 本页的核对命令（只读，谁都能重跑）

```bash
cd <仓库根>
# ① 本页点名的落点是否真在盘上
for f in report/{README,background_and_novelty,architecture,modules,ps_vs_pl,rotation_and_effects,\
40-optimization,50-results,60-failure-analysis,70-reproduce,90-open-items,optimization_log,perf_report,\
comparison-notes,timing_global,known_issues,known-limitations,build,commands,command_precedence,defaults,\
host_guide,board_pins,demo_script,ai_collaboration,llm_collab,interface-table,repro-check,claims-vs-evidence,\
submission-package,questions-for-team,acceptance-recipes,bench_mutation,final-gate,declarations}.md \
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
# ② 未决项计数现算（口径与分母只在 90-open-items.md 第 0–1 节定义，本页不复述数字）
for p in "【待验证】" "【未核实】" "【未实测】" "NOT_MEASURED"; do
  echo "$p $(grep -rho --exclude=90-open-items.md -- "$p" report/ board/ skills/ README.md | wc -l)"
done
# ③ 交付一致性与死引用检查
node build/checks/check_repo_consistency.mjs
```

## 6. 这一层的缺口

- 框图目前是文本原件，没有可直接放进演示稿的图。
- 没有第三方视角的一次干净复现演练：只读自检那八步不需要板子，构建与上板那半需要在场时间与一块可断电重上的板。
- `data/metrics.csv` 的四行与它点名的现件读数不同源，尚未裁决改哪一侧。
- 涉及观感与手感的验收条目（画面稳定性、拔卡恢复、角度读数）没有机器可读的输入口，只能由看屏幕的人确认，检查脚本判不了；这些格子在 `../board/acceptance.md` 与 `../board/signoff.md` 里按"需要人判"标注，不写成已通过。

# 赛题 §3.3.4 / §3.3.5 逐条对照：有什么、缺什么、下一步做什么

对象：`Video_Processing` 仓库（`main` 分支 HEAD）+ 本目录里的学习档与判断件。
这份对照给出官方那五条"优化目标"与三类"提交内容"今天各自的证据在哪、缺口在哪、按什么顺序补最划算。

口径（三态，不许写"应该没问题"）：
- **PASS** = 盘上有件、命令实跑过、判定行可当场复核；
- **FAIL** = 有缺口，且缺什么写得出来；
- **NOT_MEASURED** = 读不到输入、或需要人眼/需要一次真构建/需要工具链，不能判。

每一行的"复核命令"都在仓库根执行。数字会随交付树漂，以命令现算为准，这份对照不做计数容器。

## 1. §3.3.4 优化目标（五条）

| 官方那条 | 今天的证据 | 状态 | 复核命令 | 还差什么 |
|---|---|---|---|---|
| 在目标器件上取得可测量的性能表现，并给出与基线的对比 | `data/metrics.csv`（28 行，每行点名证据件与测量方式）、`结果页`、`优化流水账` 的逐批对照表、`report/40-optimization.md` §5 | **PASS（但"基线"这一格是软的）** | `node src/host/metric_recheck.mjs`（现：判 117 个数 红 0） | 提交版与**哪一版**比、为什么那一版算基线，散在批记录里；应在 `report/40-optimization.md` 顶部立一张"基线版 ↔ 提交版"的单一对照表（动作 A2） |
| 合理使用片上资源，避免用大量片上资源去换有限收益 | `report/40-optimization.md` §5（点名"赛题 3.3.4 的考察点"）、`build/utilization.rpt` + `build/util_hier_probe.rpt` 逐实例分解、以及三笔**量过并否决**的账（校验和常数折叠、强制复制广播网、HDMI 源端窗） | **PASS（这条是本工程最强的一条）** | `bash build/timing_roster_diff.sh --self`；`node build/deliver_spec_check.mjs`（C2/C6 层） | 否决类的证据现在散在 `开发流水账` 与台账里；把它们压成 §5 的一张"收益／代价／判定"三列表（动作 A2） |
| 保证工程可由他人从零复现 | `report/70-reproduce.md`（A/B/C 三条路径）、`report/repro-check.md` 的逐行判定、`build/tcl/*.tcl` + `build/sim/run_one.sh` + `node build/ps_app.mjs` | **PASS（未测 12 行是环境边界，不是没写）** | `node build/checks/check_repo_consistency.mjs \| grep '^C9 '` | 现跑（笔 `4dcefdd`）：判定列在内 61 行 = PASS 49 / FAIL 0 / **未测 12** / 判定列不成词 **0**。未测那 12 行里 10 行要一次真构建 + 真板（合理挂着），第 11 行 `C3c` 要换 ELF 对照，第 12 行是第三轮 `C4`：两跑健康计数的原件已被记录在案的精简笔删掉、包内指不到件，只能转述 ⇒ 不能算判定 |
| 将设计过程中的判断依据写进报告，而不只是呈现结果 | `report/60-failure-analysis.md`、`声明与凭据对照`、`问题清单`、`未决项集中表`、`时序债务账`，加上两份"只判断不动手"的：`域划分候选评估`、`发侧跨域清单` | **PASS** | `node src/host/doc_currency_check.mjs`（CURRENCY 干净）；`node src/host/line_cite_check.mjs`（D5 硬错 0） | 判断类件的名字对评委不显眼：应在 `report/README.md` 的阅读路径里给它们一格（动作 A4） |
| 将与大模型协作中获得的经验提炼为他人可复用的技能包 | `skills/`（49 条目 / 10 类 + `skills/README.md` 生成索引 + `skills/_meta/` 自检），`report/07-skill-distillation.md` 写"从哪些失败里总结、怎么验证有效、边界在哪" | **PASS** | `node skills/_meta/check-skill-package.mjs skills`（必须带参数）；`node build/checks/check_repo_consistency.mjs \| grep -E '^C(6\|12) '` | 见 §3.2 的加分项：技能包今天没标"是否绑定本题"，评委会难判断可复用性（动作 A3） |

## 2. §3.3.5.1 工程包（五条）

| 官方那条 | 位置 | 状态 | 备注 |
|---|---|---|---|
| 完整工程文件与源码（RTL、PS 侧软件等） | `src/rtl/`（80 个 `.v`）、`src/ps/`、`src/constraints/`、BD/XDC | **PASS** | PS 侧 ELF **可用一条命令重建**（`PS_CC=… PS_BSP=… node build/ps_app.mjs`，实测记录 `build/evidence/1005_ps_app_rebuild.txt`）；重建那颗与板上那颗 md5 不同，所以"重建成功"不等于"可互换" |
| 仿真或验证结果，说明功能正确性如何确认 | `sim/` 台架 + `build/sim/run_one.sh` + 判定件 `build/tb_v98_report.txt`、`build/evidence/`；口径在 `report/06-validation.md` 与 `台架变异对照` | **PASS** | 台架的"改前必须红"有入口，判定行末列即结论；`report/14` 那类形状（判红不许 `exit 0`）已被尺子盯住 |
| 综合与实现报告（资源占用、时钟频率、关键性能指标） | `build/utilization.rpt`、`build/timing_summary.rpt`、`build/clock_util.rpt`、`build/power.rpt`；逐实例 `build/util_hier_probe.rpt` | **PASS** | 本轮新加一条纪律：**资源归属句也要能核**（`metrics.csv` 那句"19 只 DSP 用在…与 gamma 计算"已被逐实例读数改口，台账 #389） |
| 上板工程、运行脚本、实测输出与参考结果的比对数据 | `board/`（上板工程 + 脚本 + 实测输出）、`data/inputs` + `data/golden` + `data/measured`、`验收配方` | **PASS（板侧人眼判据除外）** | 人眼那几条（E4/E5/E6 类）在 `问题清单` 与 `board/acceptance.md` 里明写"由谁在何时判"，不冒充机器结论 |
| 可复现的构建脚本 | `build/tcl/build_system_axigpio.tcl` 等 + `build/roll_isolated.sh`（隔离轮）+ `build/make_submission.sh` | **PASS** | 一条注意：**提交包目前是从 `ef68bb3` 那一次导出的**，合并今天的改动后要重导（动作 A5，>25 min） |

## 3. §3.3.5.2 技能包（四类 + 通用 Skill 加分）

| 官方列的类型 | 现在的条目 | 状态 |
|---|---|---|
| 提示词工作流 | `skills/prompts/`（含"从算法描述推软硬件划分""从综合报告定位瓶颈"两类） | **PASS** |
| 案例模板 | `skills/templates/`（工程骨架、报告模板、门禁脚本模板） | **PASS** |
| 校验脚本 | `skills/scripts/`（`regmap_check`、时序名册差分、资源/时序检查、可复现性检查） | **PASS** |
| 踩坑清单 | `skills/pitfalls/`（结构化：触发条件 + 排查步骤 + 来源失败） | **PASS** |

**每条是否写明"适用场景 / 使用方法 / 已验证效果 / 失效条件"**：由 `skills/_meta/check-skill-package.mjs`
机检（现判 9 项 红 0），并在 `report/07-skill-distillation.md` 里给"从哪些失败里总结"。

**加分项这一格要说老实话**：官方给的是"通用 **PYNQ** Skill 单独加分（换题目、换板卡仍可用）"。
本工程**不使用 PYNQ 框架**（PS 侧是裸机 standalone + 自己的 host 脚本），所以：
- 不该做的事：把本题技能硬贴成"PYNQ 技能"骗加分——评分人一跑就穿。
- 该做的事（动作 A3）：给技能包每条目补一栏**"绑定程度"**（`本题专属` / `同族 FPGA 题目可复用` / `框架无关工具流程`），
  并在 `skills/README.md` 说明"本工程不用 PYNQ，因此不申报 PYNQ 专项加分；
  申报的是框架无关的那一批"（如"改前必须红的变异对照""逐时钟名册差分""判定行必须在末列"这三条）。
  这样这条加分从"含糊"变成"可核的取舍声明"。

## 4. §3.3.5.3 设计报告（七条）

先纠一件事：`提交清单` 第 9 行先前写"设计报告分章 **FAIL**：
`10-background`、`20-principle`、`30-partition-if`、`novelty-claims`、`prior-art-search` 五章未写"。
"未写"用错了——那五个名字是一版没采用的装配方案；官方这三格的内容一直在盘上，只是不在那五个文件名里。
这份对照第一版把清单的话照抄了过来，等于把一条命名债说成内容债，已按现算改口（下表右列是逐份开过看的）。

| 官方那条 | 内容真的在哪 | 状态 |
|---|---|---|
| 选题背景与创新点（为什么选它、解决什么实际问题、前人做过什么） | `背景与创新`（158 行：§1 要解决的问题、**§2 同类工程在做什么（公开可查的对照）**、§3 创新点＋每条要付的代价、§4 应用价值、§5 还欠什么、末尾出处） | **PASS** |
| 设计原理与功能框图 | `架构章`（§1 数据从哪来/到哪去、§2 时钟与复位、§3 软硬件划分、§4 关键常数、§5 改哪里要看什么、§6 未覆盖范围）＋ `算法章`（效果链/缩放旋转/形态学/OSD/打包逐段）＋ `架构章` ＋ `report/figures/` | **PASS** |
| 软硬件划分依据与接口设计 | `软硬件划分`（§3"为何最终选 PL 网口"、§6"自写 FIFO vs IP"就是依据式写法）＋ `report/interface-table.md`（1509 行寄存器与位序）＋ `report/host_guide.md` | **PASS** |
| 优化过程（含前后性能与资源对比表） | `report/40-optimization.md`（§5 明写"赛题 3.3.4 的考察点"）、`优化流水账`、`data/metrics.csv` | **PASS（但"基线是哪一版"分散在批记录里** ⇒ 动作 A2） |
| 大模型协作记录（提示词、模型回答、自我纠错轨迹、智能体工作流设计） | `report/collaboration/`（登记卡＋纠错轨迹＋提示词分栏＋成本统计＋脱敏台账）、`report/ai_collaboration.md`、`大模型协作记录` | **PASS** |
| 技能包的提炼过程（从哪些失败总结、如何验证有效、边界如何确定） | `report/07-skill-distillation.md` ＋ `skills/_meta/validation.md` ＋ 每条目 SKILL 里的"来源失败/失效条件"段 | **PASS** |
| 复现说明（可供他人从零开始完整执行的操作步骤） | `report/70-reproduce.md` ＋ `复现步骤` ＋ `report/repro-check.md` | **FAIL（这条才是真缺口）**：C9 现跑 61 行判定 = PASS 36 / FAIL 0 / **未测 11 / 判定列不成词 14** |

§3.3.5.3 的缺口只有一处、且分两半：未测那 11 行要一次真构建＋真板（合理的债，明写着）；
不成词那 14 行是这份对照的表没把判定列填完——不补，C9 这项机检就会一直"看着过了其实没写"（动作 A1）。

**结论**：官方 §3.3.5.3 的七条里，六条内容都在盘上（前两格先前被 `提交清单`
第 9 行写成"五章未写"——那是一版没采用的装配文件名造成的假缺口：背景/创新点/同类对照在
`背景与创新`，原理与框图在 `架构章`＋`算法章`＋`report/figures/`，
划分依据与接口在 `软硬件划分`＋`report/interface-table.md`；清单那一格已按现算改口）。
唯一的内容级缺口是最后一条：复现说明的判定列有 14 行没写完、11 行未测（未测那 11 行要一次真构建＋真板，
是合理的债；不成词那 14 行是这份对照的表没填完，是动作 A1）。

## 5. §3.3.5.4 推荐结构与命名（非强制，但机检在管）

- 命名（纯小写 ASCII）：`build/checks/check_repo_consistency.mjs` 的 **C4 现判 违规=0**
  （跟踪文件 1161、点名豁免 70 条：`LICENSE` 1、`README.md` 19、`README_EN.md` 1、`SKILL.md` 49）。
  先前那份清单里"违规 286"那一格是旧读数，已随改名波清掉。
- 目录结构：`提交包说明` 给的是"采用其他组织方式 + 理由"，
  导出器 `build/make_submission.sh` 产出的就是推荐形状；
  `build/deliver_spec_check.mjs` 判 18 项（现 红 0 未测 0），其中 C0-4 管目录集合、C3 管指路存活、
  C7 管风格红线（时间点叙事、轮次号、裸台账编号、黑话不进正文）。
- 学习文档（`docs/` 旧十章 + 本目录 `deep_course/` 深读版 16 章）**不入库、不随包**：
  仓库 `.gitignore` 与本目录 worktree 的 `.gitignore` 双侧钉住，防止 `git add -A` 把它们带回去。

## 6. 下一步（按"分高 × 成本低"排，每条都能单独验收）

| 编号 | 动作 | 为什么是它 | 验收方式 |
|---|---|---|---|
| **A0** | 在 `report/README.md` 里加一张**"官方 §3.3.5.3 七条 ↔ 现有章节"索引表**（每条给文件与节号，不重写内容） | 六条内容都在盘上，但按官方那一格的问法找不到入口——评委照条款找会以为缺；加索引比补写三章便宜得多，也诚实得多 | `report/README.md` 里出现七个可点开的路径；`doc_currency` 干净、C3 死引用 0 |
| **A1** | 把 `report/repro-check.md` 里 14 行"判定列不成词"补齐（已有读数的填 PASS/FAIL，真没跑的填 `未测` 并写缺哪件） | C9 是机检项，缺的是这份对照自己的表；纯文档机械活 | `check_repo_consistency.mjs \| grep '^C9 '`：不成词 = 0 **已达成（笔 `4dcefdd`）：现跑 `判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`。做法是把 §8.1 的判定列搬回末列、§9 那张第三轮表补判定列（件 `build/r124_repro_verdict_col.mjs`）；`C4` 那一格如实记 NOT_MEASURED（两跑健康计数的原件已被精简笔删掉、包内指不到件）** |
| **A2** | `report/40-optimization.md` 顶部立一张"基线版 ↔ 提交版"总表，并把三笔**量过并否决**（校验和常数折叠、强制复制、HDMI 窗）压成"收益／代价／判定"三列 | 直接对着 §3.3.4 第 1、2 条的措辞；否决类证据现在散在 timing 目录 | 表内每个数点名一份 `build/evidence/` 件；`metric_recheck` 红 0 |
| **A3** | `skills/README.md` 与每条 SKILL 的 frontmatter 加"绑定程度"一栏，并写明"本工程不用 PYNQ ⇒ 不申报 PYNQ 专项加分，申报框架无关那批" | 把一条含糊的加分变成可核的取舍声明，成本极低 | `check-skill-package.mjs skills` 仍全绿；新增栏位由该尺子一起数 |
| **A4** | `report/README.md` 的阅读路径里给两份"判断件"（`timing/eth_rxc_partition_options.md`、`timing/eth_tx_decoupling_inventory.md`）一格 | §3.3.4 第 4 条要的是"判断依据看得见"，现在得翻目录才找得到 | `doc_currency` 干净；首页指路 C3 死引用 0 |
| **A5** | 合并后重导提交包：`bash build/make_submission.sh`（>25 min），包才会绑到新 HEAD | 今天所有改动都还没进包 | 导出器自检：文件数、死链、残留 token 三项为 0；包内 `MANIFEST` 与 HEAD 一致 |
| **A7** | （做 A1 时挖出来的，已顺手做完）补终审 **C3 的射程洞**：路径正则的字符类缺 `/`、右边界不认反引号 ⇒ 三层路径与 `path` 写法**根本不进分母**，那条"死引用=0"是看不见不是没有 | §3.3.5.1 要"指路活"，一把读不到输入的尺子等于没有这条门；改对之后同一棵树从 628 条涨到 5244 条，抓到 13 条真缺口与四条假话（`board/firmware/`"在"、原理图裁图"在仓库内"、技能包"12 项全绿两跑一致"、`build/timing/` 那一层） | `check_repo_consistency.mjs \| grep '^C3 '`：`检查路径引用=5244 死引用=0 历史精简=140`；`--self` 判 28 项（含"嵌套会红／嵌套在盘上就不红"与"精简名单外照旧红"两对对照），转录 `build/evidence/1006_c3_scope_selftest.txt`；台账 #391 |
| **B** | 发侧独立 125 MHz 那一整轮（先读 `发侧跨域清单` 的 33 条无同步器边） | 唯一还可能买到 `eth_rxc` 余量的结构性改法；**要动 RTL、跑台架与构建、再上板复验，需要立案** | 名册差分八对全配 + 门禁 24 项 + `board_verify` 全过才写"板上已验" |

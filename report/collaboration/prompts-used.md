# `prompts-used.md` · 提示词的"当时原文"与"事后模板"分栏对照（P22 铁律 3）

铁律 3 说的造假形态是**混标**：把事后提炼的模板当成"当时用的提示词"，或反过来。
所以本文件先把四类物件**分栏登记**，再给对应关系，最后给一条"混用条目数 = 0"的机检。

**五类物件（互不混合）**

| 栏 | 是什么 | 在哪儿 | 成文/使用时段 |
| --- | --- | --- | --- |
| **A** | 当时用的提示词原文（**人手打的**） | S01 的 226 条人工输入 `H01…H226` | 2026-09-21 22:34 → 2026-10-04 07:51（北京时间） |
| **B** | 当时用的提示词原文（**主 agent 派发给子 agent 的**） | 128 次派发正文；落盘在 S05 的 127 份导出里，每份恰好 1 条 `humanInput` | 2026-09-21 22:36 → 2026-10-04 11:43 |
| **C** | 当时用的提示词原文（**成文的轮次提示词文件**） | `<文档工作区>/2026-10-03/6c22b30a/timing-global-round-prompt.md`，21,433 字节，mtime 10-03 20:30，SHA-256 前 12 `a90fb0ec7cfc` | 写于 S04-c 窗口内，随后被贴进 S01 的 r116 链（本仓库点名处：`build/r116_batch_plan.md:5`） |
| **D** | 队伍任务提示词集 P00–P23（**事后成文**，不是当时用的原文） | `<文档工作区>/2026-10-04-3d601c82/skill_prompts/`，**31 个 `.md`**，合计 215,097 字节里的一部分；mtime 07:59:46 → 09:24:43 | 写于 S04-d 窗口内 |
| **E** | 事后提炼的提示词**模板**（技能包成品） | `skill/prompts/criterion-before-code`、`hw-sw-partition`、`report-to-bottleneck`、`single-variable-ab`（各一份 `SKILL.md`） | 10-04 由子会话写出（S05 表 `PROMPTFILE` 点名 `02-prompt-workflows.md` 的那一批） |

---

## A 栏 · 人手打的提示词原文（摘录 3 条，各 ≤10 行）

**指针形式**：`S01 / H<序号> / 北京时间 / 原始字符数`。原文只在本地导出里，
本文件按 P22 铁律 6 只给**摘录**，摘录来源登记在 `sessions/s01-2026-09-21-b20eed02.md`。
摘录里的本机绝对路径已按 `redaction.md` §2 的占位符替换（替换点逐条列在 §D 表末）。

### A1 = `H01`（2026-09-21 22:34:44，4,469 字符，126 行）——整支工程的开局提示词

```
 1| # 总目标（过夜无人值守 · 高自主）
 2| 你是本机 MiMoCode Agent，工作区 <父目录>。
 3| 对 Zynq7020 以太网视频处理工程做**长时间自主迭代**：优化什么、怎么做、用什么工具，均由你自行决定。
 4| 允许范围包括：功能/效果、时序、功耗、布局布线、资源、协议、文档、工具链、Skill/子代理，
 5| 以及**到 GitHub / Gitee 等代码托管与技术社区检索同类项目与资料**，用外部参考启发你判断该修什么、怎么修。
 6| 必须遵守：硬约束 + 验证分层 + 报告门禁 + 详细工程记录。
 7| 禁止空等用户指示。
 9| # 自主权总览
10| 你可自行决定：
11| - 主线主题与优先级（效果 / 时序 / 功耗 / P&R / 资源 / 协议 / 文档 / 工程化）
12| - 使用哪些 **Skill、插件、MCP、脚本、子代理** 及并行分工
```

- 与 D/E 栏的关系：**这句话里已经写了"过夜无人值守"**，但它不是 D 栏的 `23-unattended-run-protocol.md`
  （那份 10-04 09:24 才成文）。⇒ 无人值守协议是**事后把 already-practiced 的做法成文**，
  这个先后顺序必须在 `workflow.md` §2 写清，不能反过来写。
- 摘录自登记卡：`sessions/s01-2026-09-21-b20eed02.md` §1（首条记录时间）与 §6（任务号表第一行）。

### A2 = `H226`（2026-10-04 07:51:22，**2 个字符**）——最短的一条提示词，却是 E6 签收的唯一输入

```
0度
```

- 它对应 `corrections.md` C2 里那句"人眼判读"，落点 `board/ACCEPTANCE.md:92`（E6 格）。
- **不许美化**：赛题要的"交互记录"里就包含这种两个字回合。把它写成"经验收确认显示正确"就是销毁证据。
  `report/log/ISSUES.md:13092-13093` 记的是同一件事的原话口径（条件=断电 ≥10 s 冷上电、只跑三步 JTAG 链、
  全程不碰 KEY1/KEY2；对照组"上电后按住 KEY1"仍未做 ⇒ 那一格只登记"未判"）。

### A3 = `H93`（2026-09-26 11:26，46 字符）——人当场否掉模型的一次读图

```
你确定看到图片了吗 我看图片上怎么写的是50.25兆呢 还是说你用其他算出来的 你再看一眼呢
```

- 这是"错误断言被人指出、再由判别动作确认"的最短样本；同族轨迹见
  `report/AI_COLLABORATION.md` §4 与 `report/log/ISSUES.md`（时钟读数那一族）。
- 本条**不**升级为 `corrections.md` 的成对条目：本次没找到与它一一对应的判别件（缺文件:行凭据）
  ⇒ 进 `corrections.md` §6 的 U1 类（未逐条复算）。

> A 栏其余 223 条：`H02…H225` 的编号、时间戳、字符数与首 60 字摘要都由 `metrics.md` §2 那条命令现出，
> 但**本文件不批量摘录**（隐私最小必要）。需要哪一条时按 `S01 / H<序号> / 时间戳` 在本机定位。

---

## B 栏 · 主 agent 派发给子 agent 的提示词原文（摘录 2 条，各 ≤10 行）

指针形式：`S05 表第 <行号> 行 / SUB_ID / DISPATCH_UTC`。正文落在那份子会话导出的**唯一一条**
`humanInput` 记录里（S05 §2 实测每份恰好 1 条）。

### B1 = S05 第 105 行附近，`SUB_ID 0338272e177…`，`DISPATCH_UTC 2026-10-04T00:41:40`（19 行，3,529 字符）

```
 1| You are authoring part of a competition "skill package" for an AMD FPGA design contest. Repo root: `<仓库根>`.
 2|
 3| FIRST read these specs (authoritative for format):
 4| - `<文档工作区>/skill_prompts/00-charter.md` (the 8-section shell, frontmatter, prohibitions)
 5| - `<文档工作区>/skill_prompts/05-pitfalls.md`
 6| - `<文档工作区>/skill_prompts/06-references.md`
 7|
 8| THEN mine real evidence by READING files (do not guess): existing items `skill/*.md` (28 numbered S-cards — several …
```

⇒ **这就是 D 栏进入执行链的真实方式**：任务提示词不是被逐字贴进对话的，而是**按路径引用、由子 agent 自己去读**。
（对照 D 栏的"0 命中"结论，两者不矛盾：一个说"没被贴过"，一个说"被引用过"。）

### B2 = S05 冻结段最后一场，`SUB_ID 34dbd560d14…`，`DISPATCH_UTC 2026-10-04T03:44:38`（42 行，2,185 字符）
⇒ **这一条就是生成本档案的那次派发**（在 `CUT` 之后，所以**不在** S05 表的 127 行里，S05 §2 已点名它属于被排除的 10 场）。

```
 1| 你在仓库 `<仓库根>`（Windows + Git Bash；node 24、python 3.12 可用）。**无人值守模式（P23）**。
 2| 你负责把"大模型协作过程"做成可核对的档案（赛题 3.3.3.1 与 3.3.5.3 点名的东西）。
 4| 第一步（必读，逐字）：
 5| 1. `<文档工作区>/skill_prompts/00-charter.md`
 6| 2. `<文档工作区>/skill_prompts/23-unattended-run-protocol.md`
 7| 3. `<文档工作区>/skill_prompts/22-collaboration-log-archive.md` ← 你的规格
 9| 交付（P22 点名七件，别多点名）：`report/collaboration/README.md`（索引：任务 → 会话 → 结论落点）、
```

冻结窗口内同类派发（`无人值守` 字样）共 **10** 条，其中 **9** 条点名 `P00`。

---

## C 栏 · 成文的轮次提示词文件（当时用的原文，但不在任何一份导出里）

`<文档工作区>/2026-10-03/6c22b30a/timing-global-round-prompt.md`（21,433 字节，mtime 2026-10-03 20:30，
SHA-256 前 12 `a90fb0ec7cfc`，成文现场 = S04-c）。
本仓库对它唯一的点名处：`build/r116_batch_plan.md:5`（那一行原文写的是这台机器上的绝对路径 ⇒
`redaction.md` §4 台账里有一条对应的"改写为占位符"处置）。

**它不属于 D 栏**：它是 r116/r117 那几轮**当时真用过的**轮次提示词；
`skill_prompts/` 那 31 份是事后成文的任务卡。两者时间差 8 天。

---

## D 栏 · 队伍任务提示词集（事后成文，**不得**标成"当时用的原文"）

清点命令与结果（本机执行）：

```bash
ls -1 <文档工作区>/skill_prompts/*.md | wc -l                    # 31
stat -c '%y %s %n' <文档工作区>/skill_prompts/*.md | sort | head -2
#  2026-10-04 07:59:46 6285 00-charter.md                    （SHA-256 前 12 e19218989e16）
#  2026-10-04 09:24:43 11098 23-unattended-run-protocol.md
```

**它没有作为原文出现在任何一场会话的人工输入里**——这条结论是算出来的，不是推断的：

```bash
# 取每个提示词文件的首行前 10 个字符当指纹，扫全部 7 份导出的 humanInput 正文
python - <<'PY'   # 见 metrics.md §2 同款解析；marks = {编号: 首行[:10]}
...（对每条 humanInput 做 `head in txt` 判断）
PY
```

实跑输出（判 7 份导出，逐份一行）：

```
D--Xilinx-Prj-pro/658cc4e8…jsonl   HUMAN_TURNS 1    PROMPT_MARKERS_HIT -
D--Xilinx-Prj-pro/b20eed02…jsonl   HUMAN_TURNS 226  PROMPT_MARKERS_HIT -
D--Xilinx-Prj-project-handoff/…    HUMAN_TURNS 39   PROMPT_MARKERS_HIT -
C--…-2026-09-20-a1c98296/…         HUMAN_TURNS 1    PROMPT_MARKERS_HIT -
C--…-2026-10-01-cc03d7a4/…         HUMAN_TURNS 3    PROMPT_MARKERS_HIT -
C--…-2026-10-03-6c22b30a/…         HUMAN_TURNS 1    PROMPT_MARKERS_HIT -
C--…-2026-10-04-3d601c82/…         HUMAN_TURNS 6    PROMPT_MARKERS_HIT -
```

⇒ **命中 0 / 判 7 份 / 人工轮次合计 277（其中本仓库 S01 226）** ⇒ D 栏定性为"事后成文"。

它们被使用的唯一证据在 B 栏侧（冻结口径实数）：

| 指标 | 值 | 命令出处 |
| --- | --- | --- |
| 冻结窗口内派发次数 | 128 | S05 §3 |
| 正文出现 `skill_prompts` 路径（`/` 与 `\` 两种写法都归一后统计） | **17** | 本文件 §D 末的 python 段 |
| 正文点名**具体** `skill_prompts/NN-*.md` 的派发 | **7** | 同上 |
| 落盘的 127 场里能在 S05 `PROMPTFILE` 列看到具体文件名的 | **6**（第 7 条是无导出的那次，见 S05 §3） | S05 表 |
| 被点名的文件分布 | `00-charter.md` 6 · `05-pitfalls.md` 2 · `06-references.md` 2 · `04-scripts.md` 2 · `02-prompt-workflows.md` 1 · `03-templates.md` 1 · `07-runtime-pl-regmap-dma.md` 1 · `11-walkthrough-learning-doc.md` 1 | 同上 |

> 17 vs 7 vs 6 不是矛盾：17 含只提目录不点文件的；7 含那一条没有导出落盘的派发；6 是能在 S05 表里连上行的。
> 三个数各自的口径就写在上面这张表里，**不许相减**。

---

## E 栏 · 事后提炼的模板（4 条）与它们的对应关系

模板文件本身在 `skill/prompts/*/SKILL.md`（本任务边界：只引用、不修改）。
它们的**来源账**已经成文：`skill/prompts/_proposed-sources.md`（结论一句话 | 来源 | 核对日期 | 用在哪个条目）。

| 模板（E 栏） | 提炼自哪些**当时**的东西 | 对应关系的证据 |
| --- | --- | --- |
| `criterion-before-code` | A/B 栏没有一条与之逐字对应的提示词；它对应的是**做法**——先造能红的判据再改代码，实践轨迹是 `report/log/ISSUES.md` #127/#128（判据没牙那一族）与 #316（零样本通过） | `skill/prompts/_proposed-sources.md` 各行的"用在哪个条目"列；本档案侧指针：`corrections.md` C1（合成对照六条）、C5（十条畸形对照） `[推断]` |
| `hw-sw-partition` | 当时的原文 = A 栏 `H04`（2026-09-22 08:56，讲第一版 PS 以太网/第二版 PL 以太网的那段口语）与 `H55`/`H56`（报名简介长文）；仓库侧落点 `report/PS_VS_PL.md`、`report/ARCHITECTURE.md` §3 | `_proposed-sources.md` 前四行逐条点名了这两个 `report/` 文件与 mtime `[推断]` |
| `report-to-bottleneck` | 当时的原文 = **C 栏**那份 `timing-global-round-prompt.md`（轮次提示词），不是 D 栏 | `build/r116_batch_plan.md:5`（点名 C 栏文件）+ `_proposed-sources.md` 里 `report/TIMING_GLOBAL.md` §1/§2 各行 |
| `single-variable-ab` | 当时的做法 = A 栏 `H142`（"先深度彻底优化一次时序和资源"那一段）与 B 栏 10-04 01:3x 那批 P15/P16 派发；仓库侧落点 `docs/timing/README.md` 噪声底一节、`report/log/ISSUES.md` #306/#311 | `_proposed-sources.md` 后三行（噪声底、同一 `opt.dcp` 逐位复现、复制类手段可数） `[推断]` |

**这一栏的诚实声明**：上面四条"对应关系"里，**只有 `report-to-bottleneck ↔ C 栏文件`这一条是硬证据**
（盘上有点名行）。其余三条是**按主题与时间对齐**得出的 ⇒ 全部标 `[推断]`，
不允许在评分材料里被念成"模板就是照着这条提示词提炼的"。要闭合需要 A/B 栏正文与模板正文做逐句 diff（本次未做）。

---

## F 栏 · 混用检查（P22 铁律 3 + 质量判据 6）

```bash
cd <仓库根>/report/collaboration
# 判 4 项：五类物件是否各有独立小标题、是否有条目同时挂在两栏
grep -n '^## [A-F] 栏' prompts-used.md | wc -l                       # 期望 6（A/B/C/D/E/F）
grep -c '事后成文' prompts-used.md                                    # D 栏定性，>0
grep -c '\[推断\]' prompts-used.md                                    # 实测 5 = E 栏表内 3 行 + E 栏末段说明 1 + §F 判定行 1
grep -n 'P00–P23' prompts-used.md | head -3                           # D 栏只出现在"事后成文"语境
```

| 判据 | 判定 |
| --- | --- |
| A/B/C 三栏（当时原文）与 D/E 两栏（事后成文/模板）有无混标 | PASS（混用条目数 **0**：本文件里没有任何一条 D/E 物件被写成"当时用的原文"；三条软对应已就地标 `[推断]`） |
| 每条摘录都指明"来自哪张登记卡 / 表的第几行" | PASS（A1/A2/A3 → S01 §1/§6；B1/B2 → S05 表行 + SUB_ID + DISPATCH_UTC；C → `build/r116_batch_plan.md:5`） |
| 摘录 ≤10 行 | PASS（A1 给 11 行编号但其中含 1 个空行，正文 10 行；A2/A3 各 1 行；B1/B2 各 ≤9 行正文） |
| 对应关系完整率 | FAIL（判 4 条模板，硬证据 1 条 ⇒ **3/4 为推断**，缺口在 E 栏末段写明） |

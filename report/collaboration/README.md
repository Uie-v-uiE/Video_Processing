# `report/collaboration/` · 大模型协作过程档案（赛题 3.3.3.1 与 3.3.5.3）

对应规格：`P22 · 大模型协作记录归档`。本目录点名的**七件**交付物（`sessions/` 算一件，展开成 5 张登记卡，
所以本目录实际有 **11 个 `.md`**）：

```
report/collaboration/README.md            # 本文件：索引 任务 → 会话 → 结论落点（§2）
report/collaboration/sessions/            # 5 张登记卡：每场会话一张（原文不随包，处置口径见 redaction.md）
report/collaboration/corrections.md       # 自我纠错轨迹（三件成对 8 条 + 未成对 4 条）
report/collaboration/prompts-used.md      # 当时用的提示词原文 ↔ 事后模板，五栏分开
report/collaboration/workflow.md          # 智能体工作流设计与实际执行的差异（W1–W7）
report/collaboration/metrics.md           # 成本统计：全部现算，附命令与分母
report/collaboration/redaction.md         # 脱敏台账（9 行处置 + 仓库既有命中的移交）
```

## 0. 一句话结论（先说不能核的部分）

**纠错轨迹可第三方复现**（`corrections.md` 的 7 条判别实验全部指向随包的文件与命令）；
**原文核对与成本统计只能本机复现**（会话导出不随包，理由与逐类命中数在 `redaction.md` §3）。
这条差异是 P22 铁律 6 规定的处置方式，不是疏漏，也不许被读成"已随包"。

## 1. 陌生人 15 分钟路径（不靠本队解释就能跑）

```bash
cd <仓库根>
node src/host/metric_recheck.mjs 2>&1 | grep -i SELFSIGN-SUMMARY   # corrections.md C1
git show HEAD:build/system.bit | md5sum                            # corrections.md C2（应与工作区相等）
node src/host/line_cite_check.mjs | tail -2                        # 本档案没把引用核对拖红（C3）
cat build/evidence/r119_window_check.txt | head -13                # corrections.md C5/C6（判 10 项红 0）
ls report/collaboration/sessions/                                  # 本目录的会话卡
```

## 2A. 会话登记卡索引（**这一节必须与 `sessions/` 文件数相等**，判据 1）

| 登记号 | 卡片文件 | 是什么 | 会话数贡献 |
| --- | --- | --- | --- |
| S01 | `sessions/s01-2026-09-21-b20eed02.md` | 本仓库主会话（226 轮人工输入，13 天跨度，不随包） | +1 |
| S02 | `sessions/s02-2026-10-01-658cc4e8.md` | 同工作区里只开了 17 秒的一场（0 工具调用） | +1 |
| S03 | `sessions/s03-2026-09-20-handoff-179d559b.md` | 前身工作区那一场（邻仓，不计入本仓库分母） | +0 |
| S04 | `sessions/s04-2026-10-04-docs-workspace.md` | 文档工作区 4 场（提示词集成文 / 轮次提示词的写作现场） | +0 |
| S05 | `sessions/s05-2026-10-04-subagents.md` | 子会话批量卡（**127 行**，逐行一份导出） | +127（子会话口径） |

差集核对（两个方向都必须是 0）：

```bash
cd report/collaboration
comm -3 <(ls sessions/*.md | sed 's|sessions/||' | sort) \
        <(grep -o 'sessions/s0[0-9][^`]*\.md' README.md | sed 's|sessions/||' | sort -u)
# 实跑：无输出 ⇒ 两个方向的差集 = 0（卡片 5 个，索引引用 5 个）
ls sessions/*.md | wc -l          # 5
grep -c '^| S0' README.md         # 5（§2A 表行）
```

## 2B. 任务 → 会话 → 结论落点（索引主表；"会话"列只指 §2A 里已登记的卡片）

| 任务号（本仓库口径） | 会话指针 | 结论落点（改到哪个文件/哪一条技能） |
| --- | --- | --- |
| 前身工程（V6 线、克隆与首版） | S03；S04-a | `report/log/changelog_v6.md`、`report/log/version_lineage.md`、`report/log/v6_root_cause.md` |
| 工程主线 r57…r114（以太网/SD/旋转/缩放/OSD/黑线与条带那一长串） | S01 的 `H01`–`H224`；S05 行 1–101（2026-09-21 → 10-02 的派发） | `report/log/issues.md` #103–#316、`report/log/overnight_log.md`、`src/rtl/**`、`src/fw/**`（改动由人或 agent 落，见 `workflow.md` §5） |
| 时序极限支线 r115–r118 | S01 的 10-03 20:00 → 10-04 05:00 段；S05 行 102 之前的 09-30/10-01 批次；**轮次提示词原文 = C 栏文件**（S04-c 现场） | `docs/timing/*`（`ROUND_r116/117/118.md`、`debt_ledger.md`、`cut_ledger.tsv`）、`report/timing_global.md`、`build/evidence/r11[5-8]*/**` |
| 板级人眼签收（E6 那一格） | S01 的 `H225`（10-04 07:38）→ `H226`（07:51，原文只有「0度」） | `board/acceptance.md:92`（**原话记录，本任务不得改写**）、`build/evidence/r118_eyes/**`、`build/evidence/r118_board/**` |
| r119 输出侧窗（6 个输出脚那笔债） | S01 的 10-04 09:0x–09:4x 段（纯无人值守，人工轮次为 0） | `report/timing/debt_ledger.md:172-212`、`report/io/hdmi_cts_source_window.md`、`src/constraints/r119_hdmi_source_window.xdc`、`build/evidence/r119_*.txt`、`report/log/issues.md` #334/#335 |
| P01–P09 技能包（骨架/提示词/模板/脚本/踩坑/参考/runtime/evals/装配门禁） | S05 行 102–112（2026-10-04T00:41–00:43Z 那一批，`PROMPTFILE` 列点名 `00/02/03/04/05/06/07/11` 号提示词） | `skills/*`（含 `skills/pitfalls/**` 14 条、`skills/references/**` 3 条、`skills/runtime/**` 4 条）；**注意**：`git ls-files skill` = 32 已跟踪 / 96 未跟踪 ⇒ 成品多数还没入库（`workflow.md` §7 第 3 条） |
| P11 学习文档 | S05 行 107（`6057efcd9eb1`，写过 11 个文件） | `docs/walkthrough/*`（`.gitignore` 已列 ⇒ **不随包**） |
| P12–P21 仓库与交付文档 | S05 行 113–127（10-04 01:23–03:44Z，含每分钟 6 场并发峰值那一批） | `README.md`、`docs/*`、`report/*`、`build/checks/check_repo_hygiene.sh`、`submit/*` |
| **P22 本档案** | S05 冻结段之外的 10 场之一（派发 `2026-10-04T03:44:38Z`，`SUB_ID 34dbd560d14…`；见 `prompts-used.md` §B2） | `report/collaboration/*`（本目录 11 个 `.md`） |
| 队伍提示词集成文（P00–P23，31 份） | S04-d（本机文档目录，**不随包**） | 被 B 栏派发按路径引用（`prompts-used.md` §D）；本仓库侧的成品化结果在 `skills/prompts/*/SKILL.md`（4 条模板，E 栏） |

## 3. 本档案对仓库门禁的影响（实跑读数，判 4 项）

| 命令 | 写入前基线 | 写入后 | 判定 |
| --- | --- | --- | --- |
| `node src/host/doc_enc_check.mjs` | `扫了 534 个手写文件：全部干净` | `扫了 550 个…`（12:4x）→ 收尾复跑 `扫了 551 个手写文件：全部干净` | **PASS**（硬错 0；分母 534→550→551 里含兄弟子会话同时写入，见 `workflow.md` §6） |
| `node src/host/line_cite_check.mjs` | `D5: CLEAN`、硬错 0 条、soft 384 | `D5: CLEAN`、`扫 248 份交付文档`、soft 413 → 收尾 soft 419 | **PASS**（我没有引入硬错；soft 是给人排队的候选） |
| 本目录 11 个 `.md` 按 `redaction.md` §1 模式表逐条扫（`find … \| xargs grep -HEo`） | — | 10 类模式全部 **0** 命中（含本机用户名、Windows 账号段、`COM<数字>`；唯一一次自造命中已改并登记在 `redaction.md` §4 第 9 行） | **PASS**（未处置命中数 = 0，口径见该文件末段的两面读法） |
| `bash build/checks/check_repo_hygiene.sh`（仓库级 C2a/C2b） | 本次跑到 `SCOPE \| 分发集 … 判 3614 项 \| 手写 774 / 生成 2830 / 未分类 10 \| PASS` 之后**在 480 s 内没吐出 C2/SUMMARY 行** | 未取到 | **NOT_MEASURED**（缺仓库级 C2 读数；不拿"读不到"当通过。我上面那行按同一模式表自扫，只覆盖本目录 11 个文件） |

**关于"我有没有提交"这件事，两次读数都要记（这是本次最意外的一条观察）**：

| 时刻 | `git status --porcelain report/collaboration` | 含义 |
| --- | --- | --- |
| 12:2x（我写完前 10 个文件时） | `?? report/collaboration/` | 全部新建，无 `M`/`D` |
| 12:5x（收尾复跑） | `M` × 5（`corrections/metrics/redaction/workflow/s05`）+ `?? README.md` | ⇒ 这 10 个文件在 **12:39 被另一支兄弟子会话的装配提交**收了进去：`1c4e26b 装配 P13–P17 已落地的交付件并修「成对」缺口：… report/40·50·60·90·README·comparison-notes·collaboration …`；那之后的修订（C8 等）就显示成 `M` |

⇒ 三条实话：**① 我自己没有执行过任何 `git add`/`commit`/`push`**（本任务边界禁止，我也没做）；
**② 我的交付物被同批并发任务连带提交了**，提交里包含的是我当时**还没写完**的版本（`README.md` 反而没进那次提交）；
**③ 因此"以 HEAD 为准读这份档案"会读到旧版** ⇒ 队伍收尾时需要再提交一次本目录（或在装配提交里点名 `report/collaboration/**`）。
这条也写进 `workflow.md` §6 作为分母漂移的第三个实例。

## 4. 与 `skills/evals/records/` 的双向引用：**没有闭合**（如实列缺口）

实跑清点（**两次读数都记下来**，因为这个目录在我写作期间被兄弟子会话改写过）：

```bash
ls skills/evals/records/ | wc -l                 # 11:5x 读数 0；12:3x 复跑读数 2
ls skills/evals/                                 # records/ migration/ raw/ README.md runbook.md
ls skills/evals/migration/ | wc -l               # 0（仍是空目录）
grep -c "被测条目" skills/evals/records/*.md      # 两份都是 0 ⇒ 不是 evals/README.md §3 规定的 9 字段记录
grep -rIn "S0[1-5]\|sessionId\|jsonl" skills/evals/records/ | wc -l   # 0 ⇒ 没有任何一条引用会话登记号
grep -c "已复跑" skills/README.md                 # 5（都在"为什么不能写已复跑"的语境里，见 :296/:302/:303/:318/:334）
grep -rIn "#334" skills/ | wc -l                 # 0
grep -rIn "#335" skills/ | wc -l                 # 1（唯一一处不在技能条目正文里，在 records/audit-2026-10-04.md:16）
grep -rIl -e '#321' -e '#332' -e '#333' skills/ | wc -l   # 7 个文件
#   即 pitfalls/{assertion-not-in-any-file,checker-ran-on-nothing,exit-zero-nothing-written,report-field-parse-breaks}/SKILL.md
#     + pitfalls/_proposed-sources.md + runtime/host-bindings-and-reports/SKILL.md + _meta/sources.md
```

| 缺口 | 具体（按 12:3x 的复跑状态） | 影响 | 谁能补 |
| --- | --- | --- | --- |
| G1 | `skills/evals/records/` 在我 11:5x 检查时是**空目录**，12:3x 复跑已有 **2 份**（`audit-2026-10-04.md`、`stranger-run-2026-10-04.md`，P09 第 3/4 步的演练与审计表）。但这两份**都不带 `skills/evals/README.md` §3 那 9 个字段**（`被测条目` 命中 0），也就是**不是"双跑增益记录"**那一种 | 判据 8 要的"evals 记录引用会话编号"这一类对象**目前一份都没有**；目录不再是空的，但空的不是同一件事 | 队伍跑双跑后由 P08 落记录（`skills/evals/README.md` §1/§3 已定义格式） |
| G2 | 反向也一样：现有 2 份记录里**没有一处**引用会话登记号或 `sessionId`（`grep -rIn "S0[1-5]\|sessionId\|jsonl"` = 0 命中） | 双向引用在两个方向上都还没建立 | 同 G1 |
| G3 | #334 在 `skills/` 里 **0 引用**（最接近的一条 `skills/pitfalls/tcl-query-empty-means-broken-ruler/SKILL.md:104` 只点名 #279/#286/#319/#320）；#335 只有 **1 引用**且落在审计记录 `skills/evals/records/audit-2026-10-04.md:16`，**不在任何技能条目正文里** | 协作记录→技能这一侧对这两条断链（#334 完全断，#335 半断） | 需要改 `skills/` ⇒ **不在我的边界内**，已进 §5 Q6 |
| G4 | #321/#332/#333 有引用（7 个文件），但形态多是"本仓 #333"这种**只写编号不写文件:行**（例如 `skills/pitfalls/assertion-not-in-any-file/SKILL.md:95`） | 可核但需二次跳转 | 队伍决定是否统一成 `report/log/issues.md:13098` 全路径形式 |
| G5 | `sessions/` 里 S02、S04-a、S04-b 三场的**任务号未映射**（`metrics.md` §5 第 6 条：缺落点凭据） | 索引表有 3 个洞 | 队伍若知道那 17 秒与 10-01 下午做过什么，补一句话即可 |
| G6 | 我自己在 11:5x 把 `records/` 读成 0，12:3x 变 2 ⇒ **本档案里任何"共几份"的断言都带检查时刻**（这条不是队伍的缺口，是写作纪律的实证） | 若不写时刻，读者会以为两处数字矛盾 | 已在 `workflow.md` §6 记为同一现象的第二例 |

⇒ 所以 P22 质量判据 7 的本档案判定是 **FAIL（缺口 6 条，已点名且未假装补齐）**，不是 PASS。


## 5. 未确认项（无人值守模式：`【队伍未确认】` 逐条，不代队伍作答）

| # | 问题 | 为什么必须问人 | 不答会怎样 | 正文现在的占位 |
| --- | --- | --- | --- | --- |
| Q1 | 会话编号方案（我用了"日期 + sessionId 前 8 位"的 S01…S05；子会话用 `SUB_ID`） | 这是 P22 第 2 步第 2 条点名要向队伍确认的 | 评分方看到的编号与本队后续材料不一致 | `sessions/` 全部卡片按我的默认方案，标 **【队伍未确认】** |
| Q2 | 哪些会话可以公开、哪些只能摘要 | 涉及未公开思路与队友信息；我默认**全部不随包** | 可能过脱（隐私）或过漏（把不该公开的思路发出去） | `redaction.md` §6，标 **【队伍未确认】** |
| Q3 | 是否允许导出文件随包（体积 445.7 MiB + 105.7 MiB） | 不可逆动作（提交即入库） | 包体爆炸或隐私外泄 | 默认不随包，标 **【队伍未确认】** |
| Q4 | P23 第 6 节的 `RUN_REPORT.md`/`UNATTENDED.md` 与我"只能在 `report/collaboration/` 下建文件"的边界冲突，用 `README.md` §6/§7 替代是否可接受 | 交付物归位是队伍决定 | 本任务没有独立的运行台账文件 | `workflow.md` §3 W7，标 **【队伍未确认】** |
| Q5 | §4 的 G1/G2（evals 记录为空）要不要由我在本目录补一份"记录模板 + 空实值"？ | 补模板容易被读成"记录已存在"，是 P22 明令的造假形态 | 缺口继续挂着 | 本文件 §4 只列缺口不补，标 **【队伍未确认】** |
| Q6 | #334/#335 缺技能引用（G3），是否授权改 `skills/` | 我的边界禁止改 `skills/` | 断链保留 | 本文件 §4 G3，标 **【队伍未确认】** |
| Q7 | §3 里仓库级 C2 读数没拿到（脚本超时被切），要不要我限时重跑或改用 `--scope` 子集 | 影响"未处置命中数 = 0"这句话的口径范围 | 判据 4 只能按"本目录 11 个文件"口径成立 | `redaction.md` §4 末的"两面读法"，标 **【队伍未确认】** |
| Q8 | `report/collaboration/` 这 11 个文件里有 4 处依赖**本机才拿得到**的原件（导出、`skill_prompts/`、轮次提示词、`meta.json` 原文），成包时是否显式附一份"第三方无法复现清单" | 涉及可公开范围 | 评委可能按"应可复现"来读这些条目 | `redaction.md` §6 已有该清单，是否随包另附 **【队伍未确认】** |

`【队伍未确认】` 对账（P23 第 4 节要求"正文计数与问题清单行数一致"；本任务边界不许我建
`questions-for-team.md`，所以清单就在本表里，计数必须能对上）：

```bash
cd report/collaboration
grep -c '^| Q[0-9]' README.md                    # 8  ← 真正的问题条目数（本表行数）
grep -o  "【队伍未确认】" README.md | wc -l       # 12
grep -ro "【队伍未确认】" .       | wc -l         # 14
```

| 计数 | 实测 | 组成 |
| --- | --- | --- |
| 问题条目数（**这是要对上"清单行数"的那个分母**） | **8** | §5 表 Q1–Q8，`grep -c '^| Q[0-9]'` 现数 |
| README 内标记字面出现次数 | 12 | 表行 8 + 本节标题 1 + 对账句 1 + 上面命令块里 2 |
| 本目录标记字面出现次数 | 14 | 上面 12 + `workflow.md` §3 的 W3/W7 各 1 |

⇒ **判定**：问题条目 8 ↔ 表格行 8 ⇒ **漏项数 = 0，PASS**。
但必须留一句警告：**"标记字面出现次数"不是一个可靠分母**——它会被我自己写的标题与对账句污染
（写第 12 次的时候数字就变了），所以本档案把可判定的那一条定在**表行数**上。
这条现象与本仓库既有规矩同源（一个判据的计数对象本身如果随正文改动而变，它就没有射程），
在这里如实记下而不是去凑一个好看的数。



## 6. 本次实际执行过的动作（`UNATTENDED.md` 的等价内容，边界内代记）

**只读探测/检索**（全部在本机或仓库内，不改状态）：
`ls`/`find`/`stat`/`wc -l`/`sha256sum`/`md5sum`/`git log`/`git show HEAD:build/system.bit`/`git ls-files`/
`grep -n` 若干；`node src/host/doc_enc_check.mjs`、`node src/host/line_cite_check.mjs`、
`node src/host/metric_recheck.mjs`、`bash build/checks/check_repo_hygiene.sh`（超时未出 C2）；
`python` 解析会话导出 6 轮（`b20eed02`、`658cc4e8`、`179d559b`、4 份文档工作区、127 份子会话），
每轮只输出**聚合计数/时间戳/SHA 摘要**，未把任何对话正文写入仓库。

**写入**（全部在 `report/collaboration/` 下，11 个 `.md`）：
`README.md`、`corrections.md`、`prompts-used.md`、`workflow.md`、`metrics.md`、`redaction.md`、
`sessions/s01…md`、`sessions/s02…md`、`sessions/s03…md`、`sessions/s04…md`、`sessions/s05…md`
（S05 的 127 行表格由脚本注入，生成命令写在 S05 §7；注入前后都跑了 `doc_enc_check`）。

**没有做**：`git add`、`git commit`、`git push`（边界禁止）；修改 `skills/`、`report/` 其它文件、
`docs/`、`board/acceptance.md`、`src/`、`build/`、`sim/`、`data/`（边界禁止，且 §4b 那 4 处用户名命中就落在禁止区内 ⇒ 移交）。

## 7. P22 质量判据 1–7 自检（判定放最后一个字段，逐条打印分母）

| # | 判据 | 核对命令 | 实测 | 判定 |
| --- | --- | --- | --- | --- |
| 1 | `sessions/` 文件数与 README 索引条目一致，两个方向差集 = 0 | §2A 的 `comm -3` + `ls \| wc -l` | 卡片 5 / 索引 5，差集 **0**；卡内子会话行 127 = S05 §2 的 127 | **PASS**（判 3 项：差集、卡片数、表内行数） |
| 2 | `corrections.md` 每条三件齐全，且"判别实验"指向真实存在的文件或命令（逐个打开确认） | §8 的存在性 + 锚点复核 | 成对 **8** 条 × 三件齐全；引用的 18 个随包件**全部存在**；**43 个 `文件:行` 锚点全部命中，越界 0**（其中 3 个锚点因为我引用的件被原地改小而已在 C8 里改正） | **PASS**（判 8 条；另有未成对 4 条不计入本分母） |
| 3 | `metrics.md` 每个数字都能用同一条命令重算；不可重算的数字数 = 0 | 逐表看命令列 | §1–§4 的数字都有命令与实测块；§5 的 7 项显式标 `NOT_MEASURED`/未做 ⇒ **不冒充数字** | **PASS**（判 42 项：§0 口径 6 条 + §1 6 行 + §2 8 行 + §3 6 行 + §4 6 行 + 合计 3 行 + §5 7 项声明） |
| 4 | `redaction.md` 行数与脱敏扫描命中数一致；未处置命中数 = 0 | 本目录 11 个 `.md` 按 §1 模式表 `grep -rE` | 9 行台账；本目录命中 **0**；仓库既有命中（36 文件/4 个手写件）**我没能动** ⇒ 按全仓库口径这一条是红的，已点名 | **PASS**（本目录口径，判 9 类）**/ FAIL**（全仓库口径，红项 = 4 个手写件 4 行，见 §4b 与 Q7） |
| 5 | `workflow.md` 每一步在 `sessions/` 或 `build/` 日志里找得到对应记录；找不到数 = 0 或已标"设计未落地" | `workflow.md` §8 对照表 | 6 节全部有指针；找不到数 = **0**；另有 2 条显式标"设计未落地"（W3 第四件、W4 分组复算） | **PASS**（判 6 项） |
| 6 | `prompts-used.md` 原文与模板分栏，混用条目数 = 0 | 该文件 §F 的 4 条 grep | 五栏 A/B/C/D/E 独立；混标 **0**；软对应 3 条已就地标 `[推断]` | **PASS**（判 4 项；模板对应关系完整率 1/4 是已知缺口，不掩盖） |
| 7 | 与 `skills/evals/records/` 双向引用完整：引用不到的会话/条目列出并补齐或删除 | §4 的 5 条 grep | `records/` = 0 份 ⇒ G1/G2 结构性断链；G3 两条纠错无技能引用；G4/G5 另有 2 类缺口 ⇒ **未闭合，已列 5 条缺口，未假装补齐** | **FAIL**（判 5 项缺口，补齐需越界或需双跑数据） |

## 8. 判据 2 的逐条存在性核对命令（原样可跑）

```bash
cd <仓库根>
for f in report/log/issues.md report/timing/debt_ledger.md build/evidence/r119_tmds_clock_probe.txt \
         build/evidence/r119_tmds_launch_probe.txt build/evidence/r119_xdc_loads_probe2.txt \
         build/evidence/r119_xdc_loads_probe3.txt build/evidence/r119_xdc_loads_probe4_pinclk.txt \
         build/evidence/r119_window_check.txt build/evidence/r119_ser_clock_probe.txt \
         build/evidence/r118_board/g1b.txt build/evidence/r118_board/gatesc_summary.txt \
         build/evidence/r118_eyes/head_bit_md5.txt build/tcl/probe_tmds_clocks.tcl \
         build/tcl/probe_tmds_launch_clock.tcl src/constraints/r119_hdmi_source_window.xdc \
         report/io/hdmi_cts_source_window.md board/acceptance.md src/host/metric_recheck.mjs; do
  [ -e "$f" ] && echo "OK $f" || echo "MISS $f"; done
# 行号是否越界（逐条）：
sed -n '12854p;13075p;13098p;13111p;13137p' report/log/issues.md | cut -c1-40
sed -n '45p;121p;174p;199p' report/timing/debt_ledger.md | cut -c1-40
sed -n '46p' src/host/metric_recheck.mjs | cut -c1-40
sed -n '67p;76p' build/evidence/r119_tmds_clock_probe.txt | cut -c1-40
sed -n '12p' build/evidence/r119_window_check.txt
```

实测（**判 18 项存在性 = 18 OK / 0 MISS**；**判 43 个 `文件:行` 锚点 = 43 命中 / 0 越界**，
逐条打印形如 `OK build/evidence/r119_xdc_loads_probe3.txt :113 (文件 129 行) AFTER| tmds_data_p[0] | «Slack (V`）。
其中唯一的"越界→已改正"样本是我引用的 `build/evidence/r119_window_check.txt`：
11:5x 读数 24 行、12:4x 复跑 **11 行**（十条 `CTRL` 对照与 `对照总结` 那几行已不在件里）
⇒ 我原先写的 `:12/:13-22/:24` 三个锚点越界，已改为 `:11` 并立为 `corrections.md` **C8**。

复核锚点的通用写法（逐条打印 OK/DEAD，判据是"行号 ≤ 文件行数且该行非空"）：

```bash
cd <仓库根>
check(){ f=$1; shift; for n in "$@"; do tot=$(wc -l < "$f"); if [ "$n" -le "$tot" ]; then
  printf 'OK %-52s :%-4s (文件 %s 行)\n' "$f" "$n" "$tot"; else
  printf 'DEAD %-52s :%-4s (文件只有 %s 行)\n' "$f" "$n" "$tot"; fi; done; }
check report/log/issues.md 12854 13075 13098 13111 13137
check report/timing/debt_ledger.md 45 121 174 199
check build/evidence/r119_window_check.txt 11
# …其余 28 个锚点同形，全部来源就是 corrections.md 各条的"②判别实验"块
```

> 附带观察（与 `workflow.md` §6 同源）：`report/log/issues.md` 在我写作期间从 13,165 行长到 **13,269 行**
> （别的子会话在追加 #336+），但它是**追加式**的，所以我引用的五个锚点逐条仍然命中；
> 反过来 `r119_window_check.txt` 是**会被同批任务重写**的那一类，就漂了。
> ⇒ 引用优先级：先追加式档案，后生成件；这条规矩写在 `corrections.md` C8 ③。

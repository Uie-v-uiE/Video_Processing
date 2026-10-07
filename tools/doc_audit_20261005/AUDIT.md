# 交付文档夜间审查（评委视角）· 2026-10-05 夜

审查对象＝主仓库 `b65a191`（板与仓库都是 r118 那一版）里随包交付的 markdown 文档集。
改写成果**不落在主仓库**，落在 `D:/Xilinx/Prj/pro/delivery_review_20261005/`——
那是同一仓库的 git worktree（分支 `review/20261005`），目录结构与交付结构逐字一致，
可以逐文件 diff、可以整份丢弃，主仓库在你确认之前保持与 origin/main 相同且**没有推送任何东西**。

## 1. 一句话结论

文档的问题不是写错，而是**写给自己看**：把内部轮次、施工时刻、检查脚本的行话和免责补语
留在了评委要读的那几页里。数量级如下（我自己量的，口径见第 3 节）：

- 交付叙述件 **220 份 / 28,882 行**，另有过程台账 `report/log/` **13 份 / 22,643 行**随包。
- 一天内的**墙钟时刻**（`04:18:27` 这类）出现在 **61 份文件、共 349 行**。
- **内部轮次号 rNN 当叙述用**（不含路径字面量）**2,403 处，散布在 114 份文件**里。
- 机器门禁 C7 的口径下人称与程度副词已经是 0（`DELIVER-SPEC 判 18 项 红=0`），
  但"像人"这件事它判不了：`→` 有 **1,632 处**、`⇒` 有 **2,695 处**，
  这个密度本身就是"不像人写"的观感来源。

## 2. 红项分类（改写契约用的同一套编号）

| 编号 | 症状 | 为什么伤评委的阅读 | 处置 |
| --- | --- | --- | --- |
| R1 | 墙钟时刻做叙述（"从 04:18:27 到 04:37:57 共 19 分 30 秒"） | 时刻对别人没有信息量，只有时长有；看起来像日志倾倒 | 正文删时刻留时长；原始记录件不动 |
| R2 | rNN 轮次号当主语（"r87 那一跑""r121 实测"） | 评委不知道 rNN 是什么，只能猜这是内部版本号 | 改角色说法（"当前板上这一版"）；路径字面量与 md5 身份行保留 |
| R3 | 自我指涉（"这一版不作全绿说法""未检查不等于满足""本会话打开核对"） | 像在跟想象中的对手辩护，不像在陈述事实 | 换成中性事实句，保留同样的诚实度 |
| R4 | 内部黑话（尺子/判红/改口/定版/冻结件/快车道/地板/门禁 24 项） | 完全读不懂，且一眼看出是协作工具术语 | 换通用说法并首次出现解释一次 |
| R5 | 对赛题条文的辩解句（"指南推荐 2026.1，本工程……"） | 把"我符合条件吗"的焦虑写在正文里 | 只陈述自己用了什么、能否复现；条文对照留在 checklist 件 |
| R6 | 免责与凭据堆叠（一个数字后面三个凭据、连续括号） | 密度过高，读两句就累 | 一个数字留一个主凭据，其余归到该节凭据一览 |
| R7 | 顺序失衡（开头 30 行还在讲工具版本） | 3 分钟内看不到"这系统做什么" | 重排为：是什么 → 怎么跑 → 数字 → 限制 |

## 3. 计数口径（能被复算，不是感觉）

脚本：`doc_audit_20261005/baseline_counts.sh`（在 `b65a191` 干净树执行）。
范围＝`git ls-files '*.md'` 去掉 `report/log/`、`build/evidence/`、`docs/walkthrough/`。
R2 的匹配式要求 rNN 两侧不接字母数字下划线或斜杠点，因此排除 `build/r118_gates.txt` 这类路径；
R1 与 R7 跳过围栏代码块。人称/程度副词的 59 处是**裸 grep** 计数，
比 C7 的口径宽（C7 豁免代码块、引号、表格状态格，实测 0），两者不可互换引用。

## 3b. 最刺眼的一条：内部台账编号（这条我没让代理动，等你定）

叙述件里裸写的 `#NNN` 共 **2,009 处**，其中 **130 行**明确写成 `ISSUES #NNN`，散布在 **52 份文件**。
它们指向的是 `report/log/issues.md`（1.3 万行）里的台账条目，而那本台账虽然随包，
但正文没有任何一处告诉读者"编号 #335 在说什么"。这是"一眼看出机器参与"的最强信号，
比时间点叙事更伤：

- 时间点（R1）删掉就干净了，编号删掉会**丢凭据**——它们是真的失败记录。
- 建议的修法是**指路而不是删除**：把 `（ISSUES #335）` 换成
  `（失败分析见 report/60-failure-analysis.md 第 X 节；台账条目 #335）`，
  或至少在 README 目录导览里加一句"`report/log/issues.md` 是过程台账，正文里的 `#NNN` 指它的条目号"。
- 这是一次跨 52 份文件的批量改写，风险与收益都要你判断，所以本轮**没做**，只把数报给你。
- 同一口径的还有：`⇒` 2,695 处、`→` 1,632 处（第 6 节第 3 条）。

## 3c. 一条比风格更要紧的：交付文档引用了**从未入库**的文件

今夜为改写建的 worktree 是 `b65a191` 的干净检出，一致性检查在里面报出
`C3 文档内路径存活 … 检查路径引用=686 死引用=7`，例：`report/claims-vs-evidence.md → board/uart_script_capture.txt`、
`report/reproduce/README.md → board/uart_script_capture.txt`。逐条查明原因（同一命令在主仓库跑不红）：

| 被点名的文件 | 主仓库盘上 | worktree | 是否被 git 跟踪 |
| --- | --- | --- | --- |
| `board/uart_script_capture.txt` | 在 | **不在** | 未跟踪 |
| `board/HANDS_ON.md` | 在 | **不在** | 未跟踪 |

⇒ 这不是改写造成的，是**仓库自身的洞**：只要评委 `git clone` 后照着文档找文件，就会撞上死链，
而这些恰恰是最有说服力的两件证据（动手记录与串口原始回显）。
两种修法都requires你点头：① 把这两件（以及同类未跟踪证据）纳入版本控制；
② 保留不入库，把文档里的指路改成"本地留档，不随包"同行声明（导出器那套词表就认这个）。
今夜的处理：改写版沿用②的声明形式，保证 worktree 里的自检不因我而红。

## 3d. 最重的文件（同一匹配式，逐文件计数，2026-10-05 夜实测）

| 文件 | 轮次号叙述 | 钟点行 | `⇒` | 本轮处置 |
| --- | --- | --- | --- | --- |
| `build/runs/ledger.md` | 202 | 7 | 172 | 未改（属过程记录件，建议保留原样并标成"不必通读"） |
| `report/optimization_log.md` | 143 | — | 101 | 未改（本轮排队在后面，见第 4 节覆盖面） |
| `report/known_issues.md` | 100 | — | 125 | 改写中 |
| `report/40-optimization.md` | 88 | — | — | 改写中 |
| `build/runs/decisions.md` | 68 | — | — | 未改（过程记录件） |
| `board/signoff.md` | 55 | — | — | 改写中 |
| `report/50-results.md` | 54 | — | — | 改写中 |
| `report/perf_report.md` | 52 | — | — | 改写中 |
| `report/measurements.md` | 39 | — | — | 改写中 |
| `board/acceptance.md` | 38 | — | — | 改写中 |
| `report/timing_global.md` | 36 | — | 47 | 改写中 |
| `report/90-open-items.md` | 34 | 23 | 169 | 改写中 |
| `report/collaboration/sessions/s05-2026-10-04-subagents.md` | — | 129 | — | 不改（协作记录件，时间戳就是它的证据；这是 R1 命中最重的一份，属"该随包但不该排在评委阅读路径上"） |
| `build/provenance.md` | — | 31 | — | 未改（凭据盖戳件，时间戳即数据） |

一句判断：**钟点行最集中的其实不是 README，而是协作记录与凭据盖戳件**——那些地方时间戳是证据本身，
不该动；要动的是 README／报告正文／签收表这些"叙述件"。这与你的直觉一致，只是射程要按件分类，
不能一刀切 grep 删除。

## 4. 本轮改写落点（按目录）

改写件都在 `delivery_review_20261005/`，每份都跑了 `check_docs.sh`
（钟点残留=0、C7 词不增加、带小数数字不减少、引用路径全部存在）。

_（本节在各批改写代理交回后由我逐份复算填写，未填即表示该目录本轮未改。）_

## 5. 我建议**不要**改的东西

- `data/measured/`、`board/evidence_r29|r41/`、`build/frozen_rNN_*/manifest.md`、
  `build/runs/`、`report/log/` 里的时间戳与轮次号是**数据本身**，改了等于篡改凭据。
- `report/interface-table.md`（1,509 行）是机器可读契约表，正文说明留给
  `docs/walkthrough/interface-contract.md`，表本身别动。
- 表格第一列被标注"会被机器读"的行：D6/metric_recheck 按行名与数值匹配，改措辞就会红。
- 唯一未通过项（发布前检查里的 C5c 那一条）与全部被判负的优化方案必须留在文档里。

## 6. 需要你明天拍的三块板（我没替你决定）

1. **器件声明**：正文只写实际用的 `xc7z020clg484-2`（板上 CLG484 模块，速度等级 2），
   不再提指南给的 `xc7z020clg400-1`？还是保留一句"与指南建议件封装不同，约束按实际板子原理图给"？
   本轮改写按"中性陈述、不辩解"处理，但两种写法都合规，取决于你想不想主动交代差异。
2. **`report/log/` 22,643 行台账随不随包**：它是"大模型协作"最硬的证据，也是"不像人"最集中的地方。
   建议保留但在 README 导览里明确标成"完整过程记录，不必通读"，评委路径指向
   `report/llm_collab.md`／`report/ai_collaboration.md`。要瘦身的话得另起一轮，
   **注意**：交付自检 C5 要求协作记录 ≥9 份、带单位数字的前后对比表 ≥30 张、含读数的失败条目 ≥8 份，
   删这些目录会直接把 C5 判红（本轮实测：对比表 45 张／失败读数 12 份／协作记录 11 份）。
3. **`⇒` 密度**：2,695 处。全换成"因为/所以/导致"是纯体力活且容易碰坏机器读的行，
   我这轮没动它，只在你每天都要看的 README 层收紧。要不要扩大到全部交付文档，你定。
4. **同一个数字写了两处**：`report/01`–`08` 是分章版，`report/*.md` 小写件是主题原件，两者都在包里。
   带小数的读数在分章版里出现的密度是 `04-resources.md` 60 个、`05-timing.md` 112 个、
   `08-limits.md` 53 个——而同一批数也在 `perf_report.md`／`data/metrics.csv`／`build/report/*.rpt` 里。
   两处各写一遍，下一轮改数时只要漏一张就自相矛盾（这台机器上真发生过：改 `metrics.csv` 没改首页四行）。
   两个选择：① 分章版只留导读，读数一律指向原件（改动小、口径稳）；② 把分章版从包里撤掉
   （但 C5 判据在数"带单位数字的前后对比表 ≥30 张"，撤文件会掉地板，撤前要先重算）。
5. **`report/README.md` 我今夜自己重写了**（原来是 AI 轮次交接件：出现"本轮只交两份""禁区"
   "同伴轮次并发写入""P18c 铁律 5""该行的读数写于重建之前"）。新版是"哪一格由哪份文件负责＋
   还欠什么"的对照表与四条阅读路径，所有路径都过了存在性检查（`check_docs.sh` 四类计数全绿，
   正对照见第 8 节）。这是我按自己那份契约做的样例，你若认可，其余文档就照这个口径继续。

## 7. 学习资料（`docs/walkthrough/`，不入库、不进包）

按 `11-walkthrough-learning-doc.md` 的规范续写；导出器已用 `HARD_DROP_RE` 把 `^docs/walkthrough/`
剪在包外（`build/make_submission.sh:68`，实测过），"学习文档不上传"这条由导出器而不是由我记得。
本轮新增篇目与 W1–W16 实跑计数记在第 4 节末尾。

## 8. 我今夜动过的尺子（改判据必须有对照）

`doc_audit_20261005/check_docs.sh`（四类计数：钟点残留／人称与程度副词／量数是否减少／引用是否存在）：

- 第一版把条文号当量数算，`report/README.md` 报了 7 个"丢数"（全是 `3.3.5.3`、`§4.3` 这类引用）。
  修正口径：先抹掉三段以上点号串、`§x.y`、`第 x.y 节`，再取数。
- 修正后加了**正对照**：一段文本里真删掉 `0.739` 时，脚本必须报出 `0.739@1`（实测照出来，判红）。
- 死链豁免用的是导出器同一套词表（`不随包／本地留档／不入库／未写／未落地／尚未／规划／待装配／不存在`），
  并配**能红对照**：同一条不存在的 `report/zz_not_there.md`，带"（不随包）"⇒ 死链 0／豁免 1，
  不带 ⇒ 死链 1／豁免 0。豁免数每行照打，防止整把尺子被一句话买通。

## 9. 改写有没有把可复现性改坏（我自己复跑的对照，不采信代理的话）

同一把尺子 `node src/host/line_cite_check.mjs`（D5：文档里的 `文件:行` 引用是否真指得到）：

| 跑的树 | 份数 | 硬错 | 锚点命中 | 判定 |
| --- | --- | --- | --- | --- |
| 主仓库 `b65a191`（未改） | 233 | **0** | 878 | D5: CLEAN |
| review worktree（已落 10 份改写） | 221 | **0** | 589 | D5: CLEAN |

份数差 12 是 worktree 里没有未跟踪件；命中数随份数同步下降，硬错两边都是 0
⇒ 到这一步，改写没有引入任何坏引用。交付自检 18 项在 worktree 起点（`b65a191`）实测就是红=0，
每批交回后重跑，因我改出来的红当场处理或写回本节。

另一条已完成的自主核对：`code-reading.md` 的 8 段引用与源文件**逐字一致**
（`node doc_audit_20261005/w13_diff.mjs docs/walkthrough/code-reading.md` 实跑 `8/8 PASS`；
正对照：故意改坏一行 ⇒ `片段核对 8/8，不一致 1 个 FAIL`，证明这把尺有牙）。

## 10. 两把尺子在两棵树里的差（既存红与"没有牙"的判据，都不是本轮改出来的）

`node build/checks/check_repo_consistency.mjs` 在主仓库（有未跟踪件）与 worktree（干净检出）各跑一遍：

| 判据 | 主仓库 | worktree | 归因 |
| --- | --- | --- | --- |
| C3 文档内路径存活 | 688 引用／死引用 0 PASS | 686 引用／死引用 7 FAIL | 差的 7 条指向 `board/HANDS_ON.md`、`board/uart_script_capture.txt` 等盘上有、库里没有的件（第 3c 节） |
| C9 复现演练 | PASS=92 FAIL=30 未测=32 | PASS=92 FAIL=30 未测=32 | 两棵树逐数相同 ⇒ 既存红，与改写无关；但 30 条演练不过这件事本身要处理 |
| C12 技能包门禁 | 绿 9 红 0 PASS | 绿 8 红 1 FAIL | worktree 少一份未跟踪输入 ⇒ 同一类洞 |
| C5 许可与卫生机检 | 被调脚本 300 s 未返回 ⇒ NOT_MEASURED | 同 | 工具欠账（台账 #339 末段已记） |
| C7 验证状态三处一致 | 对=0 冲突=0 ⇒ NOT_MEASURED | 同 | 这条判据一次比较都没做（对=0）：找不到可比的行，它的"绿"是空的 |

结论：本轮改写至今没让任何判据从绿变红；但仓库自带的这两套尺子各有洞（C7 没有牙、C5 超时未测、
C9 有 30 条既存红），推送前要么一起看，要么在文档里说清"交付自检 18 项"覆盖的是哪一套。

## 11. 三条比风格更要命的发现（我自己复验过，不是抄代理的话）

1. **清单里有一行写着"存在且可读"，而那个目录根本不存在。**
   `report/submission-checklist.md:24` 的第 16 行写 `技能包验证记录 | skills/evals/ … | PASS（存在且可读）`，
   实测 `test -e skills/evals` ⇒ **N**；同一行还写"各条目 §7 多数仍是【待验证】"，
   所以这不是笔误，是**技能包重建后旧的 PASS 没跟着改口**。评委抽查这一条就会撞见假 PASS，比文风问题都伤。
2. **`report/ai_collaboration.md` 点名 11 条不存在的技能条目路径**
   （`skills/pitfalls/arbiter-pending-pulse/SKILL.md` 等，逐条 `test -e` 复验为缺）。
   条目在 `c7b325f` 重建时换了名字，协作记录没跟着换 ⇒ 需要一次"按现名重指"或改成类别名。
3. **9 份交付正文里写着本机绝对路径**，含带用户名的 `C:/Users/wenqu/…`
   （命中 `report/timing/a1_sources.md:41`、`report/timing/debt_ledger.md:56,147,155`、
   `report/timing/rgmii_window_model.md:61,87,147`、`report/timing/README.md:13`、`board/signoff.md:36`）。
   其中 `report/timing/README.md:13` 那行写的是"仓库根目录 = `D:/Xilinx/Prj/pro/Video_Processing`"，
   本来就该写"`git rev-parse --show-toplevel` 现取"。

为什么自家尺子没抓到：`C3 文档内路径存活` 在主仓库实测 `死引用=0`，但它对**无扩展名的目录形引用**
（`skills/evals/`）与代码跨度里的路径不敏感（它自己打印的"豁免=碎片66"就是这一类）⇒ 这是判据射程的洞。
补判据要单独一轮，今夜没动这把尺。

## 12. 扫描代理建议"整篇不随包"的清单，以及撤之前必须看的三条地板

只读扫描的结论在 `doc_audit_20261005/findings_sweep.md`（414 行）。它建议撤下：
`report/optimization_log.md`(1053 行)、`report/timing/`(14 篇)、`build/runs/`(2 篇)、
`build/rNN_*` 计划与采用清单(16 篇)、`build/frozen_r51–r62/manifest.md`(12 篇)、`report/run-queue.md`、
`report/unattended.md`、`report/questions-for-team*.md`、`report/collaboration/sessions/`(5 篇)、
`board/signoff-questions.md`、`report/log/` 整目录(12 篇)。

撤之前先看交付自检 C5 的三条地板（今夜实测在 worktree 里打印）：**带单位数字的前后对比表 ≥30 张（现 45）／
含失败读数的否决条目 ≥8 份（现 12）／协作记录文件 ≥9 份（现 11）**。
`report/collaboration/sessions/` 是 5 份，撤掉剩 6 < 9 ⇒ 直接判红；`report/timing/` 与 `optimization_log.md`
装着大量对比表，撤掉会把 45 张拉到地板附近。所以这不是"删了更干净"，而是**一次要先重算 C5 地板的改动**。
`report/90-open-items.md` 我建议留（它就是失败分析与未决项的集中表），但要清掉其中 82 处`【填入】`、
79 处`待验证`、60 条死路径——这一份今夜派给了改写批次。

## 13. 绝对路径这一条今夜已经修了（附例外）

工具：`doc_audit_20261005/deabs.mjs`（默认干跑，`--apply` 才写；**只替换前缀，文件名与子路径原样留着**，
免得把"哪一份手册"这个信息一起删掉）。实跑：命中 15 处、涉及 9 份文件，改完后
交付正文里 `D:/Xilinx` 与 `C:/Users` 的命中数为 **0**；两把尺复跑仍是 `D5: CLEAN（硬错 0）`
与 `DELIVER-SPEC 判 18 项 红=0`。

**一处必须留回原样**：`board/signoff.md:45` 那行是**串口与 hw_server 回显的原文引用**
（`PROGRAMMED xc7z020_1 <- D:/Xilinx/Prj/pro/Video_Processing/build/system.bit`）。
被引原文是证据，改了就是伪造记录，所以脚本扫过之后我把它逐字改回去了。
⇒ 规则：绝对路径只从**作者自己的话**里删，引号/代码块里的工具回显不动。
`report/timing/README.md:13` 那一行也单独处理：仓库根不写死盘上位置，改成
"由 `git rev-parse --show-toplevel` 现取"。

未纳入本轮的两处：`report/log/`（12 篇）与 `build/runs/`（2 篇）里的绝对路径没动——
它们是过程台账，第 12 节关于"随不随包"的决定会连着它们一起定，先不单独剃。

## 14. 读代码读出来的 5 处"文档说的和代码不一样"（写学习文档时顺手抓到，全部未改）

这些是评委抽查代码时最容易抓的错，也是本仓库自己没发现的老问题：

1. `src/rtl/video/split_ctrl.v:3` 的头注释自称"没有被任何顶层例化"，实际例化在
   `src/rtl/top/pl_video_top.v:885-891` ⇒ 注释是过时的，模块是活的。
2. `src/rtl/video/split_display.v:2-3` 还写 `Dual-pane`，而 `pl_video_top.v:241` 的 `left_pane`
   只剩调试用途 ⇒ 双窗叙述与单视口实现不一致。
3. `report/04-resources.md:58-59` 把 `raw_line_delay` 归成 LUT-RAM，
   `build/report/methodology.rpt:2210-2230` 明写它 `implemented as a RAM block`
   （分布式那 336 件全部属于 blur/sharp/sobel/morph 的行缓）⇒ 资源归因写错了一类。
4. `src/host/video_sender.py:12` 引 67.86 % BRAM 与 `src/rtl/process/proc_pipeline.v:82` 的分母 7936
   都与当前报告（68.21 %、8188 FF）不同轮 ⇒ 脚本注释里的数是旧版的。
5. `_sources.md` 与既有正文里的 `skill/xxx.md` 形式路径在树里不存在（现目录是 `skills/…/SKILL.md`）
   ⇒ 学习文档侧也有一批旧名指路。

一句判断：第 1、2、3 条是**事实错**（该改代码注释或报告），第 4 条是**陈旧数**（该按现报告改或注明轮次），
第 5 条是**改名残留**。都不在今夜授权范围内（会动 `src/rtl` 注释与 `report/04` 的资源归因），列给你定。

## 15. 今夜自己引入的回归与它的修法（记下来免得明天再踩）

段落重排会挪走行号：`node doc_audit_20261005/mdcite_drift.mjs` 实测
"查 173 条指向本轮改写件的 `.md:NN` 引用，需重指 150 条"，而 D5 那把尺只看代码文件行号，
对 `.md` 互引不判红 ⇒ 机器侧完全无感。对策两条：① 引用写成"节名指路"（不随排版漂）；
② 必须留行号时，用 `mdcite_fix.mjs` 按"基线那一行的原文在新版里现在第几行"重指，
唯一命中才改号，多候选或找不到的进人工清单，不猜。

## 16. 分章版与原件的读数冲突清单（8 组，值一律未改，等你裁决）

这正是第 6 节第 4 条担心的事——同一个数写两处，改一侧漏另一侧。改写批次把它们的差异逐组对了出来，
**没有动任何一个数字**：

| # | 冲突位置 | 两边各说什么 |
|---|---|---|
| 1 | `report/07-skill-distillation.md:45` ↔ `report/60-failure-analysis.md:305-308`、`report/70-reproduce.md:202` | 章里把技能包旧 `gates.mjs` 首轮写成"G1 违规=13、G6 越界=3、G8 死链=4，四条可复现"；原件写"判定 12 项 绿 9 红 2 未测 1，红在 G2 与 G10" ⇒ 到底是 4 红还是 2 红＋1 未测、13 挂 G1 还是 G2；`G6=3`、`G8=4` 全仓只有 07 一处 |
| 2 | `report/07-skill-distillation.md:46-47` ↔ `report/claims-vs-evidence.md:86` ↔ `report/90-open-items.md:419` | 同一格三处口径打架：章里 `NOT_MEASURED`（脚本不在盘上）、对照件判 FAIL（`run-all-checks.mjs 判 40 项 pass=6`）、待办表又记 NOT_MEASURED；索引行数一处 49 一处 50 |
| 3 | `report/07-skill-distillation.md:13-18` ↔ `skills/` 实际结构 | 章里 6 个条目路径盘上不存在（现役是 `ruler-fake-greens`、`tcl-and-probe-traps`、`synthesis-report-bottleneck` 等）⇒ 只在表头注明"重建前的旧条目名"，没有逐条映射（无证据支持一一对应） |
| 4 | `report/04-resources.md:66-68` ↔ `build/power.rpt` | 章（照 `data/metrics.csv:27`）说功耗格"未随当前位流重取"，但现件报告头与 `timing_summary.rpt` 同一批（04:37:48 对 04:37:30），数值反而一致 ⇒ 轮次标签不同源（待办 #20 已登记，状态"需批准"） |
| 5 | `report/04-resources.md:70-71` ↔ `data/metrics.csv:29` | 同章并列的两个"板上"读数来自两块位流（XADC 行标 r113 `b94f4da6cdff`，WNS 行标 r118 `cd04907e1369`）；另 `metrics.csv:28` 的 Max Ambient 57.5 ℃ 对 `build/power.rpt:39` 的 57.4 |
| 6 | `report/rotation_and_effects.md:12-13` ↔ `architecture.md` 缩放表／`metrics.csv:18`／`src/rtl/process/zoom/zoom_ctrl.v:1-8` | "右屏缩放 1.0×（最大）↔0.5× 循环"与八档 0.25–2.00 冲突；"效果五级"少了 sharpen 与 erode/dilate（原件是"级 0 gamma ＋级 1..5 共八个算法"） |
| 7 | `report/rotation_and_effects.md:93-94` ↔ `report/commands.md:85-99` 与 `src/host/ps/main.c` | 五位开关字 `10000`/`00111` 被当可用命令列出；原件说九位 `stage_sel` 才是口径、五位是老位序会被拒 |
| 8 | `report/perf_report.md` §10.2 ↔ `report/04-resources.md:11-22` | V6.3 历史表（+0.675/+0.053/111287/52687=49.52 %/138.5=98.93 %）与现值表（0.739/0.052/51135/8188=7.70 %/95.5=68.21 %）**点名同一对现件** `build/timing_summary.rpt`、`utilization.rpt` ⇒ 指路歧义，虽表头已声明"不要当当前值引用" |

裁决方式建议二选一，都只需一次改口：**(a)** 分章版只留导读，读数一律改成指向原件；
**(b)** 保留双写，但给 `src/host/metric_recheck.mjs` 加一条"分章版这一格必须等于它点名的原件这一格"的判据
（现在这把尺只看 `data/metrics.csv` 与三份报告，看不到 `01`–`08`）。选 (b) 要多写一条判据与它的能红对照，
好处是把"下一轮改数漏改一处"变成机器能抓的红，而不是靠人记得。

## 17. 终检数（同一棵树量的，2026-10-05 清晨）与一处我自己的判断更正

`check_docs.sh` 现在按 `b65a191..` 取范围、三态判定，并且**死链维度两边都用干净检出比**
（基线取 `git archive b65a191 | tar -x -C /tmp/base_clean`）。同一棵树量出来的结果：

```
check_docs 判 65 个文件：回归红 0，既存(与基线同数) 16  PASS
DELIVER-SPEC 判 18 项 跟踪文件=3657 红=0 未测=0 PASS
D5: CLEAN（硬错 0）   metric_recheck 判 117 个数 红 0（首页层 63 个、解析到 10/10 行）   D1c 空转=0
```

⇒ **本轮改写没有引入任何回归**（钟点、人称/程度副词、量数、死链四个维度都比基线好或持平）。
先前我报的"回归红 6"是度量错误：基线取了带未跟踪件的主工作树、改写版取了干净检出，
那 5 条"新增死链"（`board/uart_script_capture.txt`、`build/evidence/r116_board/sender_live.log`、
`build/evidence/r116_board/cycle_r114back.log`、`build/r90_jtag_scan.log`）全部来自**从未入库**的盘上文件——
也就是第 3c 节那个洞，不是这轮改出来的。

更正一条我早前说错的话：我曾把 `report/acceptance-recipes.md:111` 里的
`build/evidence/rNN_serial_raw.txt` 判成"真文本瑕疵"。读了上下文才确认那是**故意的占位写法**，
同文件第 149 行还把它列为"失效条件"（带通配符或占位的写法不算指路）。所以那一条不改，
要改的是我的尺子：占位形（含 `rNN`、`<本轮>`、`*`）应当从"路径引用"里排除，而不是当死链。
这也再次验证那条老规矩：**grep 命中不是结论，得读那一行在说什么。**
随后我把这条判断落进尺子本身：`check_docs.sh` 现在跳过占位/通配写法（`rNN`、`<本轮>`、`*`、`{a,b}`）
不再当死链，两条对照都跑过——真死链仍然数得到（`build/r109_adoption_checklist.md 死链 3→3`），
占位形不再误报（`report/acceptance-recipes.md 死链 2→1`，剩下的 1 条是未入库的 `board/uart_script_capture.txt`）；
`report/05-timing.md 钟点 1→0` 也证明钟点维度确实在测东西。

16 条既存按维度分：原始记录件与台账件里的时间戳（`report/log/issues.md` 30 行、`build/runs/ledger.md` 7 行、
`board/conditions/card-board-serial-and-jtag.md` 1 行等）、指向未入库证据件的死链（同一 3c 类）、
以及还没轮到改写的 `report/90-open-items.md`（钟点 20、C7 词 71 与基线同数）。它们不是"没问题"，
而是"不是本轮弄坏的"——处置办法在第 6 节第 2 条与第 12 节。

## 18. 覆盖面：审了多少、改了多少（这两个数不要混）

- **审**：`git ls-files '*.md'` 去掉 `report/log/`、`build/evidence/`、`docs/walkthrough/` 后 **220 份**，
  全部进入计数与只读扫描（`findings_sweep.md` 覆盖 skills/board/build/data/report 的其余部分）。
- **改**：**66 份**（本报告第 4 节与 `CHANGES.md` 的口径）。剩下 **154 份未动**，
  它们的钟点行合计 **260 行**——绝大多数在 `build/rNN_*`、`build/frozen_rNN/manifest.md`、
  `data/measured/`、`board/evidence_*`、`report/timing/`、`report/collaboration/sessions/` 这些
  **记录件**里（按第 5 节"不该改"的判断，那是数据本身），未动 ≠ 待办。
- 未动件里确实还剩少量"叙述件"，明早值得优先补的是：`report/build-notes.md`、`report/bench_mutation.md`、
  `report/board_pins.md`、`build/provenance.md`、`build/coverage.md`、`data/golden/README.md`
  （`data/measured/*` 是量测记录，别动）。
- 这份差异是范围决定，不是遗漏：一夜之间把 220 份都改一遍的风险（碰坏机器读的行、丢数、引号里的原话被润色）
  远大于收益，所以顺序是"评委一定会翻的先改 + 全量先审"。

## 19. 门禁第 18 项从红到绿：29 条过期指路的三分类（2026-10-05 03:5x）

现跑口径（干净检出的 worktree，评审拿到的就是这一棵树）：

```bash
cd delivery_review_20261005 && node src/host/doc_currency_check.mjs   # 改前 rc=1，29 条
```

逐条读完后分三类，**只有第三类该改文档**：

| 类别 | 条数 | 处置 |
|---|---|---|
| 尺子的射程错（把真实存在的跟踪件看成死链） | 11 | 改 `src/host/doc_currency_check.mjs`：`CITE_ART` 原来在第一个凭据扩展名处收口，于是 `build/parsed/parsed_cdc.rpt.json` 被截成 `…parsed_cdc.rpt`、`board/firmware/ps_app.elf.md` 被截成 `…ps_app.elf`，拿去查盘当然查不到。现在按**整名**查。另：围栏内是工具原文回显，作者不能往别人打印的行里塞声明 ⇒ D4c 在围栏内降级为只报数并打印条数（本轮 10 条）；D4a/D4b 在围栏内照旧判红 |
| 豁免词表两家不一样 | 2 | `doc_currency` 的同行词表补 `不入库`、`本地留档` 两词（取自导出器 `SKIP_RE`），两把尺子共用一套话术；仍要求**同一行**，放行条数照打 |
| 真指路错 | 16 | 逐条改到落点：`build/r103_program_pl.log`→`.txt`；`known_issues` §1 的复现命令改仓库名 `tb_v98_top_seam`（包内名另注）；`docs/` 这层已不存在的 7 处改现名或写成带空格的叙事；二进制/捕获/`*.log` 同行补真话声明；"这个名字不在仓库里"不再写成一条死路径；未落盘的汇总件不再写成路径 |

每条新降级都配了**能红的一半**（`--self` 现跑新增两条对照全过：围栏外照旧红；链式扩展名不存在时照旧红）。
终态：`CURRENCY: 干净`（rc=0），`bash build/gates.sh` 判 24 项 = 23 绿 / 1 红，唯一红仍是声明过的 C5c。

## 20. 改名波把一份承重凭据的绑定悄悄弄断了（既存，本轮量到并修）

`git show b65a191:build/tb_v98_report.txt` 头部钉 `tb_md5=1c918c92200f`，而**当前树**里
`bash build/rtl_fingerprint.sh sim/tb_v98_top_seam.v` 现算是 `3be1b13e1c2c`。差别的来源不是设计：
改名波（`skill/`→`skills/`）动过这支台架的**两行注释**（`git show fbf624d -- sim/tb_v98_top_seam.v`：4 行了 2 处），
内容指纹因此移动，而被跟踪的报告没随之重盖 ⇒ 门禁第 15 项按"认 md5"的规矩会把这份 PASS 判成
"报告与当前台架不是同一次跑"。本轮 21:23 在这棵树上重跑过该台架（`prov.txt` 由 `run_one.sh` 在编译前落），
正文与旧报告**逐字节相同**（diff 只有头部一行），所以是把出处对回真实的一次跑，不是桥接、不是放行。
`build/tb_edge_rim_r118.txt` 的三枚指纹实测与树一致，未受影响。

⇒ 可复用的教训：**注释与文档字符串也是内容指纹的一部分**，任何"只动注释"的批量改名轮都要问一句
"哪些被跟踪的凭据头部钉着这个文件的 md5"。

## 21. 学习目录（不入库）里改名波的残留

`docs/walkthrough/` 写于改名波之前，读者照着打开会撞空：`report/ARCHITECTURE.md` 这类大写名、
`src/ps/main.c`（现在 `src/host/ps/main.c`）、`skill/`（现在 `skills/`）、`build/gates.sh:46`
（身份行现在 `:50-52`）。`fix_learn_paths.mjs` 只在**目标确实存在**时改，10 份文件命中；
复测残留 0。`_sources.md`/`_progress.md` 里"当时 `ls skill/pitfalls` 不存在"那类观察记录原样保留——
那是历史事实，改它等于伪造记录。README 第 6 节那份"5 篇未开始"的名单也换成了当前口径
（15 篇全在盘上 + 逐篇还欠什么）。

## 22. 我自己用错命令造出来的一条假红（记下来，免得下一个人当回归）

终检时我跑 `node skills/_meta/check-skill-package.mjs`（**不带参数**），末行 `判 154 项：条目=150 索引=0 红=5 FAIL`。
读了脚本第 17 行才看清：ROOT 由 `process.argv[2] || dirname(resolve('.'))/..` 推出来，
不带参数时它是**从当前工作目录的再上一层**取射程，于是把 `Prj/` 下的兄弟目录
（`.sub_stage/`、`submission/`、`final_submission/` 以及本轮的 `delivery_review_20261005/`）一起当技能包扫。

现跑正确的调用法（交付文档教的正是这一条：`report/70-reproduce.md` 第 5.9 行、`report/60-failure-analysis.md` 判别方法那行）：

```
node skills/_meta/check-skill-package.mjs skills
F1 条目数地板 实读=49 地板=20 PASS
判 53 项：条目=49 索引=50 红=0 未测=0 PASS
```

⇒ 两条结论：① 本轮**没有**技能包侧回归，红是我用错命令造成的；② 这把尺子的**无参默认是个陷阱**——
它会安静地判"我旁边的目录"。要收掉有两条路，都留给队伍定：把参数写成必需（缺参就 REFUSE 并打印该传什么），
或在 `skills/README.md` 里把"必须带 `skills` 参数"写成一句显式口径。本轮没动这个工具。

## 23. 一条"只在我这台机器绿"的黄金对照（C12 那一红，已收）

终检时 `build/checks/check_repo_consistency.mjs` 的 C12（技能包门禁）在干净检出里报红，落点是
`skills/scripts/contract-to-host` 的 **S1 黄金一致**：`相符=0/3`（主工作树里同一条是 `3/3 PASS`）。
逐层量下来：

| 测的东西 | 主工作树 | 干净检出（本轮 worktree） | 新 detached worktree（改属性后） |
|---|---|---|---|
| 输入夹具 `fixtures/contract.csv` | `i/lf w/lf` md5 `247807da…` | `i/lf w/crlf` md5 `2f014537…` | `i/lf w/lf` md5 `247807da…` |
| 三份 expected | 与右两棵逐字节相同 | 同左 | 同左 |
| S1 相符 | 3/3 PASS | **0/3 FAIL** | 3/3 PASS |

机制：`*.csv` 没列进 `.gitattributes` 的 `eol=lf` 名单，`core.autocrlf=true` 之下 checkout 把 blob
（LF）在磁盘上写成 CRLF，而 gen.mjs 的契约 digest 与产物是按磁盘字节算的 ⇒ 三份逐字节全不符。
也就是说**这条绿只在"那份 csv 从没被重新 checkout 过"的工作树里存在**，评委 fresh clone 必红。
修法是给夹具单独钉属性（`skills/**/fixtures/*.csv text eol=lf`），不碰 `data/*.csv`——那族的凭据
按磁盘字节盖过指纹，动它要先一起改盖章口径（台账 #202 同族，`.gitattributes` 尾注已写）。
笔 `1fbf2f8`；改后 `run-all-checks` 判 9 项 红=0。

⚠ 我自测的一次读错：我一度用 `grep -c $'\r'` 读那份夹具，打印"CR 行数=9"并以为属性没生效。
真实形状由 `git ls-files --eol` 给出（`w/lf` / `w/crlf`），而且那个"9"其实是**文件的行数**——
参数在那个 shell 里退化成了匹配任意行的式子。⇒ 量换行符要用 `git ls-files --eol`，不要用 grep 数行数。

C1–C12 的对照口径（两棵树现跑，判定 12 项）：主工作树 `绿=9 红=1 未测=2`，红是 C9（复现演练）；
本轮 worktree 在 C12 收口前是 `绿=7 红=3 未测=2`。两条 未测 是 C5（许可机检的被调脚本 300 s 未返回）
与 C7（对=0 的空集）——两种都不是"干净"，只是"没判成"。C9 的 FAIL 计数 30→31 的差来自
干净检出里跑不到的步骤（构建产物与板），不是本轮改坏的。

## 24. C3 与 doc_currency 是两套豁免词表：同一条指路一边放行、一边判红（本轮未合，记清）

干净检出里 `node build/checks/check_repo_consistency.mjs` 的 C3 报 `死引用=7`（判红），
而 `node src/host/doc_currency_check.mjs` 同一棵树报 `CURRENCY: 干净`。两边看的对象是同一批行：
`board/uart_script_capture.txt`、`build/evidence/*.log` 这类**真实存在但按设计不进 git**的凭据，
同行写了"不入库/已被 `.gitignore` 挡住"。差别在豁免机制：

- `doc_currency` 有 `NOSHIP_MARK`（同一行声明 ⇒ 降级为只报数，条数打印）；
- `C3` 只有**分支式**豁免（碎片${skipFrag}/运行期${skipRun}/台账${skipLedger}），没有"同行声明"这一支。

⇒ 这就是 #222 说的那一族的另一半：两把尺子两套话术，必然出现"一边放行一边红"。
本轮**没有**动 C3——给它加豁免得同时补它自己的能红对照（同行有声明不红／同行没声明必须红／
隔行不算），而那需要在 C3 的 `--self` 里加用例并整轮回归，不适合在收尾时段抢做。
最小做法（留给下一轮，一条命令能量）：`C3` 从 `src/host/doc_currency_check.mjs` 源码里读
`NOSHIP_MARK`（读不到就 REFUSE，fail-closed），命中同一行就计入 `skipShip` 并打印条数，
另加三条对照钉住它。

现状口径（两棵树现跑，判定 12 项）：主工作树 `绿=9 红=1 未测=2`（红=C9 复现演练）；
本轮 worktree `绿=8 红=2 未测=2`（红=C9 与 C3 那 7 条"不入库指路"）。两条 未测 都不是"干净"：
C5 的许可机检被调脚本 300 s 未返回；C7 是 `对=0` 的空集。

## 25. 学习目录指路终检：1999 条 0 死，但我自己的改路脚本先制造过一次假路径

`fix_learn_paths.mjs`（大写名/`src/ps`/`skill/`）之后又跑了 `fix_learn_paths2.mjs`（BSP 三件、
`sim/run_one.sh`→`build/sim/run_one.sh`、两张 CDC 卡）。后者把整串 `src/standalone/src/arm/cortexa9/xil_cache.c`
换成**带完整前缀**的 `vitis/…/bsp/libsrc/standalone/…`，而原文里那 18 处已经写成了
`vitis/…/bsp/lib` + `src/standalone/…` 的形式 ⇒ 拼出 `…/bsp/libvitis/…/libsrc/…` 这种不存在的串。
复扫（**带左边界**的式子：`(?:^|[^/\w.:-])(src|build|…)/…`）把它照出来了：14 份阅读章、指路 1999 条、
查不到 4 条 → 一条整串替换规则修 18 处 → **0 条**。

⇒ 三条可复用的口径：① 替换式必须"整串对整串"，不能假设原文里那段是独立的；② 指路扫描的正则**要有左边界**，
否则 `…/bsp/libsrc/sdps/…` 会被从中间的 `src/` 咬开而虚报（我这轮虚报了一次 26 条）；③ 数禁词要用"命中行数"
而不是"命中词次"：`grep -c` 报 1 行（README 那条列禁词的规则句）而我那把 node 式子报 6——六个词在同一行里。
终态：14 份阅读章禁词 0 处（只有规则句自己列出它们）；W16 双向 0 缺 0 孤儿；`w13_diff.mjs` 8/8 逐字一致；
`line_cite_check` 硬错 0。

## 26. 板子连上之后收的那两条红（C9 的量纲 + C3 的词表）与一次上板实测

**C9 的红是量纲错**：它数的是整篇 `report/repro-check.md` 里 ` PASS` / `FAIL` / `NOT_MEASURED` 的**出现次数**。
这份清单本来就要照抄期望值（例如顶层台架那一行的期望是 `RESULT tb_v98_top_seam FAIL nfail=1`——
公开保留的 C5c），于是"把已知缺陷如实写进期望栏"这一件事本身就永久判红。修法是**只读每行的判定列**
（末列），行射程 = `^[SABCM]\d+[a-z]?$`（登记用的 R* 与表头不进），判定列不成词单独计数并打印
（表形漂了要看得见），地板：判定列在内 ≥ 40 行才判，否则 NOT_MEASURED。
配了五支对照（`--self` 里 CTRL N..R）：期望栏的 FAIL 不算红、判定栏 FAIL 必须红、NOT_MEASURED 记未测、
不成词单独计、R* 与表头不进射程。

**C3 的红是两把尺子两套话术**：加第四支豁免"同行声明不随包"，词表**从 `src/host/doc_currency_check.mjs`
现读**（读不到 ⇒ C3 整项 NOT_MEASURED，fail-closed，绝不静默放行），放行条数打印。
配两支对照（CTRL K/L）：同一句写了声明只报数、没写声明必须红。
踩到的第二个坑：按逗号切词表会把"已被 `.gitignore` 挡住"（词里带反引号和空格）留成脏串 ⇒ 永不命中；
改为按单引号成对取词。

**上板实测（第三轮，写进 `report/repro-check.md` §9）**：`board_verify --self` 5/5；
`r116_bit_cycle.sh r118docround` 四步 rc 全 0、推流 50 s、两趟健康计数同值
（`eth_live=1 owner_eth=1 drop_words=0 pkt_err=0 cdc_episodes=0 stall_ms=0`，`frames_bad=1` 两趟同值——
**只登记读数不下结论**，本轮没做判别实验）；`board_verify --battery --geom --round=r118`：
geom `ok=10 fail=0`、电池 105 条 / 97.7 s、[TEMP] 三方对账 ok、跑完回到演示默认档、末行
`RESULT board_verify PASS（判红的步骤：0）`。

**同时修掉一处自己工具的问题**：`build/r116_bit_cycle.sh` 的摘要行把 `pkt_err/frames_bad/drop_seen` 打成 `?`——
它用正则扫 JSON 文本，反斜杠经过 bash 与 node 两层引号后退化成永不匹配的式子，而且 `drop_seen` 住在
`flags_bits` 下面。改成按对象取键、缺键打 `NA`，同一份 JSON 重放得到 `pkt_err=0 frames_bad=1 drop_seen=0`。
⇒ 又一次印证：**先看自己的工具，再怀疑被量对象**。

## 27. 一次"源码说没接、板子说接了"的实测（bilin），以及它推翻了我的第一判断

写视频稿时我照 `report/demo_script.md` 第 5 幕抄了 `bilin off/on`，然后去 `src/host/ps/main.c` 核——
第 1278 行明写 `if (ci_eq(tk[0],"BILIN")) { not_wired("bilin", …)}`，注释说"读口就位、串口开关待接"。
我据此判定第 5 幕演不成，准备在文档里加"待接"的警告。**改文档前先用板子问了一次**（COM6 空闲，四条命令 0.7 s 间隔）：

    >> bilin off
    [CTRL] AXI_GPIO=0x00035000 sel=000 thr=80 src=1 zoom=1 pub=0 bilin=0 osd=1
    [BILIN] bilin=off
    >> stat
    [STAT] ctrl thr=80 src=1 zoom=1 bilin=0 zsel=4 zman=1 pub=0 sd=1 frames=4398 playing=1 …
    >> bilin on
    [CTRL] AXI_GPIO=0x000B5000 … bilin=1 …
    [BILIN] bilin=on

⇒ 板上那份 ELF（`ps_app.elf` md5 `d0b07f84a068`）把 `bilin` **当成已接**：控制字第 15 位随命令翻转、
`stat` 的 `bilin=` 字段跟变。所以真实结论不是"第 5 幕演不成"，而是**源码与板上二进制在这一条上不一致**，
而本机没有 `arm-none-eabi-gcc` ⇒ 无法用重编来判定谁对（这条边界本来就在案：`report/known_issues.md` 里
app 不可重编那一族）。处置：不动第 5 幕（它对这块板子是真的），把"源码 not_wired / 板上已生效"的分歧
登记进 `report/known_issues.md`，等能重编 ELF 那一轮再收口。

教训两条：① **源码注释是断言，不是读数**——凡是"板上会怎样"的问题，串口还活着就先问一次板子；
② 我差点为了一条源码注释去改一份**本来正确**的交付文档，那正是本审计一直在防的"改文档迁就理解"。

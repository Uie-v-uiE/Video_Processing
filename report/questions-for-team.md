# 需要队伍回答的问题（P23 第 0/1 节：无人值守时 STOP 环节的去向）

口径：每条问题四件齐全 —— **为什么必须问人 / 不答会怎样 / 正文现在的占位 / 影响哪个评测项**。
正文里对应位置一律写 `【队伍未确认】`，本文件行数与正文 `【队伍未确认】` 计数由 P21 的 C8 核对。

各任务先把问题写进自己的 `docs/questions-for-team-p<nn>.md`，装配时合并到这里（避免多路并发追加同一个文件互相覆盖）。
合并后的编号规则：`Q-P<任务号>-<序号>`。

| 编号 | 问题（一句话） | 为什么必须问人 | 不答会怎样 | 正文占位在哪 |
| --- | --- | --- | --- | --- |
| Q-P13-1 | 是否允许单独开一轮"只加注释与文件头"的 `src/` 改动（会让全部行号下移，需先冻结 D5 行号引用） | 这是行为不变但引用大改的动作，历史上 docs→report 改名轮两次退回 | P13 的契约头覆盖率只能记 0%，逐文件现状照 `report/src-map.md` 登记（装配位 src-audit.md 未写） | `report/run-queue.md` 阻塞项 B1 |
| Q-P19-1 | 选题的真实出发点与你想解决的问题（一句话，按你的原话写） | P19 铁律 7：动机只能由队伍口述，agent 不许替你编 | 答案落在此刻承担"选题背景"那一格的 `report/background_and_novelty.md`（装配位 10-background.md 未写），立意一节未答前留空并标 `【队伍未确认】` | 见 `report/questions-for-team.md` |
| Q-P19-2 | 允许声称哪些维度的优势、创新点主张强度定到哪一档 | P23 第 0 节：无人值守时禁止产生"首次/首创/领先/唯一"，也不许替队伍定强度 | 主张清单落在此刻承担"创新点"那一格的 `report/background_and_novelty.md`（装配位 novelty-claims.md 未写），定档之前只能是"候选主张（未定稿）" | 同上 |
| Q-P16a-1 | 接线表与供电参数里 agent 读不到的项（外设供电、线材、限流） | P16a 铁律：接线类内容只能由队伍给，不许推测引脚/电压 | `board/hardware_setup.md` 对应行写 `【待你补】` 并进未决项 | 见 `report/questions-for-team.md` |
| Q-P20-1 | 根协议选 MIT 还是 Apache-2.0；开源仓库现在公开还是提交后公开 | P20 第 2 步第 2 问；影响专利条款表述与脱敏紧迫度 | `LICENSE` 暂不放全文，先登记候选与差异说明 | 见 `report/questions-for-team.md` |
| Q-P16c-1 | 哪些验收项必须你亲自签（眼睛/手感类） | 只有你能签；agent 代签等于伪造验收 | 需要人眼的项一律 `NOT_MEASURED` 并列出等你 | 见 `report/questions-for-team.md` |
| Q-P20-2 | 仓库里 814 份**工具产出原件**带着本机名（Vivado 报告头 `Host :`、仿真日志的临时绝对路径），怎么处理？（ISSUES #336 给了三选一：接受并说明理由 / 只对新产出脱敏 / 改写历史+强推收回） | 它们既是凭据本身（改了就断 md5 绑定与尺子的同源判定），又已在公开历史里——只有队伍能决定"证据完整性"与"主机信息最小化"哪个优先 | 现在按 (a) 处理：不动历史，新写文档已清零；若选 (b)/(c) 要重跑全部证据配对与门禁 | `report/log/issues.md` #336、`build/checks/check_repo_hygiene.sh` 的声明一致性一项 |
| Q-P21-1 | 交付快照以哪个 commit 为准、是否记录仓库哈希 | P21 第 3 步第 1 问 | 终审矩阵的"快照"一格留空 | 待 P21 开跑时写 |
| Q-P21-2 | 全仓跟踪路径里 **308 条含大写字母**（末段 266 + 中间段 45 − 两段都含 3；惯例名豁免 22 ⇒ 判据报违规 286），怎么处置？三选一：(a) 只改手写文档层并同步所有引用；(b) 连 `build/frozen_r*/MANIFEST.md` 一起改名并重建 md5 清单；(c) 保留现名，在目录对照表里逐条写明"条文点名（README/LICENSE/NOTICE/MANIFEST）"与"历史沿革" | 改名会动到 md5 绑定的冻结凭据与全部引用面，是连带影响大且不易回退的动作；赛题 3.3.5.4 要求文件名纯小写，但它自己给的推荐结构里也写着 `README.md`。**注意这一项会随交付继续变差**：本轮两笔提交新增的交付件自己就带来 61 条含大写路径 | C4 一直红着，终审矩阵里这一格只能写"已知缺口 + 待裁决" | `build/checks/check_repo_consistency.mjs` 的 C4 行、`report/log/issues.md` #337 与 #339 |
| Q-P21-3 | ~~`data/metrics.csv` 有 **6 行**指标没把数字指到存在的证据文件（C2）~~ **已由 #339 关闭为"尺子的量纲错"**：现跑 `C2 行=28 全指到=28 缺或无路径=0 PASS`。**剩下的真问题是同一张表内部自相矛盾**：第 20 行说端到端时延"待复测、不填数"，第 25 行却给 33.34 ms；27–28 行的轮次标签与 `57.5 vs 57.4` 也两处不同源。改哪一侧？ | 两格都有出处，删任一格都是替队伍决定"哪个数算数"；而 §3.2.5.2 的表只允许一张 | C2 已绿，但 `report/90-open-items.md` 仍登记这一条；`metric_recheck` 的同源自洽检查会继续报 | `build/evidence/r120_repo_gates_draft.txt` 的 C2 行、`report/log/issues.md` #339 |
| Q-P22-1 | 协作记录的**会话编号方案**与"导出原件不随包"是否接受（登记卡 + 摘要 + SHA12 随包，467 MB 的原始 jsonl 不随包） | 第三方拿到登记卡只能复现"纠错轨迹"那一半，能不能算满足 §3.3.5.3 的"完整记录"是队伍的取舍 | `report/collaboration/` 的 README 第 2 节按 (a) 写，并明写"未随包的是哪一件、为什么" | `report/collaboration/README.md` §2、`report/90-open-items.md` |
| Q-P22-2 | 4 个**手写件**里仍有本机用户名（`build/r116_batch_plan.md`、`report/log/issues.md` 一处、`skills/prompts/_proposed-sources.md` 一处、`skills/_meta/sources.md` 一处——后两个是 2026-10-04 c7b325f 重建前的旧包件名，**现不存在**，本行只报当时脱敏扫描的读数不指路）——是否授权脱敏 | 与 Q-P20-2 同一类，但这四处不是工具产出，改掉不影响 md5 配对；唯一代价是台账原文被改 | 不授权就照现状登记；授权则一次改完并复跑 `build/checks/check_repo_hygiene.sh` 的 C2a | `report/collaboration/redaction.md`、`report/log/issues.md` #336 |
| Q-P22-3 | `skills/evals/records/` 的两份演练/审计记录是否要与协作记录**双向引用**（现在它们 0 处引用会话号） | 双向引用要改 `skills/` 内的记录正文，属技能包交付内容，不是我的自由面 | C7 的"三处一致"仍按技能包自身口径判，跨目录引用缺口记在 `report/90-open-items.md` | `report/collaboration/README.md` §6 |

| Q-P04-1 | 黄金参考的权威产生方式（软件模型 / 旧版 RTL / 手工向量）与容差口径 | P04 第 2 步第 2 问，决定比对可信度上限 | `skills/scripts/golden_compare/` 只交脚本骨架 + fixture，不声称增益 | 见 `report/questions-for-team.md` |

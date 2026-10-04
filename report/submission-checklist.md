# 交付清单（P21）——逐条"有什么 / 缺什么 / 凭据在哪"

口径：每条一行，状态只允许 `PASS`（盘上有件且本轮或此前实跑过）、`FAIL`（有缺口，写清缺什么）、
`NOT_MEASURED`（读不到输入或需要人/需要工具链，不能判）。**不写"应该没问题"**。
本清单的每一格都能用右侧命令当场复核；命令在仓库根执行。

| # | 交付项 | 位置 | 状态 | 复核命令 |
| --- | --- | --- | --- | --- |
| 1 | 工程本体（RTL） | `src/rtl/` 80 个 `.v` | PASS | `git ls-files src/rtl \| wc -l` |
| 2 | 工程本体（PS 固件源码） | `src/ps/` 3 个 `.c/.h` | PASS（**ELF 不可重建**：本机无 `arm-none-eabi-gcc`，见 `report/build-notes.md`） | `git ls-files src/ps` |
| 3 | 约束 | `src/constraints/` | PASS | `git ls-files src/constraints` |
| 4 | 台架 / 仿真 | `sim/` 137 个跟踪文件 | PASS | `git ls-files sim \| wc -l` |
| 5 | 构建脚本与报告原件 | `build/`（脚本 + `build/evidence/` 凭据） | PASS | `git ls-files build \| wc -l` |
| 6 | 板级材料与实测 | `board/` 76 个跟踪文件 | PASS | `git ls-files board \| wc -l` |
| 7 | 指标表（唯一一张） | `data/metrics.csv`，28 行数据 | PASS（每行点名的证据件都在盘上：终审 C2 `全指到=28 缺或无路径=0`） | `node build/checks/check_repo_consistency.mjs \| grep '^C2 '` |
| 8 | 数据层说明 | `data/README.md` + `data/golden/README.md` + `data/measured/README.md` | PASS | `test -e data/README.md && echo ok` |
| 9 | 设计报告分章 | `report/README.md`、`report/{40,50,60,70,90}-*.md`、`report/{ARCHITECTURE,PS_VS_PL,BUILD,TIMING_GLOBAL,...}.md` | **FAIL**：`report/10-background.md（未写）`、`report/20-principle.md（未写）`、`report/30-partition-if.md（未写）`、`report/novelty-claims.md（未写）`、`report/prior-art-search.md（未写）` 未落地（P18a/P19 的批次被回合上限截停）。已登记，见 `report/90-open-items.md` | `ls report \| grep -E '^(10\|20\|30)'` |
| 10 | 提交阅读路径（八章） | `submit/{README,01-overview..08-limits}.md` + `submit/reproduce/` | PASS | `ls submit` |
| 11 | 器件与工具版本声明（唯一权威源） | `report/declarations.md` 的 `BEGIN-AUTHORITATIVE` 块 | PASS（终审 C1：别处**取值不同**=0；同值抄写只登记条数） | `node build/checks/check_repo_consistency.mjs \| grep '^C1 '` |
| 12 | 源码地图 | `report/src-map.md`（83 个源文件 × 4 列，逐文件现算） | PASS（头注列为空 0 个） | `node build/r120_src_map.mjs \| tail -1` |
| 13 | 接口表 / 契约 | `report/interface-table.md` | PASS（寄存器位序与 `src/host` 契约对账在 `skills/scripts/regmap_check/`） | `head -3 report/interface-table.md` |
| 14 | 复现说明与演练记录 | `report/70-reproduce.md`、`report/reproduce/README.md`、`report/repro-check.md` | **FAIL**：A/B/C 三条路径逐条跑下来的实跑结果是 `PASS=91 FAIL=30 未测=32`（终审 C9）。缺的是将 30 条 FAIL 逐条归因（命令写错 / 前置缺失 / 需要板子或工具链），不是把表改绿 | `node build/checks/check_repo_consistency.mjs \| grep '^C9 '` |
| 15 | 技能包（§3.3.5.2 四类内容） | `skills/` 58 个条目目录 + `skills/README.md` 生成索引 | PASS（技能包门禁 G1–G12 全绿；`skills/scripts/selftest/run_all.sh` 判 40 项 6/6 绿） | `node skills/scripts/check/gates.mjs \| tail -1` |
| 16 | 技能包验证记录 | `skills/evals/`（协议、两跑原始件、`records/` 陌生人演练与第三方审计） | PASS（存在且可读）；**但**各条目 §7 多数仍是 `【待验证】`（缺"同一模板连跑 3 次"的复跑） | `ls skills/evals skills/evals/records` |
| 17 | 大模型协作记录 | `report/collaboration/`（会话登记卡 + 纠错轨迹 + 提示词分栏 + 成本统计 + 脱敏台账） | PASS（原始会话导出**不随包**，随包的是登记卡与摘要，理由写在 README §2） | `ls report/collaboration` |
| 18 | 许可与再分发 | `LICENSE`（候选协议，见 Q-P20-1）、第三方条款登记 | **FAIL**：`report/` 与未落地的 provenance-and-licenses 一页（P20 截停）；协议本身待队伍定 | `ls report/; ls docs/provenance*  2>&1` |
| 19 | 命名合规（§3.3.5.4 纯小写 ASCII） | 全仓跟踪文件 | **FAIL**：308 条路径含大写（末段 266 + 中间段 45 − 两段都含 3），惯例名点名豁免 22 ⇒ 违规 286；本轮自己新增的交付件又贡献了 61 条含大写路径。改名会断 `build/frozen_r*/MANIFEST` 的 md5 绑定 ⇒ 待裁决 Q-P21-2 | `node build/checks/check_repo_consistency.mjs \| grep '^C4 '` |
| 20 | 文档内路径存活 | 全仓（学习文档按 .gitignore 不在射程） | **FAIL**：3 条真缺口（其中 2 条指向第 9/18 项未落地的文件），豁免逐类打印 | `node build/checks/check_repo_consistency.mjs --list \| grep '^DEAD '` |
| 21 | 卫生机检（许可/敏感信息/断链） | `build/checks/check_repo_hygiene.sh` | **NOT_MEASURED**：整脚本一轮 >300 s 未返回（C1 层已修快 1800 倍，C5 层仍是每 token 派生进程）⇒ 终审 C5 记未测，测数与修法在 `report/log/issues.md` #339 末段 | `VP_HYGIENE_TMO_MS=600000 node build/checks/check_repo_consistency.mjs \| grep '^C5 '` |
| 22 | 已知限制与未修项 | `report/90-open-items.md`（未决项唯一集中表） + `report/known-limitations.md`（面向读者的限制陈述） | PASS | `head -5 report/known-limitations.md` |
| 23 | 学习文档**不上传** | `report/study/`、`docs/walkthrough/` 均在 `.gitignore` 内 | PASS（`git ls-files report/study docs/walkthrough` = 0 个跟踪文件；导出器从 `git archive HEAD` 起步，故包内也不会有） | `git ls-files report/study docs/walkthrough \| wc -l` |

## 这份清单自身怎么被检查

- 第 7/11/15/19/20/21 行的状态由 `build/checks/check_repo_consistency.mjs` 现算，本文件只**引用它的行**，不重抄数字；
  数字漂了会以 `C7/C8`（三处一致 / 未决项汇总）的形式报红，而不是悄悄漂移。
- 本文件里出现的 `【待验证】`/`NOT_MEASURED` 都在 `report/90-open-items.md` 有对应行；
  反过来，未决项表里"文档缺口"若被补上，这一张表的对应行必须同批改（C8 会数）。

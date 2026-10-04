# 任务队列与状态（P23 第 6 节点名的 `run-queue.md`）

口径说明：P23 原文把四个交付物写成 `RUN_REPORT.md / questions-for-team.md / UNATTENDED.md / report/run-queue.md`。
本仓库采用**小写文件名**（赛题 3.3.5.4 的硬性命名要求优先于提示词里的示例大小写，
差异记录在 `report/unattended.md` 顶部），内容结构逐条照 P23。

来源：队伍的提示词集 `skill_prompts/README.md`（在本机文档目录里，**不随包**）的建议顺序
（工程支线 P13→P14→P15a→P15b→P15c→P17→P16a→P16b→P16c→P12；技能支线 P00→P01→P05→P04→P02→P07→P03→P06→P08→P09；
收尾 P11→P18a→P18b→P18c→P19→P22→P10→P20→P21）。

| 任务 | 目标文件（点名范围） | 依赖 | 状态 |
| --- | --- | --- | --- |
| P01 骨架 | `skills/README.md`、`skills/_meta/*` | — | 已交付（索引由 `skills/_meta/build-index.mjs` 现算生成：本轮实跑 `node skills/_meta/build-index.mjs skills --check` ⇒ `INDEX 条目=49 类别=10 索引行=49 需改写=no PASS`，rc=0） |
| P02 提示词工作流 | `skills/prompts/*` | P01 | 已交付 8 条（4 支模板 + 本轮迁入的 `eye-acceptance-loop`、`llm-fpga-debug-workflow`、`read-only-review-agent`、`round-work-loop`）；全部 `待验证`——每条都还欠"同一模板连跑 3 次"的 evals 记录 |
| P03 案例模板 | `skills/templates/*` | P01 | 已交付 4 条；**均未经空目录演练**（各条目 §7 明写"模板未经空目录验证"，不宣称可直接使用） |
| P04 校验脚本 | `skills/scripts/*`、`skills/scripts/selftest/run_all.sh` | P01 | 已交付：5 份脚本外壳（`contract_gen`/`golden_compare`/`regmap_check`/`report_metrics`/`repro_check`）+ `selftest/run_all.sh`（判 40 项、6 行各一判据、`pass=6 fail=0 nm=0`），G11 从"未测"转 PASS，件 `build/evidence/r120_selftest.txt`（`skills/scripts/selftest/run_all.sh` 是重建前的旧包件名，2026-10-04 c7b325f 之后**现不存在**，本行那些数是当时旧件的读数、只报数不指路；今天的等价命令是 `skills/_meta/run-all-checks.mjs`） |
| P05 踩坑清单 | `skills/pitfalls/*` | P01 | 已交付 24 条（原 8 条 + 迁入 16 张扁平卡）；旧卡已按 `retire_flat.mjs` 证明"映射/八节/出处逐条覆盖"后删除 |
| P06 参考层 | `skills/references/*` | P01 | 已交付 7 条（原 3 页 + 迁入 4 页：`bench-verilog-subset`、`bench-self-inflicted-reds`、`verdict-line-must-print-scope`、`wns-logic-vs-route-lever`） |
| P07 runtime | `skills/runtime/*` | P01 | 已交付 8 条：原有 4 条壳齐（`register-map`、`pl-load-verify`、`dma-cache-coherency`、`host-bindings-and-reports`）+ 迁入 4 条（`atomic-register-window-readback`、`board-eth-uart`、`udp-offset-reasm`、`zynq-ddr-bandwidth`）；G2 现在 `条目=59 全合` |
| P08 验证与增益 | `skills/evals/*` | P04/P05 | 部分交付（`evals/runbook.md` + `raw/` 两跑原始件 + `records/` 陌生人演练与第三方审计各一份）；**缺的是"同一模板连跑 3 次"的增益对照**，各条目 §7 一律 `【待验证】`，不念成已验证 |
| P09 装配与门禁 … | … | 已交付：**技能包门禁 12 项全绿、无未测**，两跑逐字节一致（`build/evidence/r120_gates_skill_a.txt` / `..._b.txt`）；索引 `gen_index --check` 条目=58 一致=yes；陌生人演练与第三方审计两份记录在 `skills/evals/records/`，其红项按原话入档 |
| P11 学习文档 | `docs/walkthrough/*`（**不随包**，`.gitignore` 已列） | P13/P15b | 11 个文件已交付，5 篇因缺前置未写 |
| P13 `src/` … | … | 部分（`report/interface-table.md` 已落 1509 行；`report/src-map.md` 本轮由 `build/r120_src_map.mjs` 现算生成，83 文件 × 4 列；`src-audit` 装配页未写（`git ls-files` 与盘上都没有这一件 ⇒ 现不存在）；契约头改动受 B1 约束） |
| P14 `sim/` … | … | 部分（`sim/README.md` 已落；`sim/regress/` 与 `verification-claim` 装配页未写（后者从未落盘 ⇒ 现不存在）⇒ "验证声明"只能停在"逐台架判据 + 门禁"这一档） |
| P15a 构建与指纹 … | … | 已交付（`build/README.md`、`build/provenance.md` 194 行、`build/artifacts/`、`build/probe-guard.md`） |
| P15b 报告解析与名册 … | … | 已交付（`build/parsed/`、`build/roster/`、`build/coverage.md`、`report/build-notes.md` 均在盘上并入库） |
| P15c 逐轮台账 … | … | 部分（`build/runs/ledger.md`、`build/runs/decisions.md` 在盘；两轮派发都被 150 回合上限截停 ⇒ 逐轮指针目录未核，缺口记在未决项） |
| P16a 板级可复原 … | … | 进行中（`board/hardware_setup.md` 151 行、`board/firmware/` 在；`board/run/`、`bringup-checklist.md` 待核） |
| P16b 实测与比对 … | … | 已交付（`board/raw-vs-golden.md` + logs/captures/compare/conditions，比对表 12 张全部脚本产出） |
| P16c 签核与指标 … | … | 已交付（`board/signoff.md` 29 项五件齐全、`report/measurements.md`、`signoff-questions.md`、`report/acceptance-recipes.md`） |
| P17 `data/` … | … | 已交付（`data/golden/manifest.md` 214 行、`inputs/` 8 个向量、`generated/gen_inputs.mjs`、`data/README.md` 本轮补上；`data-format` 装配页未写（从未落盘 ⇒ 现不存在） |
| P12 根 README … | … | 部分（`report/repro-check.md` 已出并随文档增长复测为 PASS 91 / FAIL 30 / 未测 32；**30 条 FAIL 未逐条归因** ⇒ C9 保留为红，见 `report/known-limitations.md` 第 4 节） |
| P18a 原理与划分 … | … | 未落地（`report/figures/` 已建；`20-principle.md`、`30-partition-if.md` 未写——批次到 150 回合上限，已登记不假装完成） |
| P18b 优化与结果 … | … | 已交付（`report/40-optimization.md`、`50-results.md`、`comparison-notes.md`；15 条抽查链路一步命中） |
| P18c 失败·复现·未决 … | … | 已交付（`60-failure-analysis.md`、`70-reproduce.md`、`90-open-items.md`、`report/README.md`）；90 的表体行随每轮装配漂移，最后一轮 `gen_index` 后需再对一次 C8 |
| P19 背景与创新点 … | … | 未落地（`10-background.md`、`prior-art-search.md`、`novelty-claims.md`、`report/claims-vs-evidence.md` 未写；立意与主张强度本就依赖 Q-P19-1/Q-P19-2 的队伍回答） |
| P10 报告里技能包两章 | `report/07-skill-distillation.md`（submit 侧）与 P22 配对 | P08/P09/P22 | 部分（`report/07-skill-distillation.md` 已成文） |
| P22 协作记录归档 … | … | 已交付（`report/collaboration/` 11 份：5 张会话登记卡含 127 行子会话表、纠错轨迹、提示词分栏、工作流差异、成本统计、脱敏台账）；与 `skills/evals/records/` 的双向引用缺口 6 条登记为 Q-P22-3 |
| P20 许可与声明 … | … | 部分（`LICENSE` 在、`build/checks/check_repo_hygiene.sh` 在、`report/declarations.md` 本轮落地；**`report/` 本轮落地**：16 行第三方件，其中 12 行标 `未核`，风险最高的是第 12 行（厂商资料抄件与原理图裁图在跟踪集内）与第 13 行（`src/rtl/eth` 25 个文件无版权头、逐文件"逐字／改造"没有登记表）⇒ 处置写成 Q-P23-1；provenance 逐轮指纹页仍未单独成页；卫生机检整脚本 >300 s 未跑完 ⇒ 终审 C5 记 NOT_MEASURED，慢点定位到 C5 断链层，见 ISSUES #339 末段） |
| P21 提交前终审 … | … | 已交付（尺子 + 矩阵三份：`report/submission-checklist.md`、`report/final-gate.md`、`report/known-limitations.md`；定版读数件 `build/evidence/r120_final_gate.txt` = 绿 8 / 红 3 / 未测 1） |

阻塞项（写在这里而不是藏起来）：

- B1 `src/` 契约头（P13 允许的唯一直接修改）**本轮不做**：本仓库的文档尺子 D5 按行号锚点核对引用，
  给 51 个源文件加文件头会让全部行号下移、D5 大面积变红；这是一次"改结构"动作，需要单独一轮并先备好还原能力。
  已进 `report/questions-for-team.md`（Q-P13-1）。
- B2 旧 `docs/` 那层（P12/P15b/P16c/P20/P21 点名）与既有 `report/` 的分工：那层的 19 件名册与台账已在 90b0391c 整体改名进 `report/timing/`（`git ls-files docs/ \| wc -l` = 0，`git ls-files report/timing/ \| wc -l` = 19）；剩下的关系只有：只做加法，不搬移，
  避免第二次"docs→report 改名轮"（该动作历史上两次退回）。
- B3 任何需要重跑 127 分钟顶层台架或完整构建的数字：一律 `【待实测】`，不许用旧轮次顶替。

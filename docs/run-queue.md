# 任务队列与状态（P23 第 6 节点名的 `run-queue.md`）

口径说明：P23 原文把四个交付物写成 `RUN_REPORT.md / questions-for-team.md / UNATTENDED.md / docs/run-queue.md`。
本仓库采用**小写文件名**（赛题 3.3.5.4 的硬性命名要求优先于提示词里的示例大小写，
差异记录在 `docs/unattended.md` 顶部），内容结构逐条照 P23。

来源：队伍的提示词集 `skill_prompts/README.md`（在本机文档目录里，**不随包**）的建议顺序
（工程支线 P13→P14→P15a→P15b→P15c→P17→P16a→P16b→P16c→P12；技能支线 P00→P01→P05→P04→P02→P07→P03→P06→P08→P09；
收尾 P11→P18a→P18b→P18c→P19→P22→P10→P20→P21）。

| 任务 | 目标文件（点名范围） | 依赖 | 状态 |
| --- | --- | --- | --- |
| P01 骨架 | `skill/README.md`、`skill/_meta/*` | — | 已交付（索引由 `skill/scripts/check/gen_index.mjs` 生成） |
| P02 提示词工作流 | `skill/prompts/*` | P01 | 已交付 4 条，待与扁平卡迁移合并 |
| P03 案例模板 | `skill/templates/*` | P01 | 已交付 4 条 |
| P04 校验脚本 | `skill/scripts/*`、`skill/scripts/selftest/run_all.sh` | P01 | 进行中（5 份 SKILL.md + selftest） |
| P05 踩坑清单 | `skill/pitfalls/*` | P01 | 已交付 8 条 + 扁平卡迁移进行中 |
| P06 参考层 | `skill/references/*` | P01 | 已交付 3 条 + 迁移进行中 |
| P07 runtime | `skill/runtime/*` | P01 | 部分（`pl-load-verify`、`register-map` 有，`dma-cache-coherency`、`host-bindings-and-reports` 缺 SKILL.md） |
| P08 验证与增益 | `skill/evals/*` | P04/P05 | 进行中（协议+原始两跑件已在，记录待补） |
| P09 装配与门禁 … | … | 进行中（12 项 = 绿 8 / 红 3 / 未测 1；陌生人演练与第三方审计两份记录已入 `skill/evals/records/`） |
| P11 学习文档 | `docs/walkthrough/*`（**不随包**，`.gitignore` 已列） | P13/P15b | 11 个文件已交付，5 篇因缺前置未写 |
| P13 `src/` … | … | 进行中（`docs/interface-table.md` 已落 1509 行；`src-map`、`src-audit` 未出） |
| P14 `sim/` … | … | 进行中（`sim/README.md` 已落；`sim/regress/`、`docs/verification-claim.md` 未出） |
| P15a 构建与指纹 … | … | 已交付（`build/README.md`、`build/provenance.md` 194 行、`build/artifacts/`、`build/probe-guard.md`） |
| P15b 报告解析与名册 … | … | 重试轮在跑（`build/roster/`、`build/parsed/` 已在；`build/coverage.md`、`docs/build-notes.md` 未出） |
| P15c 逐轮台账 … | … | 已交付（`build/runs/ledger.md` 在盘；`decisions/baselines` 与叙述版待核） |
| P16a 板级可复原 … | … | 进行中（`board/hardware_setup.md` 151 行、`board/firmware/` 在；`board/run/`、`bringup-checklist.md` 待核） |
| P16b 实测与比对 … | … | 已交付（`board/raw-vs-golden.md` + logs/captures/compare/conditions，比对表 12 张全部脚本产出） |
| P16c 签核与指标 … | … | 已交付（`board/signoff.md` 29 项五件齐全、`docs/measurements.md`、`signoff-questions.md`、`docs/acceptance-recipes.md`） |
| P17 `data/` … | … | 进行中（`data/golden/manifest.md` 214 行、`inputs/`、`generated/` 在；`data/README.md`、`docs/data-format.md` 未出） |
| P12 根 README … | … | 重试轮在跑（`docs/repro-check.md` 已出：PASS 46 / FAIL 13 / 未测 23） |
| P18a 原理与划分 … | … | 进行中（`report/figures/` 已建；`20-principle.md`、`30-partition-if.md` 未出） |
| P18b 优化与结果 … | … | 已交付（`report/40-optimization.md`、`50-results.md`、`comparison-notes.md`；15 条抽查链路一步命中） |
| P18c 失败·复现·未决 … | … | 部分交付（`60-failure-analysis.md`、`90-open-items.md`、`report/README.md` 在；`70-reproduce.md` 未出） |
| P19 背景与创新点 … | … | 重试轮在跑（`10-background.md`、`prior-art-search.md` 未出） |
| P10 报告里技能包两章 | `report/07-skill-distillation.md`（submit 侧）与 P22 配对 | P08/P09/P22 | 部分（`submit/07-skill-distillation.md` 已成文） |
| P22 协作记录归档 … | … | 进行中（`report/collaboration/` 已建） |
| P20 许可与声明 … | … | 部分（`LICENSE` 在、`scripts/check_repo_hygiene.sh` 387 行；`NOTICE.md`、`declarations.md`、`provenance-and-licenses.md` 未出；卫生机检 60 s 未返回 ⇒ 射程要收紧） |
| P21 提交前终审 … | … | 尺子已交付（`scripts/check_repo_consistency.mjs`；读数件 `build/evidence/r119_final_gate_baseline.txt`、`r120_final_gate_2.txt`）；矩阵三份文档等装配完再写 |

阻塞项（写在这里而不是藏起来）：

- B1 `src/` 契约头（P13 允许的唯一直接修改）**本轮不做**：本仓库的文档尺子 D5 按行号锚点核对引用，
  给 51 个源文件加文件头会让全部行号下移、D5 大面积变红；这是一次"改结构"动作，需要单独一轮并先备好还原能力。
  已进 `docs/questions-for-team.md`（Q-P13-1）。
- B2 `docs/`（P12/P15b/P16c/P20/P21 点名）与既有 `report/`、`docs/timing/` 的关系：只做加法，不搬移，
  避免第二次"docs→report 改名轮"（该动作历史上两次退回）。
- B3 任何需要重跑 127 分钟顶层台架或完整构建的数字：一律 `【待实测】`，不许用旧轮次顶替。

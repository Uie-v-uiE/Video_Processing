# 任务队列与状态（P23 第 6 节点名的 `run-queue.md`）

口径说明：P23 原文把四个交付物写成 `RUN_REPORT.md / questions-for-team.md / UNATTENDED.md / docs/run-queue.md`。
本仓库采用**小写文件名**（赛题 3.3.5.4 的硬性命名要求优先于提示词里的示例大小写，
差异记录在 `docs/unattended.md` 顶部），内容结构逐条照 P23。

来源：`C:/Users/wenqu/Documents/Qoder/2026-10-04-3d601c82/skill_prompts/README.md` 的建议顺序
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
| P09 装配与门禁 | `skill/scripts/check/gates.mjs`、G1–G12、陌生人演练、第三方审计 | 全部 P01–P08 | 进行中（12 项里 6 绿） |
| P11 学习文档 | `docs/walkthrough/*`（**不随包**，`.gitignore` 已列） | P13/P15b | 11 个文件已交付，5 篇因缺前置未写 |
| P13 `src/` | `docs/interface-table.md`、`docs/src-map.md`、`docs/src-audit.md` | — | 进行中 |
| P14 `sim/` | `sim/README.md`、`sim/{tb,vectors,regress,results,failure-bundle}/`、`docs/verification-claim.md` | P13 | 待开 |
| P15a 构建与指纹 | `build/README.md`、`build/provenance.md`、`build/artifacts/` | — | 待开 |
| P15b 报告解析与名册 | `build/parsed/`、`build/roster/`、`build/coverage.md`、`docs/build-notes.md` | P15a | 待开 |
| P15c 逐轮台账 | `build/runs/{ledger,decisions,baselines}.md`、`docs/optimization-rounds.md` | P15a/P15b | 待开 |
| P16a 板级可复原 | `board/README.md`、`board/hardware_setup.md`、`board/firmware/`、`board/run/`、`board/bringup-checklist.md` | — | 进行中 |
| P16b 实测与比对 | `board/{logs,captures,compare,conditions}/`、`board/raw-vs-golden.md` | P16a | 待开 |
| P16c 签核与指标 | `board/signoff.md`、`docs/measurements.md`、`board/signoff-questions.md`、`docs/acceptance-recipes.md` | P16b | 待开 |
| P17 `data/` | `data/README.md`、`data/{inputs,golden,generated,fetch}/`、`data/golden/manifest.md`、`data/licenses.md`、`docs/data-format.md` | — | 进行中 |
| P12 根 README | `README.md`、`docs/repro-check.md` | P15a/P16a/P14 | 进行中 |
| P18a 原理与划分 | `report/20-principle.md`、`report/30-partition-if.md`、`report/figures/`、`docs/claims-vs-evidence.md` | P13 | 待开 |
| P18b 优化与结果 | `report/40-optimization.md`、`report/50-results.md`、`report/comparison-notes.md` | P15b/P15c/P16b | 待开 |
| P18c 失败·复现·未决 | `report/{60-failure-analysis,70-reproduce,90-open-items,README}.md` | P18a/P18b | 待开 |
| P19 背景与创新点 | `report/10-background.md`、`report/prior-art-search.md`、`report/novelty-claims.md` | — | 进行中（需联网检索） |
| P10 报告里技能包两章 | `report/07-skill-distillation.md`（submit 侧）与 P22 配对 | P08/P09/P22 | 部分（`submit/07-skill-distillation.md` 已成文） |
| P22 协作记录归档 | `report/collaboration/*` | P08 | 待开 |
| P20 许可与声明 | `LICENSE`、`NOTICE.md`、`docs/provenance-and-licenses.md`、`docs/declarations.md`、`scripts/check_repo_hygiene.*` | — | 进行中 |
| P21 提交前终审 | `docs/submission-checklist.md`、`docs/final-gate.md`、`docs/known-limitations.md` | 全部 | 待开（必须最后做） |

阻塞项（写在这里而不是藏起来）：

- B1 `src/` 契约头（P13 允许的唯一直接修改）**本轮不做**：本仓库的文档尺子 D5 按行号锚点核对引用，
  给 51 个源文件加文件头会让全部行号下移、D5 大面积变红；这是一次"改结构"动作，需要单独一轮并先备好还原能力。
  已进 `docs/questions-for-team.md`（Q-P13-1）。
- B2 `docs/`（P12/P15b/P16c/P20/P21 点名）与既有 `report/`、`docs/timing/` 的关系：只做加法，不搬移，
  避免第二次"docs→report 改名轮"（该动作历史上两次退回）。
- B3 任何需要重跑 127 分钟顶层台架或完整构建的数字：一律 `【待实测】`，不许用旧轮次顶替。

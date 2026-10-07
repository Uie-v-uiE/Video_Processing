# 改写落点清单（自动生成，2026-10-05 夜）

口径：钟点＝正文里 `HH:MM:SS` 行数；轮次号＝正文里 `rNN` 出现在非路径位置的次数；
判定＝`check_docs.sh` 四类（钟点残留／人称与程度副词／量数不减少／引用路径存在）。
生成命令：`bash doc_audit_20261005/make_change_ledger.sh`

| 文件 | 行数 基线→改后 | 钟点行 | 轮次号叙述 | 自检判定 |
|---|---|---|---|---|
| `README.md` | 84 → 87 | 1 → 0 | 4 → 2 | PASS |
| `README_EN.md` | 82 → 76 | 1 → 0 | 5 → 2 | PASS |
| `board/README.md` | 70 → 102 | 0 → 0 | 2 → 1 | PASS |
| `board/acceptance.md` | 114 → 120 | 2 → 0 | 38 → 1 | PASS |
| `board/compare/index.md` | 80 → 80 | 0 → 0 | 3 → 3 | PASS |
| `board/conditions/card-board-serial-and-jtag.md` | 119 → 119 | 1 → 1 | 16 → 16 | 既存 |
| `board/firmware/ps_app.elf.md` | 99 → 99 | 1 → 1 | 6 → 6 | 既存 |
| `board/firmware/system.bit.md` | 84 → 82 | 3 → 3 | 3 → 3 | 既存 |
| `board/hardware_setup.md` | 151 → 164 | 1 → 0 | 0 → 0 | PASS |
| `board/raw-vs-golden.md` | 148 → 148 | 1 → 1 | 11 → 11 | 既存 |
| `board/signoff-questions.md` | 94 → 94 | 7 → 7 | 7 → 7 | 既存 |
| `board/signoff.md` | 361 → 370 | 7 → 0 | 55 → 45 | PASS |
| `build/README.md` | 84 → 108 | 6 → 0 | 2 → 0 | PASS |
| `build/r109_adoption_checklist.md` | 94 → 94 | 0 → 0 | 14 → 14 | 既存 |
| `build/r109_doc_targets.md` | 65 → 65 | 1 → 1 | 3 → 3 | 既存 |
| `build/r109_rotation_worklist.md` | 47 → 47 | 0 → 0 | 12 → 12 | PASS |
| `build/r116_batch_plan.md` | 58 → 58 | 0 → 0 | 8 → 8 | PASS |
| `build/runs/ledger.md` | 621 → 621 | 7 → 7 | 200 → 200 | 既存 |
| `data/README.md` | 30 → 62 | 0 → 0 | 0 → 0 | PASS |
| `report/01-overview.md` | 52 → 94 | 0 → 0 | 0 → 0 | PASS |
| `report/02-architecture.md` | 62 → 86 | 0 → 0 | 0 → 0 | PASS |
| `report/03-algorithm.md` | 76 → 98 | 0 → 0 | 0 → 0 | PASS |
| `report/04-resources.md` | 88 → 89 | 0 → 0 | 3 → 2 | PASS |
| `report/05-timing.md` | 182 → 202 | 1 → 0 | 13 → 2 | PASS |
| `report/06-validation.md` | 164 → 219 | 2 → 0 | 12 → 10 | PASS |
| `report/07-skill-distillation.md` | 85 → 85 | 0 → 0 | 1 → 0 | PASS |
| `report/08-limits.md` | 220 → 244 | 0 → 0 | 12 → 1 | PASS |
| `report/40-optimization.md` | 236 → 249 | 0 → 0 | 88 → 17 | PASS |
| `report/50-results.md` | 190 → 199 | 0 → 0 | 54 → 11 | PASS |
| `report/60-failure-analysis.md` | 538 → 594 | 0 → 0 | 13 → 2 | 既存 |
| `report/70-reproduce.md` | 210 → 236 | 2 → 0 | 6 → 4 | 既存 |
| `report/90-open-items.md` | 548 → 548 | 20 → 20 | 7 → 7 | 既存 |
| `report/README.md` | 138 → 136 | 0 → 0 | 0 → 0 | PASS |
| `report/acceptance-recipes.md` | 257 → 257 | 0 → 0 | 10 → 10 | 既存 |
| `report/ai_collaboration.md` | 261 → 479 | 0 → 0 | 11 → 1 | PASS |
| `report/architecture.md` | 158 → 168 | 1 → 0 | 2 → 0 | PASS |
| `report/background_and_novelty.md` | 111 → 158 | 0 → 0 | 0 → 0 | PASS |
| `report/claims-vs-evidence.md` | 154 → 166 | 4 → 0 | 20 → 18 | 既存 |
| `report/collaboration/redaction.md` | 156 → 156 | 0 → 0 | 0 → 0 | PASS |
| `report/command_precedence.md` | 442 → 439 | 0 → 0 | 2 → 0 | PASS |
| `report/commands.md` | 307 → 390 | 0 → 0 | 21 → 1 | PASS |
| `report/comparison-notes.md` | 131 → 190 | 0 → 0 | 34 → 2 | PASS |
| `report/demo_script.md` | 154 → 157 | 0 → 0 | 3 → 0 | PASS |
| `report/host_guide.md` | 176 → 188 | 0 → 0 | 0 → 0 | PASS |
| `report/known-limitations.md` | 83 → 71 | 0 → 0 | 0 → 0 | PASS |
| `report/known_issues.md` | 805 → 920 | 3 → 0 | 100 → 8 | PASS |
| `report/llm_collab.md` | 218 → 275 | 0 → 0 | 7 → 0 | PASS |
| `report/log/issues.md` | 13711 → 13711 | 30 → 30 | 919 → 919 | 既存 |
| `report/measurements.md` | 201 → 240 | 3 → 0 | 39 → 8 | PASS |
| `report/modules.md` | 131 → 133 | 0 → 0 | 1 → 0 | PASS |
| `report/notice.md` | 65 → 65 | 0 → 0 | 0 → 0 | PASS |
| `report/perf_report.md` | 477 → 489 | 4 → 0 | 52 → 1 | PASS |
| `report/ps_vs_pl.md` | 93 → 111 | 0 → 0 | 0 → 0 | PASS |
| `report/questions-for-team-p12.md` | 28 → 28 | 0 → 0 | 1 → 1 | PASS |
| `report/repro-check.md` | 293 → 317 | 5 → 0 | 6 → 5 | PASS |
| `report/rotation_and_effects.md` | 83 → 100 | 0 → 0 | 0 → 0 | PASS |
| `report/src-map.md` | 97 → 101 | 0 → 0 | 0 → 0 | PASS |
| `report/submission-checklist.md` | 38 → 38 | 0 → 0 | 0 → 0 | 既存 |
| `report/submission-package.md` | 46 → 46 | 0 → 0 | 0 → 0 | PASS |
| `report/timing/README.md` | 105 → 105 | 0 → 0 | 15 → 15 | PASS |
| `report/timing/a1_sources.md` | 51 → 51 | 0 → 0 | 1 → 1 | PASS |
| `report/timing/debt_ledger.md` | 213 → 213 | 0 → 0 | 15 → 15 | PASS |
| `report/timing/handoff_r118.md` | 106 → 106 | 1 → 1 | 18 → 18 | 既存 |
| `report/timing/rgmii_window_model.md` | 432 → 432 | 0 → 0 | 12 → 12 | PASS |
| `report/timing_global.md` | 455 → 456 | 0 → 0 | 36 → 40 | PASS |
| `report/unattended.md` | 95 → 95 | 0 → 0 | 6 → 6 | PASS |
| `sim/README.md` | 87 → 134 | 1 → 0 | 0 → 0 | PASS |
| `skills/README.md` | 165 → 184 | 0 → 0 | 0 → 0 | PASS |

合计：'68' 份：改善或达标 52，与基线同数的既存 16，本轮回归 0。

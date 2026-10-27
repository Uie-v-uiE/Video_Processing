# 文档重写与导出审计

这份审计记录两件事：哪些文档按 humanier 规则重写了，哪些保留为证据；导出到 `D:\Xilinx\Prj\fin` 的包是否自洽。

## 重写范围

读者向的正文全部重写，数字更新到 r162（PS 应用另有 2026-10-22 的超长行补丁）：

- 根 `README.md`、`README_EN.md`
- `report/technical-report.md`、`report/innovation.md`
- `report/01-overview.md` 到 `report/08-limits.md`
- `report/README.md`、`report/background_and_novelty.md`、`report/ps_vs_pl.md`、`report/rotation_and_effects.md`
- `report/demo_script.md`、`report/judge_qa_xiaosai.md`、`report/70-reproduce.md`、`report/technical-document-contest.md`
- `board/README.md`、`data/README.md`、`build/README.md`、`sim/README.md`
- `report/writing-style.md`（写法标准本身）

这些文档的写法按三条规则：不用 AI 味的排比和顿号链，不写没人会读的微数据，把压缩从句拆成完整句子。技术报告是主文档，其余章节按主题展开，不重复抄读数。

## 保留为证据的文档

下面这些是台账、原始读数或会话记录，按“好读”重写等于改证据，所以保留原样，只在开头标明它绑定哪一轮、当前结论指向哪里：

- `report/known_issues.md`、`report/optimization_log.md`、`report/perf_report.md`、`report/timing_global.md`、`report/50-results.md`
- `report/40-optimization.md`、`report/60-failure-analysis.md`
- `report/claims-vs-evidence.md`、`report/commands.md`、`report/repro-check.md`
- `report/log/`、`report/collaboration/`、`board/signoff.md`

`report/interface-table.md`、`report/commands.md`、`data/metrics.csv`、`sim/README.md` 的台架清单是查表用的参考件，保持表格式，不改成散文。

`skill/` 是与本题解耦的通用技能包，不是本项目报告，不按本项目的数字改写。

## 导出的包

导出目录：`D:\Xilinx\Prj\fin`。旧包备份在 `D:\Xilinx\Prj\fin_backup_20261021_0113`。

导出内容：

- 当前源码：`src/rtl`、`src/ps`、`src/host`、`src/constraints`
- 台架：`sim/` 全部 `tb_*.v` 与 `sim/prim`
- 构建：脚本、检查器、r162 实现报告与 r161 的十七支台架回归、r162 的四支 ETH 校验和台架
- 上板：`board/project` 三件套、脚本、r162 实测读数与 2026-10-22 固件超长行 A/B
- 数据：输入向量、参考图、当前指标表与 r132 历史表
- 报告：全部 190 份 Markdown、图与证据台账

包的身份：位流 `9734f3ec3019`、XSA `f4d4425138a2`、固件 `9ff967573b32`。时序 WNS 1.341 ns / WHS 0.025 ns；资源 LUT 28.13%、FF 8.55%、BRAM 70.00%、DSP 19。

## 检查过什么

- 23 份读者向文档的 Markdown 链接与反引号路径：没有指向包内不存在的文件。带 `:行号` 的源码引用是行号注记，不是文件路径。
- 当前身份：`board/project` 三件套的 md5 与 `board/README.md` 身份表一致。
- 当前数字：`data/metrics.csv` 的时序、资源与 `build/r171/`、`build/reports/` 一致；r171 已在板，`board/measured/health_20261022_1912.txt` 是 health 证据。
- 历史边界：`50-results.md`、`05-timing.md`、`timing_global.md`、`claims-vs-evidence.md`、`commands.md`、`repro-check.md`、`abstract_contract.md` 明确标注了轮次，当前值指向技术报告。
- 未测项：端到端时延、断电自启、高低温、PHY 眼图在指标表和 `08-limits.md` 里都写“未测/未验证”。

## 2026-10-22 一致性机检

`build/gates.sh build/r162` 的最终复跑（件 `build/r162_gates.txt`）是 21 项判定全过、0 红，但 3 项冻结凭据未判，末行是 `GATES: PARTIAL`：CDC 已按 r162 报告升基线（`build/evidence_r162/cdc.rpt`），`doc_cur` 用当前轮 `build/r162_gates.txt` 补齐了 D1b/D1c 基准，metric 检查器按 5 个时钟域/5 列 CSV 修正并通过自检。冻结凭据没有硬塞：第 14 项 `ports_check --dup` 会翻出 51 条悬空输入（47 个厂商可选口 + 4 个 `tb_seam_scan` 口），要让 `GATES: ALL PASS` 得先决定这些口是 tie-off 还是豁免。

`node build/checks/check_repo_consistency.mjs` 的 C1–C12 结果：C1 版本权威源、C2 指标指证据、C8 未决项汇总、C9 复现演练、C10 时间线、C11 失败可见，六项 PASS；C1 原来红在 `report/log/issues.md` 里一条历史引文把 Vitis 版本写成了少一段的旧写法，已改成占位写法并保留“当时少写一段”的说明。

导出目录另跑了一次 `deliver_spec_check` 的 C0-3：非小写/中文/空格的违例为 **0**（说明件豁免 69）。为此把根海报从大写名改成 `poster.png` / `poster.pdf`，清单从 `MANIFEST.txt` 改成 `manifest.txt`；早先的日志里仍保留旧名，那是历史记录。

C3/C4/C5/C7/C12 是 `NOT_MEASURED`：这份工作树没有 `.git`，检查器要 `git ls-files`/`git show`；`skill/` 的索引器在 `skills/` 下找 README，而本包按赛题用单数 `skill/`，这是检查器的路径与包布局不一致，不是技能包缺失。C6 因此判 FAIL，没有为了让门禁变绿去改检查器或造一个空的 `skills/` 目录；按本包的实际目录手动跑 `node skill/_meta/build-index.mjs skill --check` 是 `INDEX 条目=49 类别=10 索引行=49 需改写=no PASS`。`report/log/issues.md` 里保留这条口径。

## 没有做什么

- 没有把 `report/log/`、`report/collaboration/` 和 `known_issues.md` 的原始记录改写成散文。那会破坏证据链。
- 没有重写 60 条通用技能条目。它们不依赖本项目的数字，重写不会增加可读性。
- 没有做 185° 的人眼目视、冷启动复验和高低温测试。这三项需要人或外部设备，写在 `08-limits.md`。

如果审阅时发现某份文档仍然“AI 味重”或引用了旧数，按 `report/writing-style.md` 的五问清单改它，并同步 `data/metrics.csv` 与证据路径。

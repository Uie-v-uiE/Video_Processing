# 报告与文档

这一目录是给评委翻的。顺序按"先看懂作品，再看证据，最后看我们还欠什么"排。
逐轮的流水账（1.4 万行的问题台账、夜轮记录、每一轮试了哪些时序方案）不在这个提交包里——
它们在仓库历史的 `main` 分支上，需要追溯某条结论的来路时按编号去那里查。

## 怎么读

| 顺序 | 文件 | 它回答什么 | 长度 |
| --- | --- | --- | --- |
| 1 | `technical-document.md` | 这是什么、实现了哪些功能、每一处怎么实现、用了哪些技术、时序与状态、三个创新点、怎么复现 | 393 行 |
| 2 | `40-optimization.md` | 优化过程：改了什么、优化前后的性能与资源对比 | 243 行 |
| 3 | `06-validation.md` | 功能正确性是怎么确认的：台架、整屏逐像素判据、变异对照、门禁 | 218 行 |
| 4 | `measurements.md` | 指标逐条的测量条件与读数出处（与 `data/metrics.csv` 同源） | 241 行 |
| 5 | `perf_report.md` | 吞吐、帧率、丢包、端到端时延的实测过程与原始计数 | 490 行 |
| 6 | `60-failure-analysis.md` | 哪些场景仍然做不好，以及为什么 | 608 行 |
| 7 | `08-limits.md` | 已知限制与欠账（约束面、观测面、验证手段的边界） | 277 行 |
| 8 | `07-skill-distillation.md` | 技能包是怎么从失败里提炼出来的、怎么验证有效、边界在哪 | 88 行 |
| 9 | `ai_collaboration.md` 与 `collaboration/` | 大模型协作记录：提示词、模型回答、自我纠错轨迹 | 482 行 + 4 份 |
| 10 | `90-open-items.md` | 未决项一览：每条写清缺什么、需要谁做什么 | 371 行 |

## 想查细节时

| 文件 | 用途 |
| --- | --- |
| `70-reproduce.md`、`repro-check.md`、`build.md` | 复现：一条命令链、每一步的前置与期望输出、演练记录 |
| `interface-table.md` | 接口与寄存器：软硬件两端的位定义、地址、时序约定 |
| `src-map.md`、`board_pins.md`、`figures/legend.md` | 模块地图、管脚表、框图图例 |
| `commands.md`、`host_guide.md`、`demo_script.md` | 串口命令表、上位机用法、演示讲稿 |
| `declarations.md` | 器件、工具版本、开源协议等声明 |

## 官方 §3.3.5.3 设计报告七条 ↔ 本包里在哪

| 官方那一条 | 写在哪 |
| --- | --- |
| 选题背景与创新点 | `technical-document.md` 第 1.1–1.3 节（三个创新点各一两句）；"为什么选它、前人做过什么"的对照在 `contest_clause_map.md` 第 4 节与 `08-limits.md` |
| 设计原理与功能框图 | `technical-document.md` 第 2 节（时钟域、数据流、规模）与第 3 节（PL 逐段实现）；框图在 `figures/`，图例在 `figures/legend.md` |
| 软硬件划分依据与接口设计 | `technical-document.md` 第 5 节（划分依据，含逐像素 20 ns 那一笔预算）；寄存器与位序在 `interface-table.md`，上位机侧在 `host_guide.md` |
| 优化过程（含前后性能与资源对比） | `40-optimization.md`（含三笔"量过并否决"的账）；测量条件与出处在 `measurements.md`、`perf_report.md`，数字对账在 `data/metrics.csv` |
| 大模型协作记录 | `ai_collaboration.md` 与 `collaboration/`（登记卡、纠错轨迹、提示词分栏、成本统计） |
| 技能包的提炼过程 | `07-skill-distillation.md`；每条技能的"来源失败 / 失效条件"写在 `skills/` 各条目里，机检是 `skills/_meta/check-skill-package.mjs` |
| 复现说明 | `technical-document.md` 第 8 节 + `70-reproduce.md`（A/B/C 三条路径）+ `repro-check.md`（逐行判定，未测的行明写欠哪一次构建） |

## 三条写作规矩

1. 数字必带单位与测量条件，且点名它的证据文件；没复核过的格子写"未报"，不填猜的数。
2. 结论后面紧跟依据；判断错了就改文档并留一条记录，不改判据把红抹掉。
3. 屏幕上的现象由人判，机器判据不冒充眼睛；反过来，机器判据也不写成"已验证现象"。

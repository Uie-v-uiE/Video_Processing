# 大模型协作记录

这份档案记录模型在项目中做了什么、哪些建议被台架或板上读数修正，以及最后留下了哪些可复核的落点。它不是聊天摘抄，重点在“判断—验证—修正”的链条。

原始会话导出含本机路径和临时目录，不随包。随包的是会话登记卡、提示词摘录、纠错轨迹、工作流、成本统计和脱敏说明；每张卡都写明哪些字段只能在原机器上重算。

## 1 怎么读

1. 先看 `sessions/` 的五张历史卡和一张本轮卡，知道每场会话负责哪条线。
2. 再看 `corrections.md`：错误断言、否定它的实验、更正后的结论，三件一组。
3. 需要复刻提示词时看 `prompts-used.md`；需要复刻工作方式时看 `workflow.md`。
4. `metrics.md` 是会话数和成本口径，`redaction.md` 说明原文为什么不随包；`recent-cases.md` 是最近 7 个修正案例的摘要。

## 2 会话登记卡

| 卡 | 文件 | 负责什么 | 计入门槛 |
|---|---|---|---|
| S01 | `sessions/s01.md` | 主会话：架构、RTL、PS、时序、板级和文档的长期迭代（226 轮人工输入） | +1 |
| S02 | `sessions/s02.md` | 同工作区里只开了 17 秒的一场，0 次工具调用 | +1 |
| S03 | `sessions/s03.md` | 前身工作区的一场，邻仓，不计入本仓库分母 | +0 |
| S04 | `sessions/s04.md` | 文档工作区 4 场：提示词集成、轮次提示词写作 | +0 |
| S05 | `sessions/s05.md` | 127 个子会话的批量卡，逐行一份导出 | +127（子会话口径） |
| S06 | `sessions/s06.md` | 最终定版轮：`link` 命令、QSPI 冷启动、目录重构、文档与推送 | +1 |

## 3 任务 → 会话 → 落点

| 任务 | 会话 | 结论落在哪里 |
|---|---|---|
| 全 PL 视频通路、三源仲裁、DDR 乒乓、几何与效果链 | S01、S05 | `src/rtl/`、`src/ps/`、`report/design-report.md` |
| 时序收敛：处理窗总线、仲裁器扇出、复位树、UDP 校验和 | S01、S05 | `report/optimization.md`、`build/reports/` |
| 验证：帧提交三条件、A9 混帧、C22/C31 一行串色、UDP 校验和 | S01、S05 | `sim/`、`report/verification.md`、`build/reports/` |
| 上板与 QSPI：JTAG 三步链、BOOT.bin、冷启动、串口电池 | S01、S06 | `board/`、`board/measured/`、`data/metrics.csv` |
| 帧间隔统计：`link`/`link clr` 与 `stall`/`gap_*` 口径 | S06 | `src/ps/main.c`、`src/rtl/eth/link_monitor.v`、`board/measured/link_gap.txt` |
| 技能包：从失败里提炼可复用做法 | S05、S06 | `skill/`、`report/skill-distillation.md` |
| 文档去 AI 味、技术文档、海报、提交包 | S04、S06 | `report/`、`README.md`、本地 `deliverables/` |

## 4 最近补充的四个修正

这四条是本轮新增的，详细记录在 `corrections.md` 的“最近补充”一节：

1. **`cmd_link` 函数存在但没有接进 `dispatch`**：源码里有函数，板上敲 `link` 回“不认”。修正后串口可直接读帧间隔统计。
2. **BSP 路径写成了不存在的目录**：文档里 `PS_BSP=board/vitis_platform/bsp` 指向一个只有平台描述、没有 BSP 的目录。改成“平台构建生成的 BSP 目录”，并在编译脚本里加前置检查。
3. **冷启动与 `link` 曾被写成“待复验”**：新固件和 QSPI 镜像完成后，断电重上实测通过，文档改回实测值。
4. **A9 混帧修复被两行否决记录掩盖**：最终 RTL 用 12 位预分频的 4 ms idle timer，`tb_udp_reasm` 有“两帧不混、恢复后第 3 帧干净”的判据；优化章节补上采纳行。

## 5 可复核的落点

| 内容 | 位置 |
|---|---|
| 会话卡与子会话计数 | `sessions/`、`metrics.md` |
| 纠错轨迹 | `corrections.md` |
| 最近案例摘要 | `recent-cases.md` |
| 提示词原文与模板 | `prompts-used.md` |
| 智能体工作流 W1–W8 | `workflow.md` |
| 成本统计 | `metrics.md` |
| 脱敏与原文处置 | `redaction.md` |
| 板上证据 | `board/measured/`、`data/metrics.csv` |
| 代码与台架 | `src/`、`sim/`、`build/reports/` |

模型回答的逐字原文不作为证据；证据是台架判定行、实现报告、板上日志和 Git 提交。原始导出不随包，第三方无法复现的部分在每张卡里单独标注。

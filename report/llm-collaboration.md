# 大模型协作记录

详细档案在 [`collaboration/`](collaboration/README.md)：六张会话卡、纠错轨迹、提示词摘录、智能体工作流、成本统计和脱敏说明。这一页只给阅读顺序和最近的修正。

## 阅读顺序

1. [`collaboration/sessions/`](collaboration/sessions/)：S01 主会话、S02 短会话、S03 前身工作区、S04 文档工作区、S05 子会话批量卡、S06 最终定版轮。
2. [`collaboration/corrections.md`](collaboration/corrections.md)：每条按“错误断言 → 否定它的实验/证据 → 更正后的结论”写。
3. [`collaboration/prompts-used.md`](collaboration/prompts-used.md)：提示词原文与事后模板。
4. [`collaboration/workflow.md`](collaboration/workflow.md)：W1–W8，智能体工作流与实际执行的差异。
5. [`collaboration/metrics.md`](collaboration/metrics.md)：会话数、轮次和成本口径。
6. [`collaboration/redaction.md`](collaboration/redaction.md)：为什么原始导出不随包，以及哪些字段只能在本机重算。
7. [`collaboration/recent-cases.md`](collaboration/recent-cases.md)：最近 7 个修正案例的摘要。

## 最近的修正

- **`link` 命令不可达**：`cmd_link` 函数存在，但没有接进 `dispatch`；板上敲 `link` 回“不认”。接回分派和帮助行后，新固件能读帧间隔统计。
- **BSP 路径不存在**：文档曾写 `PS_BSP=board/vitis_platform/bsp`，而该目录只有平台描述。改成“平台构建生成的 BSP 目录”，并在编译脚本里加前置检查。
- **冷启动/帧间隔从“待复验”改为实测**：断电重上后串口 `stat`/`link` 有回显，`DONE=1`、`EOS=1`、无 CRC/IDCODE 错误；重启流后 `gap_max=22 061 ms`。
- **A9 文档口径**：最终 RTL 用 12 位预分频的 4 ms idle timer，`tb_udp_reasm` 有“两帧不混、恢复后第 3 帧干净”的判据；优化章节补上采纳行。

## 模型没有做的事

- 没有替人判断 HDMI 画面是否可接受；E1/E2/E3 仍是人眼项。
- 没有替人决定比赛模板、页数和提交系统字段。
- 没有把“台架绿”写成“板上也绿”；仿真、实现、板上读数分开记录。
- 没有为了 WNS 数字继续改动已经签字的 RTL；时序边界在 [`limits.md`](limits.md)。

原始会话导出含本机路径和临时文件，不随包；可复核的证据是台架判定行、实现报告、板上日志和 Git 提交。模型回答的逐字原文不作为证据。

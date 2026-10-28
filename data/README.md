# 数据层

`data/` 放三类东西：测试输入、软件侧参考图、指标表。

## 测试输入

`inputs/` 放固定向量：正常帧、全零、随机、截断 299 行、超长 1.5 帧、0 字节和 1 像素边界包。生成脚本是 `generated/gen_inputs.mjs`，重跑一条命令就能得到相同字节：

```bash
node data/generated/gen_inputs.mjs --write
```

## 参考图

`golden/` 放软件侧渲染的参考图：源图、各旋转角度、效果组合和左右并排预览。它用于人眼比对，不是自动判据的唯一来源；逐像素比对以台架为准。文件清单与用途在 `golden/README.md`。

## 指标表

`metrics.csv` 是交付版本的指标表，每行给指标、数值、单位、测量条件和证据路径。数字只在这里和设计报告里各出现一次；不要建第二份表，否则两处会各自漂移。

读不到输入时写 `NOT_MEASURED`，不写“通过”。端到端时延、玻璃到玻璃延迟这类没有测的量，在表里明确保留为未测。

## 证据

板上原始日志在 `hw/measured/`，实现报告在 `hw/reports/`，台架判定行在 `hw/reports/regression.txt` 与 `hw/reports/tb_video_pipeline_top_report.txt`。指标表只指路，不复制日志正文。

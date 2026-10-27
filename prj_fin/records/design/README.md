# 设计资料

这里保存海报风格探索、设计素材和技术文档/海报的生成脚本。最终提交件在 `../../submission/deliverables/`。

## 海报风格

`poster_styles/` 保留六种 A4 竖版方案，均使用同一组最终读数：

| 方案 | 风格 |
|---|---|
| `poster_impeccable.*` | 奶油/焦橙分区，最终选用 |
| `poster_dark_scope.*` | 深色示波器 |
| `poster_swiss_grid.*` | 瑞士网格/数据表 |
| `poster_blueprint.*` | 技术蓝图 |
| `poster_bold_blocks.*` | 竞赛粗块 |
| `poster_canvas_visual.*` | 图像主导 |

`contact_sheet.png` 是六种方案的总览。每种方案都有 PNG、PDF 和 PPTX 三个版本。

## 设计素材

`assets/` 保存海报使用的同帧 A/B 分割图、原始/处理帧和 AMD 标识。

## 生成脚本

`tools/docs/` 保存技术文档模板填充、框图生成、DOCX/PPTX 导出脚本，以及生成后的 7 张非实物图；`tools/checks/` 保存仓库卫生和一致性检查脚本；`tools/` 根下保存 release 构建、海报风格生成和联系表生成脚本。

这些脚本依赖 `fin2` 工作区的模板、字体和本机 Office，归档目的是保留生成方法和参数，不保证在 FIN 目录内直接运行。

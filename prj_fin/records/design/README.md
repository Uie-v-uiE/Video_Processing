# 设计资料

这里保存海报风格探索、设计素材和技术文档/海报的生成脚本。最终提交件在 `../../submission/deliverables/`。

## 海报风格

`poster_styles/` 保留六种 A4 竖版方案和最终的 AMD 模板方案，均使用同一组最终读数：

| 方案 | 风格 |
|---|---|
| `poster_amd_template.*` | AMD 模板 16:9 横版，湖南工业大学，最终选用 |
| `poster_impeccable.*` | 奶油/焦橙分区，上一版 |
| `poster_dark_scope.*` | 深色示波器 |
| `poster_swiss_grid.*` | 瑞士网格/数据表 |
| `poster_blueprint.*` | 技术蓝图 |
| `poster_bold_blocks.*` | 竞赛粗块 |
| `poster_canvas_visual.*` | 图像主导 |

`contact_sheet.png` 是早期六种方案的总览。每种方案都有 PNG、PDF 和 PPTX 三个版本。

## 设计素材

`assets/` 保存海报使用的同帧 A/B 分割图、原始/处理帧、AMD 标识、湖南工业大学校徽和开发板照片。

## 文案

`project_intro_variants.md` 收这个工程的项目介绍：一句话、仓库简介、README 首段、设计自述、工程视角、英文版，以及一版可填表的短稿。全部不写资源占用与时序余量，只讲工程是什么、为什么这样设计、边界在哪。这些文字已落到 GitHub `master` 分支的 README 中。

`competition_intro_500.md` 收比赛用的 500 字简介：六版不同视角的初稿、按评审维度打分与锐评、两轮迭代后的三版定稿，以及三条不能写进简介的口径。

## 生成脚本

`tools/docs/` 保存技术文档模板填充、框图生成、DOCX/PPTX 导出脚本，以及生成后的 7 张非实物图；`tools/checks/` 保存仓库卫生和一致性检查脚本；`tools/` 根下保存 release 构建、海报风格生成和联系表生成脚本；`tools/make_amd_template_poster.py` 按 AMD 模板生成最终 16:9 海报。

这些脚本依赖 `fin2` 工作区的模板、字体和本机 Office，归档目的是保留生成方法和参数，不保证在 FIN 目录内直接运行。

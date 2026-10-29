# 提交交付件

这个目录随最终提交包提供，不放进源码仓库：

| 文件 | 内容 |
|---|---|
| `technical_document.docx` / `.pdf` | 按赛事模板生成的技术文档；非实物框图/流程图/界面示意已生成并嵌入 |
| `poster.png` / `.pdf` / `.pptx` | AMD 模板风格 16:9 英文海报（湖南工业大学），生成脚本在 `records/design/tools/make_amd_template_poster.py` |

技术文档由 `tools/docs/make_technical_template.py` 在赛事模板上填充，框图由 `tools/docs/make_technical_figures.py` 生成。模板页眉的赛事 Logo 和页码保留在 DOCX/PDF 中；当前为 16 页、12 张嵌入图（7 张生成图 + 5 张实拍照片），PDF 约 1.4 MB。

早期六种海报风格对比仅作本地记录，不随提交；当前提交的是 AMD 模板 16:9 方案。

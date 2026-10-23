# 提交交付件

这个目录随最终提交包提供，不放进源码仓库：

| 文件 | 内容 |
|---|---|
| `technical_document.docx` / `.pdf` | 按赛事模板生成的技术文档；非实物框图/流程图/界面示意已生成并嵌入 |
| `poster.png` / `.pdf` / `.pptx` | A4 英文海报，最终选用 Impeccable 奶油/焦橙版 |

技术文档由 `tools/docs/make_technical_template.py` 在赛事模板上填充，框图由 `tools/docs/make_technical_figures.py` 生成。模板页眉的赛事 Logo 和页码保留在 DOCX/PDF 中。

风格对比预览在本地 `poster_styles/`（不随提交）。仍保留灰色图位、需要替换为实拍图的 4 处：图 3 开发板整体、图 8 系统实物正面、图 9 系统实物斜 45°、图 11 测试现场。

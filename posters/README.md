# 作品海报（中英文，AMD 模板原版式）

严格使用 AMD 官方 16:9 海报模板：保留模板所有栏位、竖排标题、分割线、AMD Logo 和图片位置，只替换文字与图片。

- 左上：只放一张 16:9 的“左侧原图 / 右侧处理图”同帧对照图，不再压成宽扁条。
- 右上：使用比例正常的旧板卡+屏幕实拍图。
- 中间：重画为 4×3 数据面/显示链/控制观测框图，信息更完整。
- 右侧：创新设计、结果、展望写回模板原有文本区。

| 文件 | 内容 |
|---|---|
| `poster_cn.pdf` / `.png` / `.pptx` | 中文海报；PPT 为单页整图 |
| `poster_en.pdf` / `.png` / `.pptx` | 英文海报；PPT 为单页整图 |
| `poster_cn_editable.pptx` / `poster_en_editable.pptx` | 按模板原位可编辑的源文件 |
| `tools/make_final_posters.py` | 模板填充脚本 |
| `tools/arch_v2_zh.png` / `arch_v2_en.png` | 4×3 系统架构图 |
| `tools/split_16x9.png` | 左上单张同帧对照图 |
| `tools/overview.jpg` | 右上板卡+屏幕实拍 |

## 校验值（SHA-256）

```text
poster_cn.pdf            3e1b5812a5c99874e1e8c66828b93c4dd4359bc5ea600a9abc46a5e01c9d76c6
poster_cn.png            e2bef712b70b730dde9c8444481ded33929f8f91fc6b5a972c7d460d759400e2
poster_cn.pptx           0142a67994dbd4116279fe9c684bce76fcff92c14b5d3db04ea5d0d539ada488
poster_en.pdf            b931bfdb5463cd4d9891d5ebfe0e9ba349b64b2ffac86c06aefb4d0875e560f4
poster_en.png            3d7736d05fbd64c7bd144c7f8c8fde5c299f53bb7f7fc667698b6d36540aa791
poster_en.pptx           0af707252a5a0d09b59c20859dfb632506f06bcb07752ff59dae93fbaa8e1f21
poster_cn_editable.pptx  756ed7c8273a4955112d18d344cd27bc4578a4767b7ec135632fc642aae18a56
poster_en_editable.pptx  2affe59abba25a9074f30fd5763376d7ad3ae83ee7e45bf72d198dc2004582ec
```

旧版海报只在历史提交和本地 `upload/_v1_backup/old_posters/` 中保留。

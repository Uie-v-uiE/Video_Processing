# 作品海报（中英文，AMD 模板原版式）

严格使用 AMD 官方 16:9 海报模板：保留模板所有栏位、竖排标题、分割线、AMD Logo 和图片位置，只替换文字与图片。

- 左上：只放一张“左侧原图 / 右侧处理图”的同帧对照图，按原图比例居中，两侧暗边与画面融合，不再使用四联拼图。
- 右上：使用系统整体实拍照（笔记本、开发板、HDMI 屏幕、连线同框）。
- 中间：使用已有的中英文系统架构 PNG；两张卡片分别写接收/缓存与显示/处理。
- 右侧：创新设计、结果、展望写回模板原有文本区。

| 文件 | 内容 |
|---|---|
| `poster_cn.pdf` / `.png` / `.pptx` | 中文海报；PPT 为单页整图 |
| `poster_en.pdf` / `.png` / `.pptx` | 英文海报；PPT 为单页整图 |
| `poster_cn_editable.pptx` / `poster_en_editable.pptx` | 按模板原位可编辑的源文件 |
| `tools/make_final_posters.py` | 模板填充脚本 |
| `tools/arch_zh.png` / `arch_en.png` | 中英文系统架构图 |
| `tools/left_single_zh.png` / `left_single_en.png` | 左上单张同帧对照图 |
| `tools/system_thumb.jpg` | 右上系统整体实拍 |

## 校验值（SHA-256）

```text
poster_cn.pdf            4660339865a7c85013cbffe82954c2ae28b4c3d89abd6e8fbfdf595104b2503a
poster_cn.png            a2f1d332bc8c9918c83d838c32718d5af54d22c7d6374c1f30951413ebeadd42
poster_cn.pptx           8432ccf74dd9881236667f74c561a77ea405cce4de98776b4cb3134f1eded268
poster_en.pdf            989c63472a27813e3481e7a760659c1aa6d3248388554c13b7f2b6353b56264c
poster_en.png            c7bc0a566efa413d9c2dfb62557355ba24e1b8a803d8e70c8bc454ace86dde3a
poster_en.pptx           9e83186f3f94ef5da6290f92eda09c8975262003aa5bfc829151c0deb7fb65e3
poster_cn_editable.pptx  3e3a84480d8edf95fe0259f25a1033a2777ca0ba46ef9cbab583e97e33446fc6
poster_en_editable.pptx  e91d1e175ca0bff580a1690c65137fd94b5b4fd08c924de9ebea5aa7965cf6f2
```

旧版海报只在历史提交和本地 `upload/_v1_backup/old_posters/` 中保留。

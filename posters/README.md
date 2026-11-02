# 作品海报（中英文，AMD 模板原版式）

严格使用 AMD 官方 16:9 海报模板：保留模板所有栏位、竖排标题、分割线、AMD Logo 和图片位置，只替换文字与图片。

- 左上：一张 16:9 的“左侧原图 / 右侧处理图”同帧对照图。
- 右上：比例正常的旧板卡+屏幕实拍。
- 中间：4×3 数据面/显示链/控制观测架构图，浅色卡片、蓝/青/琥珀分组带、柔和阴影。
- 右侧：创新设计、结果、展望写回模板原有文本区。

| 文件 | 内容 |
|---|---|
| `poster_cn.pdf` / `.png` / `.pptx` | 中文海报；PPT 为单页整图 |
| `poster_en.pdf` / `.png` / `.pptx` | 英文海报；PPT 为单页整图 |
| `poster_cn_editable.pptx` / `poster_en_editable.pptx` | 按模板原位可编辑的源文件 |
| `tools/make_final_posters.py` | 模板填充脚本 |
| `tools/arch_v3_zh.png` / `arch_v3_en.png` | 浅色分组架构图 |
| `tools/split_16x9.png` | 左上单张同帧对照图 |
| `tools/overview.jpg` | 右上板卡+屏幕实拍 |

## 校验值（SHA-256）

```text
poster_cn.pdf            a55b20bc5f2865d098f6c235a798fca0a8c958dc40038393b3e2e094eca7c47e
poster_cn.png            9c3086181cc506fa45073c024f58dc27d982e831c01540e5b65ac3148e90e008
poster_cn.pptx           ee0160de31010aeee417c79806da084aa73370df958a8815ea0d5e30e243d331
poster_en.pdf            e87ea7ed65ed4e5f94908a21547a8b577cc787dce8873d5816db35106b8a6377
poster_en.png            9b0c0974b8ff4eb5658a5e7fad7aef77eea8714b0d6ac45b3d660f5fbb65c810
poster_en.pptx           5e53431777284c34c86ba6c68ccda0b2395ccdd224e8140deedbb72c4eca5598
poster_cn_editable.pptx  6fc50704d45f205bcc5ccfeea7beaa468f90003bdfc46331f3c30ed3fe9aee4a
poster_en_editable.pptx  11843889df578214b3458158d68b7328a346de766f2e7d8abc8e473fb0426924
```

旧版海报只在历史提交和本地 `upload/_v1_backup/old_posters/` 中保留。

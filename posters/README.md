# 作品海报（中英文，AMD 模板原版式）

严格使用 AMD 官方 16:9 海报模板：保留模板所有栏位、竖排标题、分割线、AMD Logo 和图片位置，只替换文字与图片。左上插图为“左侧原图 / 右侧处理图”的同帧对照图。

| 文件 | 内容 |
|---|---|
| `poster_cn.pdf` / `.png` / `.pptx` | 中文海报；PPT 为单页，整页嵌入中文 PNG |
| `poster_en.pdf` / `.png` / `.pptx` | 英文海报；PPT 为单页，整页嵌入英文 PNG |
| `poster_cn_editable.pptx` / `poster_en_editable.pptx` | 按模板原位可编辑的源文件 |
| `tools/make_final_posters.py` | 模板填充脚本 |
| `tools/poster_split_strip.png` | 左上“原图/处理图”插图 |
| `tools/poster_arch_cn_pad.png` / `poster_arch_en_pad.png` | 中英文系统框图 |
| `tools/poster_board_thumb.jpg` | 板卡缩略图 |

## 信息

- 团队 Uie_Team，队员王旭（Wang Xu），指导老师 Tan Huisheng / Liang Jiaojiao。
- 湖南工业大学 · 湖南省；英文版 Hunan University of Technology, Hunan Province。
- 平台 RK-ZYNQ7020-F / xc7z020clg484-2 / Vivado-Vitis 2025.2.1。
- 关键读数：WNS 1.368 / WHS 0.048 ns、LUT 28.13%、BRAM 70.00%、30.01 fps、自检 22.2/0/18.9、效果链固定 15 拍。

## 校验值（SHA-256）

```text
poster_cn.pdf            81f8b3612f140ac27ad9ce9ea61a6082c4add46c01eb51f60ae2ee7075ac389b
poster_cn.png            6d1718dbd8450a520624c626138e7b98aff81de5c5e2b15c84b6aada59ae78e3
poster_cn.pptx           bad5c428a952a806e4418efbb95b87e8fb28346bf59df0af47040ae0361d23df
poster_en.pdf            c407aff032ba50bbe24c0e9dc3e8b279880cb710d788d8ccdc4cd2d4d5f46c7b
poster_en.png            5b09f104b29d66f7e9be2548aa12f22f73b4231497ebc85805ab673c68fc8336
poster_en.pptx           d2b08cfdd866706cde017c48a1412ace3c5ae9cd50064a2d7cf2df503138a991
poster_cn_editable.pptx  d8c72521141031bba15d9b2758ce2b91362d987bd7539fede367c2edb12a5673
poster_en_editable.pptx  5a016c4bf47c24bb540cc834aa5f02e79dd291e0b0628b3b35ba3906eaaf3584
```

旧版海报只在历史提交和本地 `upload/_v1_backup/old_posters/` 中保留。

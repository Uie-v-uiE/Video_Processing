# 作品海报（中英文，AMD 模板原版式）

严格使用 AMD 官方 16:9 海报模板：保留模板所有栏位、竖排标题、分割线、AMD Logo 和图片位置，只替换文字与图片。左上插图使用已有的四联实拍素材（原图 / 放大 / 竖缝对照 / 上板实测），右上使用系统整体实拍。

| 文件 | 内容 |
|---|---|
| `poster_cn.pdf` / `.png` / `.pptx` | 中文海报；PPT 为单页，整页嵌入中文 PNG |
| `poster_en.pdf` / `.png` / `.pptx` | 英文海报；PPT 为单页，整页嵌入英文 PNG |
| `poster_cn_editable.pptx` / `poster_en_editable.pptx` | 按模板原位可编辑的源文件 |
| `tools/make_final_posters.py` | 模板填充脚本 |
| `tools/arch_zh.png` / `arch_en.png` | 中英文系统架构图（已有素材） |
| `tools/strip_zh_pad.png` / `strip_en_pad.png` | 左上四联实拍素材 |
| `tools/system_thumb.jpg` | 右上系统整体实拍 |

## 信息

- 团队 Uie_Team，队员王旭（Wang Xu），指导老师 Tan Huisheng / Liang Jiaojiao。
- 湖南工业大学 · 湖南省；英文版 Hunan University of Technology, Hunan Province。
- 平台 RK-ZYNQ7020-F / xc7z020clg484-2 / Vivado-Vitis 2025.2.1。
- 关键读数：WNS 1.368 / WHS 0.048 ns、LUT 28.13%、BRAM 70.00%、30.01 fps、自检 22.2/0/18.9、效果链固定 15 拍。

## 校验值（SHA-256）

```text
poster_cn.pdf            0b5268ab322fe755836ada6724b195aa2df4ddb70d50da2c5318abf1476be588
poster_cn.png            6bb8140658f2c0841ed3b151aa1aa406447c8002e97e79e5a2bc21588eb8ca4b
poster_cn.pptx           d55b12f120ee5019ad0edd0fe2baf764cb5818cf7a2d631ca89b1c14e1a185dd
poster_en.pdf            529e363167cd3a5f8846ee516e30f533fab73d91a242e8c4cd7df2c18973e7b8
poster_en.png            7d78c022affab4825e332f191fa2613129ccca6909492d9df23f644768adac51
poster_en.pptx           e9f41f2c858ffc6ba00e17a86dd73fff6551e3ab1f0b8449642b16cf8ab96f86
poster_cn_editable.pptx  c13c39c10448a5ce996a828b07eea0ae1e53f1f6ce7aecf5322ee934aa0a1e7d
poster_en_editable.pptx  f5a5812ce7ef1bc004e2ec43a76a6f007ee302ef1e017172f46adb1dc7c840bf
```

旧版海报只在历史提交和本地 `upload/_v1_backup/old_posters/` 中保留。

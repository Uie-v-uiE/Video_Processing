# GitHub 上传审查

审查对象：初审 `origin/main` = `70cf2bf0`、`origin/docs/prj-fin` = `3f06afe5`；关闭时 `main` = `047698ab`、`docs/prj-fin` = `1cd4d2ea`。审查只看已推送内容，不看本地未提交改动。

## 结论

主分支的提交树本身是干净的：没有 `.env`、密钥、缓存、`__pycache__`、临时压缩包，也没有签署承诺书或本机截图；`BOOT.bin`、`fsbl.elf`、`system.bit`、`system.xsa` 是复现所需二进制，不是垃圾。

需要处理的是“文档口径”而不是源码：docs 分支把本地原始台账一起发布了，且主分支有几处“只在本地、不上 GitHub”的旧说法已经和现状不符。

## P0：原审查发现（最终保留）

> 用户最终要求 docs 分支放全量文档，包括学习文档；因此下面这条不执行删除，main 仍只保留比赛提交面。

### 1. docs 分支的 `prj_fin/records/`

`origin/docs/prj-fin` 下有 4 个文件：

| 文件 | 大小 |
|---|---:|
| `prj_fin/records/README.md` | 377 B |
| `prj_fin/records/issues-full.md` | 1,694,553 B |
| `prj_fin/records/known-issues.md` | 137,175 B |
| `prj_fin/records/open-items.md` | 198,538 B |

这个目录的 README 自己写着“本地记录”“保留全量记录”，但它当前就在 GitHub 上。`issues-full.md` 里统计到 694 处日期、35 处 `D:` 路径、14 处 `/d/Xilinx`，还有大量早期过程、未采纳方案和内部判断。它适合留作 FIN 本地证据，不适合作为公开文档分支的内容。

**处理**：docs 分支保留 `prj_fin/records/` 作为内部文档归档；main 不包含它。FIN/records/issues 继续保留全量，main 的 `report/issues/README.md` 已改成“docs 分支全量、main 只放精选 20 条”。

## P1：旧说法与现状不符（已修）

以下位置已在 main 和 docs 分支同步修改；main 提交 `047698ab`，docs 提交 `1cd4d2ea`。

| 位置 | 现在写的 | 问题 |
|---|---|---|
| `report/collaboration/sessions/s06.md:11` | “技术文档与海报留在本地 `deliverables/`” | docs 分支已经有 `prj_fin/deliverables/technical_document.*` 和 `poster.*` |
| `report/collaboration/sessions/s06.md:18` | “技术文档和海报不随 GitHub 提交；评委拿到的是本地交付件和 FIN 包” | 同上；应改成“不进入 main 源码分支，随 FIN 提交并在 docs 分支留档” |
| `report/issues/README.md:8` | “完整台账：`FIN/records/issues/issues-full.md`（本地记录，不随 GitHub）” | docs 分支当前确实有 `prj_fin/records/issues-full.md`，说法与事实不符 |
| `report/issues/README.md:28` | “原始过程台账在本机 `FIN/records/issues/`，不进入 GitHub” | 同上 |
| `build/README.md:15` | 文档生成器“不进入 GitHub” | 准确说法是“不进入 main 源码分支”，本地归档在 FIN/records/design；否则和 docs 分支的存在容易混淆 |
| `prj_fin/deliverables/README.md:12` | “风格对比预览在本地 `poster_styles/`（不随提交）” | 本地预览已归档到 `FIN/records/design/poster_styles/`，docs 快照应改成归档路径或删掉这句 |

## P2：建议但不必删

### 1. 主分支 README 已同步

`main` 现在与本地一致，使用三条主线（同帧可比、帧级可信、整机可交付）；旧四条亮点已替换，提交 `047698ab`。

### 2. 原始日志里的本机路径和日期

`board/measured/flash_jtag.txt`、`qspi_program.txt` 含 `D:/Software/...`、`D:/Xilinx/...` 和运行日期；`skill` 卡片里也有少量 `D:/Xilinx/...`、`D:\...` 示例和 `某轮` 占位词。这些是原始证据/技能模板的一部分，不涉及密钥，但公开阅读时不够干净。若要“对外版”，建议把路径改成 `<repo>/...`，把“某轮”改成“一次实测”；不要改原始日志里的读数。

### 3. docs 分支重复了 main 的 482 个文件

docs 分支当前是 main 的完整副本加 `prj_fin/`，679 个文件。它可以工作，但维护两套源码容易漂移。若 docs 分支只承担文档展示，可以只保留 `prj_fin/`、根 README 和必要说明；源码仍以 main 为准。

### 4. docs 分支的拍摄手册已更新

`origin/docs/prj-fin:prj_fin/learning/demo_video_shooting_guide.md` 现在是 853 行的 A–J 分块执行版；旧 751 行时间线版已被替换。docs 提交 `1cd4d2ea`。

## 可以保留的内容

- 技术文档、海报、学习手册、演示拍摄手册：docs 分支的用途就是文档留档，保留。
- `BOOT.bin`、`fsbl.elf`、`system.bit`、`system.xsa`：复现和上板需要，保留。
- `report/collaboration/` 的会话卡、纠错、指标和脱敏说明：这是项目方法记录，不是原始逐字对话；保留。
- 精选 20 条 `report/issues/key-issues.md`：评委阅读路径，保留。
- 原始逐字会话、本机截图、签署承诺书：没有上传；继续保持。

## 建议执行顺序

1. 从 docs 分支删除 `prj_fin/records/`，保留 FIN 本地全量台账。
2. 修正 `s06.md`、`report/issues/README.md`、`build/README.md`、`prj_fin/deliverables/README.md` 的口径。
3. 把本地三主线 README 推到 main（如确认）。
4. 可选：清理 skill 卡片里的本机路径和“某轮”字样；是否改原始 measured 日志由你决定，默认不改读数。

第 1–3 项是公开文档一致性修复；第 4 项是可选抛光。此次审查没有向 GitHub 推送任何删除或改写。

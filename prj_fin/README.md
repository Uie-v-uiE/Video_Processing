# 项目文档合集

这个目录是本项目文档的完整快照：当前报告、历史版本、学习资料、原始记录和结果索引都收在这里。代码、工程和可执行脚本在仓库根目录，本目录只负责让人按文档顺序读下来并能追溯来源。

## 入口

| 内容 | 位置 |
|---|---|
| 技术文档 DOCX/PDF | `deliverables/technical_document.docx` / `.pdf` |
| 海报 PNG/PDF/PPTX | `deliverables/poster.*` |
| 设计报告、验证、优化、复现、局限 | `report/README.md` |
| 串口命令手册 | `report/commands.md` |
| 器件、工具与第三方声明 | `report/declarations.md` |
| 接口与寄存器表 | `report/interface-table.md` |
| 关键 Issue 台账 | `report/issues/key-issues.md` |
| 协作记录 | `report/collaboration/README.md` |
| 学习手册 | `learning/architecture_learning_guide.md` |
| 演示视频拍摄手册 | `learning/demo_video_shooting_guide.md` |
| 学习资料历史与参考 | `learning/archive/`、`learning/reference/` |
| 板级说明、验收、硬件连接 | `board/README.md` |
| 构建与实现报告索引 | `build/reports/index.md` |
| 历史报告与技能包历史 | `records/previous_report/`、`records/skill_archive/` |
| 跨工作区文档归档 | `records/docs_archive/README.md` 与 `MANIFEST.tsv` |
| 协作原始文档、Issue 全量、清单 | `records/collaboration_raw/`、`records/`、`records/manifests/` |
| 仿真结果索引 | `sim/results/README.md` |
| 完整 Issue 记录 | `records/README.md` |
| 技能包 | `skill/README.md` |
| 源码阅读入口 | `src/README.md`、`src/rtl/README.md` |

## 说明

- 技术文档按固定模板分五部分，页眉 Logo 和页码保留；非实物的框图、流程图和界面示意已生成并嵌入，图 3、8、9、11 仍是留给实物照片的图位。
- 报告中的板级日志、实现报告和仿真判定分别收在 `board/measured/`、`build/reports/` 和 `sim/results/`，正文引用可在本目录内对照。
- `report/design-report.md` 是长版设计报告；`deliverables/technical_document.*` 是按同一模板压缩后的交付版。
- 本目录不改变源码仓库 `main` 的源码内容，只作为文档分支的阅读入口。

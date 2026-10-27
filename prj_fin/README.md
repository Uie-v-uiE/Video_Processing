# 项目文档合集

这个目录是最终提交项目的完整文档快照，对应源码仓库 `main` 的比赛提交树。代码、工程和可执行脚本在仓库根目录；本目录收文档、图片、报告、历史记录和结果索引，方便按文档阅读和评审。

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
| 仿真结果索引 | `sim/results/README.md` |
| 完整 Issue 记录 | `records/README.md` |
| 技能包 | `skill/README.md` |
| 源码阅读入口 | `src/README.md`、`src/rtl/README.md` |

## 说明

- 技术文档按赛事模板分五部分，页眉赛事 Logo 和页码保留；非实物框图/流程图/界面示意已生成并嵌入，图 3、8、9、11 仍是留给作者的实物照片图位。
- 报告中的板级日志、实现报告和仿真判定分别收在 `board/measured/`、`build/reports/` 和 `sim/results/`，正文引用可在本目录内对照。
- `report/design-report.md` 是长版设计报告；`deliverables/technical_document.*` 是按赛事模板压缩后的提交版。
- 本目录不改变源码仓库 `main` 的提交内容，只作为文档分支的阅读入口。

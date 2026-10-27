# 学习资料

这个目录集中保存项目过程中写的学习手册、演示脚本和历史版本，按“当前版本、历史版本、参考资料”分类。源码与提交包仍在 `../submission/`，证据与原始记录在 `../records/`。

## 当前版本

| 文件 | 内容 | 适合谁看 |
|---|---|---|
| `architecture_learning_guide.md` | 从 Zynq-7020 平台、时钟与复位讲起，拆解网络/显示数据面、帧提交、DDR 带宽账、时序优化五轮迭代和上板调试方法 | 想理解工程全貌或复现实验的人 |
| `demo_video_shooting_guide.md` | 16:9 分屏演示视频的分块执行手册：全局排版、A–J 十个演示区块、每块的画面区域/拍摄方式/指令顺序/预期回显/剪辑方式/成片效果，以及拍摄顺序、3 分钟版和检查清单 | 需要拍演示视频或现场答辩的人 |

## 历史版本

| 文件 | 说明 |
|---|---|
| `archive/architecture_learning_guide_v1.md` | 早期架构学习稿，保留了当时的章节组织和推导过程；最终版以 `architecture_learning_guide.md` 为准 |
| `archive/host_guide.md` | 上位机侧使用与联调指南，记录推流、串口和常见故障处理 |

## 参考资料

| 文件 | 说明 |
|---|---|
| `reference/competition_guide_2026.txt` | 全国大学生嵌入式芯片与系统设计竞赛 2026 FPGA 创新设计赛道（AMD）选题指南的文本提取，便于离线检索 |

## 相关文档

- 技术文档 DOCX/PDF、最终海报：`../submission/deliverables/`
- 设计报告、验证、优化、复现、局限：`../submission/report/`
- 串口命令与声明：`../submission/report/commands.md`、`../submission/report/declarations.md`
- 板上原始日志、构建证据、旧报告归档：`../records/`

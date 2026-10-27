# 跨目录文档归档

这个目录保存从 `D:\Xilinx\Prj` 各工作区收集、去重后的文档。源目录里的代码、工程和可执行脚本不在这里；原始日志也不重复搬入。

## 扫描口径

- 范围：`D:\Xilinx\Prj` 下除 `FIN` 外的目录；
- 类型：`.md`、`.docx`、`.pdf`、`.pptx`、`.html`，以及文件名属于 README/guide/report/note/design/plan/review/issue/checklist/spec/summary/说明/报告/记录/笔记/指南/手册/清单/方案 的 `.txt`；
- 去重：与 FIN 已有文件哈希相同、或与本次已收文件哈希相同的，跳过；
- 结果：958 个唯一文档，约 69 MiB，保留原 `D:\Xilinx\Prj` 下的相对路径；
- 清单：`MANIFEST.tsv` 记录 `source_path`、字节数和 MD5。

## 来源分布

| 来源 | 文件数 |
|---|---:|
| `pro/` 各 worktree 和归档 | 698 |
| `fin2_local_archive/` | 109 |
| `Video_Processing/` | 89 |
| `IMU/` | 31 |
| `kx_word/` | 13 |
| `fin2/` | 13 |
| `prj_fin/` 与根目录 | 5 |

`pro/` 里包含旧分支、交付评审、打包归档和记录 worktree 的文档；`IMU/` 和 `kx_word/` 是 Prj 下的其他资料，也一并收进来，避免散落。它们不是本项目比赛提交内容。

`Video_Processing/report/log/` 那 9 份是 v6/v8 时期的板级调试记录（RGMII 起桥、根因分析、版本谱系、逐板实测），按路径哈希比对才补进来。`fin2_local_archive/report_old_20261022/` 存的是上一版提交包 report 的**清理前原文**（109 份，含 `timing/` 22 份逐轮时序记录和 `log/` 12 份开发日志）；`../previous_report/` 存的是同一棵树去掉日期与本机路径之后的版本，两份都在，便于对照清理动作。

## 没有收进来的东西

- 原始 `*.log`、仿真数据库、Vivado 生成目录、运行中间件；
- 已在 FIN、`submission/` 或 `prj_fin` 中的同名同内容文件；
- 代码、位流、ELF、XSA 等非文档文件。

原始日志仍在 FIN/records/build_logs 或各工作区中，按哈希和路径可追溯。

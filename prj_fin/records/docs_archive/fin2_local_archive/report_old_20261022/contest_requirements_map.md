# 参赛要求对照表（AMD 自主选题赛道 · 初级组）

> 依据：《全国大学生嵌入式芯片与系统设计竞赛'2026 FPGA 创新设计赛道选题指南（AMD）》3.3 节，重点是 3.3.5 的提交内容与 3.3.5.5 的评分项。这个表只回答“要求在哪、我们拿什么对上”，不代替设计报告。

## 1. 组别与平台

| 要求 | 本项目 |
|---|---|
| 初级组资格 | 本科一至三年级 |
| 器件范围 | AMD 7 Series / Zynq-7000 / UltraScale(+)；本项目用 **Zynq-7020（xc7z020clg484-2）** |
| 板级实测 | 有：JTAG 下载、FLASH GREEN、health GREEN、自检/连续流/分割读数 |
| 器件型号声明 | README、`report/01-overview.md`、`board/README.md` 都写了 xc7z020clg484-2 |

## 2. 3.3.5.1 工程包

| 要求 | 交付物 |
|---|---|
| 完整工程与源码（RTL、PS 软件） | `src/rtl/`、`src/ps/`、`src/constraints/`、`src/host/` |
| 仿真/验证结果，说明功能正确性如何确认 | `sim/`（80+ 台架）、`report/06-validation.md`、`build/msim/r162_full_regression_20261022.txt`、`build/msim/r162_tx_checksum_sim.txt`、C22/C31 记录 |
| 综合与实现报告（资源、频率、性能） | `build/r162/timing_summary.rpt`、`utilization.rpt`、`power.rpt`、`cdc.rpt`（当前副本 `build/reports/`）；r161 在 `build/r161/` 备查 |
| 上板工程、运行脚本、实测输出与参考比对 | `board/`、`board/measured/`、`report/70-reproduce.md` |
| 可复现构建脚本 | `build/tcl/build_system_axigpio.tcl`、`build/sim/run_msim.sh`、`board/scripts/board_flash.sh` |

## 3. 3.3.5.2 技能包（`skill/`）

| 要求 | 交付物 |
|---|---|
| 置于 `skill/`，README 说明适用范围/使用方法/失效条件 | `skill/README.md`、`skill/_meta/`、各条目 `SKILL.md` |
| 提示词工作流 / 案例模板 / 校验脚本 / 踩坑清单 | `skill/prompts/`、`skill/scripts/`、`skill/checklists/` 等（以 `skill/README.md` 索引为准） |
| 评价标准是可复用性 | 每条写“适用场景、使用方法、已验证效果、来自哪些失败/观察”；`skill/_meta/check-skill-package.mjs` 做装配检查 |
| 通用 PYNQ Skill 加分 | **本项目没有做 PYNQ Overlay**，这是明确缺口。若后续要补，需要把 PL 计算核封装成 Overlay、用 Python/Jupyter 组织数据流，并写清换题目/换板卡仍可用的范围 |

## 4. 3.3.5.3 设计报告

| 要求 | 本项目的对应章节 |
|---|---|
| 选题背景与创新点 | `report/innovation_and_landing.md` 第 1–4 节；`report/innovation.md` |
| 设计原理与功能框图 | `report/architecture_learning_guide.md` 第 2–8 章；`report/02-architecture.md`；7 页技术文档 |
| 软硬件划分依据与接口设计 | `report/02-architecture.md`、`report/interface-table.md`、`report/contest/` |
| 优化过程与前后对比表 | `report/40-optimization.md`、`report/50-results.md`、7 页技术文档 3.4；r160/r161/r162 时序对比 |
| 大模型协作记录（提示词/回答/纠错轨迹） | `report/log/issues.md`、`report/collaboration/`、`skill/` 的提炼记录 |
| 技能包提炼过程 | `report/07-skill-distillation.md`、`skill/README.md` |
| 复现说明（从零开始） | `report/70-reproduce.md`、`README.md`、`board/README.md` |

## 5. 3.3.5.4 目录与命名

官方要求：仓库内所有目录名与文件名用**纯英文小写字母、数字、下划线或连字符**，不得有中文、空格或特殊字符；中文只出现在正文内容里。

本包的目录结构：

```text
fin/
├── README.md / README_EN.md
├── src/        # RTL、PS 软件、约束、上位机
├── sim/        # 台架
├── build/      # 构建脚本、r156..r162 报告、msim 日志
├── board/      # 上板脚本、project 三件套、measured 读数
├── data/       # 指标与参考数据
├── skill/      # 技能包
└── report/     # 设计报告、架构学习手册、拆解/缺陷手册、创新与落地
```

**已处理**：根目录技术文档已改名为 `technical_document.docx` / `technical_document.pdf`，生成器 `build/make_technical_doc.py` 与导出脚本 `build/export_fin.sh` 已同步。海报文件名保持英文（`poster.*`），候选版本在 `poster/` 下也是英文。`fin/report/` 里的文件名都是英文，正文中文，符合要求。

## 6. 3.3.5.5 评分项与证据

| 评分项 | 权重 | 我们的主要证据 | 主要短板 |
|---|---|---|---|
| 创新性与应用价值 | 30 | 同帧 A/B 量具；PL 内可解释遥测；可红自检；C22/C31 判据化 | 没有真实客户/现场；没有多路/长稳/压缩 |
| 性能与资源优化 | 20 | r162 WNS 1.378/WHS 0.046；240 帧/8.00 s/30 fps；r162 校验和 A/B；DDR 方案测量 | BRAM 70%；没有 1080p 实现；功耗只有工具估算 |
| 功能正确性与完整性 | 20 | 全链路、三源、SD、八档缩放/任意角旋转/双线性/六级效果/竖缝/OSD；17 台架 fail=0；板上读数 | RGMII/HDMI I/O 未约束；固件 JTAG；绝对角度命令缺 |
| 大模型协作与技能包 | 15 | `skill/` 索引/条目/检查；issues 轨迹；C28→C31 案例 | 用前/用后量化不全；无 PYNQ 通用 Skill |
| 文档质量与可复现性 | 15 | README/EN、7 页技术文档、学习手册、拆解手册、创新文档、证据索引、脚本 | 文档多需入口；历史漂移；Linux 未逐条验；文档图片待放 |

## 7. 决赛海报

官方要求：进入决赛的自主选题队伍按 AMD 提供的 PPT 模板提供**一页英文 PPT 海报**，不含队伍信息，A4 彩色打印带到现场。

本包提供：`report/poster_variant_a/b/c.*`（2560×1440 PNG/PDF，源 PPTX 在 `build/`）。队伍选一版后，按官方模板替换背景/版式，保留英文与 AMD 商标声明。海报不含队伍信息。

## 8. 提交前检查清单

- [ ] 根目录中文 docx/pdf 改英文名。
- [ ] 选定的海报版本与 `README` 链接一致。
- [ ] 7 页技术文档里的两个图片占位框替换为实物照片/框图。
- [ ] `build/r162` 的时序结果写进 README/技术文档/海报（若 r162 胜出）。
- [ ] `board/project/system.bit`、`.xsa`、`ps_app.elf` 的 md5 与文档一致。
- [ ] 技能包 `check-skill-package.mjs` 与 `check-selftest.mjs` 跑过。
- [ ] 复现步骤在一台干净机器上至少走通“构建 → 台架 → 上板”三步。

# 设计报告与证据

`report/` 放四类内容：设计报告、验证与优化、复现说明、协作记录。数字只在设计报告和验证文档里各出现一次，支撑材料放 `build/reports/` 与 `board/measured/`。

## 阅读顺序

1. `design-report.md`：系统是什么、为什么这样划分、关键算法与时序、结果与边界。
2. `verification.md`：台架矩阵、专项判据、板上验收、没有覆盖的部分。
3. `optimization.md`：时序与资源优化的五轮过程、被否决的尝试、物理边界。
4. `reproduction.md`：从零构建、仿真、PS 应用、Vivado/Vitis 工程、上板与 QSPI。
5. `limits.md`：仍然成立的限制与未修项。
6. `llm-collaboration.md` 与 `collaboration/`：大模型参与方式、会话卡、纠错轨迹、提示词、工作流、成本与脱敏记录。
7. `issues/key-issues.md`：20 条关键缺陷的现象、根因、判据、修复与证据；完整台账在 FIN/records。
8. `interface-table.md`：控制字、遥测、串口、lane、地址与视频常数。
9. `commands.md`：串口命令手册，逐条说明参数、成功回显和非法输入。
10. `declarations.md`：器件、工具链、第三方与自研边界。
11. `skill-distillation.md`：技能包从哪些失败里总结、怎么验证、边界在哪。

## 图件

`figures/contest/` 放设计报告用的系统图、入包链、显示链、效果链延迟和时序资源图。图 9 是同帧左右对照的渲染示例，由测试帧生成，不是屏幕照片；报告里按这个口径引用。

## 证据在哪

| 内容 | 位置 |
|---|---|
| 时序、资源、CDC、功耗报告 | `build/reports/` |
| 完整视频台架与回归判定行 | `build/reports/`、`sim/results/`、`sim/README.md` |
| 板上启动、串口、遥测、自检日志 | `board/measured/` |
| 控制字、遥测字段、串口命令 | `interface-table.md`、`commands.md`、`design-report.md` 附录 A |
| 器件、工具链、第三方声明 | `declarations.md` |
| 关键缺陷与根因 | `issues/key-issues.md` |
| 实测与参考比对 | `board/compare/` |
| 大模型协作详细档案 | `report/collaboration/` |
| 技能包索引 | `skill/README.md`、`report/skill-distillation.md` |

## 写作口径

- 数字必须带测量条件和证据；没有量过的项写 `NOT_MEASURED`，不写“应该没问题”。
- 不写版本演进的流水账；优化只写“优化前/优化后”和代价。
- 不出现本机路径、日期和工具安装路径；仓库内路径用相对路径。
- 人眼判据和机器判据分开写，不把“台架绿”写成“板上也绿”。

## 当前边界

BRAM 70%、RGMII 发送侧保持缺口、遥测时延只覆盖 PL 内部、HDMI 画面需人眼签收。逐条说明在 `limits.md`。

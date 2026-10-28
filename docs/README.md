# 文档索引

`docs/` 放设计、验证、优化、复现、接口与限制这几类文档。主要读数以设计报告和验证文档为准，支撑材料在 `hw/reports/` 与 `hw/measured/`。

## 阅读顺序

1. `design-report.md`：系统是什么、为什么这样划分、关键算法与时序、结果与边界。
2. `verification.md`：台架矩阵、专项判据、板上验收、没有覆盖的部分。
3. `optimization.md`：时序与资源优化的过程、被否决的尝试、物理边界。
4. `reproduction.md`：从零构建、仿真、PS 应用、Vivado/Vitis 工程、上板与 QSPI。
5. `limits.md`：仍然成立的限制与未修项。
6. `issues/key-issues.md`：关键缺陷的现象、根因、判据、修复与证据。
7. `interface-table.md`：控制字、遥测、串口、lane、地址与视频常数。
8. `commands.md`：串口命令手册，逐条说明参数、成功回显和非法输入。
9. `declarations.md`：器件、工具链、第三方与自研边界。

## 图件

`figures/` 放设计报告用的系统图、入包链、显示链、效果链延迟与时序资源图。其中同帧左右对照的渲染示例由测试帧生成，不是屏幕照片，报告里按这个口径引用。

## 证据在哪

| 内容 | 位置 |
|---|---|
| 时序、资源、CDC、功耗报告 | `hw/reports/` |
| 完整视频台架与回归判定行 | `hw/reports/`、`sim/results/`、`sim/README.md` |
| 板上启动、串口、遥测、自检日志 | `hw/measured/` |
| 控制字、遥测字段、串口命令 | `interface-table.md`、`commands.md`、`design-report.md` 附录 A |
| 器件、工具链、第三方声明 | `declarations.md` |
| 关键缺陷与根因 | `issues/key-issues.md` |
| 实测与参考比对 | `hw/compare/` |

## 写作口径

- 数字必须带测量条件和证据；没有量过的项写 `NOT_MEASURED`，不写"应该没问题"。
- 不写版本演进的流水账；优化只写"优化前/优化后"和代价。
- 不出现本机路径、日期和工具安装路径；仓库内路径用相对路径。
- 人眼判据和机器判据分开写，不把"台架绿"写成"板上也绿"。

## 当前边界

片内存储决定画幅上限、RGMII 发送侧的保持缺口、遥测时延只覆盖 PL 内部、HDMI 画面需人眼签收。逐条说明在 `limits.md`。

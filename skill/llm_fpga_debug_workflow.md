# S5 · 大模型辅助 FPGA 调试的提示词与验证工作流

## 适用场景
- 用 LLM 写 RTL / 定位上板问题 / 整理工程材料，且**要求每个结论能追溯到文件与数字**。
- 工程已经有一批可跑的资产（台架、构建脚本、报告、回读工具）——没有可执行判据时本工作流不成立。
- 不适用：需要肉眼判定的画质问题（缩放走样、色彩、抖动），见失效条件 4。

## 使用方法
1. **先给上下文**：器件（`xc7z020clg484-2` 这类精确 part）、工具链版本（Vivado/Vitis 2025.2.1）、
   架构图（`report/ARCHITECTURE.md`）、失败日志**原文**（`build/*.log`、`sim/*.log`）。
2. **拆问题**：一次只要「根因假设列表 + 最小验证步骤」，不要一次要完整工程。
   本仓库的做法是让只读子代理做交叉阅读（禁止改文件、禁止跑仿真，避免和构建抢 `sim_work`），
   产候选并附文件行号（`report/OVERNIGHT_LOG.md` §7 R01/R02 行）。
3. **要求可证伪**：让模型写出「若假设成立应看到 X」，并把 X 变成一条能跑的判据。
   范例：R07 把判据写成「若拆分 impl-only 时钟组后实现阶段时序数字发生变化，就说明原先
   『synth 阶段无约束』的假定是错的 ⇒ 停下重查」，结果 `build/system.bit` 的 md5 与 R06
   **逐字节相同**（`7d2cf8ee`）⇒ 改动中性被证明（`report/OVERNIGHT_LOG.md` R07）。
4. **RTL 约束**：注释只写非显然的 WHY；禁止无端加流水「以防万一」；禁止顺手加超时计数器
   （R03 明确**否决**了「加超时兜底」，改用 CDC 排空本身当兜底条件）。
5. **交叉验证**：改完必须过 `vivado -mode batch -source sim/run_sim.tcl` 与报告门禁；
   上板问题优先对照 `report/ISSUES.md`。**数字不许采信转述**——本仓库每轮都由主代理
   直读 `build/*.rpt` 复核（`report/OVERNIGHT_LOG.md` §7 R01 行「数字全部由主代理重新直读复核」）。
6. **凡「综合器才知道」的问题用最小实验回答，而不是问模型**：
   `sim/probes/ramtest.v`（5 个写法变体，回答「为什么 `ram_style` 被忽略」）、
   `sim/probes/fbtest.v`（6 变体数 RAMB36）、`sim/probes/dpfb.v`（双读口代价）。
7. **披露与边界**按 `report/AI_COLLABORATION.md` 记录：每节写「触发问题的提示词 → 模型的关键判断
   → 被板级/仿真推翻或证实的过程」。

## 已验证效果
- 这套纪律在本仓库**推翻了 3 次模型（含我自己）的结论**，而且每次都留下了可复核的数字：
  ① R02 采纳子代理 4 条中的 3 条、否决 1 条「`else if (idle) pack_base <= ...`——在
  `!cur_dirty` 已成立时是死代码」（`report/OVERNIGHT_LOG.md` §7 R02）；
  ② R09 拔线实验推翻「断链 ⇒ PHY 停供 RXC」的假设：板上 `hb_gone` 恒 0，而 `stall_ms`
  在断流 13 秒里只走 831→1117（**+20.5 计数/秒**，不是 1000/秒）⇒ RXC 被拉慢约 48 倍；
  第二次受控拔线独立量到 **49.3×**（`data/measured/board_measure_r09.md` §受控拔线）；
  ③ R11 把自家收益表推翻重来：`2x2 盒 = 99 dB` 是「理想像坐标差半像素」造成的自证，
  修正后加**锚点 + 反向对照**双判据（带限图样恒等下最近邻实测 **45.4 dB**、故意用旧约定
  **30.0 dB**），任一不满足就 `exit(1)`、整张表不许引用（`report/CHANGELOG_V7.md` V7.7）。
- 外部检索的落地率被如实记成 0：UG901/UG473、arXiv 2009.09622、三个同类 GitHub 工程都
  **未进入构建路径**，真正改变设计决策的是探针数字（`report/OVERNIGHT_LOG.md` §8）。
- 判据纪律本身有产物：`sim/run_sim.tcl` 不再把 `NO_ASSERT` 计为 pass，
  因为「一个什么都不断言的台架可以永远绿」（`report/OVERNIGHT_LOG.md` R13 第 3 条）。
- 「工具自报成功」同样按不可信处理：`build/ps_app.mjs` 第一次「链接成功」的镜像 `.text` 只有
  **80 字节**（`--gc-sections` 把 `main` 裁光了）⇒ 现在脚本强制检查 `_start`/`main`/
  `XSdPs_CardInitialize` 与 `.text ≥ 20 KB`（R13 第 2 条）。

## 失效条件
1. 只让模型「直接改 bit / 改 xdc 管脚」而没有原理图或 `report/BOARD_PINS.md` 依据 ⇒ 立即停手。
2. 无仿真、无日志的纯猜测循环；以及把**未上板**的数据写成实测结论。
   本仓库的可执行出口就三个：`sim/run_sim.tcl`、`build/tcl/build_system_axigpio.tcl`、
   `build/tcl/ooc_newmods.tcl`（后者的数字**不是门禁**，它对输入一律加 3 ns，
   `osd_overlay` 在那里报 −0.256 而真实 L3 是 +0.527）。
3. 子代理/模型转述的数字未经直读复核 ⇒ 本工作流要求「引用即给路径」，否则降级为假设。
4. 画质类问题（缩放走样、色彩、抖动）收敛不了：判据只覆盖**数据完整性**
   （`report/AI_COLLABORATION.md` §6，右屏细线闪烁最终确认是最近邻走样、与丢字无关）。
5. 「把 ISSUES 当检索索引」这条依赖编号稳定：**本仓库 `report/ISSUES.md` 现在是 35 条**，
   旧笔记里的「19 条」指的是 `origin/v1-ps-ethernet:docs/ISSUES.md`
   （`report/VERSION_LINEAGE.md` §V1）⇒ 跨版引用编号前先核对，否则索引指向错的条目。
6. 提示词模板、模型与协作边界**没有做过跨模型/跨工程的可比性实验** ⇒ 本节只主张
   「这些纪律在本仓库抓出过具体缺陷」，不主张通用效果（未验证）。

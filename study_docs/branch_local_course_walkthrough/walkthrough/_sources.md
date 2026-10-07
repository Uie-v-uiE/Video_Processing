# _sources.md · 结论与来源登记（本目录全部引用）

口径：一行一个结论。**来源**只允许两种：本次真的打开过的仓库文件（带路径），或本次真的抓到的外部 URL。
抓失败的一律记在最后一节，并且对应的正文必须已经降级为 `【未核实】`。
核对日期全部为 **2026-10-04**。

## 第 1 节 仓库文件类来源（本次逐行打开过）

| 结论一句话 | 来源 | 核对日期 |
|---|---|---|
| 板上顶层是 `system_top`，它只例化 5 只子模块并做 lane 读回 mux | `src/rtl/top/system_top.v` | 2026-10-04 |
| 显示通路顶层 1050 行、32 只实例、11 段打拍同步链 | `src/rtl/top/pl_video_top.v` | 2026-10-04 |
| 收包链 14 只实例、`gmii_tx_clk` 与 `gmii_rx_clk` 同一根 | `src/rtl/eth/eth_udp_video_top.v`、`src/rtl/eth/gmii_to_rgmii.v` | 2026-10-04 |
| RGMII 收侧 IDDR 与 fabric 同吃一只 BUFG，延时由顶层常数给 | `src/rtl/eth/rgmii_rx.v:1-90` | 2026-10-04 |
| 跨域数据面只走格雷码异步 FIFO；满判据用"当前指针" | `src/rtl/eth/dc_fifo.v` | 2026-10-04 |
| 提交带帧尾排空门（`TAIL_GUARD`），旧判据会吃掉帧尾 4 字节 | `src/rtl/eth/ddr_bank_commit.v` | 2026-10-04 |
| 健康统计 16 位字段一律饱和不回卷；快照有发布节流 | `src/rtl/eth/link_monitor.v` | 2026-10-04 |
| `snap_cross` = 准静态总线 + 沿捕获，另有慢/停两位心跳判据 | `src/rtl/eth/snap_cross.v` | 2026-10-04 |
| 一帧提交的三重门：字节预算 + 逐行覆盖 + 无坏包 | `src/rtl/eth/frame_reasm.v:1-120` | 2026-10-04 |
| 整帧搬运只在消隐窗口做，超窗变 LED 快闪；看门狗 20 ms | `src/rtl/video/frame_commit_lock.v`、`src/rtl/top/pl_video_top.v:442-452` | 2026-10-04 |
| 搬运机 16 拍突发、4 个在途、abort 后先排在途 | `src/rtl/axi/axi_frame_writer_gated.v:1-75` | 2026-10-04 |
| 效果链固定 15 拍、内容滞后 4 行、坐标由级数推出 | `src/rtl/process/proc_pipeline.v` | 2026-10-04 |
| 角度必须在帧边界换；发射触发器不共用 | `src/rtl/process/rotate/angle_ctrl.v` | 2026-10-04 |
| 仲裁"谁活着 + 能不能安全换手"，手动锁不改换手时机 | `src/rtl/util/src_arb.v` | 2026-10-04 |
| 片源模式四态格雷码环 + 命令覆盖；同步器前不许挂组合逻辑 | `src/rtl/util/src_mode.v` | 2026-10-04 |
| 发布是电平语义（会合并），单独成模块以便台架逐相位验 | `src/rtl/util/ps_publish.v` | 2026-10-04 |
| 按键域复位是死支路 ⇒ 上电值由声明初值承载 | `src/rtl/util/key_debounce.v:1-31` | 2026-10-04 |
| 栅格 1024×600、总 1344×625、`frame_start` 落在第一个有效像素 | `src/rtl/video/video_timing.v`、`src/rtl/video/video_timing_1024x600.v` | 2026-10-04 |
| MMCM 由 50 MHz 出 50/250/200 MHz，VCO 1000 MHz | `src/rtl/clocks/clk_gen.v` | 2026-10-04 |
| PS 是控制面 + SD 回放；UDP 数据通路整个在 PL | `src/ps/main.c:1-260`、`src/ps/main.c:1571-1595` | 2026-10-04 |
| SD 帧由 DMA 直写 PL 要读的那块 DDR，读前刷 cache | `src/ps/sd_play.c:1-60`、`:86-96` | 2026-10-04 |
| 引脚与时钟约束、只有一行 hold 不确定度、假路清单 | `src/constraints/rk_zynq7020.xdc` | 2026-10-04 |
| 异步时钟组单独成文件且只在实现阶段生效（含原因） | `src/constraints/clock_groups_impl.xdc` | 2026-10-04 |
| 构建入口钉三个 GPIO 基址、地址回读校验、报告一并产出 | `build/tcl/build_system_axigpio.tcl` | 2026-10-04 |
| 早期工程脚本只建 HP0 一条互联（与现役脚本不同） | `build/tcl/create_project.tcl` | 2026-10-04 |
| 门禁 22 项、CDC 按配对集合判、`n/a` 会降级为 PARTIAL | `build/gates.sh` | 2026-10-04 |
| 单台架 runner 的退出码把"红"与"没数"分开 | `sim/run_one.sh` | 2026-10-04 |
| 唯一数字表：WNS/资源/功耗/帧率/时延各点名报告 | `data/metrics.csv` | 2026-10-04 |
| 全局时序方法与约束欠账（四域同表念法） | `report/TIMING_GLOBAL.md:1-120` | 2026-10-04 |
| 板上验收表：机器判据 10 条 + 眼睛判据若干，逐条点名凭据 | `board/ACCEPTANCE.md` | 2026-10-04 |
| 上板三步链与 JTAG 前置 | `board/README.md:1-45` | 2026-10-04 |
| 交付首页的"复现三步"与关键数字口径 | `README.md` | 2026-10-04 |
| 模块清单与"13 个未例化文件"的正本 | `report/MODULES.md:1-60` | 2026-10-04 |
| 串口命令与位表正本（本目录不复制） | `report/COMMANDS.md:1-70` | 2026-10-04 |
| 脉冲跨域只能走翻转式；发射触发器各自独立 | `skill/pulse_toggle_cdc.md:1-40` | 2026-10-04 |
| CDC 门禁要比配对集合 + unsafe 数 | `skill/cdc_pair_baseline_gate.md:1-25` | 2026-10-04 |
| lane 读回的用法与两个 GPIO 基址 | `src/host/health_read.mjs:1-45` | 2026-10-04 |
| 包形：4 字节小端偏移 + ≤1392 B 载荷；画幅 512×300 的原因 | `src/host/video_sender.py:1-40` | 2026-10-04 |
| 行号引用的判据强度与豁免边界（本文引用格式的依据） | `src/host/line_cite_check.mjs` | 2026-10-04 |

## 第 2 节 本次实跑的命令与看到的输出（不是引用别人的日志）

| 结论一句话 | 来源 | 核对日期 |
|---|---|---|
| 冻结件目录能只读跑完门禁：末行 `GATES: PARTIAL —— 判定 22 项全过，但有 2 项因缺凭据未判`；其中一份端点总数 39915 | 本人执行 `bash build/gates.sh build/evidence_r75`（件目录 `build/evidence_r75/`） | 2026-10-04 |
| 写入本目录**之后**同一把尺子：`D5: CLEAN`、硬错 0 条、锚点命中 783 条、扫 187 份文档 | 本人执行 `node src/host/line_cite_check.mjs`（本目录 11 个文件已在盘上） | 2026-10-04 |
| 行号核对尺子在写入本目录**之前**的状态：`D5: CLEAN`、硬错 0 条、命中 360 条、扫 121 份文档 | 本人执行 `node src/host/line_cite_check.mjs` | 2026-10-04 |
| `proc_pipeline` 在顶层只有一处例化 | 本人执行 `grep -n "proc_pipeline" src/rtl/top/pl_video_top.v` ⇒ 命中 `:800` 与三处注释 | 2026-10-04 |
| 当前树里 `snap_cross` 例化 4 处（`pl_demo_top` 那棵没有） | 本人执行 `grep -rn "snap_cross *#\?(" src/rtl --include=*.v` | 2026-10-04 |
| 全树实例数分母 222（历史冻结件那份是 199） | `build/ports_check.txt:1`、`build/evidence_r75/ports_check.txt:1` | 2026-10-04 |
| 交付文档里没有任何指向 `docs/walkthrough` 的反向引用 | 本人执行 `grep -rn "docs/walkthrough" README.md report skill board build sim src` ⇒ 输出为空 | 2026-10-04 |
| 三只 AXI GPIO 全部不带中断控制器 | `build/tcl/build_system_axigpio.tcl:95`、`:105`、`:124` | 2026-10-04 |
| `skill/pitfalls/` 这个目录在本仓库不存在 | 本人执行 `ls skill/pitfalls` ⇒ `No such file or directory` | 2026-10-04 |

## 第 3 节 尝试抓取但失败的外部出处（因此正文已降级）

| 想核的结论 | 尝试的来源 | 结果 | 正文处理 |
|---|---|---|---|
| 亚稳态不可消除、只能降概率（MTBF 口径） | `https://en.wikipedia.org/wiki/Metastability_(electronics)` | 两次抓取均 `fetch failed` | `glossary.md` 词条 3 第 ③ 层写 `【未核实】` |
| AXI VALID/READY 的独立性条款 | `https://developer.arm.com/documentation/ihi0022k/`（重定向到 `https://support.arm.com/documentation/ihi0022k/`） | 重定向后再抓，返回的是站点配置、没有正文条款 | `glossary.md` 词条 22 第 ③ 层写 `【未核实】`；`mechanics.md` 因此未开写 |

⇒ **这批失败直接阻塞了两篇**：`mechanics.md` 与 `next-layer.md` 按 P11 要求"每条通用原理必须带规范出处"，
没有可用外部出处就不动笔（记录在 `_progress.md`）。

小结 1：本表第 1、2 节是本目录全部实证；第 3 节是明确拿不到实证的两条，正文里已按 `【未核实】` 处理。
小结 2：下一批续写时，新增结论必须在同一张表加行；不加行的引用按红项处理。下一步：`_progress.md`。

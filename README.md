[English](README.en.md)

# Zynq 实时视频图像处理与逐像素对照显示

一块 Zynq-7020（`xc7z020clg484-2`）跑着一整套实时视频通路：**千兆网、SD 卡或片内图卡**任一路
送来视频，PL 侧完成缩放、旋转与图像处理，最终以 **HDMI 1024×600（像素时钟 50 MHz，时序 1344×625 ⇒ 场频 59.5 Hz）** 上屏（PL 处理画幅为
512×300 的 RGB565，输出侧做 ×2 展开到面板）。屏幕上任何一条竖线**以左是未经处理的画面、以右是
同一坐标系下处理后的画面**，分割线可以固定、自动扫描，也可以贴在图像域里跟着旋转缩放一起走。

这个"同帧逐像素对照"是立足点：它既是一种显示方式，也是**一台测量仪器**——边缘条带、一行错位、
一个越界格子，都不用加额外探针就能被肉眼看见，也能被同一套几何关系直接算出来、被台架判成数字。

## 特点

- **三路片源，仲裁在硬件里**：RGMII 收 UDP 视频流（自研收包链，带 CRC 校验与坏字计数）、
  SD 卡本地播放（FAT32 簇链自研解析，不依赖文件系统库）、PL 自绘动态测试图卡；任一路心跳消失
  半秒内自动让位，PS 只发命令、不参与数据面。
- **几何通路**：八档缩放（定点逆序比例，不做实时除法）、多档旋转（正弦/余弦 ROM + 象限折叠），
  最近邻与双线性插值可运行时切换。
- **效果链**：灰度、反色、3×3 均值模糊、锐化、Sobel 边缘、阈值二值化（含判决反相位）、
  3×3 腐蚀/膨胀，共九位控制字，逐级可旁路，整链固定 15 级流水。
- **对照显示**：0–100 % 任意分割线、左/右互换、2 像素标记线可关；原图抽头用行延迟环与
  处理链对齐到同一拍同一列。
- **屏上状态**：OSD 五行（`N_LINES=5`）显示片源、角度、缩放档与来源、效果码、分割线位置、
  帧率、时延、温度。
- **在线自诊断**：收包/丢包/坏字/CRC、乒乓 bank 状态、链路内时延，全部由硬件计数，
  同时上 OSD 与串口读回——拔线、拔卡之后的行为可以核对，不靠运气。
- **可复现到底**：一条命令出位流，一份脚本跑门禁与上板校验，Vivado 报告原文随包；
  数字只写实测过的，估算值（如功耗）会标明是估算。

## 复现三步

```bash
# 1) 建工程 → 综合 → 实现 → 出位流（Vivado 2025.2.1，命令行）
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
# 2) 门禁：时序/资源/端口/CDC/文档一致性 + 整屏逐像素台架（项数以脚本打印的那行为准）
bash build/gates.sh
# 3) 上板（只走 JTAG，本工程不向 QSPI/SPI flash 写入）：PS 起来 → 烧 PL → 重载应用 → 一把验完
<Vitis>/bin/xsdb.bat build/tcl/ps_jtag_boot.tcl
vivado -mode batch -source build/tcl/program_pl.tcl
<Vitis>/bin/xsdb.bat build/tcl/ps_app_reload.tcl
VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom
```

上位机推流：[src/host/video_sender.py](src/host/video_sender.py) 发**任意视频文件**
（装了 ffmpeg 就解任意格式，没装就发内置测试图，两者都缩放到 PL 的 512×300 画幅再发）；
板子在手边时**双击 [send_demo.bat](send_demo.bat)**——它先 ping 板子，再推一段自带测试视频。
命令表、寄存器映射与逐项判据见 [report/HOST_GUIDE.md](report/HOST_GUIDE.md)、
[report/COMMANDS.md](report/COMMANDS.md)、[report/BUILD.md](report/BUILD.md)、
[board/README.md](board/README.md)。

## 关键数字（每个数点名它的报告）

| 指标 | 读数 | 出处 |
|---|---|---|
| 全设计 setup WNS | **0.739 ns**，失败 setup/hold 端点 **0 / 51135**（hold 侧 0 个失败、总端点 51135）。板上现在跑的是 r118：2026-10-04 04:49:50 由三步 JTAG 链刷入，bit `cd04907e1369`，`board_verify --geom --battery --round=r118` 于 PASS PASS；24 项门禁读作 **门禁 24 项 23 绿 / 1 红**（唯一红项是声明过的 `C5c` 顶层台架那一项），件 `build/r118_gates.txt`。⚠ **这一版不带 RGMII 输入窗**：r116 给 `eth_rxd[3:0]`/`eth_rx_ctl` 绑上 min 1.200 / max 2.800 之后，那 5 个第一次被检查的端点在自家发布门上判红（WNS、WHS 与两个失败端点数一共 4 条硬门红），本轮按 H7 把这条约束**退回候选件**（`src/constraints/r116_rgmii_input_window.xdc` 原件留在仓里、`VP_R116_IO_WINDOW=1` 一条命令复现带窗那一版）。相对 r114 这**不是放宽**（r114 从来没有这条约束；`仓库内的松动台账（在不随提交包的那份文档目录里）` 仍 0 条），但代价要一起念：那 5 个收口端点现在回到**没检查**状态，而提示词 H5 禁的正是把"没检查"读成"满足"，所以这一行的含义是"片内路径零违例 + 收口 I/O 当前无窗"，不是"收口已通过"。带窗那一版的完整证明留在 `report/TIMING_GLOBAL.md` 第 6 节（0…31 全档 hold 与 setup 区间不相交：hold 要 tap ≥ 44.8、setup 要 tap ≤ 21.8；根因是两只钟的角间差 3.411 ns 而数据侧只有 0.467 ns；件 `build/evidence/r115_window/probe3_console.txt`） | `build/timing_summary.rpt`、`build/r118_gates.txt`、`build/evidence/r118_bit_md5.txt`、`build/evidence/r118_board/BOARD_NOW.txt` |
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **0.739 ns**（占它 8 ns 周期的 9.24 %（绝对最紧那一格在 `eth_rxc`，按周期归一后最紧在 `eth_rxc`））；100 MHz `clk_fpga_0` **1.85 ns**（18.5 %）；50 MHz 显示域 `clkout0_1` **3.63 ns**（18.15 %）；`sys_clk` **14.876 ns**（74.38 %，这一档最宽）。差分基线 = **r114 的官方名册**（件 `build/evidence/r114_after_roster_probefmt.txt` → `build/evidence/r117_roster_diff_vs_r114.txt`；同一套约束、同一把生成器才是同一条尺子，混口径相减会被 `build/timing_roster_diff.sh` 的口径闸门判 REFUSE——这一条我今晚踩过一次，账在 `report/log/ISSUES.md` #326）。本轮进构建只有一刀：`IDELAY_VALUE` 26→31（r116 在同一份已布线 DCP 上把 0…31 扫满量出来的眼心，只读扫描、没花一次构建）。**C9（把 `u_pl/u_row/hi_reg_0[0]` 这根 239 引脚广播网强制复制）量过并否决**：官方构建 r117 实测它确实把 `clk_fpga_0` 抬到 2.104 ns（机制也成立：239→1 引脚、10 颗 replica），但同一份名册里 `clkout0_1` 与 `sys_clk` 的 setup、`eth_rxc` 的 setup 与 hold **四格一起变小**（件 `build/evidence/r117_roster_diff_vs_r114.txt`、`build/r117_verdict_declined.txt`），起飞前预登记的 A2/A3 是严格口径（任何一格不许变小）⇒ 按 H7 回滚这一处切割；钩子原件留在 `build/tcl/r117_post_place_hook.tcl`，设 `IMPL_POST_PLACE_HOOK` 即可复现那一版（bit `beda9298331d`）。**实测结果：名册 8 对逐格与 r114 逐位相同（`clk_fpga_0` 18.5 %、`clkout0_1` 18.15 %、`sys_clk` 74.38 %、`eth_rxc` 9.24 %，hold 四格也一值不差，件 `build/evidence/r118_strict_b1.txt`）**⇒ τ=31 这一刀在片内时序上是**可证明中性**的（它只动 I/O 单元的抽头，收益在片外到达窗：+0.315 ns 的眼心余量）。`clk_fpga_0` 这一格仍然停在 18.5 %——它是名册上唯一“明知未到极限”的一格，对症那把刀（复制广播网）量过判负，所以这里留的是**没被解决、但已被证明不是逻辑与策略问题**的读数，根因 `FANOUT`：数据 7.355 ns 里 route 6.871 ns、其中 5.690 ns 在这一根 239 引脚的网上，负载铺 99 个 tile，件 `build/evidence/r117_d0/`）。规矩 35：绝对 WNS 的跨构建差不算收益也不算损失，收益只按"同一个钟自己动没动"念；`eth_rxc` 不吃这一刀，名册里它两格逐格不动 | `build/evidence/r118_after_roster_probefmt.txt`、`build/timing_summary.rpt`、`build/evidence/r114_after_roster_probefmt.txt`、`build/evidence/r117_roster_diff_vs_r114.txt`、`build/evidence/r117_d0/worst_clk_fpga_0_setup.rpt` |
| 保持时间 | 全设计最差那一格在 `eth_rxc`，**0.052 ns**（3 级逻辑、走线占这条数据路径延迟的 56.48 %；件 `build/hold_paths.rpt`，本轮布线后重生成）；逐时钟 WHS：`clk_fpga_0` **0.053 ns**、`clkout0_1` **0.059 ns**、`sys_clk` **0.222 ns**、`eth_rxc` **0.052 ns**。⚠ 两句口径要一起念：① 本版**没有** RGMII 输入窗，所以 `eth_rxc` 那个 WHS 是**片内那一族**的数、不是收口 I/O 的数（带窗那一版同一族报 −0.870，件 `build/evidence/r116/r116_io_HOLD.rpt`）；② 只有 `eth_rxc` 带着 r79 加严的 0.800 ns hold 不确定度，其余三个域的报告里没有那一行 ⇒ 这四个 WHS 目前只能两两比同域，跨域比"谁更薄"要等不确定度带补齐（`不确定度 A/B 那件（在不随提交包的那份文档目录里）` 已经量过：统一加严到 0.800 之后 WHS 变 −0.747 / 25,742 个失败端点，读数会变难看、**本轮未采纳**）。本版不挂任何物理机构（C9 已否决），所以 `IDELAY_VALUE` 只动 I/O 单元的抽头值，名册差分对 r114 逐格不劣化——判据用的是严格那把尺子（件 `build/evidence/r118_strict_b1.txt`），不是 `timing_roster_diff.sh` 的 25 % 门槛（#328） | `build/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/hold_paths.rpt`、`build/evidence/r117_roster_diff_vs_r114.txt` |
| BRAM / LUT / FF / DSP | **95.5 tile（68.21 %）/ 14154（26.61 %）/ 8188（7.7 %）/ 19（8.64 %）**与 r114 相比本版**不加机构**（C9 已否决），资源侧不应出现可归因的增量；判据 B3 的地板按数念（Slice 寄存器与 r114 同值、无 `Place 30-439`、`route_status` successful） | `build/utilization.rpt`、`build/evidence/r118_after.txt` |
| 功耗 | 动态 **2.213 W**（片上合计 2.391 W）、估算结温 **52.6 °C**（工具置信度 Low，**是估算**，没有实测；板上片上 XADC 的读数是另一路，见 `data/metrics.csv` 与串口 `temp`） | `build/power.rpt` |
| SD 本地播放 | **29.8 – 30.0 fps**（100 帧滑窗，板上读回） | [data/metrics.csv](data/metrics.csv) |
| 上板校验 | 串口命令电池 **105 条**通过、几何"最后一跳"**10 条**判定全过（`build/evidence/r113_board_verify_console.txt`，`RESULT board_verify PASS（判红的步骤：0）`；`drop_words=0` 是本轮 health 读回，彼时未推流） | [board/ACCEPTANCE.md](board/ACCEPTANCE.md) |

数值走势、哪些优化被证据否掉、以及为什么某些差值不作为收益口径，写在
[report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) 与 [report/PERF_REPORT.md](report/PERF_REPORT.md)；
本页不复制它们——同一份数字抄在两处一定会漂。

**本页不作门禁全绿声明**：某一版有没有过门禁、过几项、哪一项红，只以
`bash build/gates.sh` 打印的那一行为准（红项存在时它会明说"有红项"，不会含糊）。

## 提交阅读路径（`submit/`）

交付文档的重构阅读路径在 [`submit/README.md`](submit/README.md)：八章设计报告、复现说明、以及"推荐结构 → 本仓库位置"的目录对照说明（赛题 §3.3.5.4 对采用其他组织方式的队伍的那句要求）。它**不复制任何数字**——数字只在 `data/metrics.csv` 与门禁那一行里读。

## 目录

| 目录 | 内容 |
|---|---|
| `src/rtl/` | PL 侧 RTL，按 `top / video / process / eth / hdmi / clocks / axi / util` 分层 |
| `src/ps/` | PS 侧裸机固件：命令解析、寄存器配置、SD 播放、自诊断读回 |
| `src/host/` | PC 侧上位机与自检脚本（Python 推流、寄存器回读、文档与命令表一致性检查） |
| `src/constraints/` | 引脚与时序约束 |
| `sim/` | 台架与 runner；例化整个视频顶层那支是几何与显示的主尺子，`sim/NAMES.md` 给新旧名对照 |
| `build/` | 可复现的构建脚本（`tcl/`，入口一条命令出位流）+ 综合与实现报告（仓库里平铺在 `build/`，提交包里由导出器展平进 `build/reports/`，同一批文件两种摆法）+ 门禁与上板回读脚本；构建输出（位流/XSA/ELF）也落在这里，说明见 [build/README.md](build/README.md) |
| `board/` | 上板要用的三样：工程与二进制怎么来、运行脚本（JTAG 三步 + 串口）、跑起来之后读回来的实测输出（[board/README.md](board/README.md)、验收表 [board/ACCEPTANCE.md](board/ACCEPTANCE.md)） |
| `data/` | `golden/` 参考图、`measured/` 实测数据、[data/metrics.csv](data/metrics.csv) 是唯一那张数字表 |
| `skill/` | 大模型协作沉淀的技能卡，每张六段：触发 / 不适用 / 动作 / 完成判据 / 失效边界 / 出处（六段由 `build/check_skill_cards.py` 逐条判，条目数以 `skill/README.md` 自己那行为准） |
| `report/` | 交付文档：设计说明、优化记录、命令表、复现说明（索引在 [report/README.md](report/README.md)） |
| `report/log/` | 追加式工作记录（问题账、过夜流水）；只作过程留痕，不当结论引用 |

目录摆放按比赛要求的形状来（`src/ sim/ build/ board/ data/ skill/ report/`）。交付文档这一层仓库里就叫
`report/`；导出提交包时改的是**文件名**（按比赛要求写成纯英文小写：`BUILD.md` → `build.md`、`KNOWN_ISSUES.md` → `known_issues.md`），
文档里的指路跟着一起改；剪掉了什么、按哪条判据剪的，逐条写在包内 `_pruned.txt`，
而包内所有"路径式指路"由导出器自检——指不到就拒绝落盘。
**哪些尺子能在提交包里面直接跑**（不是只在仓库里）：`doc_enc_check`、`line_cite_check`（D5）、`doc_currency_check`（D1–D4b）、
`metric_recheck`（D6）这四把只读文本与报告，包内实测 **2026-10-02 09:2x 全部 rc=0、硬错 0**；
其中 D1b 那一层在包里会自己念"本目录没有 bit 产物 ⇒ 这一层不判"——那是**声明不可判**，不是绿。
跑不了的只有需要串口/板子的 `ps_hb_check`、`board_verify` 与需要 RTL 源重跑的台架，它们要回仓库跑。

## 许可

MIT，见 [LICENSE](LICENSE)。

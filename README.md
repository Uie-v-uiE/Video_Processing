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
| 全设计 setup WNS | **0.725 ns**（板上这一版 r107，2026-10-02 17:52 三步 JTAG 刷入，`bit 1f90c795e7e3`；门禁 22 项 21 绿 / 1 红，唯一红是声明过的 `C5c`），失败 setup/hold 端点 **0 / 51005** | `build/timing_summary.rpt`、`build/r107_gates.txt`、`build/r107_board_verify_console.txt` |
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **0.725 ns**（占它 8 ns 周期的 9.1 %，**绝对 WNS 全设计最差就是它**）；100 MHz `clk_fpga_0` **1.229 ns**（12.3 %）；50 MHz 显示域 `clkout0_1` **1.224 ns**（6.1 %）；`sys_clk` **14.906 ns**（周期 20 ns，这一档最宽） | `build/timing_summary.rpt`，Intra Clock Table 那一段。⚠ 要说两个口径，不能只念一个数：**绝对 WNS 看 `eth_rxc`，相对余量最紧的是 `clkout0_1`（6.1 %）**——那条就是 `report/KNOWN_ISSUES.md` 里 23 级 OSD 读侧锥（逻辑深度问题，与收包侧的扇出/走线问题手法不同）。⚠ 本轮换了主人：r106 的 `eth_rxc` 最差是收包重组那一族（`u_reasm/off_reg -> rows_hit_reg` 的位图使能，最差 8 条里占 6 条），r107 把那一族分组之后它自己走到 2.006 ns / 4 级（两端夹逼的读数见 `build/r107_reasm_probe.txt`），全设计最差换成 `u_icmp/u_icmp_tx` 的 IP 首部校验和锥——所以绝对数 0.723 → 0.725 **不写成收益或损失**（规矩 35），能写的只有"瓶颈换了主人"。百分数与四个 ns 都由 D6 自己从报告算（分子=逐时钟 slack、分母=该时钟周期），不是心算；这一行的同步史（r104 漏同步两天）仍在 `report/KNOWN_ISSUES.md` 时序一节|
| 保持时间 | 全设计最差那一格在 `eth_rxc`（125 MHz 收包域，落点 u_eth/u_cdc/wgray_reg[6]/C → u_eth/u_lm/full_d_reg/D）**0.050 ns**，这一格是 **3 级逻辑（CARRY4=2 + LUT6=1）**、走线占这条数据路径延迟的 **55.2 %**（`build/hold_paths.rpt`，本轮 r107 布线后 15:46 重生成）；其余逐时钟 WHS：100 MHz `clk_fpga_0` **0.057 ns**、50 MHz 显示域 `clkout0_1` **0.059 ns**、`sys_clk` **0.120 ns** —— 最薄的一类数。⚠ 口径要说清：这是"**按 r79 加严的 0.8 ns hold 不确定度**要求之后"剩下的量，不是真实余量只有 0.0x。⚠ **归属又动了**：r106 是收包域里 `arp_rx_flag_reg → arp_pend_reg`（1 级 LUT4 / route 80.9 %），r107 仍在收包域、但那一格换成 **CDC 灰码 → 链路监测**，而全局数只差 0.001 ns——只对照全局 WHS 看不见这次换格，所以这一行带归属判据（规矩 46）。上一轮的改前 6 条红凭据仍在 `build/evidence/r104_holdrow_stale_red.txt` | `build/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/hold_paths.rpt` |
| BRAM / LUT / FF / DSP | **95 tile（67.86 %）/ 14323（26.92 %）/ 8156（7.67 %）/ 19（8.64 %）**（r107 把收包位图分组之后 LUT 数与 r106 逐字相同，寄存器 +7 就是那五个分组的索引/选择逻辑） | `build/utilization.rpt` |
| 功耗 | 动态 **2.213 W**（片上合计 2.390 W）、估算结温 **52.6 °C**（工具置信度 Low，**是估算**，没有实测；板上片上 XADC 的读数是另一路，见 `data/metrics.csv` 与串口 `temp`） | `build/power.rpt` |
| SD 本地播放 | **29.8 – 30.0 fps**（100 帧滑窗，板上读回） | [data/metrics.csv](data/metrics.csv) |
| 上板校验 | 串口命令电池 100 条通过、几何"最后一跳"8 条判定全过 | [board/ACCEPTANCE.md](board/ACCEPTANCE.md) |

数值走势、哪些优化被证据否掉、以及为什么某些差值不作为收益口径，写在
[report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) 与 [report/PERF_REPORT.md](report/PERF_REPORT.md)；
本页不复制它们——同一份数字抄在两处一定会漂。

**本页不作门禁全绿声明**：某一版有没有过门禁、过几项、哪一项红，只以
`bash build/gates.sh` 打印的那一行为准（红项存在时它会明说"有红项"，不会含糊）。

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

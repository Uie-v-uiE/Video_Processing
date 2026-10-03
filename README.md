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
| 全设计 setup WNS | **−0.846 ns**，失败 setup/hold 端点 **5 / 51140**（板上这一版是 r116，2026-10-04 01:37 由三步 JTAG 链刷入，bit `bb2fb707aebc`；发布门禁件 `build/r116_gates.txt` 那一跑里有 4 条**发布硬门**为红（WNS 与失败端点各两条）（红因就是本轮第一次被检查的 5 个 RGMII I/O 端点）、1 项是声明过的 `C5c`、2 项是当晚改文档留下的行号/时效红（`report/MODULES.md` 两条例化行号 +10 已修回）、其余为读数陈述；正因为这 4 条硬门红，r117 把输入窗退回**候选件**（`VP_R116_IO_WINDOW=1` 可一键复现带窗那一版）；`board_verify --geom --battery` 01:50 PASS、判红步骤 0；门禁件 `build/r116_gates.txt`）。⚠ **这 5 格全部是本轮第一次被时序检查的 RGMII 输入端点**：绑窗之前它们报 `Slack: inf / Path Group: (none)`，那是"没检查"不是"满足"（提示词 H5 禁的就是这种读法）；片内 46,300 个端点**一格违例都没有**。⚠ 绑窗之后这一族被证明**在合法 0…31 全范围内无解**：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8（两条曲线的实测斜率 +63.0 / −92.0 ps/拍，交点 τ=31.1，件 `build/evidence/r115_window/probe3_console.txt`），根因是两只钟的角间差 **3.411 ns** 而数据侧只有 **0.467 ns** ⇒ 这一格写的是**器件/结构边界**，不是"还没找到点"（逐域判定见 `report/TIMING_GLOBAL.md` 第 6 节，不等式在 `report/TIMING_GLOBAL.md` 第 6 节）。板侧在真实流量下不为此变差：512×300@60 ≈ 147 Mbps、50 s、663,221 包里 `drop_words=0`、`pkt_err=0`，且与**回刷 r114** 的 A/B 对照四个读数逐格相同（`build/evidence/r116_board/`，`report/log/ISSUES.md` #318） | `build/timing_summary.rpt`（Design Timing Summary 行）、`build/evidence/r116/r116_io_HOLD.rpt`、`build/evidence/r116/r116_io_SETUP.rpt`、`build/r116_gates.txt` |　⚠ **同步状态要说清**：板上现在跑的是 **r118**（bit `cd04907e1369`，2026-10-04 04:49:50 三步 JTAG 链刷入，`board_verify --geom --battery --round=r118` rc=0），但**本行的数还是 r116 那一次的件**；r118 的逐格读数在 `build/evidence/r118_strict_b1.txt`（8 对逐位复现 r114）与 `build/timing_summary.rpt`。首页改口在 04:57 被我自己的 `--apply` 把 README.md 写成 0 行，已回退重做，账记 `report/log/ISSUES.md` #330。
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **−0.846 ns**（占它 8 ns 周期的 −10.57 %，**绝对 WNS 与按周期归一后的最紧余量都是它**，而这一格就是那 5 个新被检查的 I/O 端点）；100 MHz `clk_fpga_0` **1.976 ns**（19.76 %）；50 MHz 显示域 `clkout0_1` **3.698 ns**（18.49 %）；`sys_clk` **14.876 ns**（占它 20 ns 周期的 74.38 %，这一档最宽）。**逐格差分**（同一把生成器配对，件 `build/evidence/r116_roster_diff.txt`，判 6 对、比较 8 对）：`clk_fpga_0` setup 1.850−1.976（相对余量 18.50 → 19.76 %，+6.8 %）、`clkout0_1` 3.630−3.698（18.15 → 18.49 %，+1.9 %）、`sys_clk` 14.876 → 14.876 一格不动；唯一变小的是 `eth_rxc`（0.739−−0.846）——它不是被搬过来的负裕量，是**新检查暴露出来的旧债**（G1 按字面判红，本轮没有把它说成绿）。片内最差那一条**换了族**：r114 是 `u_icmp_tx/ip_head_reg[4][16]/C → check_buffer_reg[19]/D`（11 级、route 58.447 %），本轮起 `eth_rxc` 域内最差的**片内**路回到 `u_rx_par → rows_hit[*]/CE` 那一族，读数排在 I/O 那 4 条之后（`build/evidence/r116_after.txt` 的 eth_rxc 段只有 I/O 四条）；绝对差**不作为收益或损失**（规矩 35）。**这一族的"极致"位置有数**：时钟网络本身就要掉 SCD 5.008 / DCD 4.493 ns（8 ns 周期的一半），而滚过对照（`build/evidence/r117_fb_pblock/A/roll_console.txt`）逐格复现了正式构建的名册 ⇒ "再砍 RTL 逻辑"的收益上限趋近于零，剩下的杠杆只有"把捕获钟做短"（`report/TIMING_GLOBAL.md` 第 7 节，含下一刀的数值靶子与它的代价面） | `build/timing_summary.rpt`（Intra Clock Table）、`build/evidence/r116_after.txt`、`build/evidence/r116_roster_diff.txt` |
| 保持时间 | 全设计最差那一格在 `eth_rxc`（125 MHz 收包域，落点 u_eth/u_rgmii/u_rgmii_rx/u_iddr_rx_ctl/D，源是输入端口 `eth_rx_ctl`）**−0.870 ns**，这一格是 **2 级（IBUF=1、IDELAYE2=1）**、**route 0.000 %**（IO 直连，没有走线可优化）、`Path Type: Hold (Min at Slow Process Corner)`、`Input Delay: 1.200 ns`（件 `build/evidence/r116/r116_io_HOLD.rpt`）；其余逐时钟 WHS：100 MHz `clk_fpga_0` **0.053 ns**、50 MHz 显示域 `clkout0_1` **0.059 ns**、`sys_clk` **0.222 ns**——**这一轮四个 hold 数与 r114 逐格相同**（0.053/0.059/0.222 一格没动），所以"绑窗把 hold 挤薄"这个担心没有发生。⚠ 口径两条都要念：① 这三个正的 WHS 是"**按 r79 自加的 0.8 ns hold 不确定度要求之后**"剩下的量（只有 `eth_rxc` 带那条带子，其余三域没带 ⇒ #265 说这四个数**跨域不可比**，统一带子的真件在 r115 跑过、结果是全设计红 −0.747/25,742 端点，所以本轮维持原带不动它，松动台账本轮 0 条（`report/TIMING_GLOBAL.md` 第 6 节末把这条口径完整念出来））；② `eth_rxc` 这一格从 r114 的 0.052（"假设 RXD/RX_CTL 与 RXC 同时到达"给的数）换成 −0.870（第一次有到达窗的数），**旧的那个 0.052 从来不是设计值**——这是本轮对"保持时间"这句话做的实质更正。⚠ 归属换族要按规矩 46 说清：r114 的全设计最差 hold 在灰码链 `u_cdc/rgray_s1_reg[10]/C → u_lm/full_d_reg/D`（0.052，3 级、route 56.480 %），本轮它让位给新被检查的 I/O 端点（−0.870）⇒ 主人从"灰码族"换成"RGMII I/O 族"，这是**检查范围变化**的结果，不是那片逻辑变差了 | `build/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/evidence/r116/r116_io_HOLD.rpt`、`build/evidence/r116_after.txt` |
| BRAM / LUT / FF / DSP | **95.5 tile（68.21 %）/ 14154（26.61 %）/ 8188（7.70 %）/ 19（8.64 %）**（r112 这一刀的代价：按键上电武装门 **+66 LUT / +46 FF**（两只 key_debounce，综合把它们展平进 `u_pl` 的桶，逐层表里没有 u_k1/u_k2 行），ICMP 校验和累加器 32→20 位 **−31 LUT / −12 FF**，全设计净 **+35 LUT / +34 FF**——净账由两份逐层件相减**闭合到个位**（`build/evidence/r112_util_attrib.txt`）。⚠ 刀 B 记为"同族抓手成立、设计余量未抬"：它那条 `ip_head → check_buffer` 真的从最差报告里消失了，但设计的绑定约束换成了上面那条 `rows_hit` 的 CE 广播，见 ISSUES #253/#254/#255） | `build/utilization.rpt` |
| 功耗 | 动态 **2.213 W**（片上合计 2.391 W）、估算结温 **52.6 °C**（工具置信度 Low，**是估算**，没有实测；板上片上 XADC 的读数是另一路，见 `data/metrics.csv` 与串口 `temp`） | `build/power.rpt` |
| SD 本地播放 | **29.8 – 30.0 fps**（100 帧滑窗，板上读回） | [data/metrics.csv](data/metrics.csv) |
| 上板校验 | 串口命令电池 **105 条**通过、几何"最后一跳"**10 条**判定全过（`build/evidence/r113_board_verify_console.txt`，`RESULT board_verify PASS（判红的步骤：0）`；`drop_words=0` 是本轮 health 读回，彼时未推流） | [board/ACCEPTANCE.md](board/ACCEPTANCE.md) |

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

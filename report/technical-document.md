# 技术文档：Zynq-7020 多源视频实时处理与显示系统

版本对应位流 `build/system.bit`（md5 前 12 位 `cd04907e1369`），工具链 Vivado / Vitis 2025.2.1，
器件 `xc7z020-clg484-2`。本文只写上板跑通并有报告可查的内容；没量过的项目直接写"没量过"。

## 1. 作品是什么

### 1.1 一句话

一块 Zynq-7020 板子，把三路视频源（网线推流、SD 卡裸帧、自研测试图卡）在 PL 里做实时处理
（缩放、旋转、九位控制字的算法链、同帧左右对比叠加），输出到 1024×600 的 HDMI 屏，
并且把链路健康计数、帧率、温度、当前几何参数直接打在屏上，同时可从串口与 JTAG 读回。

### 1.2 功能清单与验证方式

| 功能 | 实现位置 | 怎么确认它真的在工作 |
| --- | --- | --- |
| HDMI 输入接收（TMDS 去串化） | `src/rtl/hdmi/` | 顶层台架逐像素比对；屏上出现源画面 |
| RGMII 千兆收包 + GMII 域转换 | `src/rtl/eth/rgmii_rx.v`、`gmii_to_rgmii.v` | `sim/tb_link_monitor.v` 与整屏台架；PL 自己数的丢帧计数为 0 |
| UDP 视频推流接收（512×300 RGB565） | `src/rtl/eth/`（帧重组、端口过滤） | 600 帧一轮与 300 s / 9000 帧长跑，丢帧/坏帧/重复帧均为 0 |
| ARP 请求与 ICMP ping 应答（纯 RTL） | `src/rtl/eth/arp_rx.v`、`arp_tx.v`、`icmp_rx.v`、`icmp_tx.v` | 主机 `ping` 有回包；`sim/tb_icmp_ping0.v` 等四条回归 |
| SD 卡裸帧播放（PS 读，不做解码） | `src/ps/sd_play.c` | 串口 `[STAT]` 与屏上帧号；29.8–30.0 fps |
| 自研动态测试图卡（第三源） | `src/rtl/video/`（渐变底 + 移动块 + 帧号） | 拔网线拔卡后屏不黑；长按按键切源 |
| 帧缓存与乒乓读写 | DDR（AXI）+ BRAM 行环 | 整屏台架的逐像素判据；BRAM 95.5/140 tile |
| 缩放 0.25–2.00（八档）+ 自动呼吸 + Fit | `src/rtl/process/zoom/` | lane23 回读倍率与来源；屏上量格 |
| 旋转 + 双线性插值 | `src/rtl/process/rotate/`、`bilin/` | `sim/tb_v96` 的映射判据 M1/M2/M4/M6；整屏台架 |
| 效果链（gamma / 颜色 / 滤波 / 边缘 / 阈值 / 形态学） | `src/rtl/process/proc_pipeline.v` 等 11 个文件 | 每级一条旁路判据；固定 15 拍延迟由 `tb_v86` 实测钉住 |
| 同帧左右对比（左原图 / 右处理图，缝位置可调） | `src/rtl/video/split_ctrl.v` + 顶层混合 | 串口 `split <n>` 后 marker 位不变的判据；屏上看缝 |
| OSD 叠加（帧率、丢帧、温度、几何参数） | `src/rtl/video/osd_overlay.v` | 36 行人眼验收表逐条；`[TEMP]` 回显与屏上三字符对账 |
| 链路健康自诊断（计数 + 自动回落） | `src/rtl/eth/link_monitor.v` + 顶层仲裁 | 拔线/拔卡现场复验；AUTO 回落到可用源 |
| QSPI 固化（断电自启） | `board/tcl/flash_qspi.tcl` | 见 §8 |

### 1.3 三个创新点

1. **同一帧内的左右对比显示**：把"原图 / 处理图"的混合做成逐像素、按列号实时切换的通路，
   分割线位置是一个运行时参数，所以任何算法的效果都能在同一帧、同一时刻、同一屏上被直接看出来，
   不需要外接采集卡或录屏。
2. **视频通路和网络收包在同一个 PL 里由硬件自己数账**：RGMII 接收、帧重组、ARP/ICMP 应答全是 RTL，
   丢帧、坏帧、重复帧、端到端时延这些计数由硬件产生并经串口/JTAG 读回，
   所以"演示流畅"与"链路真的零丢包"是两件事，这里能分开证明。
3. **一条把几何运算做到固定延迟的效果链**：六级算法、九位控制字，任意组合下整链延迟恒为 15 拍、
   内容偏移恒为 −4 行，坐标按每一级自己的节拍打标；这让叠加任意算法时读口调度不用重算，
   也让"某一级有没有真的生效"变成可判据化的问题。

## 2. 系统组成

### 2.1 时钟与域

| 域 | 频率 | 周期 | 用途 | setup WNS | hold WHS |
| --- | --- | --- | --- | --- | --- |
| `sys_clk` | 50 MHz | 20.000 ns | PS/AXI 侧、按键、慢速控制 | 14.876 ns | 0.222 ns |
| `clk_fpga_0` | 100 MHz | 10.000 ns | 显示读出、几何、效果链、OSD | 1.850 ns | 0.053 ns |
| `clkout0_1` | 50 MHz | 20.000 ns | 帧缓存写侧与 AXI 全互连 | 3.630 ns | 0.059 ns |
| `eth_rxc` | 125 MHz | 8.000 ns | RGMII 收发、协议栈、仲裁 | 0.739 ns | 0.052 ns |
| `clkout1_1` | 250 MHz | 4.000 ns | TMDS 串行化（OSERDESE2） | 不纳检（见 §6.4） | — |

全设计 51,135 个端点，setup 与 hold 的失败端点都是 0。
依据件：`build/timing_summary.rpt`（第 151 行是汇总行，第 154 行是 "All user specified timing constraints are met"）。

### 2.2 数据流

```
HDMI in ─► 去串化 ─► 采样对齐 ─► 写 DDR 帧缓存（乒乓） ─┐
网线 ─► RGMII ─► GMII ─► 帧重组 ─► 端口过滤 ─────────────┤
SD 卡 ─► PS 读裸帧 ─► AXI 写 ────────────────────────────┤
测试图卡 ─► 自研发生器 ──────────────────────────────────┘
                                             ▼
                              仲裁器（AUTO / ETH / SD / TEST）
                                             ▼
                    缩放 zfit/zmap ─► 旋转 + 双线性 ─► 效果链（6 级）
                                             ▼
                     同帧混合（split）─► OSD 叠加 ─► HDMI 编码 ─► 屏
                                             ▲
              PS 裸机 app（命令解析、寄存器、XADC、SD、串口回显）
```

### 2.3 规模

| 项 | 数量 | 来源 |
| --- | --- | --- |
| RTL 文件 / 行数 | 80 个 / 11,768 行 | `src/rtl/` |
| PS 侧 C 代码行数 | 2,544 行 | `src/ps/` |
| 仿真台架 | 82 个 | `sim/`（取舍清单在 `sim/README.md`） |
| 整屏逐像素判据 | 141 条（140 通过 + 1 条故意留下的 `C5c`） | `build/tb_v98_report.txt` |
| 上板人眼验收 | 36 行 | `board/verify_r87.md` |
| 一键门禁 | 24 项（23 绿 / 1 条申报过的红） | `build/gates.sh` |

## 3. PL 侧实现

### 3.1 输入与网络

RGMII 的 4 位 DDR 数据在 `rgmii_rx.v` 里用 IDDR 还原成 GMII 单沿流，IDELAY 的抽头值取 31。
这个值不是试出来的：0–31 全档扫过，hold 每档约 +63 ps、setup 每档约 −92 ps，
两者交点在 31.1，取整数 31（`report/timing/rgmii_window_model.md`）。
收包链在 PL 内完成以太网帧头解析、ARP 表项、ICMP echo 应答，PS 不参与转发，
所以推流端口打开时板子仍然能被 ping 通。

丢帧判据由硬件自己产生：帧重组模块数出坏帧、重复帧与被丢弃的字数，
`link_monitor.v` 用 125 MHz 域里的毫秒计数（`TC = CLK_HZ/1000`）判定链路是否静默，
静默超过整定时间就请求仲裁器换源。

实测：512×300 RGB565 限速 30 fps，600 帧一轮与 300 s（9000 帧）长跑，
丢帧 / 坏帧 / 重复帧都是 0；实测帧率 29.99 fps、平均帧间隔 33.34 ms。
不限速打到目标 120 fps（约 36 MB/s、287 Mbps）的 960 帧里仍未丢字，
所以"PL 能扛多少"这一格写的是**下界 ≥116.7 fps，过载点没顶到**，不给编出来的数。

### 3.2 帧缓存与仲裁

写侧由 AXI 全互连把三路源写进 DDR 的乒乓帧缓冲；读侧按显示扫描取数。
三路源共用 bank0，所以仲裁器要保证同一时刻只有一个 owner：
`pl_video_top.v:152` 的 `M_AUTO / M_ETH / M_TEST / M_SD` 就是这个状态，
owner 变化经 3 级同步送给写侧（`report/timing/` 里对这一路的 CDC 判据在门禁第 6 项）。
AUTO 下拔网线、拔 SD 卡都做过板级复验：能切走，插回能切回，不需要复位。

### 3.3 几何：缩放与旋转

缩放分两步。`zfit` 用 DSP 算出适配系数（3 个 DSP48），`zmap` 做逐像素坐标映射（8 个 DSP48）。
倍率是 8 档定点数（25/33/50/75/100/133/150/200，即 0.25–2.00 倍），
另有自动呼吸档与 Fit 档，当前倍率与来源都能从 lane23 读回。
旋转用逆映射 + 双线性插值：`rotate/` 生成目标像素的源坐标，`bilin_lerp` 做两次线性插值（6 个 DSP48），
读口按 `BILIN_ROWS = 2` 的行缓存供数。旋转态下四角是否出屏由一条两端夹逼的台架判据检查，
不靠人眼看。

DSP 合计 19 个，逐实例账是：`u_lerp` 6 + `u_blur` 1 + `u_split_ctrl` 1 + `u_zfit` 3 + `u_zmap` 8。
gamma 一级不占 DSP——它是 LUTRAM 查表，不做乘法。

### 3.4 效果链

`proc_pipeline.v` 的级序是 gamma → 颜色 → 滤波 → 边缘 → 阈值 → 形态学。
控制字是 9 位（`gpio_cfg[8:0]`，一位一个算法），级 5 的腐蚀与膨胀两位互斥，
同时置 1 时两个都不做（`proc_pipeline.v:59-60`）。
四个窗口级各自维护自己的列标签，抽头号按该级之前累积的拍数取（2→blur、5→sharp、8→sobel、12→morph），
所以任意组合下整链延迟固定 15 拍、内容偏移固定 −4 行。
顶层不许自己另写一个延迟数，只取 `u_pipe.LATENCY`；`tb_v86` 实测 `de_in → de_out` 再与它比，
任何一处漂移都会有测试变红。

### 3.5 同帧对比与 OSD

`split_ctrl.v` 输出一个按百分比定位的缝，顶层逐像素选择"这一列取原图还是取处理图"，
所以左右两半是同一帧的同一时刻。串口 `split <n>` 之后 marker 位不变这条判据，
是为了防止"参数改了但通路没跟着改"。

OSD 叠四行信息（源与分辨率、帧率与丢帧、几何参数、温度与状态），
字模索引在 1024×600 有效区整屏走一遍时有 190,464 拍越出数组上界——
这个"机会地板"用来区分"屏上没现象"与"真的被门住了"。
温度有三路对账：驱动读数、屏上三字符、写进 PL 的 gpio 值。

## 4. PS 侧实现

裸机 app（`src/ps/main.c` 等，2,544 行），跑在 `ps7_cortexa9_0`，BSP 用仓库内的
`vitis/platform/.../bsp`。职责是：命令解析（串口 115200-8N1）、寄存器整字写、
SD 卡 FAT32 目录读取与裸帧推送、XADC 采样、把状态回显到串口。

控制字接口是一条约定：**PS 一次整字写 `gpio_cfg`**，PL 侧统一打三级同步再分发，
不允许多个位分别改（`effect_ctrl.v:31` 把这条写成注释）。
两个运行时开关各占一个空位并各走一条独立同步链：`gpio_o[19]` 是双线性开关、
`gpio_o[20]` 是 OSD 总开关（反相，复位值 = 有 OSD）。
读回走 lane23：倍率、来源、手动/自动标志、bilin 状态都能从 JTAG 或串口读，
所以"开关在硬件里是真的"这件事不需要靠眼睛证明。

## 5. 软硬件划分依据

| 任务 | 放在 | 原因 |
| --- | --- | --- |
| TMDS 去串化、RGMII 收发、帧重组 | PL | 125 MHz DDR 采样与逐字校验，软件来不及 |
| ARP/ICMP 应答 | PL | 推流占满 CPU 通道时仍要能 ping 通 |
| 逐像素效果链、缩放、旋转、双线性 | PL | 50 MHz 像素率下每像素 20 ns 预算 |
| 同帧混合与 OSD 叠加 | PL | 必须与扫描同步，不能等软件 |
| FAT32 解析、SD 读、串口命令、XADC | PS | 事务性、低频、需要文件系统 |
| 参数整定与演示脚本 | PS + 上位机 | 人要能改，且要留日志 |

判据不是"哪边写得方便"，而是**每像素预算**：像素率 50 MHz 时一像素 20 ns，
任何进软件的逐像素操作都会掉帧，所以链路上没有一处逐像素的软件参与。

## 6. 时序与状态

### 6.1 收敛方法

- 时钟全部由 PS 侧 MMCM 与 BUFG 树产生，`clk_fpga_0` 100 MHz、`clkout1_1` 250 MHz 同源；
- RGMII 收口的 IDDR 与延迟抽头按 §3.1 的实测交点定；
- 跨域一律 3 级同步 + `ASYNC_REG`，格雷码指针链单独钉（`dc_fifo` 四颗 FF）；
- 时钟分组显式声明（`src/constraints/clock_groups_impl.xdc`），异步组之外的跨域路才受检查；
- 关键路径按域逐个量，不只看全局最差那条：每域前 12 档都取过端点（`build/evidence/r124_tiers_ladder.txt`）。

### 6.2 关键路径在哪

`eth_rxc` 的 0.739 ns 是 `u_icmp_tx/ip_head_reg[4][16] → check_buffer_reg[19]/D`，
11 级逻辑含 6 个 CARRY4，布线占 58.4 %。同一只锥贡献前 3 档（0.739 / 0.873 / 0.961）。
第 4–12 档全部是 `u_rx_par/p_eof_reg → u_reasm/rows_hit_reg[*]/CE`，
4 级逻辑、布线占 85 %——即该域的下一档瓶颈是一条使能广播，不是另一只加法器。
所以校验和锥整族搬走的上界是 +0.278 ns（1.017 − 0.739）。

`clk_fpga_0` 的 1.850 ns 前 12 档全部同起点 `u_pl/u_arb/owner_eth_reg/C`，
终点是帧缓存 BRAM 的写使能与地址脚，逻辑只有 1–4 级、布线占 88.8–93.6 %。
这个域没有算法锥可拆，能动的是这只高扇出旗标的复制与摆放。

### 6.3 试过并被实测否掉的优化

| 做法 | 结果 | 依据 |
| --- | --- | --- |
| 校验和摊到每拍一项 | `eth_rxc` 0.739→0.691、`clk_fpga_0` −0.123、`sys_clk` 14.876→14.068，判负回退 | `report/log/issues.md` #380 |
| 编译期常量抽出发一拍 | 更差：常量并入同一拍使加法树变深，端点只从 4835 减到 4819 | #382 |
| 强制复制 239 引脚广播网 | 本域赢 1 格、另三域跌 4 格（含最紧两格），判负 | `report/timing/round_r117.md` |
| Pblock 约束摆放 | 载链逃出边界报 Place 30-439，且未换来收益 | #186 |
| BRAM 换 setup | +0.182 ns 相对 +0.516 不够，砍掉 FF 后仍剩 4 级 ⇒ 拥塞主导 | #122 |
| RGMII 输入窗挂上 | 挂窗即 −2.885 ns，退回候选件 | `report/timing/rgmii_window_model.md` |

结论写在 `report/timing/eth_rxc_partition_options.md` 第 8 节：本版不再投时序优化轮。
当前是零违例、约束全满足的状态，继续动它买的是余量不是正确性。

### 6.4 仍然欠的账（不因为停手而消失）

- 四个域都没有 `set_clock_uncertainty` 的 setup 项，只有 `eth_rxc` 有一条自加的 hold 带
  （`src/constraints/rk_zynq7020.xdc:50`）⇒ 四列 hold 不是同一把尺子；
- 屏那一路 6 个 TMDS 输出口没有对外时序结论：HDMI 的"钟↔数据 ≤0.20 Tcharacter"是展宽不是捕获窗，
  按 `set_output_delay` 挂上去量出来是 −5.408 / −1.923 ns 整批红，判 DECLINE（§6.3 同源）；
- 异步时钟组把 4 条跨域路从检查范围里拿走了，`set_max_delay -datapath_only` 那份候选约束从未进默认集；
- 端到端时延这一格有读数出口（OSD 的 Latency lane），但只有一轮 600 帧的可信值 33.34 ms，
  没做多次复测 ⇒ 指标表里如实标条件。

## 7. 验证与实测

### 7.1 功能正确性怎么确认

三层，不互相冒充：

1. **模块级台架**：82 个 testbench（`sim/`），每条判据要求"能红"——
   判据若靠空集通过，本身算失败。5 支变异对照（`build/sim/mut_control.sh`）钉住
   "一次变异只许红它声称红的那一条"。
2. **整屏台架**：`tb_v98` 跑一遍全设计，141 条逐像素判据（140 通过 + 1 条申报过的 `C5c`），
   报告头部带编译时戳与 RTL/台架 md5。
3. **板级**：36 行人眼验收（`board/verify_r87.md`），每行给命令、预期现象、
   以及"这一行不通意味着什么"。屏幕现象只能由人判，机器判据不代替眼睛。

### 7.2 性能与资源

| 指标 | 数值 | 条件 |
| --- | --- | --- |
| 显示 | 1024×600 @ 59.5 Hz | 像素钟 50 MHz，H_TOTAL 1344 / V_TOTAL 625 |
| 入流零丢包 | 0 丢帧 / 0 坏帧 | 512×300@30 fps，限速 15 MB/s，600 帧一轮 |
| 长跑 | 0 丢帧 / 0 重复帧 | 300 s、9000 帧，实测 29.99 fps |
| 入流下界 | ≥116.7 fps 不丢字 | 不限速、目标 120 fps、960 帧；过载点未顶到 |
| 端到端时延 | 33.34 ms（min 20 / max 51） | 上位机发出 → 示相机录到该帧上屏，一轮 600 帧 |
| SD 播放 | 29.8–30.0 fps | 预转换 RGB565，板上不解码 |
| Slice LUT | 14,154（26.61 %） | 实现后报告 |
| Slice 寄存器 | 8,188（7.70 %） | 同上 |
| BRAM tile | 95.5 / 140（68.21 %） | 帧缓存乒乓 + 行环是主要去向 |
| DSP48 | 19 / 220（8.64 %） | 逐实例见 §3.3 |
| 动态功耗 | 2.213 W | 工具估算，置信度 Low（无仿真活动文件输入） |
| 结温 | 52.6 ℃（估算）／61.2–61.7 ℃（板读 XADC） | 估算是工具值；板读是六次读数极值 |

### 7.3 优化前后的对比

本版绝对值（`build/utilization.rpt`，与 `data/metrics.csv` 同源，指标表每行都点名它的证据文件）：
Slice LUT 14,154（26.61 %）、寄存器 8,188（7.70 %）、BRAM 95.5/140 tile（68.21 %）、DSP48 19/220（8.64 %）。

逐轮的增减只写有件可查的三笔（都来自 `data/metrics.csv` 的资源行与 `build/evidence/` 的逐层件）：

| 变化 | 量 | 这一格为什么变 |
| --- | --- | --- |
| 收包链把 `pay_start` / `pay_end` 两个 16 位界提前一拍寄存 | 寄存器 +22 | 用触发器换掉 `p_good` 锥里的一级加法；与"加寄存器换走线"同族 |
| 行覆盖使能独热化 | LUT −243（其中 −66 能归到这一刀，其余没有归属） | 没有归属的那部分不念成收益 |
| 两只按键去抖的武装门 + 校验和累加器 32→20 | LUT +35（+66 与 −31 相减）、寄存器 +34（+46 与 −12） | 净账由两份逐层件相减闭合 |

帧缓存与行环的 BRAM 占用是这条链的承重件：把打包 FIFO 从触发器改成 LUTRAM 释放了约 5 万个 FF，
代价是 BRAM 一度顶到 98.93 %，随后回落到本版的 68.21 %。
余量侧的逐轮读数（含 `eth_rxc` 从 0.445 ns 走到 0.739 ns 那两刀）在 `report/timing/` 的逐轮页里，
本文不重复列——那张表里的每个数都要配"同一把尺子"的前提才有意义。

有一条规矩贯穿这张表：**WNS 的绝对差不算收益也不算损失**，只有该域自己的族动了才算，
且别的域不许变差——所以上表最后一列写的是"为什么变"，不是"变好了多少"。

## 8. 复现

### 8.1 从零建工程并跑门禁

`board/` 里那份上板工程本身是怎么落位并验证的，写在两支脚本里（`board/tcl/stage_board_projects.tcl`、
`board/scripts/stage_vitis_platform.sh`），判据与实跑读数在 `board/measured/stage_2026-10-05.txt`。

```bash
# Vivado：建工程 → 综合 → 实现 → 位流（约 2 小时，含时序报告）
<DV>/bin/vivado.bat -mode batch -source build/tcl/build_system_axigpio.tcl
# 一键门禁（24 项）
bash build/gates.sh
# 整屏台架（约 108 分钟）
bash sim/run_one.sh tb_v98
```

### 8.2 上板（JTAG）

```bash
export VP_XSDB="<Vivado>/../Vitis/bin/xsdb.bat"
bash build/board_verify.sh --geom --battery      # 串口回显与几何判据，留原始日志
```

### 8.3 固化到 QSPI（断电自启）

板载 32 MB QSPI NOR（W25Q256FVI，3.3 V，挂在 PS 的 MIO1/2/3/4/5/6 = CS/DQ0/DQ1/DQ2/DQ3/CLK）。

```bash
export VP_VIVADO_BIN="<Vivado>/bin"
bash board/scripts/make_boot_image.sh        # FSBL + bit + app → board/flash/BOOT.bin
VP_QSPI_PART="mx25l25645g-qspi-x4-single" \
  "<Vivado>/bin/vivado.bat" -mode batch -source board/tcl/flash_qspi.tcl
```

三个坑是实测踩到的。bootgen 对 Zynq-7000 只接受"`the_design:` + 花括号里逐行一个文件、
不写逗号不写属性"这种 bif 写法。部件名不能照着板子丝印填：丝印是 W25Q256FV，而 Vivado 部件库里
`w25q256jw*` 那一支的 `COMPATIBLE_PARTS` 只列 zynquplus，给 zynq7000 用会报 `[Labtoolstcl 44-655]`；
真正要挑的是 `COMPATIBLE_PARTS` 里含 `zynq7000*` 的那一支同为 32 MB / x4 的 macronix 档，
`get_cfgmem_parts` 列出来再按这个属性选，换过去之后擦写与回读校验都通过。
2025.2.1 的 `hw_cfgmem` 对象没有 `PROGRAM.ADDRESS_RANGE` / `BBF_FILE` / `START_ADDRESS` / `STATUS`
这几个属性（写死会 17-142、17-54 中断），又必须设 `PROGRAM.ZYNQ_FSBL`，缺它报 `[Labtools 27-3203]`。
写完把板的启动模式拨到 QSPI、断电重上，屏上应直接出画面，不需要 JTAG。
本次写入的逐条结果（镜像与三份输入的 md5、Erase/Program/Verify 三行成功、耗时 137 s、
以及上面那两个坑）记在 `board/measured/flash_qspi_2026-10-05.txt`。
其中 `PROGRAM.VERIFY=1` 那一步是**从 flash 读回逐字节比对**，所以"Verify successful"就是片上内容
与 `BOOT.bin` 一致的证据；"断电后能自己起来"要另一次上电才算量过。

## 9. 文档与目录

| 目录 | 内容 |
| --- | --- |
| `src/` | RTL（`rtl/`）、PS 裸机（`ps/`）、上位机工具（`host/`）、约束（`constraints/`） |
| `sim/` | 82 个台架与运行脚本，`sim/README.md` 是取舍清单 |
| `build/` | 构建脚本与综合/实现报告、门禁、证据件 |
| `board/` | 上板工程（Vivado 工程 + Vitis 平台）、运行脚本、实测输出、QSPI 固化脚本 |
| `data/` | 测试向量、黄金参考、`metrics.csv` 指标表 |
| `skills/` | 技能包（49 条，八节外壳） |
| `report/` | 设计报告分章、协作记录、限制与欠账 |

指标表 `data/metrics.csv` 是数字的唯一出口，每行都点名它的证据文件；
本文里的数字与它同源，两处不一致时以证据件为准。

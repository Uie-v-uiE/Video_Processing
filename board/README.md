# `board/` —— 上板工程、运行脚本与实测输出

这个目录回答三件事：**板子上跑的是什么**、**怎么把它跑起来**、**跑起来之后读回来的是什么**。
每条实测数字都点名它出自哪一份日志或报告，没读回来的不写。

## 1. 上板工程

| 项 | 值 | 出处 |
|---|---|---|
| 器件 | Zynq-7020 `xc7z020clg484-2` | `report/BUILD.md` |
| 显示输出 | HDMI **1024×600**，像素时钟 50 MHz、`H_TOTAL=1344`/`V_TOTAL=625`（`video_timing_1024x600.v:18-20`）⇒ 场频 **59.5 Hz**。别念成 50 Hz——那是像素时钟的数值，不是刷新率 | `report/PERF_REPORT.md`、`build/timing_summary.rpt` |
| PL 处理画幅 | 512×300（RGB565），输出侧 ×2 展开到 1024×600 上屏 | `src/rtl/top/pl_video_top.v` |
| 片源 | 千兆 RGMII/UDP、SD 卡（FAT32 簇链自研解析）、PL 自绘测试图卡；仲裁与回退在 PL | `report/ARCHITECTURE.md` |
| 上板方式 | **只走 JTAG**：PS 起来 → 烧 PL → 重载应用。本工程的任何脚本都不向 QSPI/SPI flash 写入，也不碰板载 EEPROM | 下面第 2 节的三条命令 |
| 交付二进制 | `build/system.bit`、`build/system.xsa`、`build/ps_app.elf`（认 md5 不认文件名） | `build/MANIFEST`（导出器按 md5 反查它点名的报告） |

时钟域的分工要说清楚，否则"余量 0.7 ns"会被读错：**全设计最差那条 setup 在 125 MHz 收包域，
0.720 ns，占它自己 8 ns 周期的 9.0 %**；50 MHz 显示域（`clkout0_1`，周期 20 ns）是
**1.767 ns（8.8 %）**，100 MHz 那一路是 **1.142 ns（11.4 %）** —— 所以"50 MHz 只剩 2.5 %"
是拿 125 MHz 那条数去除 20 ns 周期得到的，别按那个说法讲。真正薄的是**保持时间**：
最差 **0.049 ns**（就在 125 MHz 收包域那一格），100 MHz 域 0.060、显示域 0.063。
⚠ 念这两个数要用两把尺子：**全设计最差那条 min 路径在 100 MHz 域（`clk_fpga_0`），`Requirement: 0.000ns`、不带自加不确定度**；`eth_rxc` 那一格（+0.049）才是"按 r79 加严的 0.8 ns hold 不确定度要求之后"剩下的量（实测凭据 `build/clock_uncertainty.rpt`：那一条的报告表里写着 `clock uncertainty 0.800`）。把 `+0.037` 念成"真实余量只有 0.037"或念成"被 0.8 扣过的"都不对 —— 它两个都不是，它是 100 MHz 域里一条同沿 min 检查的裸余量；
#57 那一刀之后，这一族的时钟偏斜已经在**同一棵树**里（`build/hold_paths.rpt`：最差 20 条的偏斜 0.013~0.349 ns，不再是 1.616 ns）。
逐时钟的表在 `build/timing_summary.rpt` 的 Intra Clock Table 那一段。

## 2. 运行脚本

```bash
# 0) 先确认 JTAG 链看得见（跑法是 vivado，不是 xsdb —— 它用的是 open_hw_manager 那套命令）
vivado -mode batch -source build/tcl/scan_jtag.tcl
# 1) PS 起来（ps7_init + reset system），用 Vitis 的 xsdb 启动器
<Vitis>/bin/xsdb.bat build/tcl/ps_jtag_boot.tcl
# 2) 烧 PL，用 Vivado
vivado -mode batch -source build/tcl/program_pl.tcl   # program_pl 认 VP_BIT=<路径>，用来烧"隔离滚一轮"的产物做对照；不设就是 build/system.bit
# 3) 重载 PS 应用（还是 xsdb 启动器；顺序不能换，PL 没烧之前应用起不来）
<Vitis>/bin/xsdb.bat build/tcl/ps_app_reload.tcl
```

上板之后一把验完：

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom
```

它跑四段：开机回读、寄存器/健康位读回、几何"最后一跳"（命令 → 像素域真的用了它）、
97+ 条串口命令电池（初态与末态必须逐位相同）。任何一段判红就整段停住并打印是哪一段。

推流侧（PC）与串口侧的命令表在 `report/HOST_GUIDE.md`、`report/COMMANDS.md`。
两个使用注意点：**串口 COM6 一次只能被一个程序占用**（自己开着终端占着时脚本会拒绝，不是板子坏了）；
**要看寄存器就先停止推流**，流在跑的时候读到的计数是中间值。

## 3. 实测输出

| 判据 | 读回来的值 | 凭据 |
|---|---|---|
| 串口命令电池 | `RESULT PASS uart_cmd_check (100 条命令, 93.3 s)` | `build/board_verify` 那一跑的日志与 `board/uart_script_capture.txt` |
| 几何自动化最后一跳 | `RESULT PASS geom_check（ok=8 fail=0）`；`zoom fit` 置位/复零、自动旋转下缩放跟着角度走（inv 493 → 507）、收尾 19 个几何位与进来时逐位相同 | 同上 |
| 片源与播放状态 | `[STAT] src=1 … sd=1 frames=4398 playing=1`（SD 在播，PL 拥有 UDP 通路） | `board/uart_script_capture.txt` |
| 缩放档位自洽 | `lane23 zoom → zsel=4 zcode=4 inv_scale=256 x100_actual=100 verdict=OK` | 同上（开机回读段） |
| 温度三方对账 | `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽` | 同上 |
| SD 本地播放帧率 | **29.8 – 30.0 fps**（100 帧滑窗，板上读回） | `data/metrics.csv` 那两行 |
| 全设计时序 | setup WNS **0.720 ns** / hold WHS **0.033 ns**（最差都在 125 MHz 收包域）、失败 setup/hold 端点 **0 / 50890** | `build/timing_summary.rpt` |
| 功耗 | 动态 **2.207 W**、估算结温 **52.5 °C**（工具置信度 Low） | `build/power.rpt`；**这是估算**，不是实测——片上 XADC 的读数走串口 `temp` 与 OSD 那一格 |

**要肉眼确认的（机器判不了）**：屏幕左半是未处理画面、右半是处理后的同一帧，分割线两侧的
几何关系一致；缩放/旋转时画面不出现整行错位；OSD 各格读数与串口读回一致。
这一类"眼睛判据"的结果只有在看的人点头之后才写进表，不预先打勾。

已知未修的几条限制写在 `report/KNOWN_ISSUES.md`（大角度旋转时画面角点会出屏、SD 播放中拔卡会冻帧等），
这里不重复，以免两处漂。

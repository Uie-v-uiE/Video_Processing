# `board/` —— 板上跑的是什么、怎么烧进去、跑完读回什么

这一页回答三件事：板上当前版本与它的身份、JTAG 三步烧写加一把验收的命令、这些命令读回来的实测值。
每个数都点名它出自哪份日志或报告；读不回来的不写。

板上当前版本：r118，位流 `build/system.bit` 的 md5 前 12 位 = `cd04907e1369`
（同一身份写在 `build/evidence/r118_board/board_now.txt` 的开头，配套的 xsa 与 elf 身份在 `build/r118_gates.txt` 的“身份”段）。

## 1. 上板工程

| 项 | 值 | 出处 |
|---|---|---|
| 器件 | Zynq-7020 `xc7z020clg484-2` | `report/build.md` |
| 显示输出 | HDMI **1024×600**，像素时钟 50 MHz、`H_TOTAL=1344`/`V_TOTAL=625`（`src/rtl/video/video_timing_1024x600.v:18-20`）⇒ 场频 **59.5 Hz**；50 MHz 是像素时钟的数值，不是刷新率 | `report/perf_report.md`、`build/timing_summary.rpt` |
| PL 处理画幅 | 512×300（RGB565），输出侧 ×2 展开到 1024×600 上屏 | `src/rtl/top/pl_video_top.v` |
| 片源 | 千兆 RGMII/UDP、SD 卡（FAT32 簇链自研解析）、PL 自绘测试图卡；仲裁与回退在 PL | `report/architecture.md` |
| 上板方式 | **只走 JTAG**：先起 PS，再烧 PL，最后重载应用。本工程的任何脚本都不向 QSPI/SPI flash 写入，也不碰板载 EEPROM | 下面第 2 节的三条命令 |
| 交付二进制 | `build/system.bit`、`build/system.xsa`、`build/ps_app.elf`（认 md5 不认文件名；这三份二进制已被 `.gitignore` 挡住、不入库，随包的是 `board/firmware/system.bit.md` 那三张身份卡） | `board/firmware/system.bit.md`（三张来源卡逐条给 md5 与当场回读命令） |

三个时钟域的余量分开读，混着念会读错（下面这张表按 `build/timing_summary.rpt` 的 Intra Clock Table 逐行抄，
setup 那一列是各自域内最差值）：

| 时钟域 | 周期 | setup 余量（占它自己周期的比例） | hold 余量 |
|---|---|---|---|
| `eth_rxc`（125 MHz 收包域） | 8 ns | **0.720 ns（9.0 %）**，全设计最差 setup 就在这条域里 | 0.049 ns |
| `clk_fpga_0`（100 MHz） | 10 ns | **1.142 ns（11.4 %）** | 全设计最差 min 路径落在这条域（数见下一段） |
| `clkout0_1`（50 MHz 显示域） | 20 ns | **1.767 ns（8.8 %）** | 0.063 ns；`clk_fpga_0` 那一路是 0.060 |

hold 的两个口径要分开，否则同一个数会被念成两种意思。`build/clock_uncertainty.rpt` 里并排放着两条 min 路径：
一条是全设计最差的那条，起点终点都在 `clk_fpga_0`，表头写 `Requirement: 0.000ns`，这一路没加保持不确定度，
slack 就是 0.037 ns；另一条从 `eth_rxc` 起，slack 0.049 ns，而这一族的约束里写着
`set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`，也就是扣掉自加的 0.8 ns 保持不确定度之后剩下的量。
这个数既不能念成“真实余量只有 0.037”，也不能念成“被 0.8 扣过的”：它两个都不是，
它是 100 MHz 域里一条同沿 min 检查的裸余量。

另外两处常见误读：拿 125 MHz 那条 setup 的余量去除 20 ns 的显示周期，会算出“显示域只剩 2.5 %”这种话；
把三个域压成一句“余量 0.7 ns”，听的人不知道说的是哪一路。逐时钟的原始表在
`build/timing_summary.rpt` 的 Intra Clock Table 那一段。收口只走一棵时钟树之后，
最差 20 条 hold 路径的时钟偏斜实测 0.013~0.349 ns（`build/hold_paths.rpt` 逐条读），改前那一条是 1.616 ns。

## 2. 运行脚本

四条命令按顺序跑，**都在仓库根执行**（脚本自己按所在目录解析仓库根，换目录跑会找不着 `build/`）。
扫链那一步对板子没有别的要求；起 PS、烧 PL、重载应用这三步需要板子已供好电、USB-C 已插、
本机的 `hw_server` 服务在跑。

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

| 步 | 板子该处于什么状态 | 预期看到 | 不对时先看哪里 |
|---|---|---|---|
| 扫链 | 已上电、USB-C 已插，PL 未配置也可以 | stdout 出现 `=== TARGETS ===` 与 `=== DEVICES ===` 两段，设备清单里 DAP 与 Zynq 各占一行 | 报 `No devices detected` 时先看板子的直流供电有没有插上，其次看本机 `hw_server` 服务在不在跑；反面凭据 `build/r88_jtag_scan.txt`（USB 侧全部枚举正常、链上一个设备也没列出来，缺的是板子供电） |
| 起 PS | 同上，串口没人占着 | `PS7_INIT: ok`、`RST_SYSTEM: ok`，之后 `DDR_ECHO` 那一格回读到位流写进去的图样 | 连不上且 `CONNECT:` 是空的 ⇒ 本机没有 `hw_server`，先起 `<Vitis>/bin/hw_server.bat` 再重跑这一步 |
| 烧 PL | 起 PS 已过 | `PROGRAMMED xc7z020_1 <- …/build/system.bit`，同一份输出里有 `INFO: [Labtools 27-3164] End of startup status: HIGH` | 拿 `md5sum build/system.bit` 的头一段与上面点名的当前版本对回；对不上说明烧进去的不是这一版 |
| 重载应用 | 烧 PL 已过（PL 没烧之前应用起不来） | `DOW: ok`、`CON: ok`、`RESUME: ok`，串口打出 `[BOOT]` 横幅 | 串口没动静 ⇒ 先确认 COM6 没被别的终端占住（见本节末）；`ps_app_reload.tcl` 只复位 Cortex-A9 那颗核，不会冲掉已配好的位流 |

上板之后一把验完（还是在仓库根）：`VP_XSDB` 必须指到真实存在的 `<Vitis>/bin/xsdb.bat`，
指不到就整条拒绝并退出码给 2；脚本自己 `cd` 回仓库根，日志留在 `build/evidence/`。

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom
```

它按这几段跑：开机回读（含把原始串口回显单独落一份件）、读回口（`src/host/health_read.mjs` 把 lane0..9 与
lane23..31 逐格打回来）、串口命令批量测试（`--battery`：一次性跑 105 条串口命令，逐条比对期望回显，
跑完必须回到进来的那一态）、几何“最后一跳”（`--geom`：命令发下去之后，像素域真的用了它没有）。
任何一段不过就整段停住并打印是哪一段，末尾总判定形如 `RESULT board_verify PASS（判红的步骤：0）`。
警告：上面那条命令没有带 `--round=`，所以“原始串口回显”那一段会判不通过（这是故意的：
没有版本身份的一手回显会被写成别人的旧件）；要一把全过就再补一个 `--round=`，把上面板上当前版本那一行的版本号填进去。
`--stream`（仲裁交接那一段，约 2 分钟）与 `--self`（只测判定本身、不碰板子）两个开关见脚本文件头。

推流侧（PC）与串口侧的命令表在 `report/host_guide.md`、`report/commands.md`。
两个使用注意点：**串口 COM6 一次只能被一个程序占用**（自己开着终端占着时脚本会拒绝，不是板子坏了）；
**要看寄存器就先停止推流**，流在跑的时候读到的计数是中间值。

## 3. 实测输出

| 检查项 | 读回来的值 | 凭据 |
|---|---|---|
| 串口命令批量测试 | `RESULT PASS uart_cmd_check  (105 条命令, 97.3 s)`；工具本机还会重写一份串口捕获，那份被 `.gitignore` 挡住、不随包，随包复核用右边这份总判定 | `build/r104_board_verify_console.txt`（2026-10-02 那一跑，`RESULT board_verify PASS（判红的步骤：0）`） |
| 几何“最后一跳”自动化 | `RESULT PASS geom_check（ok=10 fail=0）`；`zoom fit` 置位/复零、自动旋转下缩放跟着角度走、收尾那 19 个几何位与进来时逐位相同 | 同上 |
| 片源与播放状态 | `[STAT] ctrl thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 … sd=1 frames=4398 playing=1`（SD 在播，PL 拥有 UDP 通路） | 逐字回读 `build/evidence/r104_serial_raw.txt`（被跟踪、随包） |
| 缩放档位自洽 | `lane23 zoom → zsel=4 zcode=4 inv_scale=256 x100_actual=100 verdict=OK` | 同上（开机回读段） |
| 温度格三方对账 | `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽` | 同上 |
| SD 本地播放帧率 | **29.8 – 30.0 fps**（100 帧滑窗，板上读回） | `data/metrics.csv` 那两行 |
| 全设计时序 | setup WNS **0.720 ns** / hold WHS **0.033 ns**（最差都在 125 MHz 收包域）、失败 setup/hold 端点 **0 / 50890** | `build/timing_summary.rpt`；这组数是它点名那一次构建的读数，当前产物上的现读数以 `bash build/gates.sh` 打印的那一行为准 |
| 功耗 | 动态 **2.207 W**、估算结温 **52.5 °C**（工具置信度 Low） | `build/power.rpt`；**这是估算**，不是实测——片上 XADC 的读数走串口 `temp` 与 OSD 那一格 |

下面三条只能由看着屏幕的人确认，检查脚本判不了，所以不预先写成通过：屏幕左半是未处理画面、
右半是处理后的同一帧，分割线两侧的几何关系一致；缩放或旋转时画面不出现整行错位；
OSD 各格读数与串口读回一致。这一类的记录口径见 `board/acceptance.md` 的“要人眼确认的”一节。

已知未修的几条限制写在 `report/known_issues.md`（大角度旋转时画面角点会出屏、SD 播放中拔卡会冻帧等），
这里不重复，以免两处漂。

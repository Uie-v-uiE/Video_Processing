# `build/` —— 构建脚本导览与从空目录到位流的步骤

构建脚本在 `build/tcl/`，报告归档在 `build/report/`；`build/evidence/`、`build/frozen_*/` 与带历史轮次号的那批
`.txt` 是一次次留档，不随包。工具 Vivado v2025.2.1（版本串原文 `build/r118_build_console.txt:1-4`），
器件 `xc7z020clg484-2`（构建入口 `:16` 写死）；Vitis 侧按安装目录名 2025.2.1 记（`xsdb.bat -Version` 的原文没有取到），
同一口径写在 `build/provenance.md` 第 2 节。**下面所有命令都在仓库根执行**；这一层不需要板子，
板子上要做的动作在 `board/README.md`。

## 一、脚本对照：哪支脚本做什么、产出什么

| 脚本 | 做什么 | 产出 |
|---|---|---|
| `build/tcl/build_system_axigpio.tcl` | **唯一支持的构建入口**：`create_project -force`（`:21`）→ 收 RTL（`:25-30` 十个目录 glob 加 `pl_video_top.v`、`system_top.v`）→ 加 `rk_zynq7020.xdc`（`:31`）与只在实现生效的 `clock_groups_impl.xdc`（`:36-38`）→ 建 BD（PS7 + 3×axi_gpio + 2×interconnect）、钉基址并逐段回读 `ADDR_LOG`、`validate_bd_design`（`:273`）→ `launch_runs synth_1 -jobs 4`（`:306`）→ `launch_runs impl_1 -to_step write_bitstream -jobs 4`（`:353`）→ `set_property top system_top`（`:288`） | `build/system.bit`（`:360`）、`build/system.xsa`（`:371`）、`build/` 下 7 份 `.rpt`（`:362-370`）、`width_warnings.txt` 与 `multi_driven.txt`（`:398-407`）；末行 `SYSTEM BUILD DONE`（`:411`） |
| `build/build.tcl` | 交付口径的主入口，`:10` 直接 source 上面那支，两者等价 | 同上 |
| `build/create_project.tcl` | 只建工程并停在综合之前（`VP_STOP_AT=project`） | `vivado_system/zynq_video_sys.xpr` 与 sources_1、constrs_1、run 列表 |
| `build/add_sources.tcl` | 只把 RTL、IP、约束挂进工程 | 工程内 sources_1、constrs_1 与各约束的 `used_in_*` 属性 |
| `build/synth.tcl` | 只对已建好的工程跑综合；`VP_PROJ_SUBDIR` 可指到别处，免得覆盖正式工程 | `…runs/synth_1/` 与 `runme.log` |
| `build/impl.tcl` | 在综合结果上单独跑到 `route_design`；位流由 `gen_bit.tcl` 负责 | `…runs/impl_1/` 与 `runme.log` |
| `build/report.tcl` | `open_run impl_1` 后只重出 7 份报告，归档目录由 `VP_OUTDIR` 覆盖，默认 `build/report` | `build/report/` 下 7 份 `.rpt`，见 2.4 |
| `build/gen_bit.tcl` | 只补 `write_bitstream`，并把位流与 XSA 各拷一份到板侧目录（默认目录可用 `VP_BIT_DIR` 改；**跑完才有，仓库里现在没有这两份拷贝**） | `board/` 下的位流与 XSA 拷贝 |
| `build/tcl/build_system.tcl`、`build/tcl/build_pl_full.tcl`、`build/tcl/create_project.tcl`、`build/tcl/synth_pl_only.tcl`、`build/tcl/build_bitstream.tcl` | **别当入口用**：这五支的仓库根解析写成 `[file dirname [info script]] ..`（依次在各文件 `:6`、`:6`、`:13`、`:7`、`:12`），比入口少一层，根落到 `build/`，于是 `add_files` 指向不存在的 `build/src/…` | 在 `add_files` 就死掉，**报错之后仍然 exit 0**；`build_system.tcl:10-11` 与 `build_pl_full.tcl:45-46` 的 `file mkdir $outdir`（`$outdir` = `$root/build`，而 `$root` 已落到 `build/`）会凭空造出 `build/build/`（现在 `ls build/build/` 是目录不存在，说明这一条只在这几支真被跑起来时才成立）。**判成败只看 `build/` 里产物的修改时间，不信退出码**（过程记录 `report/log/issues.md` 的 #22 与 #41；同一说明在 `build/tcl/README.md` §1） |
| `build/tcl/crit_path.tcl`、`build/tcl/hold_paths.tcl`、`build/tcl/cdc_who.tcl`、`build/tcl/read_run_result.tcl`、`build/tcl/probe_timing_roster.tcl` | 只读查询：setup 最差路径落在哪条线 / WHS 压在哪几条 / 哪几个寄存器使 `cdc.rpt` 那行变 Critical / 当前 `impl_1` 的三个数 / 逐时钟名册 | stdout |
| `build/tcl/report_mem_hier.tcl` | 层次化资源报告，回答 BRAM 被谁吃掉（深度写死 4） | `build/util_hier.rpt` |
| `build/tcl/sweep_impl_strategy.tcl` | 同一份网表逐个实现策略重跑 `impl_1` 并汇总时序（`SWEEP_STRATS` 覆盖默认 5 档，收尾把策略恢复成扫描前的值） | `build/sweep_summary_<时间戳>.txt` 与 `build/sweep_<策略>_timing.rpt` |
| `build/tcl/ooc_newmods.tcl` | 三个新模块各做一次 out-of-context 综合，带 3 ns 输入延迟打时序，抓结构性长链 | `build/` 根下的 `ooc_util.rpt`（跑完才有）与每模块一段 Slack 行 |
| `build/tcl/scan_jtag.tcl` | 列 `hw_server` 看得见的 JTAG target 与 device，用来区分"线缆没插"和"板子没上电"；跑法是 `vivado -mode batch -source`，不是 xsdb | stdout 的 TARGETS 与 DEVICES 两段 |
| `build/tcl/set_src.tcl` | 经 JTAG 写 AXI GPIO `0x41200000` 选显示源与特效（**不是**源文件清单；RTL 清单在入口 `:25-30`） | stdout |
| `build/tcl/ps_jtag_boot.tcl`、`build/tcl/program_pl.tcl`、`build/tcl/ps_app_reload.tcl` | 上板三件套：先起 PS，再烧 PL，最后重载应用；**全程只走 JTAG，本工程的脚本从不向 QSPI/SPI flash 写入** | 板上运行状态；console 落在 `build/evidence/` 下带版本号的目录里 |

`build/tcl/` 下 git 跟踪 95 支 `.tcl`，其余是各趟探针与滚档脚本，"现在还在用的是哪几支"的名单在 `build/tcl/README.md`。

## 二、从空目录到位流

### 2.1 步骤

| 步 | 命令 | 跑之前要有什么 | 完成后应看到 | 不对先看哪里 |
|---|---|---|---|---|
| 0 起点 | 取仓库、装 Vivado 2025.2.1、`cd` 到仓库根 | 只有 Git 与 Vivado | `build/tcl/build_system_axigpio.tcl`、`src/rtl/`、`src/constraints/rk_zynq7020.xdc` 三者都在 | 少哪一个就是没取全；约束不在 `src/constraints/` 就别往下跑 |
| 1 BD-only 快检 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl -tclargs bd_only` | 磁盘可写、没有别的 Vivado 在开同一个工程 | 末行 `BD_ONLY_DONE`（入口 `:278` 早退）。实测 19 s（`build/log_r45_bdonly4.txt` 的 `:6` 与 `:245` 两端）；脚本注释 `:276` 给的理由是 BD 配置写错本来 3 分钟就能验出来，不必等 20 分钟的综合加实现 | 这一步不通过 ⇒ 只看 stdout 里 `ADDR_LOG` 与 `validate_bd_design` 那几段，地址钉错在这里就会现形 |
| 2 全量构建 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` | 同上；这一趟约 20 分钟不动板子 | 末行 `SYSTEM BUILD DONE`，中间有 `BIT:`、`XSA:` 两行（`:373-374`）；`build/` 下位流、XSA、7 份 `.rpt`、两份凭据的修改时间全部刷新 | **按修改时间判成败，按退出码判会漏**（第一节那五支报错也 exit 0） |
| 3 发布前检查 | `bash build/gates.sh` | 第 2 步已经产出这套报告 | 逐项读数与阈值比一遍，读数落 `build/ports_check.txt` 与 stdout；末行只会是三种之一：`GATES: ALL PASS`、`GATES: 有红项（判定 N 项）`、`GATES: PARTIAL —— 判定 N 项全过，但有 M 项因缺凭据未判` | 任何一项未通过 ⇒ 这一版不采纳、不归档；先读那一行点名的凭据件，不要先改阈值。`PARTIAL` 也不算过：有凭据缺席没判的项存在时，末行不会是 `ALL PASS` |
| 4 上板回读 | `VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom` | 板子已上电、三步 JTAG 链已跑完、COM6 空着 | 逐格回读，外加串口命令批量测试与几何"最后一跳"；console 落在 `build/evidence/` | 见 `board/README.md` §2 那张分步表 |

失败按顺序看日志：先在这次构建自己的 console 件里 grep `SYNTH FAILED`、`ADDRESS PINNING FAILED`、
`PORT_LOOKUP_FAILED`、`BUILD_STRATEGY_REJECTED`、`BUILD_HOOK_REJECTED`、`BUILD_PRPO_REJECTED`，
命中哪个就是哪一步停的（本版那一份是 `build/r118_build_console.txt`）；一条都不中而缺末行
`SYSTEM BUILD DONE` 就再看 `…runs/synth_1/runme.log` 与 `…runs/impl_1/runme.log`。
逐轮链脚本另需两个变量，不给就中止：`build/r118_chain.sh:22-23` 用 `${VP_VIVADO_BIN:?}` 与 `${VP_XSDB:?}`
（同文件 `:21` 那个 `:-` 默认值在 `:?` 面前是死代码），`build/board_verify.sh:118` 对 `VP_XSDB` 判文件是否存在，
缺 ⇒ `exit 2`；工具目录怎么填见 `report/build.md`。
起构建前的自探测——工具版本等值、器件在不在设备库、磁盘余量、有没有同名进程在写目标目录、
归档会不会覆盖已采纳产物——这五条现行入口一条都没做，逐条对回行号见 `build/probe-guard.md` §3。
PS 侧 ELF 不在上面这条链里：本机 PATH 无 `arm-none-eabi-gcc`（`which` 无命中），这一版没有重编，
`build/ps_app.elf` 还是上一次构建那一份（它的文件时间与校验和记在 `board/firmware/ps_app.elf.md`）；
编译与自检口径在 `src/ps/README.md`（`git ls-files src/ps` 回 5 支）。

### 2.2 可选环境变量：这些都不设就是出货档

| 变量 | 开关什么 | 不设时 |
|---|---|---|
| `VP_R116_IO_WINDOW=1` | RGMII 收口 5 个输入的候选输入窗 `src/constraints/r116_rgmii_input_window.xdc` 进实现（入口 `:57-63`），预期这 5 个 I/O 端点在时序报告上成为未通过项 | 日志念 `VP_R116_IO_WINDOW off`，窗留在候选件里 |
| `VP_R119_TMDS_WINDOW=1` | HDMI 源端 TP1 窗 `src/constraints/r119_hdmi_source_window.xdc` 进实现（入口 `:75-81`），该轮名册读数还没有做，不许读成已采纳 | 日志念 `VP_R119_TMDS_WINDOW off` |
| `IMPL_STRATEGY` | 换 `impl_1` 的实现策略，策略名打进日志 `BUILD_STRATEGY …`（`:317-323`）；非法名先念 `BUILD_STRATEGY_REJECTED` 再 `exit 1` | 工程默认档 `Vivado Implementation Defaults` |
| `IMPL_POST_PLACE_HOOK` | 布局后挂一支外部 tcl：给 `STEPS.PLACE_DESIGN.TCL.POST` 加钩子，挂了什么都打进日志（`:328-336`） | 日志念 `BUILD_POST_PLACE_HOOK none` |
| `IMPL_PRPO=1` | 打开 post-route physopt 并设 `AggressiveExplore`（`:341-352`），只动物理结果、不动网表，所以不必重跑 RTL 台架 | 日志念 `BUILD_PRPO off` |

### 2.3 耗时

出处是本版构建自己打的日志时间戳（`build/r118_build_console.txt` 与 `build/r118_console.txt`）。
换机器不保证同值，同一份 RTL 也不能保证逐位相同；这里只记时长，不记钟点。

| 阶段 | 墙钟 | 出处 |
|---|---|---|
| 建工程 + 收文件 + 建 BD + 钉地址 + wrapper | 59 s | `build/r118_build_console.txt:6` 起到 `:283` 的 `Launched synth_1`；`create_project` 自身 9 s（`:18`） |
| `synth_1`（含 6 支 OOC IP 并行，`:275` 列出名字） | 10 min 09 s | 入口 `:1744` 那行 `wait_on_runs` 的 elapsed 值（原文见本节末那段），其中 `synth_design` 本体 6 min 30 s（`:1738`） |
| `impl_1` 合计 | 7 min 22 s | 入口 `:2620` 那行 `wait_on_runs` 的 elapsed 值（原文见本节末那段）：opt 27 s（`:2030`）、place 1 min 32 s（`:2290`）、physopt 7 s（`:2324`）、route 3 min 10 s（`:2543`）、write_bitstream 29 s（`:2617`） |
| 7 份报告 + XSA + 两份凭据 | 58 s | 报告段到末行 `Exiting Vivado`（`:2734`）之间 |
| **构建合计** | **19 min 30 s** | 同上两端；链侧同一趟从起飞到 `构建 rc=0`（`build/r118_console.txt:2-3`） |
| BD-only 早退那一跑 | 19 s | `build/log_r45_bdonly4.txt:6` 与 `:245` |
| 名册 + 差分 + 读数 + 判读 | 3 min 03 s | `build/r118_console.txt:3-10` |
| 发布前检查跑两趟 | 1 min 26 s | 同文件 `:10-12` |

上面两行的 elapsed 原文（抄自 `build/r118_build_console.txt`，逐字）：

```text
:1744  wait_on_runs: Time (s): cpu = 00:00:02 ; elapsed = 00:10:09 . Memory (MB): peak = 739.680 ; gain = 0.000
:2620  wait_on_runs: Time (s): cpu = 00:00:01 ; elapsed = 00:07:22 . Memory (MB): peak = 739.680 ; gain = 0.000
```

### 2.4 报告归档与可复算

| 报告 | 归档件（归档件在就引用这一列） | 重出它的脚本 |
|---|---|---|
| 时序汇总 | `build/report/timing_summary.rpt` | `build/report.tcl`；构建那一次由入口 `:362` 落同一份 |
| 资源占用 | `build/report/utilization.rpt` | 同上，入口 `:363` |
| CDC | `build/report/cdc.rpt` | 同上，入口 `:365` |
| 方法论 | `build/report/methodology.rpt` | 同上，入口 `:366` |
| 功耗 | `build/report/power.rpt` | 同上，入口 `:368`；这份是估算（没有仿真活动文件、没有实测），引用时必须写"估算" |
| 布线状态 | `build/report/route_status.rpt` | 同上，入口 `:369` |
| 时钟利用 | `build/report/clock_util.rpt` | 同上，入口 `:370` |

`build/` 根下同名的 7 份是随包的散装副本，与 `build/report/` 那一版同源；引用报告时指归档件。
报告里的每个数都要能靠最后一列那支脚本重跑得到。本文件核对过这件事：跑 `build/report.tcl` 与正式件对拍，
7 份里 6 份只差 `Date` 行与 `Command … -file` 行各一条，`route_status.rpt` 逐字节相同，
凭据 `build/evidence/r121_c4_verify.txt`。
两条读数口径要说清：slack 绝对值在相邻两版之间会摆零点几 ns（放置运气），判断有没有变好要同口径复跑，
不看单个 WNS；`utilization.rpt` 里 `RAMB36/FIFO*` 的单元数与 `Block RAM Tile` 的瓦片数不是同一个数，引用要分清。
归档命名规则与实际形状在 `build/artifacts/README.md`；本版产物的来源与时刻表在 `build/provenance.md`。

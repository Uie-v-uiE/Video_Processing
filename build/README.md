# `build/` —— 构建脚本、发布前检查与综合/实现报告

这一层只有四类东西：**构建与查询用的 Tcl 脚本**、**发布前检查（尺子）**、**综合与实现报告**、
**报告与读数的留档**。工具 Vivado / Vitis 2025.2.1，器件 `xc7z020clg484-2`（构建入口里写死）。
下面所有命令都在**仓库根**执行；这一层不需要板子，板子上要做的动作在 `board/README.md`。

自查这一层现在到底有什么（数字会随重构漂，命令不会）：

```bash
find build -type f | wc -l                 # 全部件数
git ls-files build | wc -l                 # 入库件数
ls build/*.tcl build/tcl/*.tcl | wc -l     # Tcl 脚本数
ls build/report/*.rpt | wc -l              # 归档报告数
```

## 一、脚本对照：哪支脚本构建什么、产出什么

### 1.1 构建入口（把设计从空目录做到位流）

| 脚本名 | 做什么 | 产出 |
|---|---|---|
| `build/tcl/build_system_axigpio.tcl` | **唯一支持的构建入口**：`create_project -force` → 收 `src/rtl/` 十个目录的 RTL 与 `src/constraints/rk_zynq7020.xdc`（外加只在实现阶段生效的 `clock_groups_impl.xdc`）→ 建 BD（PS7 + 3×`axi_gpio` + 2×interconnect）→ 逐段回读并钉基址 → `validate_bd_design` → `launch_runs synth_1` → `launch_runs impl_1 -to_step write_bitstream` → `set_property top system_top` | `build/system.bit`、`build/system.xsa`、`build/` 下 7 份 `.rpt`、`build/width_warnings.txt` 与 `build/multi_driven.txt`；末行 `SYSTEM BUILD DONE` |
| `build/build.tcl` | 交付口径的主入口，正文直接 source 上面那支，两者等价 | 同上 |
| `build/create_project.tcl` | 只建工程并停在综合之前（`VP_STOP_AT=project`） | `vivado_system/zynq_video_sys.xpr` 与 sources_1、constrs_1、run 列表 |
| `build/add_sources.tcl` | 只把 RTL、IP、约束挂进工程 | 工程内 sources_1、constrs_1 与各约束的 `used_in_*` 属性 |
| `build/synth.tcl` | 只对已建好的工程跑综合；`VP_PROJ_SUBDIR` 可指到别处，免得覆盖正式工程 | `…runs/synth_1/` 与 `runme.log` |
| `build/impl.tcl` | 在综合结果上单独跑到 `route_design`；位流由 `gen_bit.tcl` 负责 | `…runs/impl_1/` 与 `runme.log` |
| `build/report.tcl` | `open_run impl_1` 后只重出 7 份报告，归档目录由 `VP_OUTDIR` 覆盖，默认 `build/report` | `build/report/` 下 7 份 `.rpt`，见第四节 |
| `build/gen_bit.tcl` | 只补 `write_bitstream`，并把位流与 XSA 各拷一份到板侧目录（默认目录可用 `VP_BIT_DIR` 改） | 板侧目录下的位流与 XSA 拷贝 |

注意：`build/tcl/build_pl_full.tcl` 的仓库根解析写成 `[file dirname [info script]] ..`，比入口少一层，
根会落到 `build/`，于是 `add_files` 指向不存在的 `build/src/…` ⇒ **别当入口用**。
判构建成败只看 `build/` 里产物的修改时间，不看退出码（这一类脚本报错之后仍然 `exit 0`）。

### 1.2 只读查询（不开综合，只读现成的实现结果）

| 脚本名 | 回答什么问题 | 输出落在哪 |
|---|---|---|
| `build/tcl/crit_path.tcl` | setup 最差那条路径落在哪根线上 | stdout |
| `build/tcl/hold_paths.tcl` | WHS 压在哪几条 hold 路径上 | `build/hold_paths.rpt` |
| `build/tcl/clock_uncertainty.tcl` | 每个时钟实际生效的 uncertainty（含 `-hold` 那一支） | `build/clock_uncertainty.rpt` |
| `build/tcl/cdc_who.tcl` | 是哪几个寄存器让 `cdc.rpt` 那一行成为 Critical | stdout |
| `build/tcl/read_run_result.tcl` | 当前 `impl_1` 的 WNS / TNS / 失败端点三个数 | stdout |
| `build/tcl/probe_timing_roster.tcl` | 逐时钟名册（每个时钟域各自的 setup/hold 最差值） | `build/roster_*.rpt` 逐时钟一份 |
| `build/tcl/probe_clk_worst.tcl`、`build/tcl/probe_cone_slack.tcl` | 指定时钟的最差路径、指定组合锥的级数与 slack | stdout，`bash build/pre_readings.sh` 调它们 |
| `build/tcl/probe_ff_init.tcl` | 上电那一拍有没有寄存器没有初值（`Synth 8-7137` 一族） | stdout，`bash build/check_powup_init.sh` 调它 |
| `build/tcl/probe_ser_clock.tcl`、`build/tcl/probe_report_shape_pin.tcl`、`build/tcl/probe_target_select.tcl`、`build/tcl/probe_uncertainty_uniform.tcl` | 串行时钟来源、报告表头形状、`get_pins` 选择器能不能命中、均匀 uncertainty 的形状核对 | stdout 与 `build/evidence/` 下的读数件 |
| `build/tcl/report_mem_hier.tcl` | BRAM 被谁吃掉（层次化资源，深度写死 4） | `build/util_hier.rpt` |
| `build/tcl/ooc_newmods.tcl`、`build/tcl/micro_rd.tcl`、`build/tcl/uram_presence.tcl`、`build/tcl/uram_sites.tcl` | 单模块 out-of-context 综合、读口探针、URAM 在这颗器件上的存在与位置 | stdout 与 `build/micro_rd/` |
| `build/tcl/sweep_impl_strategy.tcl` | 同一份网表逐个实现策略重跑 `impl_1` 并汇总时序（`SWEEP_STRATS` 覆盖默认档位，收尾恢复） | `build/sweep_summary_<时间戳>.txt` |

### 1.3 上板动作（走 JTAG，本工程从不向 QSPI/SPI flash 写入）

| 脚本名 | 什么时候用 | 产出 |
|---|---|---|
| `build/tcl/scan_jtag.tcl` | 分不清"线缆没插"还是"板子没上电"时先列 JTAG target 与 device；跑法是 `vivado -mode batch -source`，不是 xsdb | stdout 的 TARGETS 与 DEVICES |
| `build/tcl/jtag_probe.tcl` | 进一步确认链路与供电 | stdout |
| `build/tcl/ps_jtag_boot.tcl` | 三步链第一步：起 PS | 板上运行状态，console 落 `build/evidence/` |
| `build/tcl/program_pl.tcl` | 第二步：烧 PL | 同上 |
| `build/tcl/ps_app_reload.tcl` | 第三步：重载 PS 应用 | 同上 |
| `build/tcl/program_board.tcl`、`build/tcl/program_system.tcl`、`build/tcl/program_and_check.tcl` | 上面三步的一把过版本与带校验版本 | 同上 |
| `build/tcl/set_src.tcl` | 写 AXI GPIO `0x41200000` 选显示源与特效（**不是**源文件清单） | stdout |
| `build/board_verify.sh` | 三步链跑完后逐格回读板子；`--battery` 加串口命令批量测试，`--geom` 加几何"最后一跳" | 读数与 console 落 `build/evidence/` |

### 1.4 尺子（发布前检查；每一条判据都有自己的反例）

| 脚本名 | 判什么 | 怎么跑 |
|---|---|---|
| `build/gates.sh` | **发布前检查本体**：时序、资源、功耗、方法学、布线错误、CDC 配对集合、端口宽度警告、多驱动、顶层接线、顶层台架、边缘条带、PS 心跳约定、手写件编码、文档时效、排练脚本、行号锚点、数字对账、命令长度口径、结温公式 | `bash build/gates.sh`（读当前这套报告）或 `bash build/gates.sh build/frozen_r19_arb`（读一组成套冻结件） |
| `build/checks/check_repo_consistency.mjs` | 仓库一致性 C1–C12（指标表指得到证据、文档内路径存活、命名、时间线、失败可见等） | `node build/checks/check_repo_consistency.mjs` |
| `build/deliver_spec_check.mjs` | 交付规格 C0–C7（顶层结构、脚本头要素、`build/report/` 归档件与脚本一一对应、README 对照表） | `node build/deliver_spec_check.mjs` |
| `build/deliver_spec_selftest.mjs`、`build/checks/check_repo_hygiene.sh`、`build/freeze_selftest.sh`、`build/gates_cdc_test.sh` | 上面几把尺子自己的反例（"该红的必须能红"） | `node …` / `bash …` |
| `build/make_submission.sh` | 导出提交包：先剪逐轮留档，再跑死链自检 | `bash build/make_submission.sh` |
| `build/rtl_fingerprint.sh`、`build/check_ports.py`、`build/ports_floor.sh`、`build/ports_dup_ce.sh`、`build/run_one_ce.sh` | 源码指纹、顶层接线、计数地板、各自的变异对照 | 由 `gates.sh` 调用 |
| `build/freeze_evidence.sh`、`build/refresh_evidence.sh`、`build/verify_evidence.sh`、`build/restore_documented_bit.sh`、`build/orphan_rtl.sh`、`build/cleanup_wip.sh` | 冻结一版凭据、按当前树重出、回验、把位流对回文档戳着的那一颗、找零引用 RTL、清工作中间物 | 逐支 `bash build/<名>.sh`，`--help` 或文件头说明参数 |
| `build/ps_app.mjs`、`build/build_ps_app.py` | 编 PS 裸机固件（编译器不在 PATH，需 `PS_CC` 指绝对路径；`PS_BSP` 也必须绝对路径） | `node build/ps_app.mjs` |
| `build/tb98_report.sh`、`build/rim_report.sh`、`build/timing_lane.sh`、`build/timing_roster_diff.sh`、`build/roster_from_summary.sh`、`build/pre_readings.sh`、`build/check_io_timing_coverage.py`、`build/check_powup_init.sh`、`build/r119_window_check.mjs` | 台架与名册读数工具：整屏台架报告、边缘条带报告、逐lane读数、名册差分、逐时钟读数、输入窗自校验 | 文件头写了各自需要的环境变量与参数 |

`build/` 根下另有一批 `rNN_*` 开头的链脚本与读数件（例如 `build/r118_chain.sh`、`build/r116_bit_cycle.sh`、
`build/r119_window_check.mjs`）。**它们不是可复用的工具**，是因为交付文档按名字引着它们当某一刀的凭据才留在仓里：
读的时候按"当时那一步的现场"读，别照抄里面的默认路径当现行流程；文档里那句结论对回盘上件时指的就是这些名字。

## 二、从空目录到位流

| 步 | 命令 | 跑之前要有什么 | 完成后应看到 |
|---|---|---|---|
| 0 起点 | 取仓库、装 Vivado 2025.2.1、`cd` 到仓库根 | 只有 Git 与 Vivado | `build/tcl/build_system_axigpio.tcl`、`src/rtl/`、`src/constraints/rk_zynq7020.xdc` 三者都在 |
| 1 BD-only 快检 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl -tclargs bd_only` | 磁盘可写、没有别的 Vivado 在开同一个工程 | 末行 `BD_ONLY_DONE`。这一趟只验 BD 与地址回读，比全量快一个量级，配置写错在这里就现形 |
| 2 全量构建 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` | 同上；这一趟约 20 分钟不动板子 | 末行 `SYSTEM BUILD DONE`，中间有 `BIT:`、`XSA:` 两行；`build/` 下位流、XSA、7 份 `.rpt`、两份凭据的修改时间全部刷新。**按修改时间判成败，按退出码判会漏** |
| 3 发布前检查 | `bash build/gates.sh` | 第 2 步已经产出这套报告 | 逐项读数与阈值比一遍，读数落 `build/ports_check.txt` 与 stdout；末行只会是三种之一：`GATES: ALL PASS`、`GATES: 有红项（判定 N 项）`、`GATES: PARTIAL —— 判定 N 项全过，但有 M 项因缺凭据未判` |
| 4 重出报告 | `vivado -mode batch -source build/report.tcl` | 第 2 步的 `impl_1` 还在 | `build/report/` 下 7 份 `.rpt` |
| 5 上板回读 | `VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom` | 板子已上电、三步 JTAG 链已跑完、COM6 空着 | 逐格回读，console 落 `build/evidence/`；见 `board/README.md` |

失败按顺序看日志：先在这次构建自己的 console 件里 grep `SYNTH FAILED`、`ADDRESS PINNING FAILED`、
`PORT_LOOKUP_FAILED`、`BUILD_STRATEGY_REJECTED`、`BUILD_HOOK_REJECTED`、`BUILD_PRPO_REJECTED`，
命中哪个就是哪一步停的；一条都不中而缺末行 `SYSTEM BUILD DONE`，就再看 `…runs/synth_1/runme.log`
与 `…runs/impl_1/runme.log`。`build/board_verify.sh` 对 `VP_XSDB` 判文件是否存在，缺 ⇒ `exit 2`。

注意：不要把 `bash build/gates.sh` 的输出直接重定向成它自己要读的那份 `build/rNN_gates.txt`：
第一项判据跑之前文件就被截断，而文档时效那一项恰恰要拿"盘上最新且 ALL PASS 的那一份"当基准。
正确姿势两步：先 `bash build/gates.sh > /tmp/g.txt 2>&1` 跑完，全绿之后再 `cp` 到位。

### 2.1 可选环境变量：都不设就是出货档

| 变量 | 开关什么 | 不设时 |
|---|---|---|
| `VP_R116_IO_WINDOW=1` | RGMII 收口 5 个输入的候选输入窗 `src/constraints/r116_rgmii_input_window.xdc` 进实现 | 日志念 `VP_R116_IO_WINDOW off`，窗留在候选件里 |
| `VP_R119_TMDS_WINDOW=1` | HDMI 源端 TP1 窗 `src/constraints/r119_hdmi_source_window.xdc` 进实现 | 日志念 `VP_R119_TMDS_WINDOW off` |
| `IMPL_STRATEGY` | 换 `impl_1` 的实现策略，策略名打进日志；非法名先念 `BUILD_STRATEGY_REJECTED` 再 `exit 1` | 工程默认档 `Vivado Implementation Defaults` |
| `IMPL_POST_PLACE_HOOK` | 给 `STEPS.PLACE_DESIGN.TCL.POST` 挂一支外部 tcl | 日志念 `BUILD_POST_PLACE_HOOK none` |
| `IMPL_PRPO=1` | 打开 post-route physopt 并设 `AggressiveExplore`（只动物理结果、不动网表） | 日志念 `BUILD_PRPO off` |
| `VP_OUTDIR` / `VP_BIT_DIR` / `VP_PROJ_SUBDIR` / `VP_STOP_AT` | 报告归档目录 / 位流与 XSA 的拷贝落点 / 工程子目录 / 停在哪一步 | 各脚本文件头写的默认值 |
| `PS_CC` / `PS_BSP` | 交叉编译器与 BSP 路径，重编 PS 固件用 | 没有默认值：不给就报缺，`PS_BSP` 还必须是绝对路径 |

## 三、报告：现在哪几版的综合/实现结果在仓里

只留**少数几版**的实现与时序报告，其余逐轮件已经清掉。

| 是哪一版 | 位置 | 里面有什么 |
|---|---|---|
| **板上当前这一版** | `build/` 根下的平铺件 | `timing_summary.rpt`、`utilization.rpt`、`power.rpt`、`methodology.rpt`、`route_status.rpt`、`cdc.rpt`、`clock_util.rpt`（这 7 份是 `gates.sh` 与 `src/host/metric_recheck.mjs` 读的那一套），另加 `hold_paths.rpt`、`clock_uncertainty.rpt`、`cdc_details.rpt`、`check_timing_verbose.rpt`、`setup_paths.rpt`、`crit_paths_raw.rpt`、`util_hier.rpt`、`read_run_timing.rpt` 这些逐路读数件，以及逐时钟名册 `roster_r118_*.rpt` |
| **归档件（交付口径）** | `build/report/` | 与上同源的那 7 份，`build/report.tcl` 能整批重出；引用报告时优先指这一份 |
| **冻结的 r75 全套** | `build/evidence_r75/` | 位流、XSA、固件、7 份报告、门禁件 `r75_gates.txt`、构建 console 与两份台架凭据。这一套同时是 `gates.sh` 里 CDC 那一判的**采纳版对照物**（默认取 `build/evidence_r75/cdc.rpt`），删它等于让那条判据直接红 |
| **更早的三套冻结** | `build/frozen_r13/`、`build/frozen_r19_arb/`、`build/frozen_r32_sdfix/`、`build/frozen_r62_geom/` | 各自那次构建的报告与 manifest；`bash build/gates.sh build/frozen_r19_arb` 是"读一组成套冻结件"那一形的活样本 |
| **逐轮 console 与回读** | `build/evidence/` | 上板回读、JTAG 三步链的现场、各把尺子的原始件；`board_verify.sh` 与 `build/tcl/ps_jtag_boot.tcl` 每次都往这里落 |

`build/reports/index.md` 是这几处的索引页。两条读数口径要说清：slack 绝对值在相邻两版之间会摆零点几 ns
（放置运气），判断有没有变好要同口径复跑，不看单个 WNS；`utilization.rpt` 里 `RAMB36/FIFO*` 的单元数与
`Block RAM Tile` 的瓦片数不是同一个数，引用要分清。

## 四、其它留档

- `build/parsed/` —— 上面那几份 `.rpt` 的机读 JSON 版（`build/p15b_parse_reports.py` 产出）。
- `build/sim/` —— 台架单次跑法与名字表（`build/sim/run_one.sh` 是入口，`build/sim/names.md` 是名字对照）。
- `build/roster/`、`build/micro_rd/` —— 名册差分与读口探针的中间件。
- `build/runs/` —— 两份台账：跑过哪几步、为什么这么定。它们是**过程记录**，不是操作手册；
  里面点名的逐轮件按本轮口径清掉了不少，读的时候以第三节那几处现存报告为准。
- `build/coverage.md` —— 约束覆盖面核对（哪些 `.xdc` 真进了实现、哪些时钟有 uncertainty 声明）。
- `build/provenance.md` —— 当前这一版产物是哪一次构建、各件的时刻与来源。
- `build/tcl/README.md` —— `build/tcl/` 的分工说明。

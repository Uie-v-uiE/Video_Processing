# 时序一轮收敛到极限（全局法）：本目录的工件与口径

工件来源：用户 2026-10-03 夜给的提示词，题名"提示词：时序一轮收敛到极限（全局法，禁止拆东墙补西墙）"。
本目录就是那份提示词要求的交付物集合。**路径映射**：提示词里点名的是 docs 那一层的写法，而本仓库随包的
交付文档在 `report/` 下（`docs/→report/` 改名轮两次都退回过，见 ISSUES #145；docs 那一层从未随包），
所以提示词点名的文件**按原名放在本目录**（`report/timing/`）；工程侧的既有全局时序叙述仍在
[`../../report/timing_global.md`](../../report/timing_global.md)，两份互相指。

## §0 身份、任务与"成功"的定义（每项都从工程里核对，没有一项靠猜）

| 提示词要求 | 实值 | 从哪儿读到的 |
|---|---|---|
| 仓库根目录 | 不写死盘上位置 | `git rev-parse --show-toplevel`（这里每条命令都在仓库根跑） |
| 约束文件（全部 xdc + 顺序） | **构建默认加载 2 份**：① `src/constraints/rk_zynq7020.xdc` ② `src/constraints/clock_groups_impl.xdc`（② `used_in_synthesis false` ⇒ 综合网表逐字节不变，任何差异只可能来自实现阶段）。另有两份**写全了但默认不加载**的候选件，各由一个环境变量开关：③ `src/constraints/r116_rgmii_input_window.xdc`（`VP_R116_IO_WINDOW=1`）④ `src/constraints/r119_hdmi_source_window.xdc`（`VP_R119_TMDS_WINDOW=1`），两份同样 `used_in_synthesis false` | `build/tcl/build_system_axigpio.tcl:31`、`:36-38`、`:57-64`、`:75-82` 的 `add_files -fileset constrs_1`（行号按现读的源行） |
| 顶层 / 综合 / 实现工程名 | 顶层 `system_top`；runs `synth_1`、`impl_1`；BD 工程 `vivado_system/zynq_video_sys` | `build/tcl/build_system_axigpio.tcl:243`、`:277` 的 `launch_runs`；DCP 路径 `vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp` |
| 器件 part 字符串 | `xc7z020clg484-2`（速度等级 `-2` PRODUCTION） | `build/tcl/build_system_axigpio.tcl:5` 的 `set part`，并用 `仓库留档 r115_base（归档件，不随包）/timing_summary.txt` 头部的 `Speed File : -2 PRODUCTION` 交叉核对（不是照抄别处） |
| 时钟花名册 | 8 个时钟对象，4 个有 intra 路径：`eth_rxc` 8 ns（PHY 恢复钟，`create_clock` 于 rk_zynq7020.xdc:36）、`clk_fpga_0` 10 ns（PS7 `FCLKCLK[0]`，由 BD 配置推导，**不是手工写进 xdc 的周期**）、`sys_clk` 20 ns（rk_zynq7020.xdc:6）、`clkout0_1` 20 ns（`u_pl/u_clk/u_mmcm/CLKOUT0` 像素 50 MHz）；另外 4 个 `clkfbout`/`clkfbout_1`/`clkout1_1`(4 ns)/`clkout2`(5 ns) 在 Intra Clock Table 里**只有一行名字**（没有 intra 路径） | 8 行 `CLKROW`（含 `SOURCE_PINS` 原文）落在 [`roster_baseline.tsv`](roster_baseline.tsv) 与 [`baseline_index.md`](baseline_index.md) 里；那份原始打印 `仓库留档 r115_baseline_fix_console.txt（归档件，不随包）` 已随 `build/` 精简移除 |
| 目标（用户批准的上限频率） | **未批准任何提速目标**——批准的口径是"把债收口、且没有任何域变差"，不是"把频率拉高"。所以目标写成：**所有域 rel_margin ≥ 基线**，而不是"WNS ≥ 某个 ns" | 用户 2026-10-03 的原话只有"今晚开始做吧"；提示词 §0 要求"未填的不许靠猜测补全"，所以这一格留空并写明为什么留空 |
| 不可触碰的文件（黑名单） | `src/constraints/rk_zynq7020.xdc`、`src/constraints/clock_groups_impl.xdc`（**不放宽**，见 H1）、板载 QSPI/SPI flash 与 EEPROM（老规矩：不写、不碰）、`src/ps/**`：本机 `arm-none-eabi-gcc` 在、ELF 也确实重建得出来（件 `board/output/1005_ps_app_rebuild.txt`），但重建那颗与在板那颗 md5 不同 ⇒ 只改源码不许用板级口吻汇报，要重刷 + `board_verify` 复验才算板上行为 | 用户长期规矩 + 提示词 H1/H6 |
| 真实剩余墙钟时间 | 工作窗口 = 用户给的"今晚"到次日早晨醒来前，**没有更细的截止点**（不许靠猜补全）⇒ 硬闸门是**每个阶梯前重新 `date`**（§6），每个阶梯的实际耗时以工件自己打印的时刻为准 | 每次 `date` 的输出都抄进这份 README 末节的"时间线" |

**改动权限**：约束（只许加严或补覆盖）+ 实现策略 + 小型 RTL 改动（逐处挂单元 bench 与设计指纹）。

**成功只有一种形状**：`所有域的 rel_margin ≥ 基线`，或剩余红路径能被 §7 的三条极限判据证明是器件边界；
同时约束集比基线**更紧或持平**、没有任何域变差、`check_timing` 的两类"没覆盖"不增加。
**这类轮次一律判红的伪装形状**：WNS 变好但来自放宽约束/删假路径/把负裕量从 A 域搬到 B 域。

## 工件清单（提示词点名的，逐个存在性核对）

| 提示词 | 文件 | 状态（按件核对） |
|---|---|---|
| §2 A1 逐条适用性 | [`a1_sources.md`](a1_sources.md) | ✅ 写完（含"这份我到底拿到了什么"，不只列文档号；并指出提示词里 UG901 的名字与文档号不匹配） |
| §2 A2 命令选项形状 | `仓库留档 r115_help_shapes_console.txt（归档件，不随包）`（676 行 `OPT|`） | ✅ 已跑；两处基线探针的失败正是它抓出来的 |
| §2 A3 债务清单 | [`debt_ledger.md`](debt_ledger.md) | ✅ 写完，逐条挂 xdc 行号 |
| §3 B1 基线报告索引 | [`baseline_index.md`](baseline_index.md) | ✅ 20 份报告 + 指纹 |
| §3 B2/B3 冻结基线花名册 | [`roster_baseline.tsv`](roster_baseline.tsv) | ✅ 8 行，生成器 = `仓库留档 r115_roster_build.py（剪枝件，不随包）`（`--self` 5 条对照全过） |
| §3 B4 噪声底 | `仓库留档 r115_noise_cal_console.txt（归档件，不随包）` + `/tmp/kx/r115_noise/noise.txt` | ✅ **noise_ns = 0.000**（两空白滚的头条四数与最差路径身份逐位相同才算 0） |
| §4 C 切割清单 | [`cut_ledger.tsv`](cut_ledger.tsv) | ✅ 每条一个附录 2 的根因标签 |
| §4 D 打分与排序 | [`score.md`](score.md) | ✅ |
| §4 E1 逐轮花名册 | [`roster_round115.tsv`](roster_round115.tsv) · [`roster_round116.tsv`](roster_round116.tsv) · 比值口径的两张在 `build/roster/`（`roster_r118.tsv` 与 **现版 `roster_r132.tsv`**，相减件 `board/output/roster_tsv_diff.txt`） | ✅ r115：8 行、32 次比较、**4 红**。**r116**：8 行、生成器打印 `comparisons_made=24`（另 8 对双侧 NA）、`reds=2`、末列 `verdict` 只有 `eth_rxc` 一行 RED ⇒ **这是第二把尺子给的同一条结论**（与 `board/output/r116_roster_diff.txt` 的 `judged=6/pairs=8/result=RED` 独立相符）。两端各有指纹：A=`roster_baseline.tsv`（B3 冻结基线）、B=`仓库留档 r116_roster_e1.tsv（归档件，不随包）`（生成命令与来源报告写在文件头两行）。**r132**：`ROSTER-BUILT rows=8 io_unconstrained_ports=11`，对 r118 相减 `comparisons_made=32 both_NA=8 red=7 verdict=RED`（那 7 格是 r118→r132 之间几笔 RTL 改动的代价账，本轮不动它；探针百分数口径的那张表还欠着，见 `round_r132.md` 第六节第 2 条） |
| §7 L1/L2/L3 逐域极限判定（G4） | [`limit_audit_r116.md`](limit_audit_r116.md) | ✅ 写完：四域逐域判"顶住的是逻辑还是布线"；`clk_fpga_0` 判**未到极限**，D0 那一次只读量（件 `仓库留档 r117_d0（归档件，不随包）/`）把根因从"离得远"改成正读数 **`FANOUT`**（239 引脚网吃 5.690 ns）⇒ `仓库留档（本轮工作件，不随包）` 那一支自拒（`PB_EXISTING_BOX=` 空）且方向已被推翻；快车道赢的那一支（`build/tcl/repl117_roll3.tcl`，见下面 r117 索引）在正式构建里判 **DECLINED**（件 `仓库留档 r117_verdict_declined.txt（剪枝件，不随包）`） |
| r132 结果页（**先看这份**） | [`round_r132.md`](round_r132.md) | ✅ 现版补账：基线逐域名册有探针件、臂 B（RGMII 输入窗）在现版滚出 setup −0.846 / hold −0.870 并解释清"多的 5 个端点是覆盖变宽"、臂 A 的红按 #335 收回（量纲错，不是设计债）、臂 C 判 NOT RUN（owner_eth 扇出实测 5）、臂 D 用同量纲的问法给互对 0.065 / 对内 0.001 ns、`check_timing -verbose` 与名册表 `build/roster/roster_r132.tsv` 都换成现版件。欠的三条写在同一页第六节 |
| r116 结果页（那一轮的读数） | [`round_r116.md`](round_r116.md) | ✅ V1..V5 全部填成**实测读数**、一格没空；V6 是板侧实测＋回刷 r114 的 A/B 对照；尺子修补与 r117 链的落点在本页第六节，所以没有一格是"提前涂绿"的 |
| §4 E3 松动台账 | [`loosen_ledger.tsv`](loosen_ledger.tsv) | ✅ **空**（数据行 0；没有批准人在场时一条都不松，见 H1/G3） |
| §4 E2 + G1..G12 判定表 | [`gates_g1_g12.md`](gates_g1_g12.md) | ✅ 逐条填完：**r115 那一版判 RED**（G1 四格红 ⇒ C1 那把刀拒绝；G4 明写"未测"不当绿） |
| 附录 3 交付前 12 问 | [`twelve_questions.md`](twelve_questions.md) | ✅ 12 条都有答案，无留空（前后两段分别是 r115 滚与 r116 构建的读数） |
| §4 C2 的测量（SKEW-UNC / #265） | [`uncertainty_hold_ab.md`](uncertainty_hold_ab.md) | ✅ **量完了**：只有 eth_rxc 带 `Clock Uncertainty: 0.800`，其余三域报告里**没有那一行**；统一加严后 WHS −0.747 / 25,742 失败端点 ⇒ 名册 hold 列是两把尺子。**未采纳**（读数会变难看，需要用户点头） |

## 与既有工件的关系（不重复造轮子）

* 逐时钟名册的**差分**由 `build/timing_roster_diff.sh`（D1..D6，`--self` 11/11）做；本目录的
  `仓库留档 r115_roster_build.py（剪枝件，不随包）` 只做"报告 → 花名册"与"两份花名册 → 差值/判定"，两件各测各的：
  前者要求两侧同一把生成器（混口径会 REFUSE，见 ISSUES #291/#293），后者自己带 5 条能变红的对照。
* 已经量出来的三刀结论（复制驱动被名册差分否决、RGMII 窗把 hold 判死、`set_max_delay`
  叠异步组零新行）都记在 [`../../report/log/issues.md`](../../report/log/issues.md) #275–#295，
  这里直接引用，不重跑。

## 滚与读数的时刻（每次进一个阶梯前 `date`，§6 的硬闸门）

* 22:18 开工（`date` 实测）。基线树指纹 `top=56c269602e18 rtl=3969247aaf7f`（`build/rtl_fingerprint.sh`），
  与 r114 出货位流 `7142a1fbf082` 同源，因此**未修改的树 = 最便宜的对照**。
* 22:19–22:21 B1 全量报告探针（两处选项形状错误当场暴露，见 `baseline_index.md` 的"这一支踩过的两次"）
* 22:26 A2 `help` 形状批量探针（676 行 `OPT|`）
* 22:31 B4 噪声底：空白滚 n1 起跑 → 22:38 完成（6.4 min）；n2 起跑 22:38
* 22:39 `report/timing/` 的工件开始落盘（这份 README + a1 + debt_ledger）
* 22:43 B4 完成：`noise_ns=0.000`（N1–N4 全绿）
* 22:45 基线名册重生成（14 列 = B2 的 13 列 + 附加列 `intra_endpoint_total`），`--self` 5 条对照 GREEN
* 22:54 C1 那一刀的 A/B 起跑（第一版驱动 0 秒全红 = 目录没建，ISSUES #298；重跑 22:54→23:07）
* 23:07 两滚完成：**A 滚名册与基线逐格相同**（32 次比较全绿）；B 滚 `REPLICA_CELLS` 0→310（机制动了）
* 23:12 判定：F1–F4/F6 绿、**F5 红 4 格**，因此C1 **拒绝**；名册、判定表、12 问全部落盘
* 23:1x 提交并推送（不采纳任何切割，因此带复制驱动那颗位流没进发布物；板上当时仍是 r114 `7142a1fbf082`）

## r115 那一滚的结论一句话

**收敛 0 ns，未证明到极限**：那一版没有采纳任何切割（G1 红四格、H5 点名的 11 个未覆盖端口原样留着），
换来的是①可复用的名册尺子（三件各自带能红的对照）②噪声底 0.000 的正式标定
③一把"机制确实动了但代价落在最紧的域上"的负结果 ④后续顺序由这组读数定死：
**先 C3（`CLKTOPO`，把 eth_rxc 的捕获钟相位提前），再 C4（补 I/O 窗口）**，
因为 C4 一绑上去 hold 就是红的（现版 r132 滚了一次给 −0.870，件 `board/output/rgmiiwindow_roster.txt`；
r114 那轮念的 −2.885 是 ±0.500 那一版窗的数，窗本身取自规格表错行，#304/#309），顺序反过来就是"用缺约束换绿灯"。


## r116/r117 工件索引（上面那份结论讲的是 r115 那一滚，保留在此作历史）

**工件在哪（一次找齐，不用翻聊天记录）**：下表点名的 `仓库留档（本轮工作件，不随包）*.sh`、`build/tcl/*117*.tcl` 与若干滚的 console 是**过程件**，`build/` 精简那一次（提交 `02bd5c4`）之后盘上只剩被跟踪的几份；名字留着是为了对回 `report/log/issues.md` 的编号——**盘上找不到那份文件不等于那个读数没做过**，两件事分开说。

| 东西 | 路径 | 是什么 |
|---|---|---|
| r116 判读件 | 在盘上：`仓库留档 r116（归档件，不随包）/r116_io_HOLD.rpt`、`仓库留档 r116（归档件，不随包）/r116_io_SETUP.rpt`、`board/output/r116_after.txt`、`board/output/after_roster.txt`、`board/output/r116_roster_diff.txt` | V1/V2/V3/V4 的原始读数；名册与差分。警告 `r116_check_timing.txt` 已不在盘上，同一组数（WNS −0.846／失败 setup 端点 5／WHS −0.870／失败 hold 端点 5 + 逐域分组）抄在 `仓库留档 gates.txt（剪枝件，不随包）` 的身份行与"分组最差"表里 |
| r116 那颗位流与指纹 | 位流 md5 `bb2fb707aebc`（身份行 = `仓库留档 gates.txt（剪枝件，不随包）:3`）+ `board/output/tree_fp.txt`（`fpver=norm1 files=80 top=56c269602e18 rtl=07570b1ac1b4`，构建起飞前打的） | 提示词 §5 要的"位流 + 指纹一起提交"。警告 盘上现在的 `board/project/system.bit` 是 r118 那颗 `cd04907e1369`，与 r116 那颗不是同一颗；`仓库留档 r116_bit（归档件，不随包）/` 已随 build/ 精简移除 |
| r116 板侧件 | 读数抄在 [`round_r116.md`](round_r116.md) 的 V6 与"V6 的两条未定"两处；原始件 `仓库留档 r116_board（归档件，不随包）/`（`health_*.json`、`cycle_*.log`、`sender_live4.log`）与 `仓库留档（本轮工作件，不随包）` 已随 build/ 精简移除 | 三步刷板 → `board_verify --geom --battery` PASS 判红步骤 0 → 带真实流量的两次读数 → 回刷 r114 的 A/B 对照 |
| 交付改口脚本 | `仓库留档（本轮工作件，不随包）`（按行首标签定位、整行重写、命中数≠1 就 REFUSE；同样已不在盘上） | 首页两份 + metrics.csv 三行；改完 `metric_recheck` 红 0，那一次跑的输出抄在 `仓库留档 gates.txt（剪枝件，不随包）:54`（`判=115 首页=61`） |
| 极限审计（逐域） | [`limit_audit_r116.md`](limit_audit_r116.md) + 交付侧 [`../../report/timing_global.md`](../../report/timing_global.md) 第 6/7 节 | 四域各自"顶住的是逻辑还是布线、还剩什么杠杆、为什么那一晚不动" |
| C9 的 D0 量 | `仓库留档 r117_d0（归档件，不随包）/`（`worst_clk_fpga_0_setup.rpt` 逐段分解、`nethelp_console.txt` 两路取名）+ `build/tcl/{d0_117_distance_probe,n117_net_and_help}.tcl` 与 `congestion.rpt`（两支 tcl 与那份 congestion 已移除） | 把"离得远"改成 `FANOUT` 的那一次；也是"驱动侧取名与报告段名不一致"的账（#320） |
| C9 的单变量滚 | `仓库留档 r117_repl3（归档件，不随包）/b_console.txt`（`R3_AGREE/R3_BEFORE/R3_AFTER/R3_REPLICA_CELLS` + 四域 `ROW`）与对照 `仓库留档 r117_fb_pblock（归档件，不随包）/a/roll_console.txt`（对照那个目录现在盘上是空的） | 快车道赢的那一次；机制闭合等式：网引脚 239→1、10 颗 replica、端点 15721→15731。同一把刀在正式构建里判 **DECLINED**：本域 1.850→2.104 的代价是其余三域各变小（`clkout0_1` 3.630→3.353、`eth_rxc` 0.739→0.615、`sys_clk` 14.876→14.815；件 `仓库留档 r117_verdict_declined.txt（剪枝件，不随包）`、bit `beda9298331d`） |
| 两次失败的尝试 | 仓库留档 `repl117_roll.tcl`（不随包）、`repl117_roll2.tcl` 与各自 console | #319（`-skeleton_clustering` 不是 2025.2.1 的选项）、#320（目标网选成 7 引脚那根），所以留档不删；H7 的三次上限到这里用完 |
| r117 采纳入口 | `build/tcl/r117_post_place_hook.tcl` + 构建脚本的 `IMPL_POST_PLACE_HOOK`（默认不设＝不挂）+ `仓库留档 r117（归档件，不随包）/prop_probe.txt`（属性名只读验证；这份已不在盘上） | 钩子取名不一致就 `error` 停下，不许悄悄换目标 |
| r117 自动链 | `仓库留档（本轮工作件，不随包）`（等 r116 门禁 → 指纹 → 构建 → 名册/差分/快车道 → 判读 → 门禁两跑）+ `仓库留档（本轮工作件，不随包）`（等 r117 门禁 → 存位流 → 刷板 → 带流读数 → board_verify → `board_now.txt`）；两支都已随 build/ 精简移除 | 判据四条写在链脚本头部；判负的回刷命令写在 `board_now.txt` 里（现存的同类件是 `仓库留档 r118_board（归档件，不随包）/board_now.txt`） |
| 输出侧债务：从"没有来源数"到"有来源" | `build/tmds_source_scan.py` + `仓库留档 r117（归档件，不随包）/dvi_guide_scan.txt`（查过的否定：UG471 整本 + DVI Test & Measurement Guide 26 页都没有**接收端**窗口数）；数后来从 HDMI 1.4 §4.2.4 Table 4-24 取到——它是**互对偏斜上限** 0.20 Tcharacter（50 MHz 档 = 4 ns，是一个散布而不是捕获窗），SDC 里因此写成半窗 ±4.000 且只挂 `tmds_data_*`，逐条判定与"哪些只能作第三方代理"写在 [`../io/hdmi_cts_source_window.md`](../io/hdmi_cts_source_window.md) | 候选件 `src/constraints/r119_hdmi_source_window.xdc` 默认不加载；参考钟身份（`clkout1_1`）与 pin 对 pin 的实测 0.065/0.001 ns vs 4.000/0.300 限值由只读尺子 `仓库留档 r119_window_check.mjs（剪枝件，不随包）` 判（件 `board/output/window_check.txt`，W1..W10 全 PASS）；带窗跑名册的那一次构建 2026-10-20 在 r132 上滚过了（`clkout1_1` 从 NOWRITE 变成 setup −5.408 / hold −1.923，件 `board/output/tmdswindow_roster.txt`），结论仍是**不采纳**：那条红是量纲错（skew 被当采样窗，#335），复核这笔债的正确问法是只读探针 + `仓库留档 r132_pin_skew_judge.mjs（剪枝件，不随包）`，不是再滚构建 |

**r116 那一版的结论一句话（覆盖上面那句 r115 的）**：两刀都落进过构建树，然后被自己的门禁改了采纳口径——
`eth_rxc` 那 5 格是**当前结构下的无解**（不相交区间 + 角间差 3.411 vs 0.467 ns），其余三域 setup 变好或持平、
四域 hold 一格不动、资源逐字中性、告警类不增、松台账 0 条；板级在真实流量下与 r114 **不可区分**（A/B 对照）。
按字面仍红两条：G1（那 5 格第一次被检查就红）与 H5（输出侧 6 端口当时没有窗口数）。采纳状态以现在读得到的 `src/` 为准：眼心 `IDELAY_VALUE = 31` 留在后续构建（`src/rtl/top/system_top.v:172`），输入窗被发布门的 4 条硬项判红，因此退回**候选件**、默认不加载（`VP_R116_IO_WINDOW=1` 复现；撤销的是"带进发布物"这个动作，不是约束的正确性）。
**C9（复制那根 239 引脚广播网）**：快车道单变量滚量到 +0.033/+0.187/+0.298 且别处不动，同一把刀在正式构建里判
**DECLINED**（严格判据 A3：其余三域各变小；件 `仓库留档 r117_verdict_declined.txt（剪枝件，不随包）`），因此第四域 `clk_fpga_0` 仍是"绿但未到极限"，欠的是那支 40 秒只读探针（BUFIO 慢/快角 DCD，见 `report/timing_global.md` 第 7 节）。


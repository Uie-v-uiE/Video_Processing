# docs/timing/ —— 时序一轮收敛到极限（全局法）：本轮工件与口径

工件来源：用户 2026-10-03 夜给的提示词（"提示词：时序一轮收敛到极限（全局法，禁止拆东墙补西墙）"）。
本目录就是那份提示词要求的交付物集合。**路径映射**：提示词写 `docs/timing/…`，本仓库的交付文档在
`report/` 下（`docs/→report/` 改名轮两次都退回过，见 ISSUES #145），所以提示词点名的文件**按原名放在
`docs/timing/` 下**，同时在本目录留这条映射说明；工程侧的既有全局时序叙述仍在
[`../../report/TIMING_GLOBAL.md`](../../report/TIMING_GLOBAL.md)，两份互相指。

## §0 身份、任务与"成功"的定义（每项都从工程里核对，没有一项靠猜）

| 提示词要求 | 实值 | 我是从哪儿读到的 |
|---|---|---|
| 仓库根目录 | `D:/Xilinx/Prj/pro/Video_Processing` | `git rev-parse --show-toplevel`（本轮所有命令的工作目录） |
| 约束文件（全部 xdc + 顺序） | ① `src/constraints/rk_zynq7020.xdc` ② `src/constraints/clock_groups_impl.xdc`（后者 `used_in_synthesis false`） | `build/tcl/build_system_axigpio.tcl:19` 与 `:24` 的 `add_files -fileset constrs_1` |
| 顶层 / 综合 / 实现工程名 | 顶层 `system_top`；runs `synth_1`、`impl_1`；BD 工程 `vivado_system/zynq_video_sys` | `build/tcl/build_system_axigpio.tcl:243`、`:277` 的 `launch_runs`；DCP 路径 `vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp` |
| 器件 part 字符串 | `xc7z020clg484-2`（速度等级 `-2` PRODUCTION） | `build/tcl/build_system_axigpio.tcl:5` 的 `set part`，并用 `build/evidence/r115_base/timing_summary.txt` 头部的 `Speed File : -2 PRODUCTION` 交叉核对（不是照抄别处） |
| 本轮时钟花名册 | 8 个时钟对象，4 个有 intra 路径：`eth_rxc` 8 ns（PHY 恢复钟，`create_clock` 于 rk_zynq7020.xdc:36）、`clk_fpga_0` 10 ns（PS7 `FCLKCLK[0]`，由 BD 配置推导，**不是我在 xdc 里写周期**）、`sys_clk` 20 ns（rk_zynq7020.xdc:6）、`clkout0_1` 20 ns（`u_pl/u_clk/u_mmcm/CLKOUT0` 像素 50 MHz）；另外 4 个 `clkfbout`/`clkfbout_1`/`clkout1_1`(4 ns)/`clkout2`(5 ns) 在 Intra Clock Table 里**只有一行名字**（没有 intra 路径） | `build/evidence/r115_baseline_fix_console.txt` 的 8 行 `CLKROW`（含 `SOURCE_PINS` 原文）+ `docs/timing/roster_baseline.tsv` |
| 本轮目标（用户批准的上限频率） | **未批准任何提速目标**——本轮的批准范围是"把债收口、且没有任何域变差"，不是"把频率拉高"。所以目标写成：**所有域 rel_margin ≥ 基线**，而不是"WNS ≥ 某个 ns" | 用户 2026-10-03 的话只有"今晚开始做吧"；提示词 §0 要求"未填的不许靠猜测补全" ⇒ 这一格留空并说明为什么留空 |
| 不可触碰的文件（黑名单） | `src/constraints/rk_zynq7020.xdc`、`src/constraints/clock_groups_impl.xdc`（**不放宽**，见 H1）、板载 QSPI/SPI flash 与 EEPROM（老规矩：不写、不碰）、`src/ps/**`（本机无 `arm-none-eabi-gcc` ⇒ 只能 source-only，不许用板级口吻汇报） | 用户长期规矩 + 提示词 H1/H6 |
| 本轮真实剩余墙钟时间 | 开工 `date` = **2026-10-03 22:18**；写这行时 **22:39**。用户睡前只说"今晚"，没给截止点 ⇒ 按"到次日早晨用户醒来前"计，且**每个阶梯前重新 `date`**（§6 的硬闸门） | 每次 `date` 的输出都抄进本文件末节的"时间线" |

**改动权限**：约束（只许加严或补覆盖）+ 实现策略 + 小型 RTL 改动（逐处挂单元 bench 与设计指纹）。

**成功只有一种形状**：`所有域的 rel_margin ≥ 基线`，或剩余红路径能被 §7 的三条极限判据证明是器件边界；
同时约束集比基线**更紧或持平**、没有任何域变差、`check_timing` 的两类"没覆盖"不增加。
**这类轮次一律判红的伪装形状**：WNS 变好但来自放宽约束/删假路径/把负裕量从 A 域搬到 B 域。

## 工件清单（提示词点名的，逐个存在性核对）

| 提示词 | 文件 | 状态（本轮） |
|---|---|---|
| §2 A1 逐条适用性 | [`a1_sources.md`](a1_sources.md) | ✅ 写完（含"这份我到底拿到了什么"，不只列文档号；并指出提示词里 UG901 的名字与文档号不匹配） |
| §2 A2 命令选项形状 | `build/evidence/r115_help_shapes_console.txt`（676 行 `OPT|`） | ✅ 已跑；两处基线探针的失败正是它抓出来的 |
| §2 A3 债务清单 | [`debt_ledger.md`](debt_ledger.md) | ✅ 写完，逐条挂 xdc 行号 |
| §3 B1 基线报告索引 | [`baseline_INDEX.md`](baseline_INDEX.md) | ✅ 20 份报告 + 指纹 |
| §3 B2/B3 冻结基线花名册 | [`roster_baseline.tsv`](roster_baseline.tsv) | ✅ 8 行，生成器 = `build/r115_roster_build.py`（`--self` 5 条对照全过） |
| §3 B4 噪声底 | `build/evidence/r115_noise_cal_console.txt` + `/tmp/kx/r115_noise/noise.txt` | ✅ **noise_ns = 0.000**（22:43 量出：两空白滚头条四数与最差路径身份逐位相同） |
| §4 C 切割清单 | [`cut_ledger.tsv`](cut_ledger.tsv) | ✅ 每条一个附录 2 的根因标签 |
| §4 D 打分与排序 | [`score.md`](score.md) | ✅ |
| §4 E1 本轮花名册 | [`roster_round115.tsv`](roster_round115.tsv) | ✅ 8 行、32 次比较（24 数值 + 8 双侧 NA）、**4 红**（生成器 `build/r115_round_roster.py`，`--self` 3 条对照） |
| §7 L1/L2/L3 逐域极限判定（G4） | [`limit_audit_r116.md`](limit_audit_r116.md) | ✅ r116 写完：四域逐域判"顶住的是逻辑还是布线"；`clk_fpga_0` 判**未到极限**（1 级逻辑 / 93.6 % 布线），预验脚本 `build/r117_fb_pblock_fastlane.sh` |
| r116 结果页（早上先看这份） | [`ROUND_r116.md`](ROUND_r116.md) | ✅ 结构就位；V1..V6 逐格标 `【构建后填】`，没有一格被提前涂绿 |
| §4 E3 松动台账 | [`loosen_ledger.tsv`](loosen_ledger.tsv) | ✅ **空**（夜里没有批准人可问 ⇒ 一条都不松，见 H1/G3） |
| §4 E2 + G1..G12 判定表 | [`gates_G1_G12.md`](gates_G1_G12.md) | ✅ 逐条填完：**本轮 RED**（G1 四格红 ⇒ C1 那把刀拒绝；G4 明写"未测"不当绿） |
| 附录 3 交付前 12 问 | [`twelve_questions.md`](twelve_questions.md) | ✅ 12 条都有答案，无留空 |
| §4 C2 的测量（SKEW-UNC / #265） | [`uncertainty_hold_ab.md`](uncertainty_hold_ab.md) | ✅ **量完了**：只有 eth_rxc 带 `Clock Uncertainty: 0.800`，其余三域报告里**没有那一行**；统一加严后 WHS −0.747 / 25,742 失败端点 ⇒ 名册 hold 列是两把尺子。**未采纳**（读数会变难看，需要用户点头） |

## 与既有工件的关系（不重复造轮子）

* 逐时钟名册的**差分**由 `build/timing_roster_diff.sh`（D1..D6，`--self` 11/11）做；本目录的
  `build/r115_roster_build.py` 只做"报告 → 花名册"与"两份花名册 → 差值/判定"，两件各测各的：
  前者要求两侧同一把生成器（混口径会 REFUSE，见 ISSUES #291/#293），后者自己带 5 条能变红的对照。
* 今天的实测已经给出的三刀结论（复制驱动被名册差分否决、RGMII 窗把 hold 判死、`set_max_delay`
  叠异步组零新行）都记在 [`../report/log/ISSUES.md`](../report/log/ISSUES.md) #275–#295，
  本轮直接引用，不重跑。

## 时间线（每次进一个阶梯前 `date`，§6 的硬闸门）

* 22:18 开工（`date` 实测）。基线树指纹 `top=56c269602e18 rtl=3969247aaf7f`（`build/rtl_fingerprint.sh`），
  与 r114 出货位流 `7142a1fbf082` 同源 ⇒ **未修改的树 = 最便宜的对照**。
* 22:19–22:21 B1 全量报告探针（两处选项形状错误当场暴露，见 `baseline_INDEX.md` 的"这一支踩过的两次"）
* 22:26 A2 `help` 形状批量探针（676 行 `OPT|`）
* 22:31 B4 噪声底：空白滚 n1 起跑 → 22:38 完成（6.4 min）；n2 起跑 22:38
* 22:39 `docs/timing/` 工件开始落盘（本文件 + a1 + debt_ledger）
* 22:43 B4 完成：`noise_ns=0.000`（N1–N4 全绿）
* 22:45 基线名册重生成（14 列 = B2 的 13 列 + 附加列 `intra_endpoint_total`），`--self` 5 条对照 GREEN
* 22:54 C1 那一刀的 A/B 起跑（第一版驱动 0 秒全红 = 目录没建，ISSUES #298；重跑 22:54→23:07）
* 23:07 两滚完成：**A 滚名册与基线逐格相同**（32 次比较全绿）；B 滚 `REPLICA_CELLS` 0→310（机制动了）
* 23:12 判定：F1–F4/F6 绿、**F5 红 4 格** ⇒ C1 **拒绝**；名册、判定表、12 问全部落盘
* 23:1x 提交并推送（本轮不采纳任何东西，板上仍是 r114 `7142a1fbf082`）

## 本轮的结论一句话

**收敛 0 ns，未证明到极限**：本轮没有采纳任何切割（G1 红四格、H5 的 11 个端口债还在），
换来的是①可复用的名册尺子（三件各自带能红的对照）②噪声底 0.000 的正式标定
③一把"机制确实动了但代价落在最紧的域上"的负结果 ④下一轮的顺序已经由数据定死：
**先 C3（`CLKTOPO`，把 eth_rxc 的捕获钟相位提前），再 C4（补 I/O 窗口）**，
因为 C4 一绑上去 hold 就是 −2.885 ns，顺序反过来就是"用缺约束换绿灯"。

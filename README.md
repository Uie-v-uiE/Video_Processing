[English](README.en.md)

# Zynq 实时视频图像处理与逐像素对照显示

> 这一页是**操作台**，不是宣传页。九节固定：①是什么 ②版本权威声明 ③目录与对照表
> ④前置条件 ⑤环境自检 ⑥从零复现（A/B/C 三条路径）⑦结果比对 ⑧卡点速查 ⑨许可。
> 陌生队伍只靠本文件应能从第 5 节走到第 7 节。逐条命令的实测状态记在
> [`docs/repro-check.md`](docs/repro-check.md)（本文件与它成对交付；`docs/` 是仓库根的运行台账目录、**不随包**——导出器 `build/make_submission.sh:107-114` 整目录剪掉它，剪掉的件逐条列在包内 `_pruned.txt`）。

## 1. 一句话是什么 + 关键结果

一块 Zynq-7020 上跑通一整条实时视频通路：千兆网 / SD 卡 / PL 自绘图卡任一路送片源，PL 侧做缩放、
旋转与九级效果链，以 HDMI 1024×600 上屏；**屏幕任一竖线以左是未处理画面、以右是同一坐标系下处理后的
画面**——这个"同帧逐像素对照"既是显示方式，也是一台测量仪器（边缘条带、一行错位、越界格子肉眼可见，
也能被同一套几何关系算成数字）。现有做法要么把对照留给示波器与探针（要改设计），要么只报静态指标
（看不见逐像素错），本作品让"逐像素对不对"直接进台架判据与门禁。

| 关键结果 | 读数 | 出处（可当场复核） |
|---|---|---|
| 全设计 setup WNS | WNS **0.739 ns**、WHS **0.052 ns**，失败 setup/hold 端点 **0 / 51135**（两个方向都是 0；本版不带 RGMII 收口输入窗 ⇒ 那 5 个 I/O 端点当前未检查，未检查不等于满足） | `build/timing_summary.rpt:151`（本会话打开核对）、`data/metrics.csv` 第 4–6 行 |
| 逐时钟 setup 余量 | 125 MHz 收包域 `eth_rxc` **0.739 ns**（占它 8 ns 周期的 9.24 %，全设计最紧的一格）；100 MHz `clk_fpga_0` **1.850 ns**（占它 10 ns 周期的 18.5 %）；50 MHz 显示域 `clkout0_1` **3.630 ns**（占它 20 ns 周期的 18.15 %）；`sys_clk` **14.876 ns**（占它 20 ns 周期的 74.38 %，最宽的一档） | `build/timing_summary.rpt`（Intra Clock Table + Clock Summary 两段） |
| 保持时间 | 全设计最差那一格在 `eth_rxc`，**0.052 ns**；逐时钟 WHS：`clk_fpga_0` **0.053 ns**、`clkout0_1` **0.059 ns**、`sys_clk` **0.222 ns**、`eth_rxc` **0.052 ns**。⚠ 只有 `eth_rxc` 带着 r79 加严的 0.800 ns hold 不确定度，其余三个域的报告里没有那一行 ⇒ 这四个数只许两两比同域，跨域比"谁更薄"要等不确定度带补齐 | `build/timing_summary.rpt`（Intra Clock Table 的 WHS 列）、`build/hold_paths.rpt`、`build/clock_uncertainty.rpt` |
| BRAM / LUT / FF / DSP | BRAM **95.5 tile（68.21 %）**/ 140、LUT **14154（26.61 %）**、FF **8188（7.70 %）**、DSP **19（8.64 %）**/ 220 | `build/utilization.rpt`、`data/metrics.csv` 第 7–10 行 |
| 功耗 | 动态 **2.213 W**（片上合计 2.391 W）、估算结温 **52.6 °C**，工具置信度 **Low** ⇒ **这是估算，不是实测** | `build/power.rpt`；`data/metrics.csv` 第 20–21 行 |
| 显示 | 1024×600 @ **59.5 Hz**（像素钟 50 MHz，`H_TOTAL=1344`/`V_TOTAL=625`；不是 50 Hz） | `data/metrics.csv` 第 2–3 行 |
| SD 本地播放 | **29.8 – 30.0 fps**（100 帧滑窗，板上串口读回） | `data/metrics.csv` 第 11 行 |
| 整屏逐像素判据 | 本次实测 `^PASS` **161** 行 + `^FAIL` **1** 行；唯一那行 FAIL 是**声明过**的 `C5c` | `build/tb_v98_report.txt`；`bash sim/run_one.sh --verdict …` 本会话输出（见 §6 路径 A） |
| 板级机器判据 | `RESULT PASS geom_check（ok=10 fail=0）`、`RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, …)`、末行 `RESULT board_verify PASS（判红的步骤：0）` | `build/evidence/r118_board/board_verify_console.txt`（本会话读到末 5 行） |
| 门禁 | 基准件那一行原文：`GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`（基准件读作 23 绿 / 1 红，红的是声明过的 `C5c`）⇒ 本会话 12:2x 亲跑 `bash build/gates.sh` **两跑逐字节一致、末行就是那一句**，但那一跑判红的是**两项**：`C5c`（顶层台架 `tb_v98` FAIL 行=1，声明过的红）+ `文档时效 doc_cur`（成因与射程见 §2 红项 R4，不是本文件的数字行） | `build/r118_gates_final.txt` 末行（本会话读到）、本会话 `bash build/gates.sh` 两跑输出（逐字节比对记在 `docs/repro-check.md` §2.2 A9，`docs/` 不随包） |
| 板上那一版 | 板上现在跑的是 r118：2026-10-04 04:49:50 由三步 JTAG 链刷入，位流 `md5(12)=cd04907e1369`，`build/r118_gates.txt` 是戳着这块 bit 的那一份门禁件，它读作 **门禁 24 项 23 绿 / 1 红**（唯一红项 = 声明过的 `C5c` 顶层台架那一项）。⚠ "板上现在跑的是 rNN"与"门禁 N 项 X 绿 / Y 红"这两半句都是**尺子射程**：`src/host/doc_currency_check.mjs:255` 的 `NOW_MARK` + `:256` 的 `ADJ_RNN`（D1b 板态身份句）与 `:310` 的 `GATES_CLAIM`（D1c 门禁读数句）按**相邻形状**取数、并对回 `build/r118_gates.txt` 的行尾计数，中英首页各要抓到一句（地板 2）。把它改成散文、删掉，或者**在本行的行名里先出现"板上现在"四个字**（`NOW_MARK` 只取每行第一个命中，后面的那半句就进不了射程）——三种写法都会让门禁第 18 项因"空转地板"判红；本会话实测撞过第三种，记在 §2 红项 R4 与 `docs/repro-check.md` §3 R10（`docs/` 不随包） | `build/evidence/r118_board/BOARD_NOW.txt`、`build/evidence/r118_bit_md5.txt`、`build/r118_gates.txt` |

**两条必须一起念的口径**（不一起念就会读错）：

- 本版**不带 RGMII 收口输入窗**：那 5 个第一次被检查的端点在自己发布门上判红，约束按规矩退回候选件
  `src/constraints/r116_rgmii_input_window.xdc`（设 `VP_R116_IO_WINDOW=1` 复现带窗那一版）。
  所以第 1 行那组数的含义是"片内路径零违例 + 收口 I/O 当前无窗"，**不是"收口已通过"**——
  未检查不等于满足（口径见 `data/metrics.csv` 第 5 行、`build/provenance.md` 第 3 节）。
- **本页不作门禁全绿声明**：某一版过没过、过几项、哪一项红，只以 `bash build/gates.sh` 自己打印的
  最后一行为准（三态原文见 `build/gates.sh:582-586`）。采纳判据与那句"不采纳"是两条不同口径的句子，
  两条都在库里、本文件都点名：`build/r118_gates_final.txt` 末行 vs `build/evidence/r118_board/BOARD_NOW.txt`
  与 `build/provenance.md` 第 6 节。

> **上面这张表的四个行名会被机器读**：`全设计 setup WNS`、`逐时钟 setup 余量`、`保持时间`、
> `BRAM / LUT / FF / DSP`（外加 `功耗` 那一行）是 `src/host/metric_recheck.mjs` 的 `FRONT` 名单里点名的
> 首页行锚点（`src/host/metric_recheck.mjs:274-278`），它按行名取数、按括号形状取 LUT/FF/DSP 三对、
> 按"占它 X ns 周期的 Y %"回算百分数分母。**改这些行名或改成散文 = 门禁第 21 项（D6）直接判红**，
> 不是"文档风格问题"。本任务就撞过一次：先写成"资源"一栏 ⇒ 4 条 `RED … 首页与指标表脱钩`，
> 恢复行名后 `判 117 个数（首页层 63 个）／红 0`、rc=0（全程记在 `docs/repro-check.md` §3 的 R8；`docs/` 不随包）。

逐时钟余量、优化被哪条证据否掉、为什么某些差值不算收益——写在
[`report/TIMING_GLOBAL.md`](report/TIMING_GLOBAL.md)、[`report/OPTIMIZATION_LOG.md`](report/OPTIMIZATION_LOG.md)、
[`report/PERF_REPORT.md`](report/PERF_REPORT.md)，**本页不复制它们**：同一份数字抄两处一定会漂（§2 的红项就是实例）。

## 2. 器件与工具版本 —— 全仓唯一权威声明

**本节是仓库里器件与工具版本的唯一权威位。** 其他文件（`data/metrics.csv`、`build/README.md`、
`report/BUILD.md`、`board/README.md`、`submit/`）应当引用本节而不是各自复述；本节只收**能当场复核**的值。

| 项 | 权威值 | 复核方式 |
|---|---|---|
| 器件 | `xc7z020clg484-2`（Zynq-7020，CLG484，速度等级 2） | `build/tcl/build_system_axigpio.tcl:5` 逐字 `set part xc7z020clg484-2`（本会话读到行号）；器件在设备库：§5 的 S6 |
| Vivado | **v2025.2.1 (64-bit)**，SW Build 6403652 | `build/r118_build_console.txt:1-2` 工具自报横幅（本会话 `head` 读到） |
| Vitis / `xsdb` | **版本串【未核实】**：只核到"`<Vitis>/bin/xsdb.bat` 存在、其安装目录名为 2025.2.1"（本会话 `test -f`） | 本任务不许运行 xsdb，故不写它自报的版本；`build/provenance.md:84` 登记同一条未核实 |
| PS 侧编译器 | `PATH` 上**没有** `arm-none-eabi-gcc`（本会话 `command -v` 空）；Vitis 自带那份在 `<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe`（本会话 `test -f` 存在）；它自报的版本串【未核实】 | `build/provenance.md:85` |
| 赛题版本口径 | 声明 **2025.2.1**（同一主版本线的补丁版），不是指南推荐的 2026.1 | `report/log/CONTEST_CHECKLIST.md:11`、`build/provenance.md:88` |
| 显示时序 | 像素钟 50 MHz，`H_TOTAL=1344` / `V_TOTAL=625` ⇒ 场频 59.5 Hz | `data/metrics.csv` 第 2 行 |
| 操作系统 | Windows 10.0.26300 + Git Bash（`MSYSTEM=MINGW64`，本会话 `uname -a` 实测）；**Linux 分支【未在 Linux 验证】** | §5 |
| 脚本依赖 | Node **v24.21.0**、Python **3.12.10**、`python3` **无别名**、**无 pyserial**（本会话实测） | §5 |
| 版本断言现状 | 全仓**没有**任何脚本对工具版本或器件做等值断言（兜底是 `create_project -part` 自己报错） | `build/README.md` 第 7 节 P2/P3 两行 |

### ⚠ 红项：本仓现有声明并不一致（原样列出，不静默统一）

| # | 冲突点 | 两处原文（逐字） | 处置 |
|---|---|---|---|
| R1 | **Vitis 版本要不要断言 2025.2.1**（本会话实测：断言位 **4** 处、"未核实"位 **1** 处） | `data/metrics.csv:2`「xc7z020clg484-2 / Vivado+Vitis 2025.2.1」、`build/README.md:4`「工具版本：Vivado / Vitis 2025.2.1」、`report/BUILD.md:11`「Vivado / Vitis \| 2025.2.1」、`submit/07-skill-distillation.md:62`「Vivado/Vitis 2025.2.1 的报告字段位置」 vs `build/provenance.md:84`「Vitis / xsdb \| 【未核实】… 要补一次 `xsdb.bat -Version` 的原文，别拿 Vivado 的版本冒充它」 | 本节按**保守那一档**写（Vitis 未核实）。四处复述要不要统一、以哪一处为准 ⇒ `docs/questions-for-team-p12.md` Q-P12-1（`docs/` 不随包） |
| R2 | **整屏判据条数 141 vs 161** | `data/metrics.csv:15`「141 = 该文件里 `^PASS` 行数 140 加 `^FAIL` 行数 1」（provenance 头 `top_md5=2bf2ceeede07`，2026-10-02 01:15）vs 本会话实测 `build/tb_v98_report.txt`（头 `top_md5=56c269602e18`，2026-10-04 01:47）`^PASS`=161、`^FAIL`=1 | 两个数各自对它那份文件都成立，但那一格指的是"该文件"的**现值** ⇒ 红项保留；`metric_recheck` 射程不含该行（它只判点名 timing/utilization/power 的行，本会话实测输出里"其余 18 行不点名"）⇒ Q-P12-2 |
| R3 | **板上/文档里的时序与功耗读数分三档** | `build/timing_summary.rpt:151` 0.739 / 0.052 / 51135（本节权威）vs `board/README.md:62` 「setup WNS **0.720 ns** / hold WHS **0.033 ns** … 失败 setup/hold 端点 **0 / 50890**」、`board/ACCEPTANCE.md:24` 「WNS 0.553 ns、WHS 0.049 ns、失败端点 0 / 50883」；功耗 `build/power.rpt` 2.213 W / 52.6 °C vs `board/README.md:63` 「2.207 W / 52.5 °C」 | 本任务不改 `board/` 的文件（并发轮次在写，P23 授权边界）⇒ 只登记并指回本节：`docs/questions-for-team-p12.md` Q-P12-3（`docs/` 不随包） |
| R4 | **门禁第 18 项 `doc_cur` 现在是红的，且红不在本文件的数字行上**（本会话 12:5x 亲跑 `bash build/gates.sh` **两跑逐字节一致**、退出码 1：判定 24 项、两项红 = `C5c` + `doc_cur`） | 改之前那一跑原文：`文档时效 doc_cur 扫了 130 个文档 红行=0 身份句=1 门禁读数句=1 … 身份句抓到 >= 2、门禁读数句抓到 >= 2 FAIL`。两件事分开：① **身份句与门禁读数句各只剩 1 句（地板 2）**——上一轮把 §1 那两句锚点改成了散文，本会话按 `src/host/doc_currency_check.mjs:255` `NOW_MARK` + `:256` `ADJ_RNN` + `:310` `GATES_CLAIM` 的相邻形状**改回去**（中英各一句），实测恢复 `身份句=2 门禁读数句=2`；坑在于 `NOW_MARK` 只取每行**第一个**命中，所以连"本行行名先写板上现在"都会让后半句不进射程（本会话撞过一次）。② 该子判据还要求 `node src/host/doc_currency_check.mjs` 退出码 0，而它本会话数到 **188 条 `D4b`**：`src/host/doc_currency_check.mjs:140` 的 `OLD_DIR` 把仓库根 `docs/` 一律当"已删掉的旧目录"，可 `docs/` 这一轮真实存在且入库（`git ls-files docs/timing/` 有 19 件），于是并发轮次新写的 6 份 `report/*.md`（`90-open-items` 62、`40-optimization` 55、`comparison-notes` 35、`50-results` 18、`60-failure-analysis` 8、`70-reproduce` 3，全是**未入库的并发件**）里那些指向**盘上存在文件**的 `docs/…` 全被判红；本文件自己那 12 条已按尺子自己认可的写法归零（每行同处写明"`docs/` 不随包"，`build/make_submission.sh:107-114` 确实整目录剪掉它，实测 `grep -c "  README.md:"` = 0、放行条数 15→18）。⚠ 顺带一条计数假象：改后 `红行=1` 并非新红，而是 `build/gates.sh:451` 的 `' D[123][bc]? '` 把 `report/40-optimization.md:209` 那一条 **D4b**（正文里引用了表格行名 `\| D3 \|`）数了进去——同一族的规矩记在脚本注释 41(c) | 本任务不改 `report/`、`src/`、`build/`（禁区）⇒ 红项保留、不删指路、不放宽尺子；要队伍裁的是三件：`docs/` 还算不算"旧目录"（`OLD_DIR` 该不该改成"指向不存在的 `docs/…` 才红"）、那把计数模式要不要收（`D4` 不该混进 `D[123]`）、交付文档统一怎么指 `docs/` ⇒ `docs/questions-for-team-p12.md` Q-P12-11 / Q-P12-12（`docs/` 不随包）。逐条计数与两跑 md5 记在 `docs/repro-check.md` §2.2 A9–A11、§3 R9–R11 |

## 3. 目录结构与赛题 §3.3.5.4 对照表

### 3.1 目录

| 目录 | 内容 |
|---|---|
| `src/rtl/` | PL 侧 RTL，按 `top / video / process / eth / hdmi / clocks / axi / util` 分层 |
| `src/ps/` | PS 侧裸机固件：命令解析、寄存器配置、SD 播放、自诊断读回 |
| `src/host/` | PC 侧上位机与**只读尺子**（Python 推流、寄存器回读、文档一致性与数字对账检查器） |
| `src/constraints/` | 引脚与时序约束（含两档默认不加载的候选件，见 §2 与 §6） |
| `sim/` | 台架与 runner（本会话实测 `sim/tb_*.v` = **81** 支）；`sim/run_one.sh` 是单台架入口，`sim/NAMES.md` 给新旧名对照 |
| `build/` | 可复现的构建脚本（`tcl/`，入口一条命令出位流）+ 本版综合实现报告（仓库里平铺在 `build/`）+ 门禁与上板回读脚本；构建产物（位流/XSA/ELF）也落在这里 ⇒ [`build/README.md`](build/README.md) |
| `board/` | 上板三件事：工程与二进制怎么来、运行脚本（JTAG 三步 + 串口）、跑起来读回来的实测输出 ⇒ [`board/README.md`](board/README.md)、验收表 [`board/ACCEPTANCE.md`](board/ACCEPTANCE.md) |
| `data/` | `data/golden/` 参考图（含 `data/golden/manifest.md`）、`data/inputs/` 裸帧输入、`data/measured/` 实测输出留档（本会话实测 20 个件，索引在它自己的 `data/measured/README.md` 里）、[`data/metrics.csv`](data/metrics.csv) 是唯一那张数字表（`data/README.md` 本会话实测**不存在**） |
| `skill/` | 大模型协作沉淀的技能卡（索引 [`skill/README.md`](skill/README.md)；条目数只有那一行写着，本页不复制） |
| `report/` | 交付文档：设计说明、优化记录、命令表、复现说明（索引 [`report/README.md`](report/README.md)） |
| `report/log/` | 追加式工作记录（问题账、过夜流水、赛题对照表）；只作过程留痕，不当结论引用 |

**对照表**（赛题 §3.3.5.4 末句「采用其他组织方式的队伍须在 `README.md` 中给出目录对照说明」的落点——
本表就在 `README.md` 里，是**必答项**不是加分项；左列逐字取 `report/log/CONTEST_CHECKLIST.md:120`
所引的那份推荐结构的条目名，中列是本仓库现状。与 [`submit/README.md`](submit/README.md) 第 19–28 行那张
是同口径的两张（一张面向评审的阅读路径、一张面向从零复现），**要改必须两处一起改**，只改一处就是 §2 那条
"同一份东西抄两处一定会漂"的教训）：

| 赛题推荐结构里的位置 | 本仓库实际位置（本会话 `test -e` 逐条核对） | 为什么这样放 |
|---|---|---|
| `README.md`（项目简介 + 复现步骤） | 本文件：九节固定（页首那行写着顺序） | 复现步骤要能被"只拿这一个文件"的人照着敲 ⇒ 命令、目录、期望输出写在 §5–§7，不外链到一份要另下的文档 |
| 工程本体（RTL / 约束 / 固件 / 台架 / 构建脚本） | `src/rtl/`、`src/constraints/`、`src/ps/`、`sim/`、`build/tcl/`、`board/` | 交付文档指的就是这些路径；复制一份进包 = 造第二个真相源（`submit/README.md:22` 同一条理由） |
| 设计报告 / 各章节文档 | `report/*.md`（索引 [`report/README.md`](report/README.md)），阅读路径重构在 `submit/01-overview.md`…`submit/08-limits.md` | 仓库里一份、按"怎么建的"长；包里按"评审要看的顺序"重排，**只搬指路不搬数字** |
| 实测数据 / 指标 | [`data/metrics.csv`](data/metrics.csv)（唯一那张数字表，每行点名它的凭据） | 数字只在一处；其余读数一律由 §7 的尺子回算，不在文档里复述（§2 的红项 R2/R3 就是复述会漂的实例） |
| 凭据（构建 / 台架 / 板级报告原件） | `build/`（实现与综合报告平铺）、`build/evidence/`（被点名的那几份）、`build/r118_gates_final.txt` | 正文不改写：包里念的判据报告仍是工具产出的原文 |
| 技能包（§3.3.5.2 点名 `skill/`） | `skill/`，条目一律 `<目录>/SKILL.md` 八节外壳，索引 [`skill/README.md`](skill/README.md) | 赛题按目录名收，故同名；条目数只写在 `skill/README.md` 那一行，本页不复制 |
| 复现说明（他人从零执行） | §5–§7 三节 + [`submit/reproduce/README.md`](submit/reproduce/README.md)（每条命令逐字抄自脚本自己的用法头并标行号） | 命令 + 前置 + 期望输出，三件齐才算一条步骤 |
| 大模型协作记录 / 技能包提炼过程 | `report/AI_COLLABORATION.md`、`report/LLM_COLLAB.md`、`submit/07-skill-distillation.md`、`skill/pitfalls/` | 赛题 §3.3.5.3 点名的两章；原料是 `report/log/ISSUES.md` 与 `OVERNIGHT_LOG.md` |
| 学习/讲解文档（推荐结构里的"上手引导"那一类） | `docs/walkthrough/`（本会话 `ls` 存在；**不随包**、也不在提交阅读路径里，`docs/` 整目录由 `build/make_submission.sh:107-114` 剪掉） | 面向接手的人而非评审；随包会让评审翻到一堆过程件 |
| 运行台账（本仓库额外长出来的两类） | `docs/`（`run-queue.md`、`repro-check.md`、`questions-for-team*.md`、`timing/`…；**不随包**）、`report/log/` | 追加式过程留痕；它们回答"这一版的判定是谁跑的、输出是什么"，不进交付叙事 |

目录摆放按比赛要求的形状来（`src/ sim/ build/ board/ data/ skill/ report/`）。交付文档这一层仓库里就叫
`report/`；导出提交包时改的是**文件名**（按比赛要求写成纯英文小写：`report/BUILD.md` → 包内 `build.md`、
`report/KNOWN_ISSUES.md` → 包内 `known_issues.md`），文档里的指路跟着一起改；剪掉了什么、按哪条判据剪的，逐条写在
包内 `_pruned.txt`（那是提交包里的件，仓库里没有，本页把它算作"非仓库路径"不参与存在性核对），
而包内所有"路径式指路"由导出器自检——指不到就拒绝落盘。

### 3.2 提交阅读路径（`submit/`）

交付文档的重构阅读路径在 [`submit/README.md`](submit/README.md)：八章设计报告、复现说明
（[`submit/reproduce/README.md`](submit/reproduce/README.md)，每条命令逐字抄自脚本自己的用法头并标行号）、
以及"推荐结构 → 本仓库位置"的目录对照说明（赛题 §3.3.5.4 对采用其他组织方式的队伍的那句要求）。
它**不复制任何数字**——数字只在 `data/metrics.csv` 与门禁那一行里读。

### 3.3 条文依据（逐字，带出处）

- §3.3.5.4 末句：「上表为推荐结构，非强制。**采用其他组织方式的队伍须在 `README.md` 中给出目录对照说明**」
  ——引自 `report/log/CONTEST_CHECKLIST.md:120`。本节（§3）就是那份对照说明，是**必答项**不是加分项。
- §3.3.5.1：「可复现的构建脚本」与「实测输出与参考结果的比对数据」——引自同文件 `:134`、`:139`，
  落点分别是 §6 的命令序列与 §7 的比对尺子。
- §3.3.3.1（工具版本须说明并保证脚本可复现）、§3.3.3.2（声明具体型号）——条款编号与落点见同文件 `:11`、`:12`、`:82`。
- §3.3.5.4 文件名要求（小写字母、数字、下划线或连字符，不得出现中文、空格或特殊字符）：见同文件 `:21`。
- §3.3.5.2 末段「通用 PYNQ Skill 单独加分」：**本作品明确不适用**（裸机 + Vivado/Vitis 原生流程），
  登记在 `report/log/CONTEST_CHECKLIST.md:124-125`。

### 3.4 提交包里能直接跑的尺子（不是只在仓库里）

`doc_enc_check`、`line_cite_check`（D5）、`doc_currency_check`（D1–D4b）、`metric_recheck`（D6）这四把
只读文本与报告的尺子在包内也可跑（仓库内实测 2026-10-02 09:2x 全部 rc=0、硬错 0；本会话另跑了两把，见 §6 路径 A）。
其中 D1b 那一层在包里会自己念"本目录没有 bit 产物 ⇒ 这一层不判"——那是**声明不可判**，不是绿。
跑不了的只有需要串口/板子的 `ps_hb_check`、`board_verify` 与需要 RTL 源重跑的台架，它们要回仓库跑。

## 4. 前置条件

### 4.1 硬件（路径 C 才需要；路径 A/B 不需要任何外设）

| 项 | 要求 | 出处 |
|---|---|---|
| 板卡 | Zynq-7020 `xc7z020clg484-2` 一块（本工程只宣称这一块） | `report/log/CONTEST_CHECKLIST.md:12` |
| 供电 | 12 V 电源适配器 | `report/BUILD.md` §3 第 1 条 |
| 显示 | HDMI 面板，支持 1024×600 | 同上 |
| USB | USB 线（JTAG + UART 共用一根）：本会话实测枚举出 `USB Serial Converter A/B` 与 `USB Serial Port (COM6)` | `report/BUILD.md` §3；§5 S8 |
| 网口 | 网线接 **PL 侧网口**（不是 PS 口）；PC 设 `192.168.1.100/24`，板子是 `192.168.1.10`、UDP `5001` | `report/BUILD.md` §3 与 §4 |
| 演 SD 那一幕 | **下 bit 之前**把网线拔掉：PL 里 `link_active = |s_pkts|` 是"自配置以来收过任何一个包"，ARP 就够触发，拔线不清零 | `report/BUILD.md` §3 第 2 条 |
| 下载方式 | **全程只走 JTAG**；本工程没有任何脚本写 QSPI/SPI flash 或板载 EEPROM | `report/log/CONTEST_CHECKLIST.md:13`、`board/README.md` §1 |
| 线材型号 / 外设供电 / 限流 | `【队伍未确认】`——`board/hardware_setup.md` 正在由另一轮次写，本页不引用尚不完整的清单 ⇒ Q-P12-4 | — |

### 4.2 软件

- Vivado 2025.2.1（Tcl 构建、门禁取数、`program_pl`/`scan_jtag` 都走它）。**本会话实测 `vivado` 不在 PATH 上**
  ⇒ 要么把 `<Vivado>/bin` 加进 PATH，要么写全 `"$VP_VIVADO_BIN/vivado.bat"`。
- Vitis 的 `xsdb.bat`（上板那三步与 `board_verify` 用它）；路径通过环境变量 `VP_XSDB` 显式给。
- bash：Windows 用 Git Bash / MSYS（本会话 `MSYSTEM=MINGW64`）；`sim/run_one.sh` 用到 `cygpath` 与 `tasklist`，
  **这两样在 Linux 上没有对应形状 ⇒ 该脚本【未在 Linux 验证】**。
- Node 24（只读尺子与 PS 固件构建脚本用它；本会话 v24.21.0）。
- Python 3（推流上位机；只用标准库，`ffmpeg` 可选。**本机命令名是 `python`，`python3` 不存在**）。
- pyserial **本机没有** ⇒ 串口侧一律走 `board/*.ps1`（`board/uart_cap_once.ps1` 等，Windows 自带 API）。
- SD 卡（只演本地播放那一幕才需要；FAT32 簇链由 PL/PS 侧自研解析，不依赖文件系统库）。

### 4.3 环境变量（换一台机器只要设这几个）

| 变量 | 指哪儿 | 谁读它 | 不设会看到什么（脚本自己打印的那一句，逐字） |
|---|---|---|---|
| `VP_VIVADO_BIN` | `<Vivado>/bin`（安装根下的 `Vivado/bin` 那一层；找法见 §5 S5） | `sim/run_one.sh:46`、`build/timing_lane.sh:19`、`build/r118_chain.sh:22`、`build/r116_bit_cycle.sh:12` | `REFUSE: 找不到 xvlog（当前 $V）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（report/BUILD.md）`，rc=2；快车道那一支打 `LANE-REFUSE: 先设 VP_VIVADO_BIN=<Vivado>/bin（当前 ''）` |
| `VP_XSDB` | `<Vitis>/bin/xsdb.bat`（同名件在 `<Vivado>/bin` 也有一份，取 Vitis 那一份，见 §5 S7） | `build/board_verify.sh:113-114`、`build/r116_bit_cycle.sh:13` | `REFUSE: 找不到 xsdb（当前 $VP_XSDB）…` 或 `REFUSE no xsdb`；⚠ #317 那个坑是"**在子 shell 里 export、下一条命令读不到**"，命令前缀赋值对 `build/r116_bit_cycle.sh` 够用（它自己 `export VP_XSDB=${VP_XSDB:?…}`） |
| `PS_CC` / `PS_BSP` | ARM 编译器 / 已 generate 的 zynq BSP（**默认在仓库内**：`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp`，本会话 `test -d` 存在） | `build/build_ps_app.py`、`build/ps_app.mjs:29` | `FATAL: PATH 上找不到 …`（退出码 2） |
| `VP_BIT` | 要下进 PL 的那块位流 | `build/tcl/program_pl.tcl`、`build/r116_bit_cycle.sh:29` | 不设就是 `build/system.bit`（交付件身份仍由 md5 认） |
| `VP_R116_IO_WINDOW` / `VP_R119_TMDS_WINDOW` | 两档默认不加载的候选约束 | 构建入口 `build/tcl/build_system_axigpio.tcl:45-52` / `:63-70`（"入口脚本"在本文件一律指这一支，§6 B4 跑的就是它） | 都不设 = 不加载，日志各念一行 `off` |

## 5. 环境自检块（**全部只读**，跑完就知道自己缺什么）

在**仓库根**、Git Bash（Windows）里逐条敲。每条给"应看到什么"和"缺件时会看到什么"。
本会话（2026-10-04 12:5x）把 S1–S11 **全部重跑过一遍**，两轮实测摘要与每条的原文输出记在
[`docs/repro-check.md`](docs/repro-check.md) §2.1（`docs/` 不随包）；S5 的查找深度按本轮实测改过一次，见那一步的 ⚠。

```bash
# S1 shell 与平台
uname -a; echo "MSYSTEM=$MSYSTEM"
#   期望：MINGW64_NT-<版本> … x86_64 Msys 且 MSYSTEM=MINGW64
#   在 Linux 上这一行形状完全不同 ⇒ 本文件所有 Linux 分支【未在 Linux 验证】

# S2 Node（只读尺子要用）
node --version                         # 期望 v24.x；缺 ⇒ command not found（尺子一支也跑不了）

# S3 Python 与命令名
python --version; python3 --version
#   期望（本机实测）：Python 3.12.10 / `python3: command not found`
#   ⇒ 本机一律写 `python`；照抄 `python3` 的文档在这台机器上第一步就崩

# S4 pyserial 在不在
python -c "import serial; print(serial.__version__)"
#   本机实测：ModuleNotFoundError: No module named 'serial'
#   ⇒ 这不是故障：串口侧走 board/uart_cap_once.ps1（Windows 自带 API），不要用 Python 占串口

# S5 Vivado 是否真的能用（不要假设它在 PATH 上）
#   ⚠ 本块里所有 `<…>` 都是**占位符，尖括号本身要一起删掉**：原样敲
#     `export VP_VIVADO_BIN=<Vivado>/bin` 会被 bash 当成重定向，实测报
#     `bash: line 1: Vivado: No such file or directory`（rc=1）且变量变成空串。
#   先找安装位置（只读）。⚠ 深度这一格本会话实测纠正过：`-maxdepth 4` **挖不出来**
#   （`find /d/Software -maxdepth 4 -name vivado.bat` ⇒ 0 行；同一条 `-maxdepth 5` ⇒ 1 行，1.0 s），
#   因为常见安装是 `/<盘>/Software/Vivado/<版本>/Vivado/bin/vivado.bat`，从盘符根数起是 6 层。
#   所以下面写 6；读者的盘上如果更深，把数字再加一层（这条只读、代价是一两秒）：
find /c /d -maxdepth 6 -name vivado.bat 2>/dev/null          # 形如 …/Vivado/<版本>/Vivado/bin/vivado.bat
export VP_VIVADO_BIN=<把上面那行结果里的 bin 目录贴到这里>     # 例：Git Bash 形状 /<盘符>/…/Vivado/2025.2.1/Vivado/bin
command -v vivado || echo "NOT on PATH -> use \"$VP_VIVADO_BIN/vivado.bat\""
test -f "$VP_VIVADO_BIN/vivado.bat" && echo OK
#   本机实测（本会话）：PATH 上没有 vivado（`command -v vivado` 空）；`test -f` 那一步打 OK
#   ⚠ 个别脚本里留着**本队机器**的默认值（如 `build/r116_bit_cycle.sh:12`），那是"便利"不是"标准"，
#     换一台机器不要指望它（清单与死代码那处写法见 `build/README.md` 第 2 节）

# S6 器件在不在设备库（没有任何脚本替你做这件事，见 §2 末行）
grep -o "xc7z020[a-z0-9]*" "$VP_VIVADO_BIN/../data/parts/installed_devices.txt" | sort -u
#   期望三行：xc7z020 / xc7z020clg484 / xc7z020i（本会话实测正是这三行）
#   这条假定 `<安装根>/Vivado/bin` 这一层形状成立（`bin` 直接挂在 `Vivado/` 下）；
#   不成立时改成直接从 S5 找到的路径往回两级：
#   grep -o "xc7z020[a-z0-9]*" "$(dirname "$VP_VIVADO_BIN")/data/parts/installed_devices.txt" | sort -u
#   空输出 ⇒ 器件库缺 ⇒ create_project 会报错，形状像"工程打不开"而不是"器件缺"

# S7 Vitis 的 xsdb 与 hw_server
export VP_XSDB=<Vitis 安装目录>/bin/xsdb.bat; test -f "$VP_XSDB" && echo OK
netstat -an | grep ":3121"
#   期望：一行 `TCP 0.0.0.0:3121 0.0.0.0:0 LISTENING`（本会话实测有）
#   空 ⇒ 没有 hw_server 在听 ⇒ 上板第一步连不上（`CONNECT:` 空），
#        起 `<Vitis>/bin/hw_server.bat` 之后应拿到 `tcfchan#0`（`board/ACCEPTANCE.md:36` 钉了这条要先做）
#   同名件可能有两份：本会话实测 `<Vitis>/bin/xsdb.bat` 与 `<Vivado>/bin/xsdb.bat` 都在 ⇒
#   本页一律取 **Vitis** 那一份（`report/BUILD.md` §1 与 `build/board_verify.sh:113-114` 点名的就是它）

# S8 串口（只枚举，**不开口、不占用**）
powershell.exe -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()"
#   本机实测：COM6；PowerShell 不在（纯 Linux）⇒ 这一行换成 `ls /dev/ttyUSB*`【未在 Linux 验证】
#   空 ⇒ USB 线没插好 / 没枚举出 COM 号；COM6 被别的终端占着时脚本会拒绝，那不是板子坏了

# S9 源码指纹尺子自己能不能红（六条对照，只写临时目录）
bash build/rtl_fingerprint.sh --self
#   期望末行：RESULT rtl_fingerprint --self PASS   （本会话实测 rc=0）

# S10 台架判定解析器（离线、不起仿真器）
bash build/run_one_ce.sh
#   期望末行：SELF PASS run_one --verdict（八条对照都按期望动）   （本会话实测 rc=0）

# S11 你手上这份树与提交是否同一份（脏树计数只是陈述，不是判据）
git status --porcelain | wc -l; git rev-parse --short HEAD
#   本页作者写这一行时看到 35 / 384a0b3，演练会话几分钟后再跑看到 59 / 157d332，本会话（12:5x）看到
#   53 / 1c4e26b ⇒ **这一条每次都不同**，它是"现在有没有别的轮次在动仓库"的陈述，不是判据、也不是期望值；
#   但它影响一个真判断：脏树 + 已采纳产物同名 ⇒ 现在重建会覆盖什么（见 §6 路径 B 的 B4 那一行）
```

## 6. 从零复现：三条路径

**每条命令带四个字段**：在哪个目录 / 命令（与脚本自己的用法头逐字一致）/ 完成后应看到什么 /
本会话状态（`MEASURED`=本会话亲跑并贴了输出，`NOT_MEASURED`=没跑，只给"跑过的凭据"文件）。
**目录这一字段对下面 A/B/C 全部成立：一律在仓库根、Git Bash（Windows）里敲**，路径都是仓库相对路径；
只有 B4/C* 另需 `VP_VIVADO_BIN` / `VP_XSDB` 已按 §5 的 S5、S7 设好。
尖括号 `<…>` 全是占位符（连同尖括号一起替换），别原样回车。
**从未被任何人跑过的命令一律不写在下面**；写不出处的命令一律不写（排除清单见 `docs/repro-check.md` §5；`docs/` 不随包）。

### 路径 A —— 只看归档结果（不需要 Vivado、不需要板子、5 分钟内跑完）

能做到：核对"交付的数字确实出自仓库里那几份报告"、核对文档与数字对账、读回门禁与板级判据的原文。
**做不到**：证明构建可复现、证明板子上的行为。

```bash
# A1 你手上的 RTL 与 r118 位流同源吗（在仓库根，只读打印）
bash build/rtl_fingerprint.sh
#   期望四行：fpver=norm1 / files=80 / top=56c269602e18 / rtl=07570b1ac1b4
#   与 build/evidence/r118_tree_fp.txt 逐字相同 ⇒ 同源；不同 ⇒ 树变了（本会话实测：相同，rc=0）
#   射程要说清：这把尺子只看 80 份 src/rtl/*.v，不看 BD、不看 PS 固件、不看工具版本（build/provenance.md 第 1 节）

# A2 首页与指标表的每个数对回报告（D6，只读）
node src/host/metric_recheck.mjs
#   期望末行：== 数字对账：判 117 个数（首页层 63 个／解析到 10/10 行；红 0）／csv 认领 10/10 行／其余 18 行不点名这三份报告 ==
#   三个结局分开走：
#     红 N 条、行文本是 `RED row=README.md 里找不到「全设计 setup WNS」这一行 ⇒ 首页与指标表脱钩`
#       ⇒ 是**首页 §1 的行名/括号形状**被改掉了（这四行名 + `功耗` 是尺子的锚点，见 §1 表下那段警告），
#         动作是恢复行名，**不许**改尺子里的名单或阈值；
#     红 N 条、行文本是 `OK/RED … 首页=X 报告=Y` 两个数不相等 ⇒ 文档抄的数与报告不同源，改文档那一格；
#     `FATAL 读不到 …` ⇒ 报告格式变了，按 §8 的 `report-field-parse-breaks` 先修解析器再说结论。
#   N 会随文档增删变（本页作者 11:5x 看到 114/60，改完 §1 是 117/63）⇒ 读的是**红几条**，不是总数

# A3 交付文档里的 文件:行号 引用还指得对吗（D5，只读）
node src/host/line_cite_check.mjs
#   期望末行：D5: CLEAN（退出码只由硬错决定…）   rc=0
#   本会话两次实测：改 README 前 `扫 210 份 ⇒ 硬错 0`，改后 `扫 226 份 ⇒ 硬错 0；锚点命中 1088 条`
#   份数随文档增减；红只由三类硬错引起（文件不在树里 / 行号越过文件末尾 / D5b、D5d 那两条），
#   `soft`（锚点候选、取不出锚点、转述待人看）**不判红也不许拿来批量改行号**

# A4 整屏逐像素台架那份报告现在数出多少条（离线解析，不起仿真器）
bash sim/run_one.sh --verdict tb_v98_top_seam build/tb_v98_report.txt
#   本会话实测 rc=3：VERDICT tb_v98_top_seam: RESULT tb_v98_top_seam FAIL nfail=1 || FAIL 行数=1 || PASS 行数=161
#   rc=3 是**判红**不是崩：那 1 行红就是 §1 说的声明过的 C5c；换版后数字会变，读的是那一行的三个字段

# A5 HDMI 源端窗那把只读尺子（判数字可推导、成对、射程、默认不加载）
node build/r119_window_check.mjs
#   期望末行：GATES r119 窗件：判定 10 项 红=0 未测=0 PASS   rc=0（本会话实测）

# A6 技能包装配门禁（射程只在 skill/，不判工程）
node skill/scripts/check/gates.mjs
#   本会话实测 rc=1：末行 GATES 技能包：判定 12 项 绿=9 红=2 未测=1 —— 有红项，不提交 FAIL
#   红的是 G2/G10、未测是 G11 ⇒ 这一条**不是**工程回归失败，别把它念成设计坏了

# A7 读归档判据原文（不跑工具）
cat build/r118_gates_final.txt | tail -2       # 门禁那一行（原文已在 §1）
cat build/evidence/r118_board/BOARD_NOW.txt    # 板上是哪一版、什么时候刷的
```

### 路径 B —— 复现仿真与构建（需要 Vivado，不需要板子）

```bash
# B0 前置：§5 的 S5/S6 已过，且 VP_VIVADO_BIN 已 export
#   ⚠ 同一时刻只允许一个 xsim 在写 /tmp/kx/<tb>.run：脚本会自己拒绝启动而不是杀别人的进程

# B1 单台架（用法头逐字：`run_one.sh <tb_name>`，sim/run_one.sh:2）
bash sim/run_one.sh tb_osd_lines
#   应看到：VERDICT tb_osd_lines: RESULT tb_osd_lines PASS || FAIL 行数=0 || PASS 行数=3   且 rc=0
#   跑过的凭据（归档件）：build/evidence/r110_notadopted/r110_lane_after.txt:20 同一行，wall=13s
#   本会话状态：NOT_MEASURED（本任务禁止起 xsim）
#   失败分叉：rc=1 编译/例化失败（看 XVLOG FAILED / XELAB FAILED 及其后 8 行 ERROR）、
#             rc=2 REFUSE（VP_VIVADO_BIN 没给或指错）、rc=3 判红、rc=4 认不出判定行
#             ——红与"没数"必须分开：NO-VERDICT-LINE 不等于通过（sim/run_one.sh:117 给的表）

# B2 快车道（分钟级那一组，不含约 100 分钟的顶层台架）
#   逐条形状与耗时看件：build/evidence/r110_notadopted/r110_lane_after.txt 第 1 行 `清单=28`，
#   里面每一条都打 `LANE GREEN wall=<10..17>s rc=0 VERDICT …`
bash build/timing_lane.sh          # 本会话状态：NOT_MEASURED（会起仿真器）
#   它也要 VP_VIVADO_BIN：不给就 `LANE-REFUSE: 先设 VP_VIVADO_BIN=<Vivado>/bin（当前 ''）` 且 rc=2
#   （逐字出处 build/timing_lane.sh:19；它内部逐支调 sim/run_one.sh，所以同样受"只有一个 xsim"那一道拒绝）
#   ⚠ 快车道的绿**不代替门禁**：它不产 build/tb_v98_report.txt（该脚本 :88 那行自己写着这一条）

# B3 顶层整屏台架 + 门禁第 15 项要的凭据件
bash sim/run_one.sh tb_v98_top_seam        # 本会话状态：NOT_MEASURED（禁跑；一次约 100 分钟，见 R2 的两档口径）
bash build/tb98_report.sh                  # 用法头逐字：`bash build/tb98_report.sh [那份 run.log]`（build/tb98_report.sh:4）
#   应看到：build/tb_v98_report.txt 头部一行 `# provenance fpver=norm1 top_md5=<与 A1 的 top 同值> …`
#   头部 md5 与当前树对不上 ⇒ "这份报告不算当前这一版"，门禁第 15 项判红（机制 sim/run_one.sh:73-95）

# B4 一条命令出位流（Vivado 2025.2.1，命令行；从仓库根起）
"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl
#   应看到：TOP: system_top.v … / BUILD_POST_PLACE_HOOK none / BUILD_PRPO off /
#           WIDTH_WARNINGS count=0 / MULTI_DRIVEN count=0 / BIT: … / XSA: … / 末行 SYSTEM BUILD DONE
#   不该看到：SYNTH FAILED、ADDRESS PINNING FAILED、PORT_LOOKUP_FAILED、BUILD_*_REJECTED
#   耗时（只从 r118 那份日志时间戳算，出处 build/README.md §4）：建工程到出报告合计 19 min 30 s
#   本会话状态：NOT_MEASURED（本任务禁止跑构建）
#   ⚠ 这支入口会 **原地覆盖** build/system.bit / .xsa / 那 7 份 .rpt（无 seed、目录名不变）
#     ⇒ 已采纳那一版的凭据会被换掉：这条现状判定在 build/provenance.md 第 7 节是 **FAIL**，不是没测
#   只想验 BD（3 分钟那一档，用法头逐字 build_system_axigpio.tcl:265）：
#     vivado -mode batch -source build/tcl/build_system_axigpio.tcl -tclargs bd_only   # 期望 BD_ONLY_DONE

# B5 发布门禁（读 build/ 里当前这套报告）
bash build/gates.sh
#   应看到三态之一（build/gates.sh:582-586 逐字）：
#     GATES: ALL PASS（<N> 项全部判定）
#     GATES: PARTIAL —— 判定 <N> 项全过，但有 <M> 项因缺凭据未判（见上面 n/a 行），这一版不作"过门禁"
#     GATES: 有红项（判定 <N> 项）—— 不采纳，保留上一版
#   项数只以脚本打印的那一行为准（本页不写死；r118 那一跑是"判定 24 项"）
#   本会话状态：NOT_MEASURED（本任务不许跑它：它会写证据件，且已有实例在跑）
#   ⚠ 不要把它的输出直接重定向成它自己要读的 build/rNN_gates.txt（文件头 :14-20 记的自毁陷阱）
#   脚本头还给第二种形式（读一组成套冻结件），本次未跑故不列为步骤，逐字备查：
#     bash build/gates.sh build/frozen_r19_arb
#     —— "成套"的最低门是四份报告必须在所选目录里（`build/timing_summary.rpt`、`build/utilization.rpt`、
#        `build/power.rpt`、`build/route_status.rpt` 这四个**文件名**，脚本按所选目录拼路径去读），
#        缺任何一份就 `FATAL 缺报告：<路径>` 且 rc=2
#        （逐字出处 `build/gates.sh:31-33`）；其余报告缺时会打 `n/a` 行、结尾只能是 `GATES: PARTIAL`

# B6 PS 侧固件（单独一条，不在 B4 里；r118 那一轮就没重编它）
node build/ps_app.mjs            # 本会话状态：NOT_MEASURED（禁止构建）
#   编译器由 PS_CC 给（不设就假定 PATH 上有 arm-none-eabi-gcc，本机 PATH 上没有 ⇒ 会 FATAL）；
#   BSP 有**仓库内默认值**，不用设：vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp
#   （逐字出处 build/ps_app.mjs:29；该目录本会话 test -d 存在。为什么把默认指进仓库，见同文件 :26-28 与 ISSUES #89/#90）
```

### 路径 C —— 复现上板实测（需要板子、JTAG、串口）

```bash
# C0 前置：12 V / HDMI / USB(JTAG+UART) 已接，网线接 PL 口，§5 的 S7 看到 LISTENING、S8 看到 COM6

# C1 一把刷板 + 带流读回（用法头逐字：`bash build/r116_bit_cycle.sh <标签> [位流路径]`，:4）
VP_XSDB=<Vitis 安装目录>/bin/xsdb.bat bash build/r116_bit_cycle.sh <标签>
#   这一条用"命令前缀赋值"够用：脚本第 13 行自己写的是 `export VP_XSDB=${VP_XSDB:?…}`，
#   前缀变量正好被它读到；而 §4.3 那条 ⚠（ISSUES #317）说的是**另一形状**——在子 shell 里
#   `export` 完就结束、下一条命令读不到。两种写法在这里不等价的那一维就是"谁 export、活多久"。
#   应看到（token 全来自这支脚本，逐字对照件 build/evidence/r118_board/bitcycle_console.txt）：
#     recover rc=0 / boot rc=0 / DDR_ECHO: 10000000: 5A5AA5A5 /
#     pl rc=0 PROGRAMMED=2 / app rc=0 FLOW_DONE=1 / 读 A rc=0 / 读 B rc=0 /
#     a: eth_live=1 owner_eth=1 drop_words=0 pkt_err=? frames_bad=? drop_seen=? / done
#   那一行的 `?` 是**没读出来的字段**，不是 0（`report/log/ISSUES.md` #318）
#   耗时：同一件首末行 04:45:26 → 04:47:07 = 1 min 41 s
#   本会话状态：NOT_MEASURED（本任务禁止刷板、禁止占串口）
#   失败分叉：REFUSE DDR_ECHO 没过（刚上电 JTAG 链还没重枚举，重插或先跑 C3 第 1 步）、
#             REFUSE no xsdb（VP_XSDB 没给）、REFUSE 没烧进去（PROGRAMMED 计数为 0）

# C2 板级机器判据（用法头逐字，见 build/board_verify.sh:4-16）
VP_XSDB=<Vitis 安装目录>/bin/xsdb.bat bash build/board_verify.sh --battery --geom --round=<轮号>
#   应看到：RESULT PASS geom_check（ok=10 fail=0） / RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, …) /
#           RESULT board_verify PASS（判红的步骤：0）；红那一支是 RESULT board_verify FAIL nred=<N>
#   ⚠ 命令电池**条数有两个说法**，别当成同一时刻：脚本用法头 `build/board_verify.sh:6` 写
#     「97 条 = V8 的 71 + V9 的 20 + #77 的 6」，而它**自己那一跑打出来**的是 105 条
#     （凭据 `build/evidence/r118_board/board_verify_console.txt` 倒数第 4 行）。
#     **以你那一跑打印的那一行为准**，头里的 97 是写脚本那天的条数（同一族形状记在 ISSUES #220 附近）
#   ⚠ `--round=rNN` 必给：没有轮号它**判红而不写文件**（免得把今天的数写成一份名字叫旧轮的假凭据）
#   本会话状态：NOT_MEASURED（要串口）
#   没有板子也能验"这把判据自己会不会红"（本会话实测 rc=0，5/5；产物只落临时目录）：
bash build/board_verify.sh --self
#   应看到：SELF board_verify: 5/5 条形符期望（地板 5/5）

# C3 手工三步（顺序不能换；各支自己的用法头逐字。裸名字 `xsdb.bat` 不在 PATH 上——
#     本会话实测 `command -v xsdb.bat` 与 `command -v xsdb` 都空，所以这里写全路径变量）
"$VP_XSDB" build/tcl/ps_jtag_boot.tcl                    # 头 :3 逐字形如 `xsdb.bat build/tcl/ps_jtag_boot.tcl [path/to/ps7_init.tcl]`；会打印 DDR_ECHO
"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl   # 头 :3
"$VP_XSDB" build/tcl/ps_app_reload.tcl                   # 头 :4-5 逐字 `xsdb.bat build/tcl/ps_app_reload.tcl <别的.elf>`
#   ps7_init.tcl 不用你去找：`build/system.xsa` 里就带着它，脚本自己解（`build/tcl/ps_jtag_boot.tcl:6-8`）
#   ⚠ ps_jtag_boot 含 `rst -system` ⇒ 跑过它就**必须重下 bit**；ps_app_reload 只 `rst -processor`
#   JTAG 链能不能看见（跑法是 vivado，不是 xsdb —— `build/tcl/README.md` 与 `board/README.md` §2 都钉了）：
"$VP_VIVADO_BIN/vivado.bat" -mode batch -source build/tcl/scan_jtag.tcl    # 本会话状态：NOT_MEASURED（要硬件）

# C4 上位机推流（Python 标准库，装了 ffmpeg 才能发任意视频）
python src/host/video_sender.py --demo          # 先 ping 192.168.1.10，再推内置测试视频 12 s
#   板子在 hand 边也可以双击 send_demo.bat（它跑的就是上面这一条）
#   参数面（本会话实跑 --help，rc=0）：--ip --port --fps --count --seconds --pace-mbps --input --raw --demo --no-ping
#   ⚠ Windows 控制台码页实测是 gbk/cp936：--help 里的中文会糊成乱码（ASCII 参数名不受影响）。
#     要干净文本就 `PYTHONIOENCODING=utf-8 python src/host/video_sender.py --help`（本会话实测有效）
#   本会话状态：NOT_MEASURED（推流要板子）

# C5 眼睛那一半不是命令：board/ACCEPTANCE.md 的 E1–E6 给的是判法与条件，
#     只有在看的人点头之后才写进表；屏幕读数不进机器判据、也不进门禁。
```

## 7. 结果比对：怎么确认你跑出来的和交的一致

| 比什么 | 参考物 | 比对尺子（**读被比对象是只读的**；括号里写它会不会落笔） |
|---|---|---|
| 首页/指标表的数字 ↔ 报告原文 | `data/metrics.csv`（29 行，每行点它的证据文件） | `node src/host/metric_recheck.mjs`（不落笔）—— 本会话实测 rc=0、判 **117** 个数（首页层 63）、红 0 |
| 时序/资源/功耗逐列取数 | `build/timing_summary.rpt`、`build/utilization.rpt`、`build/power.rpt` | `node skill/scripts/report_metrics/report_metrics.mjs --timing … --utilization … --out-dir <临时目录>`（**要 `--out-dir`**，且拒绝指向工程目录）；本会话**没跑** ⇒ `NOT_MEASURED`，只给跑法出处（该文件 `--help`） |
| 逐像素判据条数 | `build/tb_v98_report.txt`（`^PASS` / `^FAIL` 计数） | `bash sim/run_one.sh --verdict tb_v98_top_seam build/tb_v98_report.txt`（不落笔；本会话实测 161/1，见 §2 R2） |
| 逐键带容差的表 ↔ 表 | 例：`build/CDC_BASELINE.txt` ↔ `build/frozen_r23_srcseen/cdc.rpt` | `node skill/scripts/golden_compare/golden_compare.mjs --golden build/CDC_BASELINE.txt --golden-format kv --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' --produced build/frozen_r23_srcseen/cdc.rpt --produced-format kv --produced-key '$2>$3' --produced-values 'endpoints=@5,unsafe=@3' --produced-where '$1=Critical' --tolerance 0 --out-dir <临时目录>` —— 这一串是该脚本**文件头自己点名的正例基线**，比的是 CDC 的两栏数（键 = 时钟对），**不是图片比对**；**要 `--out-dir`**（本会话实测 rc=0、判 18 项、未判 0、红 0） |
| `data/golden/` 那批参考图（`data/golden/src.png`、`data/golden/rot_000.png` 等六档旋转、`data/golden/proc_00111.png` 等效果组合） | 只作**人眼参照**：本会话打开 `data/golden/README.md` 读到它的自述——"它们**不是任何台架的输入**，全仓对 `data/golden` 的引用只有 `report/log/CONTEST_CHECKLIST.md` 提了一次目录名"，且"PNG 无法一键重跑" | **没有**逐像素 diff 的只读脚本（本会话按它给的核实命令复核过）⇒ 这一行不能写成"比对尺子"；"与黄金参考逐像素一致"这句在本仓**不成立**，缺口进 `docs/questions-for-team-p12.md`（`docs/` 不随包） |
| CDC 配对集合 | `build/CDC_BASELINE.txt` ↔ 当轮 `build/cdc.rpt` | 门禁第 6 项（`bash build/gates.sh`，可选 `CDCBASE=`）—— ⚠ **它会写门禁凭据件**，所以不在"只读"那一档，跑法与陷阱见 §6 B5 |
| 板级行为 | `board/ACCEPTANCE.md` 的机器判据表 | `bash build/board_verify.sh --battery --geom --round=rNN` 的 `RESULT …` 行逐字对表（写 `build/evidence/…`；离线那一半 `--self` 只写临时目录） |
| 位流/固件身份 | `build/evidence/r118_bit_md5.txt`、`build/evidence/r118_bit/md5.txt` | `md5sum build/system.bit` 取前 12 位比对（认 md5 不认文件名，`build/r118_chain.sh:36`）；本会话实测 `cd04907e1369` 两处同值 |

⚠ 赛题 §3.3.5.1 说的"比对数据/脚本"在本仓的落点**不在 `scripts/`**：`scripts/` 目录本会话实测只有
`scripts/check_repo_hygiene.sh`（存在但**未入库**，P20 那一轮在写）。比对尺子的真实位置是 `src/host/`（D1–D6 那几把）
与 `skill/scripts/`（`golden_compare` / `report_metrics` / `repro_check`）。这条差异已登记在
[`docs/repro-check.md`](docs/repro-check.md) §4（`docs/` 不随包）。

## 8. 卡点速查（8 条，全部来自 `skill/pitfalls/`，条目名可点进去）

本目录 `skill/pitfalls/` 下**此刻**有 24 个条目目录，其中 20 个已有 `SKILL.md` 正文、4 个还是空目录
（本会话 12:5x `ls` 逐个数的；上一轮写这一节时是 8 有 / 6 空，并发轮次一直在补，**所以这个数字只对该时刻负责**，
核对命令就一条：`ls skill/pitfalls/*/SKILL.md | wc -l`）。下表按 P12 铁律 7 只挑**真正会挡住第一次跑通**的 8 条，
是那 20 条的一个子集，不是全集；空目录一律不引用（本会话实测这 8 个条目名的 `SKILL.md` 都在，107–120 行）。

| # | 看到什么 | 先查什么 | 与硬件/授权/版本有关吗 | 条目（`skill/pitfalls/<名>/SKILL.md`） |
|---|---|---|---|---|
| 1 | `GATES: ALL PASS`、`drop_words=0`、`violations=0` 一类聚合绿 | 那一项这次真读了文件吗：分母（`判 N 项` / 未判 M 项）在不在、样本是不是空集 | 与硬件无关，尺子问题 | `checker-ran-on-nothing` |
| 2 | `run.log` 头部 md5 全对，正文却混着两跑的行；后台任务日志一直 0 字节 | 有没有第二个进程在写同一份件；MSYS 下别用 `ps -W` 判活性，用 `tasklist //FI "IMAGENAME eq xsim.exe"` | 与授权/硬件无关 | `who-else-writes-this-artifact` |
| 3 | 中文整段变空白/乱码；判据标签掉半个字；GBK 回显进 git 被编码检查判红 | 先分"编码坏了"还是"行为坏了"：`python -c "import sys;print(sys.stdout.encoding)"` 是不是 gbk；机器可读 token 保持 ASCII | 与硬件无关，是码页 | `console-codepage-verdict-shift` |
| 4 | `Vivado ERROR [Common 17-37] … does not exist [/tmp/…]`、`xvlog Can not find file`、只剩 `Cannot find design unit` | 清单走 `-f 文件` 且文件里写 **Windows 正斜杠**路径（`cygpath -m`）；export 是否被关在子 shell 里；`.bat` 不要用 `[ -x ]` 判 | 与版本有关（命令行长度/MSYS 换算），与板子无关 | `win-bash-path-split` |
| 5 | 脚本 `exit 0`、打印了 `*_DONE`，但 `build/` 里报告时间戳或 md5 没变 | 核对**产物**而不是退出码：`stat` 时间戳 + `md5sum`；历史同级脚本 `add_files` 指错根、报错仍 exit 0 | 与硬件无关 | `exit-zero-nothing-written` |
| 6 | 取数脚本报 `FATAL 读不到 …`，可你肉眼在那份报告里看得见那个数 | 出现负 slack 后取数式是否吃掉符号位；同类行字段数不同（CDC 行 4 个 token vs 2 个）能不能用固定列号；缩进 `  FAIL` 是否被计数 | 与版本有关（报告形状随工具版本变） | `report-field-parse-breaks` |
| 7 | 探针打出 `COUNT=0`、`*=0`、名册"没认出网" | 带 `-quiet` 的查询先判"过滤器坏了"；`-filter` 里 `eq` 在本版本非法；对象名带方括号要转义；不带 `-hier` 的 `get_nets *` 只回 1000 个 | **与工具版本直接相关**（本条只在 2025.2.1 量过） | `tcl-query-empty-means-broken-ruler` |
| 8 | 文档/提交信息写"已验证 / 已改 / 补进了第 N 节" | 同一段里四件齐不齐：复跑命令 + 输入文件 + 期望输出 + 实际输出摘要；缺一律降级成 `【待验证】` | 与硬件无关 | `assertion-not-in-any-file` |

## 9. 许可与致谢

- 本工程源码：**MIT**，见 [`LICENSE`](LICENSE)（本会话 `test -f LICENSE` 通过，全文 4 条）。
- 哪些是厂商例程改的、哪些自研——**本会话实测这一格在仓里没有逐文件落点**，两处说法要对着读：
  `report/BACKGROUND_AND_NOVELTY.md:32-34` 点名了来源与范围（以太网协议栈那一层
  `arp/icmp/udp/eth_ctrl` 来自开发板厂商例程，并写出它自带的两处缺陷 #37/#38），
  它同一句把"逐文件的哪些是厂商代码、哪些是自研"的落点指给 `report/log/VERSION_LINEAGE.md`；
  而本会话在那份文件里 `grep -c "厂商"` = **1**（只有 `:153` 的一句问题叙述，没有逐文件表）
  ⇒ **"逐模块登记"这句话现在不成立**，README 不替它背书 ⇒ Q-P12-5（已把这条从"清单没写完"
  升级为"两处文档互相指空"）。
- 厂商 IP 与第三方代码的**来源/协议清单**（P20 那一轮的交付物）：目标文件 `docs/declarations.md` 本会话 `test -f` = **MISSING**（`docs/` 不随包），`NOTICE.md` 同样不存在，故此处**不写成链接**，
  等它写完由本节指过去 ⇒ Q-P12-5。在此之前，读者能核对的只有上一条那句范围声明与 `LICENSE`。
- 赛题 §3.3.5.2 的"通用 PYNQ Skill 单独加分"：**不适用**（本作品是裸机 + Vivado/Vitis 原生流程，
  没有 PYNQ 层），登记见 `report/log/CONTEST_CHECKLIST.md:124-125`。
- 致谢：工具行为的全部说法都以本次打开过的文件为准；凡没核实的一律写 `【未核实】` 或 `NOT_MEASURED`，
  不许用 P00 第 8 条禁词那类含糊措辞填空。

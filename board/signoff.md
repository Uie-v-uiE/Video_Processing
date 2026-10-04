# 验收签核记录（P16c）

这份文件只做一件事：把每一条验收写成**配方**，五件齐全、判定三态，需要眼睛的那一半只引队员的原话。
**它不替代 `board/ACCEPTANCE.md`**：那份是队员签收的原件（原话、时间、当时状态都在那里），
本文件只**逐字引用**它，绝不改写、绝不补签。任何我没法指着文件或原话说的条目，一律 `NOT_MEASURED`。

## 0. 口径与规矩（先读这段再用下面的表）

- **五件固定**：`观察项 | 前置状态（含回读到的值）| 具体动作 | 我看到/读到的原文 | 判定`。
  缺"前置回读"或"原文"的条目数在下面第 5 节逐个核。
- **判定只有三态**：`PASS` / `FAIL` / `NOT_MEASURED`。读不到输入等于 `NOT_MEASURED`，不等于 `PASS`。
- **眼睛项的记法学 `board/ACCEPTANCE.md`**：引队员原话 + 时间 + 当时板上是哪块 bit。
  没有原话就不写"过"，也不写"经确认无误"。
- **本版是哪一版**：板上 = **r118**，位流 md5 `cd04907e1369`（S1）。
  凡是凭据点名 r92/r94/r96/r97/r101/r103/r104/r108/r113 的读数，**都在判定旁边标了版本**，
  不借给 r118 用（这条规矩的出处是 `board/ACCEPTANCE.md` E6 格里那句"那两句不给 r118 借用"与 ISSUES #332）。
- **零样本不算测过**：凡是"计数器 = 0"的板侧判据，同一份读数里必须带 `eth_live=1`，
  否则记 `NOT_MEASURED`（出处：`report/log/ISSUES.md:12782` 的 #316 规矩①）。
- **审美/演示效果偏好不计功能红项**（P16c 铁律 3）：登记在第 6 节，不占三态。

## 1. 机器判据（本版 r118；每条五件）

### S1 板上位流身份：三处读数是不是同一块 bit

- 观察项：PL 里现在跑的位流是不是 r118 那块，工作区、git HEAD、归档件三处是否同源。
- 前置状态（含回读到的值）：`md5sum build/system.bit` 回读 `cd04907e1369da35d21c4090d552f5ee`；`git show HEAD:build/system.bit | md5sum` 回读同一串；`md5sum build/evidence/r118_bit/system.bit` 回读同一串；`build/evidence/r118_bit_md5.txt:1` 印 `cd04907e1369`。
- 具体动作：跑上面三条 md5，再 `sed -n '1p' build/evidence/r118_board/BOARD_NOW.txt` 与 `sed -n '1,6p' build/evidence/r118_board/board_verify_console.txt` 对读。
- 我看到/读到的原文：`board_verify_console.txt:4` = `  build/system.bit  md5=cd04907e  2026-10-04 04:36`；`BOARD_NOW.txt:1` = `板上现在 = r118（刷入 2026-10-04 04:49:50，bit_cycle rc=0 board_verify rc=0）`。⚠ 那句写的刷入时间是 **04:49:50**，而 `bitcycle_console.txt` 的 `program_pl` 行是 `[r118build 04:45:47]`→`[r118build 04:46:06] pl rc=0 PROGRAMMED=2`、`board_verify_console.txt:1` 是 `== board_verify 2026-10-04 04:47:07 ==`；我在件里**没读到** 04:49:50 那一次动作的日志 ⇒ 身份三处同源这一条成立，那句时间戳的指代进了问题清单第 1 轮 Q3。
- 判定：PASS

### S2 三步 JTAG 链（PS 起来 → 烧 PL → 重载应用）在冷上电后是否都成功

- 观察项：`ps_jtag_boot → program_pl → ps_app_reload` 三步是否全部成功，且只走 JTAG、不写 QSPI。
- 前置状态（含回读到的值）：板子断电 ≥10 s 冷上电、全程不碰 KEY1/KEY2（这半是眼睛项，见 E6）；`build/evidence/r118_eyes/STATE.txt:8-10` 记三步各自 `rc=0`；`STATE.txt:12` 记 `md5sum build/system.bit` = `cd04907e1369…`。
- 具体动作：读 `build/evidence/r118_eyes/step1_boot.txt`、`step2_program_pl.txt`、`step3_app.txt` 三份；再读 `build/evidence/r118_board/bitcycle_console.txt` 里同一轮的 `boot rc=0 / pl rc=0 PROGRAMMED=2 / app rc=0 FLOW_DONE=1` 三行摘要。
- 我看到/读到的原文：`step1_boot.txt:3-6` = `RST_SYSTEM: ok` / `PS7_INIT: ok` / `PS7_POST_CONFIG: ok` / `DDR_ECHO: 10000000:   5A5AA5A5`；`step2_program_pl.txt:33` = `PROGRAMMED xc7z020_1 <- D:/Xilinx/Prj/pro/Video_Processing/build/system.bit`；`step3_app.txt:4,11,22` = `DOW: ok` / `RESUME: ok` / `FLOW_DONE`。`STATE.txt:13-16` 另记一次真失败与恢复：`07:39` 那一步死在 `targets -set 1`（`hw_server` 冷上电后还没重新枚举链路），等它枚举成 `1=APU / 2=ARM#0 / 3=ARM#1 / 4=xc7z020` 之后原脚本一字未改就过了。
- 判定：PASS

### S3 板级一把跑 `board_verify` 是否零判红

- 观察项：`board_verify --geom --battery` 在 r118 上跑完，判红的步骤数是不是 0。
- 前置状态（含回读到的值）：板上 = r118（S1）；`build/evidence/r118_board/bitcycle_console.txt` 末行 `[r118build 04:47:07] done`。
- 具体动作：`tail -4 build/evidence/r118_board/board_verify_console.txt`，并数一遍其中的 `RESULT` 行。
- 我看到/读到的原文：`board_verify_console.txt:66` = `RESULT board_verify PASS（判红的步骤：0）`；`:64` = `[BATT] 退出码 0`；`:37` = `[GEOM] 退出码 0`；日志留档行 `:65` = `== 日志留在 build/evidence/verify_1004_0447.txt ==`。
- 判定：PASS

### S4 串口命令电池（含该拒的必须拒）在 r118 上是否全绿、末态是否回到演示默认档

- 观察项：105 条命令电池是否全绿，跑完之后板子是否回到文档默认档。
- 前置状态（含回读到的值）：`board_verify_console.txt:19` 回读进入时 `lane23 zoom → {"zsel":4,"zman":1,"inv_scale":256,"x100_actual":100,…,"verdict":"OK"}`；`:44` 回读 `进来时 CFG_DATA0 = 0x30400000（几何位 0x400000）`。
- 具体动作：`node src/host/uart_cmd_check.mjs --port COM6`（或整把 `bash build/board_verify.sh --battery --geom`），再读 `RESULT PASS uart_cmd_check` 那一行与末态那条 `ok`。
- 我看到/读到的原文：`board_verify_console.txt:63` = `RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, 捕获 board/uart_script_capture.txt)`；`:59` = `ok   末态 = 演示默认档（thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 sel=000 gm=0.00 mode=0 geom=00400000 osd=1）—— 与起点无关（#177）`；`:60` = `NOTE 初态 = 文档默认档（zsel=4 zman=1 mode=0 AUTO）⇒ 上面那条"回到初态"是在默认档上证的`。⚠ 那句里的 `board/uart_script_capture.txt` 是**工具本机重写、被 `.gitignore` 挡住的捕获件**（`git check-ignore -v` 命中 `.gitignore:134:board/uart_*.txt`）：它此刻在盘上，但**不随包**；随包复核要用 `board_verify_console.txt:63` 这一行与 `build/evidence/r118_serial_raw.txt`（`board_verify_console.txt:15`：`落点=build/evidence/r118_serial_raw.txt 行数=4 [TEMP]=2 判定=绿（地板 2）`）。
- 判定：PASS

### S5 几何"最后一跳"：命令 → 像素域 lane23/CFG_DATA0 真的用了它

- 观察项：几何命令是否真的落到像素域寄存器，并且收尾把 19 个几何位带回默认档。
- 前置状态（含回读到的值）：`board_verify_console.txt:24` 回读 `进来时 CFG_DATA0 = 0x30400000（几何位 0x400000）`。
- 具体动作：`bash build/board_verify.sh --geom`（或读 `geom_check` 段的 10 条 `ok` 与 `RESULT` 行）。
- 我看到/读到的原文：`board_verify_console.txt:36` = `RESULT PASS geom_check（ok=10 fail=0）`；`:26` = `ok   G1a \`zoom fit 1\` ⇒ lane23.bit19（zoom_fit）= 1  lane23=0x800e4903 alive=1`；`:31` = `ok   G5b 四次里至少真的钳住一次（bit19=1 且 inv>256）—— 不然 G5 是空判据  钳住=4/4`；`:35` = `ok   G4 整串跑完，CFG_DATA0 的 19 个几何位回到演示默认档…末 19 位=0x400000 默认=0x400000（与进来时差 0x0）`。**这一轮的 G5b 明确带着"防空判据"那半**，所以 G5 不是一次空过。
- 判定：PASS

### S6 上电默认档位（ACCEPTANCE 机器判据第 4 行那一格，本版重读）

- 观察项：刷完之后不碰任何命令，开机默认档是不是文档默认档（1.00×）。
- 前置状态（含回读到的值）：板上 = r118（S1）、`uart_stat.txt` 与 `uart_stat2.txt` 回读 `[STAT] … zsel=4 zman=1 … geom=00400000 osd=1`。
- 具体动作：读 `build/evidence/r118_board/board_verify_console.txt:19` 的 `lane23 zoom` JSON；或串口发一条 `STAT`。
- 我看到/读到的原文：`board_verify_console.txt:19` = `  lane23 zoom → {"raw":2147893504,"alive":1,"zoom_fit":0,"zman":1,"zsel":4,"zcode":4,"zoom_active":0,"zoom_dir":0,"inv_scale":256,"x100_actual":100,"rule":"manual_tier","inv_expected":256,"inv_ok":true,"code_ok":true,"verdict":"OK"}`；`build/evidence/r118_eyes/uart_stat.txt:1` = `[STAT] ctrl thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 pub=1 sd=1 frames=4398 playing=1 sel=000 gm=0.00 (PL owns UDP datapath) mode=0 geom=00400000 osd=1`。这一格在 `board/ACCEPTANCE.md:19`（r94 那一行）与 `:39`（r96"没有盖章"那一行）历史上漂过两次，本版这三次回读彼此一致 ⇒ 以本件为准，历史两行不覆盖。
- 判定：PASS

### S7 带真实流量时的收包链零丢字（r118 自己那一滚）

- 观察项：147 Mbps 真实流量在跑的时候，PL 收包链自己数的丢字/坏包是不是 0。
- 前置状态（含回读到的值）：`build/evidence/r118_board/bitcycle_console.txt:23` = `[r118build 04:45:47] 2) program_pl build/evidence/r118_bit/system.bit`（板上那一刻就是 r118）；`:26-28` = 起流 50 s、读 A 04:46:37、读 B 04:47:02；`build/evidence/r116_board/sender_r118build.log:1-2` 回读 `[TX] -> 192.168.1.10:5001  512x300 RGB565 @60fps  pace=0.0 MB/s`、`[TX] 3001 帧 / 50.02 s = 60.00 fps`（该件第 2 行后半是被 GBK 截断的中文，我只念能读清的三个数）。
- 具体动作：读 `build/evidence/r116_board/health_r118build_a.json` 与 `_b.json` 两个 JSON 的 `src_state.eth_live`、`owner_eth`、`drop_words`、`pkt_err`、`flags_bits.drop_seen`。
- 我看到/读到的原文：A 件 = `"eth_live":1,"owner_eth":1` / `"drop_words":0` / `"pkt_err":0` / `"flags_bits":{"drop_seen":"0",…"stream_live":"1"}` / `"pkts":221001,"bytes":307508160`；B 件同五个字段为 `1 / 0 / 0 / "0" / 558689`（包数在涨说明两次是不同时刻的真读数，不是同一份拷贝）。⚠ 两件**放在 `build/evidence/r116_board/` 目录里**但内容是 r118 那一滚（`cycle_r118build.log`、`health_r118build_*.json` 都以 r118build 命名）；目录名与内容不同源这件事我按原样记，不改名。`cycle_r118build.log:31-32` 的摘要行自己写的是 `a: eth_live=1 owner_eth=1 drop_words=0 pkt_err=? frames_bad=? drop_seen=?`——摘要器读不出后三个字段（`?`），所以我判的是 JSON 原文而不是那行摘要。
- 判定：PASS

### S8 空闲态的 `drop_words = 0`（board_verify 里那一读）

- 观察项：`board_verify` 第 2 步读到的 `drop_words → 0` 能不能当作链路健康的凭据。
- 前置状态（含回读到的值）：同一份读数里 `board_verify_console.txt:18` 回读 `lane30 src_state → {"eth_tb_ok":1,"eth_live":0,…,"why_no_stream":1,…,"why":"没有流"}`；`:17` 回读 `frames=4398`（`uart_stat.txt:1` 也是 4398，两次 3 s 间隔不变）。
- 具体动作：对照 `report/log/ISSUES.md:12782`（#316 规矩①：凡是"计数器=0"的板侧判据必须同一份读数里带 `eth_live=1`）。
- 我看到/读到的原文：`board_verify_console.txt:21` = `  drop_words → 0`，与 `:18` 的 `"eth_live":0` 在同一份读数里 ⇒ 这正是 #316 抓过的**零样本通过**形状：没有流量时它不可能不丢。带流的那一半见 S7，不是这一条。
- 判定：NOT_MEASURED

### S9 链路内时延同源一致（屏上那一格 ↔ 回读的那个计数）

- 观察项：OSD 的 `Latency` 那一格与 JTAG 回读的 `tot/100000` 是不是同源。
- 前置状态（含回读到的值）：S7 的两次带流读数 `eth_live=1`；空闲那一读 `eth_live=0`。
- 具体动作：读 `board_verify_console.txt:20` 与 `health_r118build_a.json`/`_b.json` 里的 `lat.osd_ms_matches_tot`。
- 我看到/读到的原文：`board_verify_console.txt:20` = `  lat.osd_ms_matches_tot → true`；A 件 = `"osd_ms_matches_tot":true`（`tot_ms":10.356`、`osd_ms":10`）；B 件 = `"osd_ms_matches_tot":true`（`tot_ms":5.888`、`osd_ms":5`）。`board/ACCEPTANCE.md:21` 那一行（屏上 `Latency=6ms` ↔ `tot/100000=6`）的凭据是 `build/evidence/r92_health.txt`，属 r92，不借给本版。
- 判定：PASS

### S10 温度格三方对账（驱动读数 ↔ 屏上三字符 ↔ 写进 PL 的 gpio）

- 观察项：`[TEMP]` 那一行的 `degC`、`osd`、`gpio` 三处是否自洽，凭据是否是被跟踪件而不是手抄。
- 前置状态（含回读到的值）：`board_verify_console.txt:15` = `[SERIAL] 落点=build/evidence/r118_serial_raw.txt 行数=4 [TEMP]=2 判定=绿（地板 2）`。
- 具体动作：读 `build/evidence/r118_serial_raw.txt` 全文 4 行，再读 `board_verify_console.txt:61` 那条对账判定。
- 我看到/读到的原文：`r118_serial_raw.txt:1` = `[TEMP] degC=60.65 raw=0xA990 vccint=998mv th=85C over=0 sane=1 osd=61C gpio=0x61`；`:3` = `[TEMP] degC=60.85 raw=0xA9AA vccint=997mv th=85C over=0 sane=1 osd=61C gpio=0x61`；`board_verify_console.txt:61` = `ok   V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`。⚠ 电池里那 4 条逐条 `degC` 值我没有单独落盘的件（本版只有 `r118_serial_raw.txt` 那 2 条被跟踪的原始回显），所以"4 条"这句话我能引、逐条数值我不能引——这一点写进第 4 节欠账。
- 判定：PASS

### S11 时序读数与文档一致（全设计 WNS / WHS / 失败端点）

- 观察项：`build/timing_summary.rpt` 的三项读数是否等于首页与指标表现在念的那三个数。
- 前置状态（含回读到的值）：报告 `Design Timing Summary` 表体回读 `0.739 / 0.000 / 0 / 51135 / 0.052 / 0.000 / 0 / 51135 / 0.264 / … / 0 / 12634`。
- 具体动作：`sed -n '145,151p' build/timing_summary.rpt`；再跑 `node src/host/metric_recheck.mjs`（它把这三个数对回 `data/metrics.csv` 与两份首页）。
- 我看到/读到的原文：`build/timing_summary.rpt:150` = `      0.739        0.000                      0                51135        0.052        0.000                      0                51135        0.264        0.000                       0                 12634`；`:152` = `All user specified timing constraints are met.`；`metric_recheck` 汇总行（我今天跑的那一份，件 `build/evidence/p16c/metric_recheck_before.txt:71`）= `== 数字对账：判 114 个数（首页层 60 个／解析到 10/10 行；红 0）／csv 认领 10/10 行／其余 18 行不点名这三份报告 ==`。⚠ 那句 `All user specified timing constraints are met.` 与本仓库自己的口径不一致：`data/metrics.csv:6` 明写"收口 I/O 的 5 个端点当前无输入窗 = 未检查（H5：未检查不等于满足）"，所以这行工具话**不**当"收口已过"用。
- 判定：PASS

### S12 资源读数与文档一致（LUT / FF / BRAM / DSP）

- 观察项：`build/utilization.rpt` 的四项占用是否等于首页与指标表念的数。
- 前置状态（含回读到的值）：回读 `| Slice LUTs | 14154 | … | 53200 | 26.61 |`、`| Slice Registers | 8188 | … | 106400 | 7.70 |`、`| Block RAM Tile | 95.5 | … | 140 | 68.21 |`、`| DSPs | 19 | … | 220 | 8.64 |`。
- 具体动作：`grep -n "^| Slice LUTs\|^| Slice Registers\|^| Block RAM Tile\|^| DSPs" build/utilization.rpt`；同一批数由 `metric_recheck` 的 `fromUtil()` 读回并比对（S11 的汇总行）。
- 我看到/读到的原文：`build/utilization.rpt:35,40,106,121` = `| Slice LUTs                 | 14154 |     0 |          0 |     53200 | 26.61 |`、`| Slice Registers            |  8188 |     0 |          0 |    106400 |  7.70 |`、`| Block RAM Tile    | 95.5 |     0 |          0 |       140 | 68.21 |`、`| DSPs           |   19 |     0 |          0 |       220 |  8.64 |`。⚠ `board/ACCEPTANCE.md:24,41,59` 三行历史读数把 BRAM 念成 `95 tile`，本版报告的那一格是 `95.5`——口径差在半块瓦片，不是回归。
- 判定：PASS

### S13 功耗读数（含"置信度 Low"这句必须一起念）

- 观察项：`build/power.rpt` 的动态功耗与估算结温是否等于文档念的数，且置信度那格是否如实。
- 前置状态（含回读到的值）：报告头回读 `| Device : xc7z020clg484-2 |`、`| Design State : routed |`、`| Process : typical |`、`| Date : Sun Oct  4 04:37:48 2026 |`。
- 具体动作：`sed -n '1,14p;30,45p' build/power.rpt`。
- 我看到/读到的原文：`build/power.rpt:36` = `| Dynamic (W)              | 2.213        |`；`:39` = `| Junction Temperature (C) | 52.6         |`；`:40` = `| Confidence Level         | Low          |`；`:38` = `| Max Ambient (C)          | 57.4         |`；`:42` = `| Simulation Activity File | ---          |`。⚠ `data/metrics.csv:28` 那行写 `Max Ambient 57.5 ℃` 而报告现在印的是 **57.4**：这一格不在 `metric_recheck` 的射程里（它只取 `Dynamic (W)` 与 `Junction Temperature (C)`），所以没人回头读它 ⇒ 记为文档差异，见第 4 节。
- 判定：PASS

### S14 时钟结构判据（#57：收口只有一棵时钟树，不靠 slack 碰运气）

- 观察项：`build/clock_util.rpt` 里 `BUFIO` 用量与 `BUFGCTRL` 用量是否等于文档念的两个数。
- 前置状态（含回读到的值）：`board/ACCEPTANCE.md:25,42` 记的历史口径 = `BUFIO 0`、`BUFGCTRL 8`；本版件 `build/clock_util.rpt` 由 r118 那一次构建产出。
- 具体动作：`grep -n "BUFIO\|BUFGCTRL" build/clock_util.rpt` 读第 43/45 行；再读 `:61` 那一行确认 `eth_rxc` 只经一只 `BUFG/O`。
- 我看到/读到的原文：`build/clock_util.rpt:43` = `| BUFGCTRL |    8 |        32 |   0 |            0 |      0 |`；`:45` = `| BUFIO    |    0 |        16 |   0 |            0 |      0 |`；`:61` = `| g2        | src2      | BUFG/O          | None       | BUFGCTRL_X0Y1  | n/a          |                 5 |        2544 |               1 |        8.000 | eth_rxc    | …`。⚠ `ACCEPTANCE.md:25`（r94 行）把 `eth_rxc` 的 fabric 负载念成 **2478**，本版这一格是 **2544**：那是逐轮读数、不是同一轮，我不当回归念，也不把 2478 当本版读数用。
- 判定：PASS

### S15 整屏逐像素台架（判据条数与那条故意留红的 C5c）

- 观察项：`build/tb_v98_report.txt` 现在数得出多少条判定、唯一的 FAIL 是不是声明过的那条。
- 前置状态（含回读到的值）：文件第 1 行 provenance 回读 `top_md5=56c269602e18 tb_md5=1c918c92200f rtl_md5=07570b1ac1b4 date=2026-10-04T01:47:53+08:00`。
- 具体动作：`grep -c "^PASS" build/tb_v98_report.txt`、`grep -c "^FAIL" build/tb_v98_report.txt`、`grep -n "^FAIL" build/tb_v98_report.txt`。
- 我看到/读到的原文：命中数 = **161 行 PASS + 1 行 FAIL = 162 条判定**；`:55` = `FAIL C5c frame head is not the previous frame's tail | first OFF+BILIN output rows must carry their own source row on BOTH sides of the seam`。⚠ **`data/metrics.csv:15` 那一行还写着 `141`（并自述"141 = `^PASS` 行数 140 加 `^FAIL` 行数 1"，provenance 点名 `top_md5=2bf2ceeede07`）**——它点名的就是这份文件，而文件已经不是那一次跑的。这一格不在 `metric_recheck` 射程里，所以尺子不红，但它是**指标表与报告不同源**的一条实物证据 ⇒ 进第 4 节与问题清单第 2 轮 Q4，我不改 `data/metrics.csv`。
- 判定：PASS（唯一 FAIL 是声明过的 C5c；`report/KNOWN_ISSUES.md` 第 1 节把它写成对外口径，故意留红不掩盖）

### S16 门禁一把跑（项数、绿/红计数、红项是不是只有声明过的那条）

- 观察项：`bash build/gates.sh` 在 r118 上判多少项、几绿几红、红的是不是只有 C5c 那一项。
- 前置状态（含回读到的值）：刷板前那一次门禁回读 `build/evidence/r118_board/BOARD_NOW.txt:3` = `刷板前那一次门禁：绿=21 红=3（其中 2 条是文档时效，改口后由最终两跑复验）`。
- 具体动作：读 `build/r118_gates.txt` 的第 34 行（唯一 FAIL 项）与第 53/54 行（范围句与结论句）；再读 `build/evidence/r118_board/gatesd_summary.txt` 那两行定版汇总。
- 我看到/读到的原文：`build/r118_gates.txt:34` = `  顶层台架 tb_v98    top=56c269602e18 FAIL行=1 指纹(norm1):fresh fresh fresh 同一次跑且无 FAIL      FAIL`；`:53` = `…# 结尾必须把**范围**一起念出来：判定 24 项、未判 0 项。`；`:54` = `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；`gatesd_summary.txt:1-2` = `GATESD done id=identical green=23 red=1` + 同一条 tb_v98 FAIL。⚠ `build/gates.sh:582` 是那句结论的出处——**只要有任何红项就固定打印"不采纳，保留上一版"**，而板上跑的确实是 r118（S1、S3）。所以那半句是脚本的红项语，不是一次"板子退回上一版"的动作；这个反差进问题清单第 2 轮 Q5。本条观察项判的是"门禁跑完并点名了项数与唯一红项"，成立。
- 判定：PASS

### S17 数字对账尺子（metrics.csv / 两份首页 ↔ 三份报告）

- 观察项：`data/metrics.csv` 与两份首页里点名那三份报告的每个数，是否都等于报告现在的值。
- 前置状态（含回读到的值）：S11/S12/S13 的三份报告读数；`data/metrics.csv` 未被我改动（我只新建 `docs/measurements.md`）。
- 具体动作：`node src/host/metric_recheck.mjs`（正跑）与 `node src/host/metric_recheck.mjs --self`（反例必须红）。
- 我看到/读到的原文：`build/evidence/p16c/metric_recheck_before.txt` = `OK` 行 **70** 条、`RED` 行 **0** 条、`rc=0`，汇总行见 S11。⚠ 同一把尺子在**我写完四份文档之后**重跑变成 `判 86 个数（首页层 32 个／解析到 6/10 行；红 4）… rc=1`（件 `build/evidence/p16c/metric_recheck_after.txt`），四条红全是 `RED row=README.md 里找不到「…」这一行`；`metric_recheck` 从不打开我这几份文档（它只读 `data/metrics.csv` + 三份 `.rpt` + 两份 `README`），红因是 `README.md` 在两次跑之间被别的写入者重写 ⇒ 这一条 PASS 的读数时刻已在第 4 节 L14 钉死。
- 判定：PASS（三个时刻都读过：会话开始 判 114／红 0／`rc=0`；写完四份文档后 判 86／红 4／`rc=1`；收尾重跑 判 117／红 0／`rc=0`，`OK` 行 73 条（件 `build/evidence/p16c/metric_recheck_final2.txt`）。中间那 4 条红的成因与归属见 L14）

### S18 #170/#171 的板级 abort 注入（拷贝中途被看门狗打断后撕裂帧不再显示）

- 观察项：板级这一格在 r118 上有没有做过。
- 前置状态（含回读到的值）：S7 的两次带流读数里 `flags_bits.abort_seen = "1"`（那一次会话里确实被置起过），但没有任何一份 r118 件把"注入 abort → 再读 `eth_ready`/撕裂帧显示"写成一次判据运行。
- 具体动作：在 `build/evidence/` 全树找点名 r118 的 abort 注入件（`grep -rl "abort" build/evidence/r118_board build/evidence/r118_eyes`）。
- 我看到/读到的原文：`board/ACCEPTANCE.md:44-46`（r96 那一节末尾）= `**r96 这一版还欠两格，不打勾**：① #170/#171 的**板级**形态…模块级凭据齐而板级这一格空着`；`:61`（r97 那一节）重复同一句欠账。我在 v118 的两个证据目录里没有读到任何"注入 + 复看显示"的判定件。
- 判定：NOT_MEASURED

### S19 OSD `FPS:` 那一格的机器那一半（`tb_shown_rate` 与变异对照）

- 观察项：屏幕刷新率那一格改成"数写进屏的新帧"这件事，机器那一半有没有凭据。
- 前置状态（含回读到的值）：`board/ACCEPTANCE.md:91` 记的件是 `build/r99_tb_shown_rate_console.txt` 与 `build/mut_shown_rate_r97.txt`（两份都还在盘上）。
- 具体动作：`grep -c "^PASS\|^FAIL" build/r99_tb_shown_rate_console.txt`；或复跑 `bash sim/run_one.sh tb_shown_rate`（跑法见 `report/BUILD.md`）。
- 我看到/读到的原文：`board/ACCEPTANCE.md:91` = `RESULT tb_shown_rate PASS（13 条判据、0 FAIL，控制台 build/r99_tb_shown_rate_console.txt）`——那是 **r99 那一棵树**上的重跑；r118 树上我没有重跑过这一支台架。
- 判定：PASS（读数属 r99，本版未重跑，已在 measurements.md 逐轮列出）

## 2. 眼睛判据（机器判不了；只引队员原话 + 时间 + 当时状态）

> 记法照 `board/ACCEPTANCE.md` 的"要肉眼确认的"那一节：谁的哪句话、什么时候、当时板上是哪一块。
> 引号里的就是原件里的字。没有原话的格子一律 `NOT_MEASURED`，我不代签。

### E1 分割线以左是原画面、以右是同一帧的处理结果，两侧几何一致

- 观察项：50/50 分区下左右两侧的同一物体是否对得上（不左右错开、不上下错位）。
- 前置状态（含回读到的值）：`build/evidence/r92_eye_capture2.txt:3` 回读 `[STAT] ctrl thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 pub=0 sd=1 frames=4398 playing=1 … geom=40400000 osd=1`；`:12` 回读 `[SPLIT] 50% -> pos=512/1024（显示列；manual；屏上 Split 格应显示 50%）`；`:15` 回读 `[SPLIT] marker=0（那条 2 像素蓝线）`；`:17` 回读 `[SPLIT] pos=512/1024（显示列） = 50% manual marker=off`。
- 具体动作：双击 `send_demo.bat` 推流 → 串口依次 `split manual`、`split 50`、`split marker 0`、`split show`，然后**同屏一次看两侧**（不是分次切换），看的前提是 `split show` 回显 `marker=off`。
- 我看到/读到的原文：`board/ACCEPTANCE.md:69` 的"结果"列 = `**过（2026-09-30 06:2x，在场的人原话"现在都很正常"）**：右半的白线与红块和左半对得上`。板上那一刻是 **r92**，本版 r118 我没有把这一格重判过（眼睛项我不能自己判）。
- 判定：PASS（签收人=在场队员，时间 2026-09-30 06:2x，版本 r92；r118 未重判）

### E2 缩放 + 自动旋转时不出现整行错位、画面不出屏

- 观察项：`zoom 0.5` + `rot auto 1` 下，屏上有没有整行错位、有没有左右错开的水平界线。
- 前置状态（含回读到的值）：`board/ACCEPTANCE.md:70` 记 r93 那两次的状态回读件 `build/evidence/r93_e2b_capture.txt`、`build/evidence/r93_ab_state_capture.txt`；10-01 那一次的状态件是 `build/r95_eye_park.txt`（末态 `geom=00400A00` ⇒ rot auto=1、speed=2、fit=0）。
- 具体动作：`split 50` + `split marker 0`（关掉辅助叠加层才好判）→ `zoom 0.5` → `rot auto 1`；对照做法是**只改推流节奏**（25 fps ↔ 29.76 fps 各看一遍同一格）。
- 我看到/读到的原文：`board/ACCEPTANCE.md:70` = `**过（2026-09-30 06:5x–07:0x，在场的人原话"现在画面正常只有一条"）**`；同格另引 2026-10-01 22:1x 那句 = `1 rot 在走 zoom 是 0.52 没有 3 没有`，且该格自己写明 `0.52` 这个数字**我在屏上找不到能显示它的格子**（`Rot:` 印十进制度数、`Zoom:` 只有八档标签）⇒ 它不当倍率读数用；问"有没有整行错位/沿角度的细鬼影"答**没有**，问"`split 50` 缝两侧同一行有没有上下错开"答**没有**。该格还如实留了两条限定：① 当时标记线有没有关没问到 ⇒"缝两侧"那一判是在标记状态未证下给的；② #189 的发生率台架量到 ≈0.27 % ⇒ 这一格"过"的意义是"没看到错位"，不是"逐行验过"（逐行那部分靠 `sim/tb_zoom_frac.v` 的 S1/S2/S3，件 `build/r103_tb_zoom_frac.txt`）。
- 判定：PASS（签收人=在场队员，时间 2026-09-30 06:5x–07:0x 与 2026-10-01 22:1x，版本 r92/r93 与 r103；带上面两条限定）

### E3 移动白线与红块连续、无撕裂

- 观察项：内置测试图每帧都在动，动的时候有没有撕裂/断线。
- 前置状态（含回读到的值）：同 E1（`build/evidence/r92_eye_capture2.txt` 的 `src=1`、`pos=512/1024`、`marker=off`、`zsel=4` 那一组回读）。
- 具体动作：`send_demo.bat` 推流（测试图每帧都动），盯着右半的白线与红块看一段。
- 我看到/读到的原文：`board/ACCEPTANCE.md:71` 的"结果"列 = `**过（同上，原话"现在都很正常"）**`，"同上"指向 E1 那一组屏上状态回读。板上那一刻是 r92。
- 判定：PASS（签收人=在场队员，时间 2026-09-30 06:2x，版本 r92；r118 未重判）

### E4a 旋转 + 拟合时四个角不戳出屏幕（45°/60° 那一半）

- 观察项：`rot auto` 走到 45°/60° 档时，整幅画面的四个角是否都在屏内。
- 前置状态（含回读到的值）：板上 = r118（S1 的 `cd04907e1369`）；判法要求的那一态由 `board/ACCEPTANCE.md:72-75` 那左列钉出：`src 2` + `bilin on` + 手动 `zoom 1.0` + `zoom fit 0` + `rot auto 1 speed 0`，屏已摆在 `build/r95_eye_park.txt` 记的末态 `geom=00400A00`（rot auto=1、speed=2、fit=0，画面正在走）；要停住判四角就串口 `rot auto 0` 冻在**当前角度**，**看屏上 `ROT:` 那一格**，再按 KEY1/KEY2 走 ±1°。
- 具体动作：如上设态 → `rot auto 0` 冻角 → 只看四角在不在屏内（左缘那一半是 E4b，分开问）。
- 我看到/读到的原文：`board/ACCEPTANCE.md:76` = `**过（"四角在不在屏内"这一半 2026-10-04 08:3x 由队员判完，原话「现在屏幕没问题了四角都在屏幕内」**；板上 r118，bit `cd04907e1369`，判法就是本行左列那套：`src 2` 图卡 + `zoom fit` + `rot auto` 走到 45/60 档看四角）`。机器那一侧的旁证：`build/r104_tb_zoom_fit_corners_console.txt`（0/30/45/60/90/270 六档 4/4 命中，`board/ACCEPTANCE.md:76` 已排除项①）。
- 判定：PASS（签收人=队员，时间 2026-10-04 08:3x，版本 r118）

### E4b 左缘不再有沿对角的宽彩条与细线

- 观察项：斜角冻住时，画面左缘有没有沿对角方向的宽彩条/细线。
- 前置状态（含回读到的值）：态与 E4a 同一套（`build/r95_eye_park.txt` 末态 `geom=00400A00`）；`board/ACCEPTANCE.md:76` 那一格的 2026-10-02 段还记着末态收回文档默认档的回读 `zsel=4 zman=1 bilin=1 geom=00400000`，件 `build/evidence/r104_rotfringe_state.txt`。
- 具体动作：`rot auto 0` 冻在 45°/60°，只看左缘那一列带。
- 我看到/读到的原文：`board/ACCEPTANCE.md:76-77` 里这一半的句子仍是未判口径 = `**这一格原本那半仍未判**（45°/60° 时四角在不在屏内、左缘有没有沿对角的宽彩条）`——同一格里"四角"那一半已被 08:3x 的原话判掉，"左缘"这一半**没有任何队员原话**；我在 `report/log/ISSUES.md` 也没搜到针对左缘彩条的回答句（唯一相关的是 `:10133` 那条"眼睛路径"的设态串，不是读数）。⚠ 顺带记一句原件形状问题：`ACCEPTANCE.md:76` 内部同时并存"四角…过（08:3x）"与"这一格原本那半仍未判（含四角）"两句，我没有改它的权限，也不替它选一句。
- 判定：NOT_MEASURED

### E4c 旋转时屏幕顶部的碎影（归到 C5c 帧头窗）

- 观察项：自动旋转时屏顶那一条里有没有角内容向左右分散的碎影。
- 前置状态（含回读到的值）：`src 2` + `bilin on` + `zoom fit` 随 `rot auto 1` 一起开，末态 `rot show` 回读 `auto=1 speed=0`；我扫的速度档序列 1→2→4→6→7→6→4→2→1→0（07:52:53–07:54:38，每档约 7 秒）；逐格凭据 `build/evidence/r104_c5head_band.txt`（错的 8 格全在最上面 6 个显示行，本体行一格都不错）；末态回读 `build/evidence/r104_rotfringe_state.txt`。
- 具体动作：队员只看两件事并各答一句：碎影是不是只贴在屏幕最上面那一条（约 6 行以内）、我扫的那轮 `rot speed` 里它随不随速度变宽变乱。
- 我看到/读到的原文：`board/ACCEPTANCE.md:76` 逐字记的用户原话 = 「我看到旋转的视频四个角划过屏幕上面时角周围会有一些向左右分散的同视频角内容一样的颜色在顶部周围」，三条补充 = 「bilinoff 还在，四个角都有，我是开始 rot auto 看到的现象」「停住的时候没有」「bilin on 的时候比较明显，off 的时候几乎看不到」；08:0x 两条回答 = 「角在顶部的时候才会有」「没有，跟速度看不出差」（同一批原话在 `report/log/ISSUES.md:10044-10045,10080-10081`）。板上那一刻是 **r104**（bit `680f38f5794c`，见 `build/evidence/r104_temp_lines.txt:1`）。
- 判定：PASS（这条判的是"现象归属已答且与逐格凭据对得上"，不是"缺陷已修"；缺陷本身仍红在 `C5c`，见 S15 与 `report/KNOWN_ISSUES.md` 第 1 节）

### E4r `rot auto 1 speed 0`（角度停住）时顶部是否还有细线

- 观察项：把每帧角度步数钉成 0，顶部那条还存不存在。
- 前置状态（含回读到的值）：板上 = r108，bit `25bf35a9900e`（`board/ACCEPTANCE.md:78` 同一行点名）；设态由我驱动串口完成。
- 具体动作：`rot auto 1 speed 0`（角度停住）看顶部；再 `rot auto 1 speed 2` 看它是不是只贴在最上面几行。
- 我看到/读到的原文：`board/ACCEPTANCE.md:78` 的结果列 = `**已答（2026-10-02 21:5x，板上 r108，bit 25bf35a9900e）：`speed 0` 角度停住时顶部干净，动起来才有 ⇒ 这是「每帧换角 × 帧头 6 行」的交互，不是纯帧头绕回**`。⚠ 那是 ACCEPTANCE 的**记录句**，不是逐字引号里的队员话；它的逐字对应句是 E4c 那两条「停住的时候没有」「角在顶部的时候才会有」。第二个问题（"是不是只贴在**最上面几行**"）我没有在原件里找到针对"行数"这一维的逐字回答 ⇒ 只判第一问。
- 判定：PASS（第一问；第二问记 NOT_MEASURED，见 E4b 同一族的欠账）

### E5 OSD 的 `FPS:` 那一格数的是写进屏的新帧

- 观察项：同一块板上，15 fps / 30 fps / 图卡三档在屏上是否分别读 ≈15 / ≈30 / ≈59（旧版 r97 三档都读 59/60）。
- 前置状态（含回读到的值）：串口 `src 1` 钉住网络那一路；上位机 `python src/host/video_sender.py --demo --fps 15`（再换 `--fps 30`），最后 `src 0` 钉图卡。⚠ 这一格**只能看屏**：`board/ACCEPTANCE.md:84-85` 明写"串口既没有 `[LINK]` 回包也没有 `FPS` 的数字回读（`src/ps/main.c` 里没有任何 fps 读者，实测 grep）"。机器那一半见 S19。
- 具体动作：三档各看屏 L0 那一格一次，档间只换推流参数与 `src`，不动别的。
- 我看到/读到的原文：`board/ACCEPTANCE.md:86` = `**过**（用户 2026-10-01 15:3x 在 **r101** 上目视三档，原话"第一个我看了和你说的都符合"；`；同一句在 `report/log/ISSUES.md:8984-8985` 记成 = `E5 闭合：三档（--fps 15 / --fps 30 / src 0 图卡）用户在 **r101** 上目视，原话"**第一个我看了和你说的都符合**" ⇒ board/ACCEPTANCE.md 的 E5 行由"待队员判"改"过"`。⚠ 原话字面只点名"**第一个**"，两句记录句都写"三档目视/闭合"——这差别我不能替队员定，已进问题清单第 1 轮 Q2。板上那一刻是 r101，不是本版 r118。
- 判定：PASS（签收人=队员，时间 2026-10-01 15:3x，版本 r101；三档射程待确认）

### E6 冷上电那一度：屏上 `ROT:` 那一格应当读 0

- 观察项：断电重上电、只跑三步 JTAG 链、全程不碰按键之后，屏第二行 `ROT:` 读几度。
- 前置状态（含回读到的值）：板子断电 ≥10 s 冷上电；`build/evidence/r118_eyes/STATE.txt:8-10` 记三步 `rc=0` 与各自的原文读数（`DDR_ECHO 10000000: 5A5AA5A5` / `PROGRAMMED xc7z020_1 <- build/system.bit` / `DOW ok`）；`STATE.txt:16-17` 记刷进去的位流 `md5sum build/system.bit = cd04907e1369da35d21c4090d552f5ee == build/evidence/r118_bit/system.bit`；`uart_stat.txt:1` 与 `uart_stat2.txt:1-2` 回读 `… osd=1`（`STATE.txt:18-20` 解释这一位为什么重要：OSD 叠加开着，`ROT:` 那一格才会被画出来）。
- 具体动作：按 `board/ACCEPTANCE.md:94-97` 写好的前置走一遍（断电 ≥10 s → 只跑 `ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl` → 全程不碰 KEY1/KEY2），然后**只看屏第二行 `ROT:` 那一格**（串口读不到角度，见 `report/log/ISSUES.md:11816-11818`）。
- 我看到/读到的原文：`board/ACCEPTANCE.md:98` = `**过（2026-10-04 07:52 前，队员原话「0度」）**；条件按本节前置逐条满足…`；同一句在 `report/log/ISSUES.md:13092` 记成 = `队员 2026-10-04 07:5x 在 r118 上判，原话「0度」`；更早一次（板上 r113，bit `b94f4da6cdff`）的原话是 `report/log/ISSUES.md:11812` = `**原话**：「是0已经修复了」`。
- 判定：PASS（签收人=队员，时间 2026-10-04 07:5x，版本 r118；机器那一半的网表实测 `build/evidence/r113_ff_init_probe.txt` + 判定 `build/r113_powup_rejudge.txt`）

### E6b 对照组：上电后按住 KEY1 直到链跑完，那一读应当是 1 度

- 观察项：武装门是否真把"配置那一刻的手按"吞掉。
- 前置状态（含回读到的值）：需要**再断一次电**（≥10 s），其余前置与 E6 相同；这一步我在无人值守下不能做（不驱动串口、不碰板子）。
- 具体动作：上电后先按住 KEY1 不放，直到三步链跑完再松手，看屏 `ROT:`。
- 我看到/读到的原文：`board/ACCEPTANCE.md:98` 末尾 = `**对照那一半仍未做**：上电后按住 KEY1 到链子跑完再松手、那一读应当是 1 度——它需要你再断一次电，所以这一条只登记"未判"，不写成过`；`report/log/ISSUES.md:13094` 同一句 = `对照组（上电后按住 KEY1 到链跑完，应当读 1）仍未做`。没有任何原话。
- 判定：NOT_MEASURED

## 3. 历史轮次的机器判据（只登记，不覆盖、不当本版用）

`board/ACCEPTANCE.md` 是**按行记版本**的（`:8-12` 明写"把某一行的数当这一版验过之前，先看这一行有没有 r94 字样"）。
这份文件的第 1 节全部点名 r118 的件；下面这几条只有历史轮的件，逐轮的数在 `docs/measurements.md` 里全列，
不挑最好的一行（P16c 铁律 6）：

| 判据 | 哪一版 | 读数出处（原件行） | 本版是否重跑 |
|---|---|---|---|
| 三步刷板链 | r94 / r96 / r97 | `ACCEPTANCE.md:16,36,54` | 是，见 S2 |
| 串口命令电池 100 → 105 条 | r94 / r96 / r97 | `ACCEPTANCE.md:17,37,55` | 是，见 S4 |
| 几何最后一跳 ok=8 → ok=10 | r94 / r97 / r118 | `ACCEPTANCE.md:18,56` | 是，见 S5 |
| 以太推流链路健康 | r94 | `ACCEPTANCE.md:20` | **否**，本版带流那一读见 S7（不同判据、不同工况：r94 是 25 fps 演示推流，S7 是 60 fps 不限速 ≈147 Mbps） |
| 链路内时延同源一致 | r92 | `ACCEPTANCE.md:21` | 是，见 S9 |
| 时序/资源/功耗 | r94 / r96 / r97 | `ACCEPTANCE.md:24,41,59` | 是，见 S11/S12/S13 |
| 时钟结构（BUFIO/BUFGCTRL） | r94 / r96 | `ACCEPTANCE.md:25,42` | 部分：本版重读 `BUFIO=0/BUFGCTRL=8`，**没有**逐条重读"最差 20 条 hold 偏斜"（`ACCEPTANCE.md:42` 自己就这么写的），所以那一半是 NOT_MEASURED（见第 4 节） |
| SD 本地播放帧率 | r87 | `ACCEPTANCE.md:23` | 本版只读到 `sd=1 … playing=1`（`uart_stat.txt:1`），滑窗 fps 数没重取 ⇒ 见第 4 节 |

## 4. 欠账与红项的后续（每条都有归属，不留悬空）

| # | 欠的那格 | 判定 | 后续（三选一：修 / 判为误报并给依据 / 交裁决） |
|---|---|---|---|
| L1 | S8 空闲态 `drop_words=0` 是零样本 | NOT_MEASURED | **修**：S7 那两次带流读数已经把同一判据作实了；这一条不是设计缺陷，是记录口径，处理方式=只按 S7 念，S8 永远不升 PASS |
| L2 | E4b 左缘沿对角的宽彩条 | NOT_MEASURED | **交裁决**：要队员的眼睛，问题清单第 1 轮 Q1 |
| L3 | E6b 按住 KEY1 的对照读数 | NOT_MEASURED | **交裁决**：要队员再断一次电，问题清单第 2 轮 Q6 |
| L4 | E4r 第二问"只贴在最上面几行"的逐字回答 | NOT_MEASURED | **交裁决**：问题清单第 3 轮 Q7 |
| L5 | E5 原话字面只覆盖"第一个" | PASS（限定） | **交裁决**：问题清单第 1 轮 Q2 |
| L6 | 最差 20 条 hold 时钟偏斜的逐条重读（r92 那一次的读法） | NOT_MEASURED | **修**：`build/hold_paths.rpt` 在盘上，重跑一次 `report_timing` 的逐条读法即可，不需要人 |
| L7 | SD 播放帧率的滑窗读数（本版） | NOT_MEASURED | **修**：`build/evidence/r87_boot_stat_drain.txt:4-5` 是 r87 的 `29.956 / 29.815 fps`；r118 只回读到 `sd=1 playing=1 frames=4398`（不随时间变化 ⇒ 上位机不在推流、SD 帧窗没在动），要重取需要板子在场 |
| L8 | `data/metrics.csv:15` 写 141 条而 `build/tb_v98_report.txt` 现在数出 162 条（provenance 也不同一串） | FAIL（文档同源，不是功能） | **交裁决**：`data/metrics.csv` 不在我的可改范围（禁区），问题清单第 2 轮 Q4 |
| L9 | `data/metrics.csv:14` 写门禁"22 项"而 `build/r118_gates.txt:53` 印"判定 24 项" | FAIL（文档同源，不是功能） | **交裁决**：同上，并进问题清单第 2 轮 Q4（同一族，一次问） |
| L10 | `data/metrics.csv:28` 写 `Max Ambient 57.5 ℃` 而 `build/power.rpt:38` 印 `57.4` | FAIL（文档同源，不在尺子射程） | **交裁决**：并进问题清单第 2 轮 Q4；顺带记一句：`metric_recheck` 的 `fromPower()` 不取这一格，所以它永远不会红 |
| L11 | `BOARD_NOW.txt:1` 的"刷入 04:49:50"与 `bitcycle_console.txt` 的 04:45:47→04:46:06 / `board_verify_console.txt` 的 04:47:07 差约 2 分钟，我没在件里读到 04:49:50 那次动作的日志 | NOT_MEASURED | **交裁决**：问题清单第 1 轮 Q3 |
| L12 | S10 里"4 条 `[TEMP]` 的逐条 degC"没有单独被跟踪件（本版只有 2 条原始回显） | PASS（判定）+ 射程不足 | **修**：`board_verify_console.txt:15` 的地板是 `[TEMP]=2`，而电池那句念"4 条"——两把地板不同；把电池的 4 条也 grep 成被跟踪件（`build/evidence/r113_temp_lines.txt` 那种写法）就是修法 |
| L13 | `#170/#171` 板级 abort 注入（S18） | NOT_MEASURED | **修**：需要 `--drop-packet` 注入 + 复看 `eth_ready`，机器能做，但无人值守下我不碰板子 |
| L14 | `data/metrics.csv` 之外的那把尺子在我这次会话**中途**变红过：会话开始 `判 114 个数…红 0`/`rc=0`（件 `build/evidence/p16c/metric_recheck_before.txt`）→ 写完四份文档后 `判 86 个数（首页层 32／解析到 6/10 行）…红 4`/`rc=1`（件 `metric_recheck_after.txt`、`metric_recheck_final.txt`），4 条红全是 `RED row=README.md 里找不到「全设计 setup WNS」这一行`一类的**首页形状**红 → 收尾重跑又回到 `判 117 个数（首页层 63／解析到 10/10 行）…红 0`/`rc=0`、`OK` 行 73 条（件 `metric_recheck_final2.txt`）| FAIL（中途那 4 条）→ 现为红 0 | **判为误报并给依据**（依据三条，全部可复跑）：①`metric_recheck` 一生只打开 `data/metrics.csv` + 三份 `.rpt` + `README.md` + `README.en.md`（`src/host/metric_recheck.mjs:50,73,86,211,287,289` 就是全部读文件入口），我新建的四份文档不在其射程；②被打开过的是 `README.md` 自己：会话开始时 14278 B / mtime 08:50 → 36822 B / 12:04 → 36980 B / 12:07 → 40683 B / 12:15 → 45715 B / 12:19（**到我这条为止它还在被改**）——**在我这两次跑之间被别的写入者连续重写**，我从未对它发起写；③同族尺子 `doc_currency_check` 的过期指路 106 → 132 → 135 条，**逐条出处里我这四份文档 = 0 条**（件 `build/evidence/p16c/doc_currency_final2.txt`；`DELIVERY` 名单 `src/host/doc_currency_check.mjs:175` 根本不含 `docs/` 与 `board/` 的非 README 文件）。`line_cite_check`（D5）与 `doc_enc_check` 在我写完四份文档后仍是 `D5: CLEAN 硬错 0`／`扫了 536 个手写文件：全部干净`，两支都 `rc=0`。⇒ 中途那 4 条红**不需要我改判据、也不需要我改首页**（两者都在禁区）；留给队里的只有一句话：确认 `README.md` 现在这版的行名是否要继续喂 `metric_recheck.mjs` 的 `FRONT` 名单（要改就是**加射程**，不许减地板）|
| L15 | 同一次并发重写之后，`docs/measurements.md` 第 5 节登记的三处"指标表 ↔ 报告不同源"里，`data/metrics.csv` 那一侧没变、**首页那一侧的数字与形状都可能已经不是我引用的那一版** | NOT_MEASURED | **修**：重跑 `node src/host/metric_recheck.mjs` 并把它点名的行号重新抄一遍（不需要人，只需要 `README.md` 停止变动） |

## 5. 三态计数与"PASS 必须有回读 + 证据"的自证

### 5.1 三态计数（分母 = 本文件五件齐全的观察项）

```
观察项分母 = 29 条（S1..S19 = 19 条机器判据 + E1/E2/E3/E4a/E4b/E4c/E4r/E5/E6/E6b = 10 条眼睛判据）
  PASS            25
  FAIL             0
  NOT_MEASURED     4   （S8 零样本、S18 板级 abort 注入、E4b 左缘彩条、E6b 按住 KEY1 对照）
第 4 节欠账表 = 15 行（L1..L15），其中 6 行是上面已计条目的"后续处置"（L1/L2/L3/L5/L12/L13，不重复计数），
  新登记的 9 行：NOT_MEASURED 6（L4/L6/L7/L11/L15 + L13 已计入 S18 的那半不算）／FAIL 3（L8/L9/L10）+ L14 FAIL 1
全表合计（含新登记的欠账）：PASS 25 / FAIL 4 / NOT_MEASURED 9
```

复跑核对命令（数本文件自己）：

```bash
grep -c '^### [SE]' board/signoff.md              # 条目数（只数 S/E 开头的观察项），实得 29
grep -c '^- 判定：PASS'           board/signoff.md  # 实得 25
grep -c '^- 判定：FAIL'           board/signoff.md  # 实得 0（grep 无命中，退出码非 0 是正常）
grep -c '^- 判定：NOT_MEASURED'   board/signoff.md  # 实得 4
for k in 观察项 前置状态 具体动作 我看到/读到的原文 判定; do printf "%s=%s\n" "$k" "$(grep -c "^- ${k}" board/signoff.md)"; done
```

### 5.2 被记为 PASS 但无回读或无证据的条目数 = **0**（这条是真核对，不是声明）

核对做法（机器可检，缺任一件就当场把该条改成 `NOT_MEASURED` 再重数）：

```bash
cd <仓库根>
# ① 五件齐全：五个字段的条数必须都等于条目数 29（实得见 5.1 的输出）
# ② 每条 PASS 的"前置状态"必须含回读值（数字或 key=value），"原文"必须点名一个带反引号的具体件：
awk '
BEGIN{np=0;b1=0;b2=0}
/^### /{if(id!=""&&ver ~ /PASS/){np++; if(pre !~ /[0-9=]/){b1++;print "NO-READBACK:" id} if(orig !~ /`/){b2++;print "NO-EVIDENCE:" id}} id=$0;pre="";orig="";ver=""}
/^- 前置状态/{pre=$0}
/^- 我看到\/读到的原文/{orig=$0}
/^- 判定/{ver=$0}
END{if(id!=""&&ver ~ /PASS/){np++; if(pre !~ /[0-9=]/){b1++;print "NO-READBACK:" id} if(orig !~ /`/){b2++;print "NO-EVIDENCE:" id}}
printf "PASS 条目=%d  缺回读=%d  缺点名件=%d\n", np,b1,b2}' board/signoff.md
# ③ 每条 PASS 的"原文"必须点名一个真实存在的件 + 行号或字段：把本文件点名的路径全量 test -f
grep -o '`[^`]*`' board/signoff.md | tr -d '`' | grep -E '^(build|board|data|src|sim|report)/' \
  | sed -E 's/:[0-9].*$//' | sort -u | while read -r p; do [ -f "$p" ] || echo "MISS $p"; done
```

实得：② = `PASS 条目=25  缺回读=0  缺点名件=0`；
③ = 逐条结果（点名/命中/A 真缺/B 写法/C 目录）列在件 build/evidence/p16c/evidence_existence.txt 里，
本文件不复述目录名——复述会把它们变成新的点名，清点就永远在数自己；**A 桶（真指路却不在盘上）= 0**。
⇒ **缺"前置回读"或"原文观察"的条目数 = 0；被记为 PASS 但无回读或无证据的条目数 = 0。**
尺子前后对照与"那 4 条首页红不是我造成的"的静态射程证据，整体落在 `build/evidence/p16c/rulers_before_after.txt`（见第 4 节 L14）。



## 6. 改进项登记（不占三态、不计功能红项）

- 测试图动画观感：`board/ACCEPTANCE.md:107` = `同一时间他还提了一句与判据无关的观感意见（测试图动画"太丑"）——记进任务，不当成红项，也不改动已经验完的那一块位流`。
  这条按 P16c 铁律 3 记为改进项。它指向的是画面素材，不是可判定的缺陷，所以**没有**对应判据。

## 7. 复看路径（下一批人怎么用这份文件）

1. 先确认板上是哪一版：`md5sum build/system.bit` 对 `build/evidence/r118_bit_md5.txt` 与 `board/ACCEPTANCE.md` E6 格的版本句。
2. 再确认这份文件里**每一条**点名的件还在：跑 `docs/acceptance-recipes.md` 第 R9 条（凭据存在性清点配方，一条命令）。
3. 换版本时**不覆盖本文件的历史条目**：照 `board/ACCEPTANCE.md:30-59` 那一族的写法，新开一节写"rNN 重跑的那几行"，
   原行留着当历史读数（`ACCEPTANCE.md:32` 的理由：`上表的原行**不覆盖**（留作历史读数）`）。
4. 需要眼睛的条目：**照抄第 2 节"具体动作"那一行去问，把回答逐字写进"原文"字段**，不要写"经确认无误"。

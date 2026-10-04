# 采集条件卡 · 软件算出侧与参考侧（卡 C1–C3、卡 D1）

本文件的"卡 N"是本文件内部编号（C 族 = 软件算出、D 族 = 参考侧），与同目录其它批次卡的编号无关。
**这一族全部不是板上读数**（P16b 铁律 2）：它们进"软件算出"那一栏，不许写进"硬件读出"。

---

## 卡 C1 · 顶层整屏台架 `build/tb_v98_report.txt`（逐像素判据）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | `sim/tb_v98*`（顶层整屏台架，自己给自己灌帧）；判据号 `C0a..C11` 与 `F*`/`G*` 系列 | `build/tb_v98_report.txt:1-12` 的 PASS 行文本 |
| 输入规格 | 台架内置图案（`C0a ruler encodes position in the pixel`、`C0a3 no black cell exists in the pattern`）——**不是 `data/inputs/` 的那些边界文件**，也不是 `data/golden/frame_640x360.mem` | `src/host/ddr_verify.mjs` 之外，台架侧无 golden 读取者（`data/golden/manifest.md` §6 第 4 条实测：没有任何仿真/板级台架读 `data/golden`） |
| 时钟与功耗模式 | 仿真时间基准（xsim 的 `$time`，1 ps 量级），**不是板上 50 MHz/125 MHz 真实时钟** ⇒ 与任何板级 ms 数不同口径 | `sim_work/*.vcd` 的 `$timescale 1ps`（见卡 C2） |
| 软件版本 | 件头自报 `fpver=norm1 top_md5=56c269602e18 tb_md5=1c918c92200f rtl_md5=07570b1ac1b4 date=2026-10-04T01:47:53+08:00 src=<仿真工作目录>/run.log` | `board/compare/tb98-count-vs-metrics-claim.txt` 第 6 行（原样抄） |
| 仪器量程 | 判据条数 = `^PASS` 行数 + `^FAIL` 行数（脚本数出来的，不是手抄）；本轮实测 **161 + 1 = 162**，唯一 FAIL 是 `C5c`（`:55`） | `board/compare/tb98-count-vs-metrics-claim.txt` |

**这格里有一条必须公开的"摘要不符"**：`data/metrics.csv:15` 的"整屏逐像素判据 = 141 条"点名的是
`top_md5=2bf2ceeede07 tb_md5=36d0de483e6d rtl_md5=8997a62b75ba` 那份台架件；
而 `grep -rl "^# provenance.*2bf2ceeede07" build | wc -l` 现在 = **0**（那份件已被 2026-10-04 01:47 那一跑覆盖）。
⇒ 按 P16b 铁律 6 与 P17 §7 第 3 条：**该基准摘要不符 ⇒ 报 `NOT_MEASURED`，不许继续用 141 这个数**，
也不许把 162 当成"141 变好了"（两次跑的 `rtl_md5` 不同，是两份不同的被测对象）。

`C5c` 那一行是**故意留红**的已声明缺陷（`build/evidence/r104_c5head_band.txt:7` 明写"判据号 C5c，
就是 `report/KNOWN_ISSUES.md` 第一节那条故意留红的判据"），逐格读数：
`judged=本体行 3564 格不符 0 ｜ head rows=帧头窗 36 格 不符 24`（同件 `:9`）。

---

## 卡 C2 · 仿真波形导出 `sim_work/*.vcd`（本仓库唯一的"波形件"）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | 各自测试bench（tb_eth_video / tb_rotate_window / tb_udp_parser / tb_udp_reasm / tb_v796_src_arb / tb_v80_ku5p_cmd / tb_v81_test_card） | 文件名即 tb 名 |
| 输入规格 | 逐 tb 内置，件内**不含**激励描述 ⇒ `【待补】`（每件对应哪份激励与哪一个 rNN 构建） | `$date` 段只给到 2026-09-27 18:5x |
| 时钟与功耗模式 | `$timescale 1ps`（仿真）；与板级时钟树无关 ⇒ `【待补】` 该 tb 里 `create_clock` 的周期设置 | `$timescale` 原文见卡内下方抽样 |
| 软件版本 | `$version 2025.2.1`（xsim 版本，件内自报） | 同左 |
| 仪器量程 | 时间粒度 1 ps；信号数 = `$var` 声明数；事件数 = 以 `#` 开头的时间戳行数 | `board/captures/index.md` 的复算命令（本轮实测：见下表） |

本轮实测（`grep -c` 现算，不手抄）：

| 件 | 字节 | 时间戳事件 | 声明信号数 | 可用作波形凭据？ |
| --- | --- | --- | --- | --- |
| `sim_work/tb_eth_video.vcd` | 96982 | 624 | 136 | 可（但只到 2026-09-27 那一版 RTL） |
| `sim_work/tb_rotate_window.vcd` | 158123 | 552 | 416 | 同上 |
| `sim_work/tb_udp_parser.vcd` | 20156 | 440 | 61 | 同上 |
| `sim_work/tb_udp_reasm.vcd` | 231453 | 4308 | 72 | 同上 |
| `sim_work/tb_v796_src_arb.vcd` | 178 | **0** | **0** | **否：`$dumpvars` 后为空 ⇒ 全空件** |
| `sim_work/tb_v80_ku5p_cmd.vcd` | 178 | **0** | **0** | **否：同上** |
| `sim_work/tb_v81_test_card.vcd` | 179 | **0** | **0** | **否：同上** |

⇒ 后三份是"波形容器存在但内容是空的"（只有 `$date/$version/$timescale/$enddefinitions/$dumpvars $end`）。
按 P00"把空值当通过是最严重的一类错误"，这三份在任何比对表里只能记 `NOT_MEASURED`，
**不能**记成"波形已采集"。

**本仓库没有**：板级截图/屏摄、逻辑分析仪导出、示波器截图 ⇒ `board/captures/` 里"屏幕证据"这一类是空的，
所以任何"屏上看起来对"的说法都没有可复核的图像凭据（见 `board/raw-vs-golden.md` 的失败分析一节）。

---

## 卡 C3 · 工具报告与时钟名册（`build/*.rpt`、`docs/timing/roster_*.tsv`）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | 不适用（静态时序分析/实现后报告，被测对象是 RTL+SDC，不是板子） | — |
| 输入规格 | 器件 `xc7z020clg484-2`；SDC 集合见 `src/constraints/` | `data/metrics.csv:2`（共用条件行） |
| 时钟与功耗模式 | 逐时钟周期来自名册 `period_ns` 列：8 / 10 / 20 / 20 / 4 / 5 / 20 / 20 ns 八个对象；本版**不带 RGMII 输入窗**（`data/metrics.csv:5` 明写，窗退回候选件 `VP_R116_IO_WINDOW=1` 可复现）；功耗档 `【待补】` | `docs/timing/roster_baseline.tsv:6-13`、`board/compare/roster-diff-baseline-vs-r116e1.txt` |
| 软件版本 | 报告 mtime 2026-10-04 04:37（`build/timing_summary.rpt`、`build/utilization.rpt`）⇒ 与 r118 位流同龄；`build/CDC_BASELINE.txt`/`build/frozen_r23_srcseen/cdc.rpt` 是 2026-09-25 的 r23 冻结件 | `stat` 实测（`board/logs/index.md` 表里带了日期列） |
| 仪器量程 | 时间余量分辨率 = 报告给的 3 位小数 ns；`rel_margin_*` 口径 = `wns_*/period_ns`（名册文件头第 2 行钉死）；hold 那一列**两把尺子**：只有 `eth_rxc` 带 `Clock Uncertainty 0.800`（`docs/timing/uncertainty_hold_ab.md`） | 名册头两行 + `build/clock_uncertainty.rpt` |

---

## 卡 D1 · 参考侧 `data/golden/`（13 个数据件 + manifest）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | 不适用（参考侧不是被激励跑出来的，是"期望值"） | `data/golden/manifest.md` §8 |
| 输入规格 | PNG：8 bit/通道 RGB、colortype=2、**640×360**（`dual_preview.png` 是 1280×360）；`.mem`：16 bit RGB565、640×360、行主序 230400 行、CRLF | `data/golden/manifest.md` §3 的"精度口径"列（实测 IHDR/长度） |
| 时钟与功耗模式 | **不适用**（合成件，与板级时钟无关） | 同上 |
| 软件版本 | **产生程序不在树里**（12 个 PNG + 1 个 `.mem` = 13 件全部指不到仓库内脚本）；最早可观察到的存在 = 首次入库 `fc314bb`（2026-09-18） | `data/golden/manifest.md` §8（含糊 13 行） |
| 仪器量程 | 无量化损失（RGB565 4 位十六进制小写）；但**与 PL 画幅不同口径**：板上处理画幅是 512×300，参考件是 640×360 | `board/README.md` 第 1 节（PL 处理画幅 512×300）、`manifest.md` §3 |

摘要核验（本轮重跑，不抽样）：`board/compare/golden-digest-verify.txt` ⇒ **13 行 OK、0 行 FAIL**；
双向差集核对：`磁盘 N=13 表里 N=13`，两个方向的差集都是 0 行。
⚠ 与 `data/golden/manifest.md` §5 里贴的那份输出（`磁盘 N=14 表里 N=14`）**不同数**；
本轮的 13/13 是现算的，§5 的 14/14 是那一份文件的登记日读数 ⇒ 这一处差额留给 P17 解释，我不改 `data/`（禁区）。

缺项后果：**"产生程序不在树里"这一格缺** ⇒ 任何"板上输出与 `data/golden/` 逐像素一致"的说法现在都不成立
（`manifest.md` §8 原话），要比就得先落地两件事之一：① 可复现的渲染脚本（Q-P04-1 / Q-P17-2），
② 一份与 512×300 同口径的板级抓帧件（现在仓库里没有：`data/measured/` 里的 DDR 回读是 **frameid/wordid 图案**，不是图卡内容）。

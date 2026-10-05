# 采集条件卡 · 板级串口 / JTAG 读数（卡 A1–A4）

每张卡五格（激励 / 输入规格 / 时钟与功耗模式 / 软件版本 / 仪器量程）+ 一行"缺它这行数字不能和谁比"。
卡里只登记**已在凭据件里读到的**内容；读不到的写 `【待补】`。
本卡引用的凭据件全部**只在原位置**（`build/`、`board/`），本目录不复制大文件。

---

## 卡 A1 · r118 板级机器验收（board_verify 一把跑）

| 格 | 值 | 凭据（文件:行） |
| --- | --- | --- |
| 激励 | `bash build/board_verify.sh --round=r118`：串口命令电池 105 条 + `geom_check` 10 条 + `health_read` lane0..9/23..31 + 原始串口回显抓取；**全程没有上位机推流** | `build/evidence/r118_board/board_verify_console.txt:36,63,66`；lane30 自报 `"why_no_stream":1,"why":"没有流"`（同件 :19） |
| 输入规格 | 无视频输入（图卡/SD/ETH 三路的 ETH 那一路无人推帧）；串口 115200-8N1，COM6 只读 | 同上件 :19（`src=1`＝PL 拥有 UDP 通路但没有流）；`build/evidence/r118_serial_raw.txt` 4 行原样 |
| 时钟与功耗模式 | 逐时钟周期取自本版名册：`eth_rxc` 8 ns、`clk_fpga_0` 10 ns、`sys_clk` 20 ns、`clkout0_1` 20 ns。功耗档（Zynk LP/HP 之类）**没有任何件自报** ⇒ `【待补】` | `report/timing/roster_baseline.tsv` 的 `period_ns` 列；`【待补】`：板上供电/功耗档读数在仓库内不存在 |
| 软件版本 | 位流 `md5=cd04907e`（2026-10-04 04:36）、`system.xsa md5=934ebdba`（04:37）、**`ps_app.elf md5=d0b07f84` 的时间戳是 2026-10-01 00:12** ⇒ PS 固件比 PL 位流旧三轮 | `board_verify_console.txt:4-6`（脚本自报的 md5 与 mtime） |
| 仪器量程 | ① JTAG（hw_server:3121 + xsdb `mrd`）读 GPIO_0/GPIO_1 与 DDR；② 板载 XADC：全码 0..65536 → −273.15 … 230.82 °C（端点已由脚本锚定）；③ 串口计数没有独立秒表可校 ⇒ 帧率类读数的时间基准 = 固件自己的 `cps_to_ms` | ① `src/host/health_read.mjs:6-12`；② `board/compare/temp-formula-check.txt`（`raw=0x0000 → −273.15`、`raw=0xFFFF → 230.82`）；③ `【待补】`（固件时基晶振精度无件可查） |

本轮读数（硬件读出，原样）：`RESULT PASS geom_check（ok=10 fail=0）`、`RESULT PASS uart_cmd_check (105 条命令, 97.9 s)`、
`RESULT board_verify PASS（判红的步骤：0）`、`drop_words → 0`、`lane23.inv_scale=256 / x100_actual=100`。

缺项后果：**功耗模式 `【待补】`** ⇒ 本轮 `drop_words=0` 不能与"换了供电/功耗档或超频"的任何一轮并列比；
elf 与 bit 不同龄 ⇒ 本轮的板级结论只能盖到"bit r118 + elf r101 组合"，不能写成"r118 全版验过"。

---

## 卡 A2 · r118 冷上电复判（ACCEPTANCE E6 那一格）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | 队员**断电 ≥10 s 冷上电**，之后只跑三步 JTAG 链 `ps_jtag_boot.tcl → program_pl.tcl → ps_app_reload.tcl`，全程不碰 KEY1/KEY2；随后只看屏第二行 `ROT:` 那一格 | `build/evidence/r118_eyes/state.txt:6-10`（逐步 rc 与 token）；判据条件原文 `board/acceptance.md:95-97` |
| 输入规格 | 无推流、无按键；只看屏 + 一次 `STAT` 串口只读 | `build/evidence/r118_eyes/uart_stat.txt:1` |
| 时钟与功耗模式 | 同卡 A1；上电态（`FDRE` 初值）是这一格的观察对象，r118 带 `ASYNC_REG` 放置指令（不改上电值的逻辑） | `board/acceptance.md:93`、`build/evidence/r113_ff_init_probe.txt`（`INIT=1'b1` 网表实测） |
| 软件版本 | 刷进 PL 的位流 `md5sum build/system.bit = cd04907e1369da35d21c4090d552f5ee`，与 `build/evidence/r118_bit/system.bit` 及 `board_now.txt` 的 r118 身份行一致 | `state.txt:12`、`build/evidence/r118_board/board_now.txt:1` |
| 仪器量程 | 三步链的 token 与 rc 是仪器级（xsdb 退出码 + `DDR_ECHO`/`PROGRAMMED`/`DOW`）；**屏上角度格没有第二支读者**：串口既无 `[LINK]` 回包也无角度数字回读 | `state.txt:7-10`（step1 `DDR_ECHO: 10000000: 5A5AA5A5`、step2 `PROGRAMMED xc7z020_1`、step3 `DOW ok / pc 00007cee`）；`board/acceptance.md:98` 明写"串口读不到角度，`status` 口那 9 位在 `system_top` 没有读者" |

同一天 07:39 的第一次尝试**失败**（异常前后原样，`state.txt:16-19`）：
```
# Note on the earlier refusal this morning: at 07:39 the same step1 died inside `targets -set 1`
# (hw_server's view of the chain was still stale right after the power cycle) and r116_bit_cycle.sh
# then printed "REFUSE DDR_ECHO 没过". The chain re-enumerated as 1=APU / 2=ARM#0 / 3=ARM#1 / 4=xc7z020
# (probe_target_select.tcl run, all selection forms rc=0) and step1 now passes unmodified.
```

队员的眼睛读数（`board/acceptance.md:93` 原话，2026-10-04 07:5x）：**「0度」**；更早一次（r113，2026-10-03 15:19）：**「是0已经修复了」**。
⇒ 这一读**属"人眼报告（无仪器证据）"**：`ROT:` 那一格没有任何仪器回读通道能复算它，所以它只进 `board/raw-vs-golden.md` 的失败/观察分析，
**不进比对表**。有仪器凭据的是"三步链 rc + DDR_ECHO + `[STAT] osd=1`"这一族（`state.txt`、`uart_stat.txt`）。
对照那一半（上电按住 KEY1，应读 1 度）**仍未做**（`acceptance.md:98` 自己登记为"未判"）。

缺项后果：**没有角度/倍率的仪器回读通道** ⇒ 屏上任何数字都不能与串口 `[STAT]`、lane23 之外的第三方对账；
要把它变成实测，缺的是"角度数字的读出口"（#247/#185 的 `status` 口读者），不是再多看一次屏。

---

## 卡 A3 · r116 板级刷板循环与上位机推流（含两份失败读数）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | `r116_bit_cycle.sh` 系：JTAG `rst -system` → 重下 elf → 刷 bit → 上位机推流；推流命令 `node src/host/video_sender.mjs`（`--demo`，512×300 RGB565 @60fps 节奏） | `build/evidence/r116_board/cycle_r116again.log:1-11`（时间戳 02:19:17–02:19:30，`RECOVER_BEGIN/DONE`）；`sender_live.log:1-2` |
| 输入规格 | 512×300 RGB565（307200 B/帧），目标 `192.168.1.10:5001`；`sender_live.log` 报 3001 帧 / 50.03 s = 59.98 fps / 663221 包；`sender_live2.log` 报 3601 帧 / 60.03 s = 59.99 fps / 795821 包 | `build/evidence/r116_board/sender_live.log`、`sender_live2.log`（两份都只有 2 行，且中文行是 GBK 字节，见下） |
| 时钟与功耗模式 | 同卡 A1（`eth_rxc` 8 ns 收包域是推流路径）；本轮是**有流**态，与卡 1 的**无流**态不可混用 | `report/timing/roster_baseline.tsv`；`cycle_r116again.log:10`（`TARGETS_AFTER` 列出 `4 xc7z020`） |
| 软件版本 | 这一段量的是 **r116**（bit `r116_bit`），后来被 r118 复刷覆盖；`acceptance.md:93` 明确"01:50 那次 PASS 与 02:14 那次带 147 Mbps 真实流量的两次重读量的是上一版 r116，件 `build/evidence/r116_board/`，**不给 r118 借用**" | `board/acceptance.md:93`、`build/evidence/r116_board/BOARD_NOW`（同族身份件） |
| 仪器量程 | 上位机侧：Node 计时（fps 由发送端自报，取样 50 s/60 s 两档）；板侧 lane 计数：JTAG `mrd` GPIO_1（32 bit） | `src/host/health_read.mjs:14-20`（lane 语义与"两遍读数只许单调"规则） |

两份**失败读数**必须一起登记（异常前后原样）：
```
[build/evidence/r116_board/health_live1.json:1-3，与 health_idle.json 逐字节相同（sha256 前 8 = 17f70555）]
[HEALTH] xsdb(cur) 退出码 1：Command failed: "xsdb.bat" <仓库路径>\data\measured\health_cur.tcl > ...
[HEALTH] 读不到 GPIO_0 的当前值，拒绝继续（否则会踩掉 src_sel/特效/阈值）。
[HEALTH] 先确认 JTAG 与 hw_server 可用：xsdb 里 mrd 0x41200000
```
⇒ 这两个文件名（`live`/`idle`）想表达的"两种状态下的读数"**没有成立**：两份内容是同一次失败的同一个字符串，
所以这一族 lane 读数按 `NOT_MEASURED` 处置，不许当成"两种状态都读到了同样的值"。

```
[build/evidence/r116_serial_raw.txt：2 字节、0 行 [TEMP]（地板 2）]
[board_verify.sh 的判据：`if [ "${SN_TEMP:-0}" -lt "$TEMP_FLOOR" ]` ⇒ 空捕获必须红（build/board_verify.sh:42,65-66）]
```
⇒ 这是一次**空捕获**（串口那 5 秒窗口没吃到 `[TEMP]`）。同目录的 `r116b_serial_raw.txt`（5 行、2×`[TEMP]`）是重抓的那一份。
另有一份纯空回显的留档：`build/evidence/no_echo_20260928_0142.txt`（发了 99 条命令、回显空）。

编码缺陷（同族的自伤，登记不回避）：`sender_live.log` / `sender_live2.log` 的中文行是按 GBK 字节写盘的，
在 UTF-8 下呈 `3001 ֡ / 50.03 s` 这类乱码 ⇒ **数字与单位仍可读**（都是 ASCII），但"帧/包"这两个汉字已丢；
今后同名件要显式定 ASCII 或 UTF-8（P23 §5 那条）。

---

## 卡 A4 · `build/evidence/rNN_serial_raw.txt` 家族与 0930 两份验收件

共同条件（**逐件差异列在下面**）：激励 = `board_verify.sh` 里"边听边抓"那一步（`--round=rNN`），
串口 115200-8N1、COM6 只读、抓取窗口 5 s；输入规格 = 当时上位机是否在推流**逐件不同**；
时钟/功耗模式 = 同卡 A1；软件版本 = 该 rNN 的 `build/system.bit` md5（认 md5 不认文件名，见 `board/README.md` 第 1 节）；
仪器量程 = 固件自打的 `[TEMP]`（XADC raw + 定点 degC + vccint mV）与 `[STAT]`（`src/host/ps/main.c` 的状态行）。

| 件 | 日期(mtime) | 行数 | [TEMP] | [STAT] | sha256 前 8 | 与别件能不能直接比 |
| --- | --- | --- | --- | --- | --- | --- |
| `build/evidence/r104_serial_raw.txt` | 2026-10-02 02:43 | 5 | 2 | 2 | `20463a0b` | 同条件可比（同一把尺子 TEMP_FLOOR=2） |
| `build/evidence/r106_serial_raw.txt` | 2026-10-02 14:59 | 5 | 2 | 2 | `64ae4d56` | 同上 |
| `build/evidence/r107_serial_raw.txt` | 2026-10-02 17:53 | 5 | 2 | 2 | `5c68e499` | 同上 |
| `build/evidence/r108_serial_raw.txt` | 2026-10-02 20:55 | 5 | 2 | 2 | `d207a0b6` | 同上 |
| `build/evidence/r109_serial_raw.txt` | 2026-10-03 02:12 | 5 | 2 | 2 | `947642bc` | 同上 |
| `build/evidence/r110_serial_raw.txt` | 2026-10-03 07:52 | 5 | 2 | 2 | `2cc053f2` | 同上 |
| `build/evidence/r113_serial_raw.txt` | 2026-10-03 14:36 | 5 | 2 | 2 | `8abaf849` | 同上 |
| `build/evidence/r114_serial_raw.txt` | 2026-10-03 21:32 | 5 | 2 | 2 | `44504ce6` | 同上 |
| `build/evidence/r116_serial_raw.txt` | 2026-10-04 01:38 | 1（**2 字节，空**） | **0** | **0** | `7eb70257` | **地板 2 未达 ⇒ 该件按 NOT_MEASURED 处置**，是失败件 |
| `build/evidence/r116b_serial_raw.txt` | 2026-10-04 01:50 | 5 | 2 | 2 | `c7b9bac1` | 同条件可比（r116 的重抓） |
| `build/evidence/r118_serial_raw.txt` | 2026-10-04 04:47 | 5 | 2 | 2 | `9f225141` | 可比；`board_verify_console.txt:15` 自报"行数=4 [TEMP]=2 判定=绿（地板 2）" |
| `build/evidence/verify_0930_1845.txt` | 2026-09-30 18:48 | 60 | 1 | 0 | `56da9851` | 与上一族**不同尺子**（那是 board_verify 全量控制台，不是原始逐字回显） |
| `build/evidence/verify_0930_2215.txt` | 2026-09-30 22:18 | 62 | 1 | 0 | `084c09c0` | 同上 |
| `board/uart_capture.txt（不随包）` | 2026-09-29 07:05 | 7 | 0 | 1 | `511b3e50` | 单条 `stat` 的手动抓取，窗口与轮次身份 `【待补】` |
| `board/uart_script_capture.txt`（本机原始捕获，不入库） | 2026-10-04 04:49 | 364 | 8 | 3 | `cc3c165a` | 105 条命令电池的原始捕获（r118 那一跑，`board_verify_console.txt:63` 点名它） |

注：`r116_serial_raw.txt` 的 sha256 前 8 这一轮**没有**单独复算（它只有 2 字节，登记行数以 `wc -c`=2 为准）；
需要摘要时按 `board/logs/index.md` 的复算命令跑即可。这一行是本目录里唯一一条"登记了但摘要未复算"的行，
所以它的判定 = `NOT_MEASURED`（缺摘要核验），不是 `PASS`。

缺项后果：`【待补】`＝每件的**当轮上位机是否在推流**没有写在件自己里（只有 `board_verify_console.txt` 那种控制台才带 lane30 的 `why` 字段）。
⇒ 同一温度格（`[TEMP] degC`）在"有流"与"无流"两种激励下是**两个口径**：r118 那一份是无流（`why_no_stream=1`），
`acceptance.md:58` 的 63.38/63.17/63.13 那一份是 r97 验收跑里有流的读数 ⇒ 两者相差约 2.5 ℃ 不能念成"芯片变凉了"。

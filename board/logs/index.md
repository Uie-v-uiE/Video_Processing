# `board/logs/` · 实测日志索引件（不复制大文件）

本目录只放**索引**：登记真实路径 + 采集日期 + 对应构建指纹 + 摘要 + 该件旁边是哪张采集条件卡。
每一件都还在原位置（`build/`、`board/`、`data/`），本仓库不允许改动它们（P00 铁律 6）。

复算命令（任一行都能一条命令验回来；`sha8` = `sha256sum` 前 8 位，`wc -l` = 行数）：

```bash
for f in <表里的路径>; do printf "%s | %s | lines=%s | sha8=%s\n" "$f" \
  "$(stat -c %y "$f" | cut -c1-16)" "$(wc -l < "$f")" "$(sha256sum "$f" | cut -c1-8)"; done
```

本轮登记日：2026-10-04（本机 `date`）。

## 1. 板级机器验收与控制台（硬件读出侧）

| # | 真实路径 | 日期(mtime) | 构建指纹 | 行数 | sha8 | 关键读数行（原样） | 条件卡 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L01 | `build/evidence/r118_board/board_verify_console.txt` | 2026-10-04 04:49 | bit `cd04907e` / xsa `934ebdba` / elf `d0b07f84`（件内 `:4-6` 自报） | 66 | `a824a2c5` | `RESULT board_verify PASS（判红的步骤：0）`（`:66`）、`RESULT PASS geom_check（ok=10 fail=0）`（`:36`）、`RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, 捕获 board/uart_script_capture.txt)`（`:63`）、`drop_words → 0`（`:21`） | 卡 A1 |
| L02 | `build/evidence/r118_serial_raw.txt` | 2026-10-04 04:47 | 同上（控制台 `:15` 点名落点与"判定=绿（地板 2）"） | 5 | `9f225141` | `[TEMP] degC=60.65 raw=0xA990 vccint=998mv th=85C over=0 sane=1 osd=61C gpio=0x61`（`:1`）、`[STAT] … frames=4398 playing=1 … osd=1`（`:2`） | 卡 A1 |
| L03 | `board/uart_script_capture.txt`（原始捕获，不入库；随包的是 L01 那份控制台） | 2026-10-04 04:49 | 同上（L01 `:63` 点名这份是 105 条电池的原始捕获） | 364 | `cc3c165a` | 8 行 `[TEMP]`、3 行 `[STAT]`（`grep -c` 现算） | 卡 A1 / 卡 A4 |
| L04 | `build/evidence/r118_board/board_now.txt` | 2026-10-04 04:49 | r118（刷入 04:49:50，`bit_cycle rc=0 board_verify rc=0`） | 3 | `224992be` | `B1 严格名册：B1 pairs_compared=8 losses=0 verdict=GREEN`（`:2`） | 卡 A1 |
| L05 | `build/evidence/r118_board/gatesb_summary.txt` | 2026-10-04 07:57 | r118 刷板前那一跑 | 5 | `f564224d` | `GATESB rc_done id=identical green=21 red=3`（`:1`）；三条红里含 `顶层台架 tb_v98 … FAIL行=1 … FAIL`（`:2`） | 卡 A1 + 卡 C1 |

## 2. 冷上电 / 三步 JTAG 链（含一次失败尝试）

| # | 真实路径 | 日期 | 构建指纹 | 行数 | sha8 | 关键读数行 | 条件卡 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L06 | `build/evidence/r118_eyes/state.txt` | 2026-10-04 07:47 | r118，`md5sum build/system.bit = cd04907e1369da35d21c4090d552f5ee` | 19 | `d34b7639` | 07:39 那次 `REFUSE DDR_ECHO 没过` 的自述（`:16-19`，异常前后原样已在卡 A2 抄出） | 卡 A2 |
| L07 | `build/evidence/r118_eyes/step1_boot.txt` | 2026-10-04 07:45 | 同上 | 8 | `e085f71a` | `DDR_ECHO: 10000000: 5A5AA5A5` | 卡 A2 |
| L08 | `build/evidence/r118_eyes/step2_program_pl.txt` | 2026-10-04 07:45 | 同上 | 35 | `08794c93` | `PROGRAMMED xc7z020_1 <- build/system.bit` | 卡 A2 |
| L09 | `build/evidence/r118_eyes/step3_app.txt` | 2026-10-04 07:45 | 同上 | 21 | `91ff38f9` | `DOW: ok`、`pc 00007cee`、`cpsr 2003007f` | 卡 A2 |
| L10 | `build/evidence/r118_eyes/uart_stat.txt` / `uart_stat2.txt` | 2026-10-04 07:46 / 07:47 | 同上 | 2 / 3 | `ad272e47` / `7e3cdd42` | 相隔 3 s 两条 `[STAT] … frames=4398 … osd=1`（**帧号不变**：当时没有上位机推流） | 卡 A2 |

## 3. 刷板循环 / 推流 / 失败与空读数（保留失败轮）

| # | 真实路径 | 日期 | 构建指纹 | 行数 | sha8 | 关键读数行 | 条件卡 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L11 | `build/evidence/r116_board/cycle_r116again.log` | 2026-10-04 02:21 | r116 系（身份见 `acceptance.md:93`：这两次重读量的是 r116，不给 r118 借用） | 109 | `b3a4f668` | `RECOVER_BEGIN Sun Oct 04 02:19:19`、`RST_SYSTEM rc=0`、`TARGETS_AFTER: … 4  xc7z020` | 卡 A3 |
| L12 | `build/evidence/r116_board/sender_live.log` | 2026-10-04 02:09 | r116 + 上位机 Node 发送端 | 2 | `7c46a7ec` | `3001 帧 / 50.03 s = 59.98 fps，共发 663221 包`（**汉字已按 GBK 存坏，数字行 ASCII 可读**） | 卡 A3 |
| L13 | `build/evidence/r116_board/health_live1.json` | 2026-10-04 02:09 | r116 | 3 | `17f70555` | **失败件**：`[HEALTH] xsdb(cur) 退出码 1 …` ⇒ 这一族的 `live`/`idle` 两份内容逐字节相同 ⇒ 记 `NOT_MEASURED` | 卡 A3 |
| L14 | `build/evidence/r116_board/health_idle.json` | 2026-10-04 02:15 | 同上 | 3 | `17f70555`（与 L13 **同摘要**） | 同上 | 卡 A3 |
| L15 | `build/evidence/r116_serial_raw.txt` | 2026-10-04 01:38 | r116 | 1（**2 字节 = 空捕获**） | `7eb70257` | `[TEMP]=0`，地板 2 未达 ⇒ 失败轮，不许当"没测就是不红" | 卡 A3 |
| L16 | `build/evidence/r116b_serial_raw.txt` | 2026-10-04 01:50 | r116 重抓 | 5 | `c7b9bac1` | 2×`[TEMP]` + 2×`[STAT]` | 卡 A3 |
| L17 | `build/evidence/no_echo_20260928_0142.txt` | 2026-09-28 | 当时板号未记 ⇒ `【待补】` | 见件 | — | `=== CAPTURE START 99 commands ===` 之后只有命令回显没有状态行 ⇒ 空回显留档 | 卡 A3 |

## 4. 串口 `[TEMP]`/`[STAT]` 家族（同一把尺子：`TEMP_FLOOR=2`，`build/board_verify.sh:42`）

| # | 真实路径 | 日期 | 行数 / `[TEMP]` / `[STAT]` | sha8 | 条件卡 |
| --- | --- | --- | --- | --- | --- |
| L18 | `build/evidence/r104_serial_raw.txt` | 2026-10-02 02:43 | 5 / 2 / 2 | `20463a0b` | 卡 A4 |
| L19 | `build/evidence/r106_serial_raw.txt` | 2026-10-02 14:59 | 5 / 2 / 2 | `64ae4d56` | 卡 A4 |
| L20 | `build/evidence/r107_serial_raw.txt` | 2026-10-02 17:53 | 5 / 2 / 2 | `5c68e499` | 卡 A4 |
| L21 | `build/evidence/r108_serial_raw.txt` | 2026-10-02 20:55 | 5 / 2 / 2 | `d207a0b6` | 卡 A4 |
| L22 | `build/evidence/r109_serial_raw.txt` | 2026-10-03 02:12 | 5 / 2 / 2 | `947642bc` | 卡 A4 |
| L23 | `build/evidence/r110_serial_raw.txt` | 2026-10-03 07:52 | 5 / 2 / 2 | `2cc053f2` | 卡 A4 |
| L24 | `build/evidence/r113_serial_raw.txt` | 2026-10-03 14:36 | 5 / 2 / 2 | `8abaf849` | 卡 A4 |
| L25 | `build/evidence/r114_serial_raw.txt` | 2026-10-03 21:32 | 5 / 2 / 2 | `44504ce6` | 卡 A4 |
| L26 | `build/evidence/verify_0930_1845.txt` | 2026-09-30 18:48 | 60 / 1 / 0（r96：`RESULT board_verify PASS（判红的步骤：0）`） | `56da9851` | 卡 A4（不同尺子） |
| L27 | `build/evidence/verify_0930_2215.txt` | 2026-09-30 22:18 | 62 / 1 / 0（r97 第一次跑出 2 条红的那一份，`acceptance.md:56`） | `084c09c0` | 卡 A4（不同尺子） |
| L28 | `board/uart_capture.txt（不随包）` | 2026-09-29 07:05 | 7 / 0 / 1 | `511b3e50` | 卡 A4（手动抓取，轮次身份 `【待补】`） |

## 5. 异常与失败现场的凭据（进分析、不进比对表）

| # | 真实路径 | 日期 | 异常 | 条件卡 |
| --- | --- | --- | --- | --- |
| L29 | `build/evidence/r75_sd_remount_before.txt` | 2026-09-27 06:23 | `[SD] remount failed: XSdPs_CfgInitialize failed` + 回读 `[STAT] sd=0 playing=0 frames=0`（sha8 `0bd4edf2`，10 行） | 卡 C |
| L30 | `build/r104_board_ping.txt` | 2026-10-02 01:22 | ICMP 三档 `4/4`、`3/3`、`4/4`，RTT 1–2 ms；件头中文是 GBK 乱码（sha8 `edfadcfd`，15 行） | 卡 D |
| L31 | `report/log/issues.md:8928-8943` | 2026-10-01 15:08 | **应答器几分钟后变哑**：`64 × 32 字节 0/64`、交替 `-l 32`/`-l 0` 全 `0/4`；同节把 14:59 那条"板上不过"就地作废 | 卡 D |
| L32 | `report/log/issues.md:10906-10934` | 2026-10-03 00:1x–00:2x | **#235 串口零字节 → AP 不可达 → 只能断电重上**：`BYTES: 0`、`DAP status 0xF0000021`、`PC_BEFORE_CON: pc: N/A` | 卡 E |
| L33 | `report/log/issues.md:3614-3640` | 2026-09-26 17:1x | **#94 SD 拔卡永久冻帧**（`have_src` 粘滞位只置不清，`pl_video_top.v:594-597`） | 卡 C |

## 6. 软件算出侧（分栏用；不是板上读数）

| # | 真实路径 | 日期 | 指纹 | 判定行（脚本自产） | 条件卡 |
| --- | --- | --- | --- | --- | --- |
| L34 | `build/tb_v98_report.txt` | 2026-10-04 03:40 | `top_md5=56c269602e18 rtl_md5=07570b1ac1b4 date=2026-10-04T01:47:53` | `^PASS` 161 行 + `^FAIL` 1 行（`C5c`，`:55`） | 卡 C1 |
| L35 | `build/evidence/r114_bit/tb_v98_report.txt`（同族还有 `r112_bit/`、`r110_notadopted/`） | 2026-10-03 19:15 | `rtl_md5=3969247aaf7f` | 同样 161 + 1 | 卡 C1 |
| L36 | `build/evidence/r104_c5head_band.txt` | 2026-10-02 07:55 | 它点名的 provenance 是 `2bf2ceeede07/36d0de483e6d/8997a62b75ba 2026-10-01T23:27:45` | `judged=本体行 3564 格不符 0 ｜ head rows=帧头窗 36 格 不符 24`（`:9`） | 卡 C1 |
| L37 | `build/r97_180_before.txt` / `build/evidence/r174_f2e_preverify.txt` | 2026-09-30 20:05 / 2026-10-03 00:05 | r97 树 / 拷贝树两腿 | `FAIL F2e B lane5 kept pre-clear history: sum=518 > 2x130`（长期红的凭据）；预验 `base红=1 → cut红=0` | 卡 C1 + `raw-vs-golden.md` 失败分析 |
| L38 | `build/timing_summary.rpt`、`build/utilization.rpt`、`build/clock_uncertainty.rpt`、`build/hold_paths.rpt`、`build/clock_util.rpt` | 2026-10-04 04:37（前两份） | r118 构建 | 逐格读数见 `board/compare/metric-recheck.txt`（114 个数对账，红 0） | 卡 C3 |
| L39 | `report/timing/roster_baseline.tsv`、`build/evidence/r116_roster_e1.tsv` | 2026-10-03 22:45 / 2026-10-04 03:27 | 名册头两行自报 src_reports | `comparisons_made=32 both_NA=8 red=2 verdict=RED`（`board/compare/roster-diff-baseline-vs-r116e1.txt`） | 卡 C3 |
| L40 | `build/cdc_baseline.txt`、`build/frozen_r23_srcseen/cdc.rpt` | 2026-09-25 16:00 | r23 冻结件（bit md5 `18443ffd`，见基线头 `:2`） | `GOLDEN … 判 18 项 未判 0 项 红 0 项 PASS`（`board/compare/cdc-golden_compare-console.txt`） | 卡 C3 |

## 7. 未登记的（缺口，如实列出）

1. **板级抓帧件**（屏上实际显示的 512×300 或 1024×600 抓帧）：**仓库里没有**。
   `data/measured/` 里的 DDR 回读是**自描述图案（frameid/wordid）**，不是图卡内容 ⇒ 任何与 `data/golden/` 的逐像素比对现在无法进行。
2. **`build/evidence/r117_board/` 是空目录**（本轮 `ls` 实测）⇒ r117 那一轮没有可登记的板级实测件；
   该轮的信息只在 `report/timing/round_r117.md` 与 `build/r117_*.txt` 里（名册/门禁侧），不属"板级实测"。
3. **功耗模式**：全仓库没有任何件自报 Zynq 功耗档/供电读数 ⇒ 每张卡的这一格都是 `【待补】`。

# 板上验收表（交付这一版）

一张表说清"这一版在真板子上被验过什么"。每行都点名它的凭据；**没验到的写在最后一节，不打勾**。
上板方式只走 JTAG（`ps_jtag_boot → program_pl → ps_app_reload`），本工程不向 QSPI/SPI flash 写入。

## 机器判据（脚本读回来的）

| # | 判据 | 读数 | 凭据 |
|---|---|---|---|
| 1 | PS 起来 + PL 烧写 + 应用重载三歩都成功 | `DDR_ECHO: 10000000: 5A5AA5A5` / `PROGRAMMED xc7z020_1`（位流 md5 `883dd3b7654d`）/ `RESUME: ok` | `build/evidence/r92f_1_psboot.txt`、`build/evidence/r92f_2_program_log.txt`、`build/evidence/r92f_3_app.txt` |
| 2 | 串口命令电池（100 条，含该拒的必须拒） | `RESULT PASS uart_cmd_check (100 条命令, 92.9 s)`；`RESULT board_verify PASS（判红的步骤：0）` | `build/evidence/verify_0930_0424.txt`、`board/uart_script_capture.txt` |
| 3 | 几何"最后一跳"：命令 → 像素域真的用了它 | `RESULT PASS geom_check（ok=8 fail=0）`；ok   跑完回到初态：thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 sel=000 gm=0.00 mode=0 geom=00400000 osd=1 | 同上 |
| 4 | 上电默认档位 | `lane23 zoom → zsel=4 zman=1 inv_scale=256 x100_actual=100`（屏上画 1.00×） | `build/evidence/verify_0930_0424.txt` 的开机回读段 |
| 5 | 以太推流期间链路健康 | Python 上位机 `--demo --fps 25`：**2501 帧 / 100.05 s = 25.00 fps、共发 552721 包**；推流**之中**读回累计 `pkts=184315`、`bytes=256205760`、`drop_words=0`、`丢过字=0`、`stall_ms=0`、`流活着=1`、屏幕归 ETH、`eth_rxc 心跳：正常` | `build/evidence/r92f_tx.txt`（发送端）、`build/evidence/r92f_health.txt`（推流中 `health_read.mjs --once` 读的） |
| 6 | 链路内时延同源一致 | 屏上 `Latency=6ms` 与回读 `tot/100000=6` 一致（ok） | `build/evidence/r92f_health.txt` |
| 7 | 温度格三方对账 | `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽` | `build/evidence/verify_0930_0424.txt` |
| 8 | SD 卡本地播放 | `sd=1 playing=1`，帧率 29.8 – 30.0 fps（100 帧滑窗） | `board/uart_script_capture.txt`、`data/metrics.csv` |
| 9 | 时序/资源读数与报告一致 | 全设计 setup WNS 0.522 ns、hold WHS 0.037 ns、失败端点 0 / 50885；BRAM 95 tile、LUT 14351、FF 8075、DSP 19 | `build/timing_summary.rpt`、`build/utilization.rpt` |
| 10 | 收口只有一棵时钟树（#57 的结构判据，不靠 slack 碰运气） | `build/clock_util.rpt`：**`BUFIO` 用量 0**（改前那一份是 1），`eth_rxc` 只经一只 `BUFG/O`（`g2`←`src2`=`IBUF/O @IOB_X1Y28`，fabric 负载 2478）；最差 20 条 hold 的时钟偏斜由 `build/hold_paths.rpt` 逐条读，实测 0.013~0.349 ns（改前那一条是 1.616 ns） | `build/clock_util.rpt`、`build/hold_paths.rpt`；改前对照是仓库里的 `build/r88_clock_util.rpt`（rNN 命名的对照件，不随包） |

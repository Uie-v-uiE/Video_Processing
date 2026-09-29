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

第 5 行里有两个数要如实写出来：`作废过帧=1`、`缺行峰值=300` —— 那是推流起始那一帧没收齐被整帧丢掉
（三重提交门限的行为，不是丢字），所以"一个字都没丢"讲的是**字级**，不是"每帧都到齐"。

## 要肉眼确认的（机器判不了，所以先空着）

| # | 看什么 | 怎么起 | 看不到时先看哪一格 |
|---|---|---|---|
| E1 | 分割线以左是原画面、以右是处理后的同一帧，两侧几何一致 | 双击 `send_demo.bat`，串口 `split 50` | `STAT` 的 `src`/`sel`；OSD 的 Split 格 |
| E2 | 缩放/旋转时不出现整行错位、画面不出屏 | `zoom 0.5` → `rot auto 1`（`split 50` + 关标记线最好判） | 台架 `C2/C3/C9` 三段（数到的列/行） |
| E3 | 移动白线与红块连续、无撕裂 | `send_demo.bat`（内置测试图每帧都动） | `pkts`/`drop_words`；OSD 的 FPS 格 |

这三条只有看的人点头之后才写"过"。本轮结束时 E1–E3 由在场的人口头确认了吗 —— 见下面"结论"。

## 结论

- 机器判据 9 条全部通过，凭据都在表里点名；
- 已知未修项（大角度旋转角点出屏、SD 播放中拔卡冻帧等）在 `docs/KNOWN_ISSUES.md`，这里不重复；
- 门禁的**项数与红绿以 `bash build/gates.sh` 打印的那一行为准**，本表不复制它，以免两处漂。

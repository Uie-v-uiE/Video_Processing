# 板上验收表（交付这一版）

一张表说清"这一版在真板子上被验过什么"。每行都点名它的凭据；**没验到的写在最后一节，不打勾**。
上板方式只走 JTAG（`ps_jtag_boot → program_pl → ps_app_reload`），本工程不向 QSPI/SPI flash 写入。

## 机器判据（脚本读回来的）

| # | 判据 | 读数 | 凭据 |
|---|---|---|---|
| 1 | PS 起来 + PL 烧写 + 应用重载三歩都成功 | `PS7_INIT: ok` / `PROGRAMMED … system.bit` / `DOW: ok` | `build/r90_flash_1_psboot.txt`、`_2_program.txt`、`_3_app.txt` |
| 2 | 串口命令电池（100 条，含该拒的必须拒） | `RESULT PASS uart_cmd_check (100 条命令, 93.3 s)` | `build/r90_board_verify.txt`、`board/uart_script_capture.txt` |
| 3 | 几何"最后一跳"：命令 → 像素域真的用了它 | `RESULT PASS geom_check（ok=8 fail=0）`；自动旋转下 inv 493 → 507；收尾 19 个几何位与进来时逐位相同 | 同上 |
| 4 | 上电默认档位 | `lane23 zsel=4 zman=1 inv=256 x100_actual=100 verdict=OK`（屏上画 1.00×） | `board/uart_script_capture.txt` 的开机回读段 |
| 5 | 以太推流期间链路健康 | Python 上位机 `--demo --fps 25`：**300 帧 / 12.02 s = 24.97 fps、66300 包**；板上累计 `pkts=496659`、`drop_words=0`、`丢过字=0`、`流活着=1`、屏幕归 ETH | `build/r90_tx.txt`（发送端）、`build/r90_health.txt`（`node src/host/health_read.mjs --once` 在推流中读的） |
| 6 | 链路内时延同源一致 | 屏上 `Latency=6ms` 与回读 `tot/100000=6` 一致（ok） | `build/r90_health.txt` |
| 7 | 温度格三方对账 | `4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽` | `build/r90_board_verify.txt` |
| 8 | SD 卡本地播放 | `sd=1 playing=1`，帧率 29.8 – 30.0 fps（100 帧滑窗） | `board/uart_script_capture.txt`、`data/metrics.csv` |
| 9 | 时序/资源读数与报告一致 | 全设计 setup WNS +0.516 ns、失败端点 0 / 50885；BRAM 95 tile、LUT 14358、FF 8075、DSP 19 | `build/timing_summary.rpt`、`build/utilization.rpt` |

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

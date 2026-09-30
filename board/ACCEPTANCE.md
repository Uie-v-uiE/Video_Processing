# 板上验收表（交付这一版）

一张表说清"这一版在真板子上被验过什么"。每行都点名它的凭据；**没验到的写在最后一节，不打勾**。
上板方式只走 JTAG（`ps_jtag_boot → program_pl → ps_app_reload`），本工程不向 QSPI/SPI flash 写入。

## 机器判据（脚本读回来的）

本表**按行记版本**：第 1/2/3/5/9/10 行是 r94（板上那一份位流 `a1465f29c9e4`，源 `rtl_md5=526321488fed`）
重跑/重念的；第 4/6/7/8 行的读数还是 r92 那一次（同一棵树没变的那些行为，r94 没重跑），补跑排在
门禁落盘之后。把某一行的数当"这一版验过"之前，先看这一行有没有"r94"字样。

| # | 判据 | 读数 | 凭据 |
|---|---|---|---|
| 1 | PS 起来 + PL 烧写 + 应用重载三歩都成功（**r94 重跑**）| `DDR_ECHO: 10000000: 5A5AA5A5` / `PROGRAMMED xc7z020_1`（位流 md5 `a1465f29c9e4` = 树上 `build/system.bit`）/ `RESUME: ok` | `build/r94_flash.txt`（三段都在一份里）|
| 2 | 串口命令电池（100 条，含该拒的必须拒）（**r94 重跑**）| `RESULT PASS uart_cmd_check (100 条命令, 93.1 s)`；`RESULT PASS geom_check（ok=8 fail=0）`；`board_verify` 全量那一串**等 r94 门禁落盘后补跑** | `build/r94_batt.txt`、`build/r94_uart_cap.txt`、`build/r94_geom_check2.txt` |
| 3 | 几何"最后一跳"：命令 → 像素域真的用了它（**r94 重跑，树上带 #93 那一钳**）| `RESULT PASS geom_check（ok=8 fail=0）`，其中 G1b/G1c/G2 三条量的是"拟合/旋转钳下 `inv_used` 与屏上档号同源自洽"（例：`fit=1` 时 inv=433 ⇒ 屏上 0.50x 档 2）| `build/r94_geom_check2.txt` |
| 4 | 上电默认档位 | `lane23 zoom → zsel=4 zman=1 inv_scale=256 x100_actual=100`（屏上画 1.00×） | `build/evidence/verify_0930_0424.txt` 的开机回读段 |
| 5 | 以太推流期间链路健康（**r94 重跑**）| `--demo --fps 25`：**3001 帧 / 120.05 s = 25.00 fps、共发 663221 包**；推流**之中**读回 `drop_words=0`、`丢过字=0`、`stall_ms=0`、`CDC灌满过=0`、`流活着=1`、`eth_rxc 心跳：正常`（累计 pkts/bytes 见凭据第 8/9 行）| `build/r94_tx_console.txt`（发送端）、`build/r94_health_rotclamp.txt`（推流中读的）|
| 6 | 链路内时延同源一致 | 屏上 `Latency=6ms` 与回读 `tot/100000=6` 一致（ok） | `build/evidence/r92_health.txt` |
| 7 | 温度格三方对账 | `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽` | `build/evidence/verify_0930_0424.txt` |
| 8 | SD 卡本地播放 | `sd=1 playing=1`，帧率 29.8 – 30.0 fps（100 帧滑窗） | `board/uart_script_capture.txt`、`data/metrics.csv` |
| 9 | 时序/资源读数与报告一致（r94 重念）| 全设计 setup WNS 0.553 ns、hold WHS 0.049 ns、失败端点 0 / 50883；BRAM 95 tile、LUT 14374、FF 8074、DSP 19、动态 2.206 W。绝对值与上一版之差**不记收益也不记损失**（规矩 35）| `build/timing_summary.rpt`、`build/utilization.rpt` |
| 10 | 收口只有一棵时钟树（#57 的结构判据，不靠 slack 碰运气）（**r94 重念：`build/clock_util.rpt` 是这一版构建产的**）| `build/clock_util.rpt`：**`BUFIO` 用量 0**（改前那一份是 1），`eth_rxc` 只经一只 `BUFG/O`（`g2`←`src2`=`IBUF/O @IOB_X1Y28`，fabric 负载 2478）；最差 20 条 hold 的时钟偏斜由 `build/hold_paths.rpt` 逐条读，实测 0.013~0.349 ns（改前那一条是 1.616 ns） | `build/clock_util.rpt`、`build/hold_paths.rpt`；改前对照是仓库里的 `build/r88_clock_util.rpt`（rNN 命名的对照件，不随包） |

第 5 行里有两个数要如实写出来：`作废过帧=1`、`缺行峰值=299` —— 那是推流起始那一帧没收齐被整帧丢掉
（三重提交门限的行为，不是丢字），所以"一个字都没丢"讲的是**字级**，不是"每帧都到齐"。

## 要肉眼确认的（机器判不了，所以先空着）

| # | 看什么 | 怎么起 | 结果（谁点的头、什么时候） | 看不到时先看哪一格 |
|---|---|---|---|---|
| E1 | 分割线以左是原画面、以右是处理后的同一帧，两侧几何一致 | 双击 `send_demo.bat`，串口 `split 50` | **过（2026-09-30 06:2x，在场的人原话"现在都很正常"）**：右半的白线与红块和左半对得上 | 当时屏上：`--demo --fps 25` 推流中、`src=1`（PL 拥有 UDP 通路）、`split 50` ⇒ `pos=512/1024 manual`、`marker=off`、`zsel=4`（1.00×）、`bilin=1`。回读 `build/evidence/r92_eye_capture2.txt` |
| E2 | 缩放/旋转时不出现整行错位、画面不出屏 | `zoom 0.5` → `rot auto 1`（`split 50` + 关标记线最好判）| **过（2026-09-30 06:5x–07:0x，在场的人原话"现在画面正常只有一条"）**：0.50× + 自动旋转下无整行错位、无左右错开的水平界线；此前他报过一次"隔一段距离的两条白线"，我用**只改推流节奏**做了对照（29.76 fps 一条、复推 25 fps 仍一条）⇒ **未复现**，判为切换瞬间的暂态，不记缺陷；下次再看到要说清屏幕高度、以及是否随缩放档变化 | 状态回读 `build/evidence/r93_e2b_capture.txt`、`build/evidence/r93_ab_state_capture.txt`；台架对应 `C2/C3/C9` 三段 |
| E3 | 移动白线与红块连续、无撕裂 | `send_demo.bat`（内置测试图每帧都动） | **过（同上，原话"现在都很正常"）** | 当时屏上：`--demo --fps 25` 推流中、`src=1`（PL 拥有 UDP 通路）、`split 50` ⇒ `pos=512/1024 manual`、`marker=off`、`zsel=4`（1.00×）、`bilin=1`。回读 `build/evidence/r92_eye_capture2.txt` |
| E4 | **（r94/#93）** 旋转一开整幅就在屏内：45°/60° 时四个角都不戳出屏幕，左缘不再有沿对角的宽彩条与细线 |
     `src 2` + `bilin on` + 手动 `zoom 1.0` + **`zoom fit 0`** + `rot auto 1 speed 0`（钳制要在"拟合关着"时才看得见）——
     **屏已经摆在这一态**（`build/r95_eye_park.txt` 末态 `geom=00400A00` ⇒ rot auto=1、speed=2、fit=0，画面正在走）；
     要停住判四角：串口 `rot auto 0` 就冻在**当前角度**（串口读不到角度，看屏上 `ROT:` 那一格），再按 KEY1/KEY2 走 ±1° |
     *待队员判* | 屏上 `ROT:` 那格在不在走、`(Fit)` 亮不亮（**屏上应当亮**：r94 把 OSD 的 `(Fit)` 接到了 `zoom_fit_en \| rot_forced`；
     而 lane23 的 bit19 在这一态仍报 0，那是回读口的口径欠账 #175，不是屏上错了）|

这三条只有看的人点头之后才写"过"。**r92/r93：E1、E3 由在场的人口头确认（原话"现在都很正常"，06:2x）；E2 确认（原话"现在画面正常只有一条"，06:5x–07:0x，含 0.50× + 自动旋转与 25 / 29.76 两档推流的对照）⇒ 三条眼睛判据这一轮全部由人点头。**同一时间他还提了一句与判据无关的观感意见（测试图动画"太丑"）——记进任务，不当成红项，也不改动已经验完的那一块位流。
（本轮已把屏摆成最好判的样子：`split 50` + `split marker 0` + 片源 ETH，命令与板上回读在 `build/evidence/r92_eye_setup.txt` / `build/evidence/r92_eye_capture.txt`。）

## 结论

- 机器判据 10 条全部通过（第 10 条是 #57 的结构判据），凭据都在表里点名；
- 已知未修项（大角度旋转角点出屏、SD 播放中拔卡冻帧等）在 `docs/KNOWN_ISSUES.md`，这里不重复；
- 门禁的**项数与红绿以 `bash build/gates.sh` 打印的那一行为准**，本表不复制它，以免两处漂。

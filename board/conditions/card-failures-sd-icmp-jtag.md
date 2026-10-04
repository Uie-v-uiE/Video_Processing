# 采集条件卡 · 失败与异常轮（卡 C：SD 拔卡/重挂、卡 D：ICMP 应答器变哑）

本文件的"卡 N"是本文件内部编号，与同目录其它批次卡的编号无关。
两张卡都对应**真实失败**，按 P16b 铁律 5 保留，不许只交成功的那一轮。

---

## 卡 C · SD 卡在播放中被拔 / 重挂失败（r75 现场 + #94 立案）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | 手工串口命令 `sd remount`，随后 `stat` 只读回读；更早一次是**物理拔卡**（用户的手） | `build/evidence/r75_sd_remount_before.txt:2-4`（`>> sd remount`）、`:5`（失败行）、`:6`（`>> stat`） |
| 输入规格 | SD 卡上的裸帧序列 512×300 RGB565（板上不解码）；卡不在座 = 无输入 | `data/measured/README.md`、`report/log/ISSUES.md:3616-3618`（用户实测三步：拔网线 / 拔 SD / 插回） |
| 时钟与功耗模式 | 同 `card-board-serial-and-jtag.md` 的卡 A1（`clkout0_1` 20 ns 显示域、`eth_rxc` 8 ns 收包域）；功耗档 `【待补】` | `docs/timing/roster_baseline.tsv` |
| 软件版本 | r75（件名与台账同轮）；**位流 md5 未写进这份捕获件** ⇒ `【待补】`。固件那条"只能断电重插"的提示语本身在 `src/ps/sd_play.c`/`main.c` 里，`ISSUES.md:3813` 给了改前/改后两份件 | `ISSUES.md:3614`（立案日期 2026-09-26 17:1x，板 r70） |
| 仪器量程 | 只有串口回显（115200-8N1）与固件自报的 `[STAT]` 位；**没有总线分析仪/示波器**，所以"≤0.5 s 落到 SRC:TEST"这类时间判据没有独立仪器校 | `board/HANDS_ON.md（不随包）:116`（那句 0.5 s 出自治具/文档，不是仪器量） |

异常前后原样（整份件只有 10 行，全抄）：
```
=== CAPTURE START 2 commands ===
>> sd remount
sd remount
[SD] remount failed: XSdPs_CfgInitialize failed
[SD] 若卡已经在座：SD 控制器停在半途传输里，只能断电重插（见 ISSUES #45/#94）
>> stat
stat
[STAT] ctrl thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=0 pub=1 sd=0 frames=0 playing=0 sel=000 gm=0.00 (PL owns UDP datapath) mode=0 geom=00400000
=== CAPTURE END ===
```
状态靠回读（铁律 3）：`sd=0`、`playing=0`、`frames=0` 三个字段就是"卡没了/没在播/一帧都没发"的回读凭据；
**同一条 `[STAT]` 里没有"卡是否在座"这一位**，所以"插回去没有"这件事无法只靠串口断言。

归因（铁律 8，先排除仪器/接线/状态/固件版本/口径）：
失败签名是 `XSdPs_CfgInitialize failed` ⇒ 归因落在**固件状态**（`mounted` 置位后永不清零、
`CfgInitialize` 一个上电周期只成功一次，`ISSUES.md:3631-3640` 给了 `sd_play.c:51,539,475` 三处 file:line，
另见 #45 立案条目 `ISSUES.md:513`），
**不是**读卡器/插槽坏了——同一上电周期里重跑 JTAG 三件套就能恢复（`ISSUES.md:750` 第 5 行实测：
完整一遍 `ps_jtag_boot → program_pl → ps_app_reload` 后 `sd=1 frames=4398 playing=1`，**不用断电**）。

"永久冻帧"这一条的机理与实测边界：`ISSUES.md:3620-3626` 给出 `pl_video_top.v:594-597` 的 `have_src`
是两个**只置位不清零**的粘滞位 ⇒ 拔卡后屏上停的是帧缓存里的最后一帧；
③ 插回不恢复 = #45 的 `mounted` 老账叠加。**这一格至今没有板级 abort 注入复验**
（`ACCEPTANCE.md:44-46` 自己写着"模块级凭据齐而板级这一格空着"）⇒ 该结论强度 = `NOT_MEASURED`（板级）。

缺项后果：位流指纹 `【待补】` ⇒ 这份失败件的读数不能与 r9x/r11x 的 `[STAT]` 逐位比"同一版前后行为不同"；
时间判据无仪器 ⇒ "0.5 s 内落到图卡"不能与上位机 measured 的毫秒数比。

---

## 卡 D · ICMP 应答器"几分钟后变哑"（#216/#188）与它的恢复读数

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | 上位机 `ping -n N`（Windows）打板 IP `192.168.1.10`；分档：默认 32 B、`-l 0`、`-l 32`；中途叠加"推 8 秒 UDP"与"静置 25 s"两个扰动 | `report/log/ISSUES.md:8930-8933`（14:56–15:0x 逐时刻序列）、`build/r104_board_ping.txt:3-15` |
| 输入规格 | 只有 ICMP echo 请求；板 IP 常量在 `src/rtl/eth/arp.v:30`（`ISSUES.md:9332` 点名） | `build/r104_board_ping.txt:1`（`board IP=192.168.1.10 (src/rtl/eth/arp.v:30)`） |
| 时钟与功耗模式 | 收包域 `eth_rxc` 8 ns；应答器是 PL 里的 `icmp_tx`/`arp_tx` 支路；功耗档 `【待补】` | `docs/timing/roster_baseline.tsv`；`ISSUES.md:8940-8943`（怀疑点写在发送侧握手） |
| 软件版本 | 哑的那一场是 r101 时段（`ISSUES.md:8928` 日期 2026-10-01 15:08）；后来"阴影没回来"那一次是 **r104**（`ISSUES.md:9676` 点名凭据 `build/r104_board_ping.txt`） | 同左 |
| 仪器量程 | Windows `ping` 的统计行（已发送/已接收/丢失、RTT 最短/最长/平均，**粒度 1 ms**）；这台机器、同一张网卡 `192.168.1.100`、**没有清过 ARP**（`ISSUES.md:8929` 明写） | `build/r104_board_ping.txt:3-6` |

失败与恢复的读数序列（原样）：
- 哑：`64 × 32 字节 0/64`；`-l 32` 与 `-l 0` 交替各 4 次**全 0/4**；推 8 秒 UDP 后仍 `0/4`；静置 25 s 后仍 `0/4`（`ISSUES.md:8931-8933`）。
- 一次**误判被就地作废**（保留，不删）：`ISSUES.md:8928` 的标题就是"更正我 14:59 写下的结论：`ping -l 0` 不过 = 说早了"，
  原因是"我拿长度 0 当变量去对比，其实对比的是**两个时刻**，不是两个条件"⇒ 该格判为"未验"，不是过也不是不过。
- 复位救回：`4 发 1 收，RTT 3 ms` ⇒ 复位能把应答器救回来（`ISSUES.md:8994`）；复位后 `ping -n 4` 连测 7 轮全 `4/4`（`ISSUES.md:9012`）。
- r104 三档复测（2026-10-02 01:21）：默认档 `4/4，RTT 1/2/1 ms`；`-l 0` 档 `3/3，RTT 1/1/1 ms`；`-l 32` 档 `4/4，RTT 1/1/1 ms`（`build/r104_board_ping.txt`）。

归因（铁律 8）：`ISSUES.md:8936-8938` 顺手量到的那条**否掉了一个候选尺子**——
`health_read` 的 lane8 pkts / lane9 bytes 在只发 ping（64 次，两种长度）期间**一字未动（仍是 0x0）**，
而推流时照涨 ⇒ 这对计数器只统计视频通路，**看不见 ICMP**，所以"没收到"与"收到没回"用现有 lane 分不开。
⇒ 这格的口径是"上位机可见的应答与否"，分母 = 发出的 echo 请求数（**丢失与超时都算失败**），
不是"板内收到的 ICMP 包数"（该口径现在量不到）。

证据件缺陷（登记不回避）：`build/r104_board_ping.txt:1` 的中文是 GBK 字节存进本仓库的 UTF-8 件里
（`r104 ICMP 涓夋靛疄娴`），汉字已损坏但**数字行是 ASCII、仍可读**；同族的空捕获见 `card-board-serial-and-jtag.md` 卡 A3。

缺项后果：ping 的分母口径与 lane 计数器口径**不同源** ⇒ 这两族数字不能互相解释；
`RTT 1 ms` 的量程粒度是 OS 的 1 ms，不能用来支撑任何"链路时延 < 1 ms"的说法（时延那一格见
`data/metrics.csv` 的"端到端时延"行，它自己写的就是"不填没有复核过的数"）。

---

## 卡 E · JTAG 链"全 0 / AP 不可达"要断电重上（#235）

| 格 | 值 | 凭据 |
| --- | --- | --- |
| 激励 | 一条 127 字节 + CRLF 的越界命令（#167 的边界注入）把命令通道打到钉死，之后 `STAT`/`split show` 无回显 | `ISSUES.md:10909-10911` |
| 输入规格 | 串口命令文本（>127 B 的非法长度，属 `data/inputs/` 里"overlong"那一类的板级对应物） | `ISSUES.md:10922-10924`（因果假设，**标注为假设**） |
| 时钟与功耗模式 | 不适用（PS 侧已不可访问）；`【待补】`：断电时长与上电顺序之外的供电读数 | `ISSUES.md:10929`（恢复要人手断电重上） |
| 软件版本 | 当时板上的 elf/bit 身份在件里**没有自报 md5** ⇒ `【待补】` | 同左 |
| 仪器量程 | xsdb 退出码 + `DAP status` 十六进制；串口字节计数（`board/serial_bytes.ps1` 的 `BYTES:`） | `ISSUES.md:10909,10915` |

异常前后原样（`ISSUES.md:10909-10916`，逐条是实测输出）：
```
- 00:13:13 与 00:13:29，`board/serial_bytes.ps1` 发 `STAT` 与 `split show` ⇒ `BYTES: 0`（串口**一个字节都不回**）。
  00:05 之前它至少还回 `[CMD!] dropped 17 trailing byte(s)`（#233 记的那一步），现在连那句都没有了。
- 00:13:52 我第一次跑 `xsdb build/tcl/ps_app_reload.tcl`：脚本打出 `RESUME: Already running` 与
  `pc: 00009ed4`，我把 `tail -12` 当成了"没报错"——**这是我的读数错误**：`DOW:` 那一行在窗口外面。
- 00:14:50 我按脚本文件头自己的判据补了一次"边听边重下"（`uart_cap_once.ps1 -Seconds 26` 纯听 + 同时重下）：
  `RST_PROC: ok`，然后
  `DOW: Memory write error at 0x0. Cannot flush CPU cache. APB AP transaction error, DAP status 0xF0000021`，
  `PC_BEFORE_CON: pc: N/A`、`cpsr: N/A` ⇒ **ELF 根本没写进去**，26 秒的串口捕获只有 2 字节（空）。
```
这一族的**形状**与 `ISSUES.md:3211` 同签名（换位流时 app 正在狂打 AXI ⇒ `DAP status 0xF0000021`），
`0xF0000021` 在本仓记忆里就是"PS 被楔住 / 寄存器读不回"。恢复顺序与三道各自的 token 写在
`ISSUES.md:10929-10931`（`DDR_ECHO … 5A5AA5A5` / `PROGRAMMED xc7z020_1` / `RESUME: ok` + `DOW: ok`，
并强调 **`DOW:` 必须是 ok、`pc` 必须能读回来**）。

两次读数失误（保留）：`ISSUES.md:10911` 与 `:10932` 自我更正——长输出要用**判据点名的那几行**去读，
不要用 `tail` 的窗口去猜。⇒ 本目录的每张卡都把 token 原文抄进"异常前后"块，就是为了不再犯这一条。

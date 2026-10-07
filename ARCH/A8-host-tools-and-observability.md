# A8 · 上位机与可观测面（实现级拆解）

这一卷的对象是"PC 这一侧"与"板上能被读到的那一面"：三份发送实现各自怎么算包、板上三类串口行每个字段从哪一行来、
`health_read.mjs` 怎么把 32 位读回译成一句人话、`board_verify.sh` 每一步拿哪一行当判据、
`one_click_test` 四步各自测什么、JTAG 三步链与 COM6 抓取脚本各自做什么。
固件内部的机制（写哪一位、为什么两次写）在 `ARCH/A7-ps-firmware-internals.md`，这里不重做，只讲"从外面怎么看它"。

约定：每个数字后面都点名来源；引号里的英文都是被引文件自己的拼写；中文留档件里的乱码段（`?`）我不当证据。

---

## 1. 三份上位机实现的分工

| 实现 | 运行时 | 定位 | 有没有对照图案 | 有没有丢包开关 | 有没有匀速开关 |
|---|---|---|---|---|---|
| `src/host/video_sender.py` | Python 3 标准库 | 零依赖默认入口：发任意视频（有 ffmpeg 就什么都发） | 内置测试图（渐变 + 白线 + 红块） | 无 | `--pace-mbps`，默认 20.0（来源：`src/host/video_sender.py:47`） |
| `src/host/video_sender.mjs` | Node 内置 `node:dgram` | 归因实验台：一整套自带对照的图案 + 确定性丢包 | 八种：`bars` `grad` `edge` `blocks` `hold` `move` `wordid` `frameid`（来源：`src/host/video_sender.mjs:13`） | `drop-every`（来源：`src/host/video_sender.mjs:164`） | `pace-mbps` 默认 15（来源：`src/host/video_sender.mjs:43`）+ 开关 `no-pace`（来源：`src/host/video_sender.mjs:42`） |
| `src/host/udp_push.py` | Python 3 标准库 | 判据工具：只有 `edge` 一种图案，专为"换帧是否原子"与确定性丢包 | 只认一种 `--pattern`（来源：`src/host/udp_push.py:47`） | `--drop-every`（来源：`src/host/udp_push.py:49`） | `--pace-mbps` 默认 15.0（来源：`src/host/udp_push.py:43`） |

三者的定位是文档里定下来的：默认推流走 Python，Node 是"带对照图案的实验台"，`udp_push.py` 是"做有对照条件的推流实验时用"（来源：`report/host_guide.md:32`、`:36-38`）。
`one_click_test` 的第③步在两份实现里用的是**不同**发送器——Node 侧交给 `video_sender.mjs`（来源：`src/host/one_click_test.mjs:201`），发送端收的是 `--file`, ` -`（来源：`src/host/one_click_test.mjs:202`），Python 侧交给 `udp_push.py`（来源：`src/host/one_click_test.py:224`），两实现喂给发送脚本的是同一串字节（来源：`src/host/one_click_test.mjs:105`）。

### 1.1 必须保持一致的常数

这些数在三份实现里各写一遍，任何一处改了另外两处不会报错——所以这张表就是"改动的射程清单"。

| 常数 | 值 | 出现在哪几处 | 改了会怎样 |
|---|---|---|---|
| 画幅 | 512 × 300 | `OUT_W, OUT_H = 512, 300`（来源：`src/host/video_sender.py:32`）、`const W = 512, H = 300`（来源：`src/host/video_sender.mjs:26`）、`W, H = 512, 300`（来源：`src/host/udp_push.py:28`） | 与位流不一致 ⇒ 写进去的帧几何与读出来的显示几何对不上（来源：`src/rtl/top/system_top.v:135`） |
| 一帧字节 | 307200 | `FRAME_BYTES = OUT_W * OUT_H * 2`（来源：`src/host/video_sender.py:33`）、`FRAME_BYTES = W * H * 2`（来源：`src/host/video_sender.mjs:26`）、`FRAME_BYTES = W * H * 2`（来源：`src/host/udp_push.py:29`） | 半帧会让板端"这一帧少一行"变成常态，`frames_bad` 无法对账（来源：`report/host_guide.md:84-85`） |
| 载荷上限 | 1392 | `MAX_PAYLOAD = 1392`（来源：`src/host/video_sender.py:35`）、`MTU = Number(get('mtu-payload', 1392))`（来源：`src/host/video_sender.mjs:29`）、`--mtu-payload` 默认 1392（来源：`src/host/udp_push.py:45`）、对账两侧 `MTU = 1392`（来源：`src/host/one_click_test.mjs:24`、`src/host/one_click_test.py:24`） | 载荷必须是 8 的倍数，否则包边界落在 64 bit DDR 字中间（来源：`src/host/udp_push.py:5-7`） |
| 头 | 4 B | `HDR = 4`（来源：`src/host/video_sender.py:34`）、`HDR = 4`（来源：`src/host/video_sender.mjs:26`）、`HDR = 4`（来源：`src/host/udp_push.py:30`） | 头是 `[u32 小端 帧内偏移]`头是 `[u32 小端 byte_offset]`（来源：`report/host_guide.md:90`） |
| 每帧包数 | 221 | `PKTS_PER_FRAME = Math.ceil(FRAME_BYTES / MTU)`（来源：`src/host/one_click_test.mjs:25`）、Python 侧 `PKTS_PER_FRAME = -(-FRAME_BYTES // MTU)`（来源：`src/host/one_click_test.py:25`） | 307200 ÷ 1392 = 220 余 960 ⇒ 221 包，最后一包只有 960 B（算式见 §3.1） |
| 目的地址/端口 | 192.168.1.10 : 5001 | `--ip` 默认（来源：`src/host/video_sender.py:42`、`src/host/video_sender.mjs:38`、`src/host/udp_push.py:39`）；端口三处默认 5001（来源：`src/host/video_sender.py:43`、`src/host/video_sender.mjs:39`、`src/host/udp_push.py:40`） | RTL 侧收侧过滤用同一个常数 `UDP_VIDEO_PORT = 16'd5001`（来源：`src/rtl/top/system_top.v:145`） |
| 本机绑定 | 192.168.1.100 | `SRC` 默认（来源：`src/host/video_sender.mjs:40`）；文档同值（来源：`report/host_guide.md:16`） | `sock.bind` 失败只 `[WARN]` 并走默认路由（来源：`src/host/video_sender.mjs:168`） |
| GPIO 基址 | 41200000 / 41210000 | `--gpio0`/`--gpio1` 默认（来源：`src/host/one_click_test.mjs:31`、`src/host/health_read.mjs:38-39`） | BD 里钉死并回读校验（来源：`build/tcl/build_system_axigpio.tcl:244-246`） |
| hw_server 端口 | 3121 | `--hw-port` 默认（来源：`src/host/one_click_test.mjs:30`）、`--port` 默认（来源：`src/host/health_read.mjs:37`） | 在不在听可以只读地查（来源：`board/hardware_setup.md:163`） |

### 1.2 载荷为什么钉在 8 的倍数（1396 是对照，不是日常）

三份实现的警告句是同一条：载荷必须 8 的倍数，否则包边界落在 64 bit DDR 字中间，打包器对同一个字分两次推送会互相覆盖，屏上出现规律黑点（来源：`src/host/udp_push.py:6-7`、`src/host/video_sender.mjs:27-28`）。
`--mtu-payload 1396` 的存在是为了**复现**这个错误，不是日常用法（来源：`src/host/video_sender.mjs:28`）；Python 侧同一句是"这是复现缺陷用的对照，日常请给 8 的倍数"（来源：`src/host/udp_push.py:96-97`）。
两条越界警告也只有一条半生效：包长超过 1472 B 会被 IP 分片而收包链不分片（来源：`src/host/udp_push.py:98-100`），而 `video_sender.py` 根本没有 `--mtu-payload` 参数——它的上限是常数（来源：`src/host/video_sender.py:35`）。
硬件侧这件事已经被堵掉：打包器从 v6.4 起按 16bit lane 驱动 `WSTRB`，同一块板同一版 bit 复测 1396 时命中率 100.0%、空洞 0（来源：`report/host_guide.md:102-104`）；默认仍建议 1392 的理由是"少发约 0.3% 的重复 beat，而且一个包不跨两个 64 bit 字这个性质让包内相位分析还能用"（来源：`report/host_guide.md:103-104`）。

### 1.3 三份参数逐项表

`video_sender.py`（十个参数，来源：`src/host/video_sender.py:42-53`）：

| 参数 | 默认 | 作用 | 出处 |
|---|---|---|---|
| `--ip` | `192.168.1.10` | 板的地址 | 来源：`src/host/video_sender.py:42` |
| `--port` | `5001` | 目的端口 | 来源：`src/host/video_sender.py:43` |
| `--fps` | `30.0` | 推流帧率上限 | 来源：`src/host/video_sender.py:44` |
| `--count` | `0` | 推多少帧后停（0 = 推完/一直推） | 来源：`src/host/video_sender.py:45` |
| `--seconds` | `12.0` | 只作用 `--demo`：推多久 | 来源：`src/host/video_sender.py:46` |
| `--pace-mbps` | `20.0` | 限速 MB/s；帮助文本自己写"演示不要用它" | 来源：`src/host/video_sender.py:47-48` |
| `--input` | 无 | 要发的视频 | 来源：`src/host/video_sender.py:49` |
| `--raw WxH` | 无 | 裸帧源的分辨率（不是板子收的分辨率） | 来源：`src/host/video_sender.py:50` |
| `--demo` | 关 | 先 ping 再推内置测试视频 | 来源：`src/host/video_sender.py:51` |
| `--no-ping` | 关 | 跳过 ping | 来源：`src/host/video_sender.py:52` |

`video_sender.mjs`（`get()` 的统一取参在来源：`src/host/video_sender.mjs:32-37`）：

| 参数 | 默认 | 作用 | 出处 |
|---|---|---|---|
| `--ip` / `--port` | 192.168.1.10 / 5001 | 板卡地址 | 来源：`src/host/video_sender.mjs:38-39` |
| `--src` | 192.168.1.100 | 本机绑定地址；传空走默认路由 | 来源：`src/host/video_sender.mjs:40`、`:166-169` |
| `--fps` | 15 | 帧率 | 来源：`src/host/video_sender.mjs:41` |
| `--count` | 0 | 发满 N 帧退出 | 来源：`src/host/video_sender.mjs:44` |
| `--pace-mbps` | 15 | 包内匀速；旧拼写 `--pace-mpbps` 仍接受 | 来源：`src/host/video_sender.mjs:43` |
| `--no-pace` | 关 | 关掉匀速（压力实验） | 来源：`src/host/video_sender.mjs:42` |
| `--mtu-payload` | 1392 | 载荷上限（复现缺陷用） | 来源：`src/host/video_sender.mjs:29` |
| `--test` | `bars` | 图案选择 | 来源：`src/host/video_sender.mjs:45` |
| `--wordid-add` | 0 | `wordid` 图案的相位偏移 | 来源：`src/host/video_sender.mjs:135` |
| `--drop-every` | 0 | 每 N 包确定性丢一个 | 来源：`src/host/video_sender.mjs:164` |
| `--dump FILE` | 关 | 落最后两帧，供 `ddr_verify.mjs --ref` 比对 | 来源：`src/host/video_sender.mjs:222` |
| `--file -` | 关 | 从 stdin 收 ffmpeg 解出来的裸流 | 来源：`src/host/video_sender.mjs:51` |

`udp_push.py`（八项，来源：`src/host/udp_push.py:39-50`）：`--ip` 192.168.1.10、`--port` 5001、`--fps` 15.0、`--count` 0、
`--pace-mbps` 15.0、`--mtu-payload` 1392、`--pattern` 只认 `edge`、`--file` 裸帧流、`--drop-every` 0（各行的行号按 `:39` 到 `:49` 顺序）。

### 1.4 这一站的数据形状 + 出错时看到什么

- **形状**：三条发送端的开场行不同但可以互认——Python 是 `[TX] -> %s:%d  512x300 RGB565 @%.2gfps  pace=%.1f MB/s`（来源：`src/host/video_sender.py:197`），`udp_push.py` 多带图案与丢包数（来源：`src/host/udp_push.py:116`），Node 是 `[TX] ${IP}:${PORT} ${W}x${H} RGB565 @${FPS}fps test=`（来源：`src/host/video_sender.mjs:212`）；三句的成功读数差在 `report/host_guide.md:40-41` 里逐条列着。
- **出错**：`--input` 给了但没装 ffmpeg ⇒ 明说"没找到 ffmpeg"并退出码 2，不静默降级（来源：`src/host/video_sender.py:131`、`:206-207`）；`--raw` 写不成 `WxH` 也退 2（来源：`src/host/video_sender.py:175-176`）。
- **出错**：MTU 不是 8 的倍数时 Node 侧打警告但仍然发（来源：`src/host/video_sender.mjs:30`）；ping 不通时 `video_sender.py` 照样继续推，因为"ICMP 不通不等于 UDP 不通"（来源：`src/host/video_sender.py:184-185`）。
- **出错**：Node 侧 `--src` 绑不上会 `[WARN] bind ... failed` 并退回默认路由（来源：`src/host/video_sender.mjs:168`），此时源地址不是 192.168.1.100，排查网线路由时要记得这一点。

---

## 2. 发送侧的账：一帧拆成多少包、那行"stream end"是谁打的

### 2.1 包数账（全部现算）

一帧 307200 B、载荷上限 1392 B ⇒ 满包数 = 307200 ÷ 1392 = 220，余 960 B ⇒ 还要 1 包 ⇒ **221 包/帧**（来源：`src/host/one_click_test.mjs:25` 的 `Math.ceil`）。
头账：221 包 × 4 B = 884 B/帧（来源：`src/host/video_sender.py:233` 的 `HDR * ((FRAME_BYTES + MAX_PAYLOAD - 1) // MAX_PAYLOAD)`）。
线上一帧的总字节 = 307200 + 884 = 308084 B（同一个式子在 `src/host/udp_push.py:133` 写成 `len(payload) + HDR * (len(payload) // a.mtu_payload + 1)`）。
默认一键测试的账：`--frames` 默认 5（来源：`src/host/one_click_test.mjs:28`）⇒ 应发包 5 × 221 = 1105、应发字节 5 × 307200 = 1,536,000（来源：`src/host/one_click_test.mjs:112-113`）。
那 15 fps 的留档里第一帧那行就是 `first frame 307200 B = 221 pkts`（来源：`data/measured/board_measure_15fps.txt:3`），与上面的算式独立吻合。

两条包数公式的**等价性有一个缺口**：Python 的 `// + 1` 在帧长恰好是载荷上限整数倍时会多数 1 包（此时 `ceil` 给 220、`//+1` 给 221），而 307200 % 1392 = 960 ≠ 0（来源：`src/host/video_sender.py:233` 与 `src/host/udp_push.py:133` 两个式子），所以在默认 1392 下两者相等；改 `--mtu-payload` 做对照时要记住这件事。

### 2.2 `stream end: N frames, M pkts (dropped D)` 是谁打的

这行只在 **stdin 模式**（`--file -`）下、由 `process.stdin` 的 `end` 事件打出来（来源：`src/host/video_sender.mjs:267`），
文件末尾不足一帧的残字节先单独报一行丢掉多少（来源：`src/host/video_sender.mjs:266`），然后 1 秒后关 socket 并 `process.exit(0)`（来源：`src/host/video_sender.mjs:268`）。
计数口径：`sentPkts++` 在丢包判断**之前**（来源：`src/host/video_sender.mjs:200`），被丢的那包另外进 `droppedPkts`（来源：`src/host/video_sender.mjs:201-202`）——
所以 `M` 是"含被主动丢掉的"总计数，真正的发出数是 `M − D`；对账侧正是这么算的：`counted - sentDropped`（来源：`src/host/one_click_test.mjs:210`）。
读它的正则与三个变量（来源：`src/host/one_click_test.mjs:206-209`），SEND 步的 PASS 条件是三件事同时成立：正则命中、子进程退出码 0、发出包数等于应发包数（来源：`src/host/one_click_test.mjs:211`）。

**两个不打的时机**（都是"看起来像工具坏了"的源头）：
`--count N` 那条路不打印 `stream end`，它打的是 `[TX] waiting for the tx queue to drain ...` 然后延时关 socket（来源：`src/host/video_sender.mjs:232-237`）——所以拿 `--count` 跑一键测试会正则不中；
`SIGINT` 打的是 `[TX] sent ${n} frames`（来源：`src/host/video_sender.mjs:275`），同样不含 `stream end`。

### 2.3 与板上 lane 的对账

板上 lane8/lane9 的定义：`lane8 = in_pkts` 收到的包数、`lane9 = in_bytes` 收到的有效字节（来源：`src/rtl/eth/link_monitor.v:195-196`），两口的输入取自 `frame_reasm`（来源：`src/rtl/eth/link_monitor.v:28-29`）。
**字节口径是载荷、不含那 4 B 头**：`stat_bytes <= stat_bytes + pkt_pay`（来源：`src/rtl/eth/frame_reasm.v:205`），而 `pkt_pay` 是逐字加 1 的包内计数（来源：`src/rtl/eth/frame_reasm.v:165`）。
于是对账算式是两条等式，代码里就是这一句 `dPkts === EXP_PKTS && dBytes === EXP_BYTES`（来源：`src/host/one_click_test.mjs:223`）：左边 `dPkts` 应当等于帧数 × 221、`dBytes` 应当等于帧数 × 307200。
Python 侧同两条等式在 `src/host/one_click_test.py:251`。
`COLLECT` 那一行同时报差额与期间增量：先是 `lane8_pkts_delta=`（来源：`src/host/one_click_test.mjs:224`），同一行随后是 `差额_pkts=`（来源：`src/host/one_click_test.mjs:225`），
同一行末尾的 `frames_bad=` 与 `bad_pkts=` 是同一只 lane1 的低半与高半：`d(1) & 0xffff` 与 `(d(1) >>> 16) & 0xffff`（来源：`src/host/one_click_test.mjs:225`）。

### 2.4 fps 与 pace 是两套节奏，三份实现写法不同

`video_sender.py` 取**较晚**的那个截止点：`cost = (FRAME_BYTES + HDR * ((FRAME_BYTES + MAX_PAYLOAD - 1) // MAX_PAYLOAD)) / bytes_per_sec`（来源：`src/host/video_sender.py:233`），
再 `due = max((next_t + cost) if cost else 0.0, t0 + n * period)`（来源：`src/host/video_sender.py:235`）。
注释写明了为什么：只按字节算会超过 `--fps`（实测冲到 65 fps），只按帧算又限不住带宽，而两处都"各等一次"会互相叠加（第一版就是这样，25 fps 只跑到 20）（来源：`src/host/video_sender.py:230-232`）。
`udp_push.py` 用的**就是那种叠加写法**：`Pacer.spend` 先把 `next_t` 按字节推前并 sleep（来源：`src/host/udp_push.py:82-90`），随后又按 `period` 加一次再 sleep（来源：`src/host/udp_push.py:138-141`）——两份文档对"实测 25 fps 只跑到 20"的归因正好指向这个形状（来源：`src/host/video_sender.py:232`）。
`Pacer` 自己的口径要说清：节奏按**累计字节数**推时间戳、不靠 sleep 叠加，因为 sleep 会被调度抖动放大，而本项目要报的恰恰是帧间隔的抖动（来源：`src/host/udp_push.py:74-76`）。
Node 侧第三种：帧间用 `setTimeout` 补到 `period = 1000 / FPS`（来源：`src/host/video_sender.mjs:213`、`:239-242`），帧内逐包用绝对时间匀速 `paceSpend`（来源：`src/host/video_sender.mjs:178-186`），
精度上 `Date.now()` 的 1 ms 不够，所以用 `performance.now()` 加 `Atomics.wait` 睡整段、尾部自旋对齐（来源：`src/host/video_sender.mjs:172-175`、`:183-184`）。
`--fps` 默认值的差别也因此是实质的：Python 默认 30.0（来源：`src/host/video_sender.py:44`）、Node 与 `udp_push.py` 默认 15（来源：`src/host/video_sender.mjs:41`、`src/host/udp_push.py:41`）。
留档那次 15 fps 跑出的实测是 `[TX] frames=180 ~15.1 fps`（来源：`data/measured/board_measure_15fps.txt:9`），比标称高 0.1 fps——那行本身就是 `n/dt` 的均值（来源：`src/host/video_sender.mjs:227`）。

### 2.5 确定性丢包为什么不能改成随机

注释一句话：演示与对账都要"同样命令 → 同样丢包位置"，硬件的 `frames_bad` / `rows_missed` 才对得上；随机丢的话每次读数都不一样，等于没有判据（来源：`src/host/video_sender.mjs:188-190`）。
`udp_push.py` 同句写在文件头（来源：`src/host/udp_push.py:13-15`），并且给出预期现象：板上应当看到的不是"缺一块"，而是**整帧不上屏、保留上一帧**（来源：`src/host/udp_push.py:15`）。
实现上两式等价：Node 是 `sentPkts % DROP_EVERY === 0` 时 `droppedPkts++` 并 `continue`（来源：`src/host/video_sender.mjs:201-203`），Python 是 `counters[0] % drop_every == 0` 时 `counters[1] += 1` 并 `continue`（来源：`src/host/udp_push.py:65-68`）。
`src/host/video_sender.py` 没有丢包参数（来源：`src/host/video_sender.py:42-53`），要造洞只能用另外两支。

### 2.6 这一站的数据形状 + 出错时看到什么

- **形状**：一次 5 帧的一键测试应当是"发出包 1105、pkts 增量 1105、bytes 增量 1536000、差额两个 0"（算式在 §2.1，读式在来源：`src/host/one_click_test.mjs:224`）。
- **形状**：图案模式的进度行是 `[TX] frames=${n} ~${(n/dt).toFixed(1)} fps`，每 30 帧一条（来源：`src/host/video_sender.mjs:225-227`）；stdin 模式换成 `[TX] frames=${n} sent_pkts=${sentPkts} dropped=${droppedPkts}`（来源：`src/host/video_sender.mjs:260`）。
- **出错**：`sendOk` 为假时 SEND 行会把发送脚本前 3 行输出原样带出来（来源：`src/host/one_click_test.mjs:212-213`），先读那一段再怀疑板子。
- **出错**：末尾残帧被丢是设计而不是损失——半帧会让"这一帧少一行"变成常态，读数就没法对账（来源：`src/host/video_sender.mjs:245-246`、`report/host_guide.md:84-85`）。
- **出错**：`--count 1` 这种短测会把大部分包丢在发送队列里，所以有 2 s 排空等待（来源：`src/host/video_sender.mjs:230-236`）；看到 `waiting for the tx queue to drain ...` 不是卡住。
- **出错**：帧数不够时 Python 侧会**落一份重复补足后的裸帧流**再发给 `udp_push.py`，用完删掉（来源：`src/host/one_click_test.py:112-117`、`:262-264`）；Node 侧是把同一串字节喂 stdin（来源：`src/host/one_click_test.mjs:106-111`）。两份实现发出去的字节应当相同（来源：`src/host/one_click_test.mjs:105`）。

---

## 3. 板上可观测面：三类行的字段表

三类行、三个出口：`[STAT]` 与 `[TEMP]` 是固件主动打的（只有你问它才说），`[HEALTH]` 是上位机自己打的（JTAG 读回失败时）。

### 3.1 `[STAT]`：一行 17 个字段

格式串分三段拼成一行：`[STAT] ctrl thr=%d src=%d zoom=%d bilin=%d zsel=%d zman=%d pub=%d`（来源：`src/ps/main.c:1381`）、
` sd=%d frames=%d playing=%d sel=%03x gm=%d.%02d (PL owns UDP datapath)`（来源：`src/ps/main.c:1382`）、
` mode=%d geom=%08x osd=%d`（来源：`src/ps/main.c:1383`）。
`stat` 也认 `status` 这个别名（来源：`src/ps/main.c:1371`）。实物一行（两张快照只差 `pub=`）：

```
[STAT] ctrl thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 pub=0 sd=1 frames=4398 playing=1 sel=000 gm=0.00 (PL owns UDP datapath) mode=0 geom=00400000 osd=1
```

上面这一行照抄自留档（来源：`board/measured/health_20261005_1031.txt:10`），同批另一张是 `pub=1`（来源：`board/measured/health_20261005_1025.txt:10`）。

| 字段 | 送进格式的是谁 | 含义 / 最终落到哪一位 | 能不能动 | 出处 |
|---|---|---|---|---|
| `ctrl` | 字面标记 | 告诉解析器"这是控制字回读" | 位置不许动 | 来源：`src/ps/main.c:1381` |
| `thr` | `cur_thr` | 二值化阈值 → `gpio_o[15:8]` | `th <0..255>` | 来源：`src/ps/main.c:1384`、`src/ps/main.c:214` |
| `src` | `cur_src` | PS 手里那一位 → `gpio_o[16]` | `src 0/1/2` | 来源：`src/ps/main.c:1384`、`:499` |
| `zoom` | `cur_zoom ? 1 : 0` | 呼吸开关 → `gpio_o[17]` | `zoom on/off` | 来源：`src/ps/main.c:1384`、`:215` |
| `bilin` | `cur_bilin ? 1 : 0` | 双线性 → `gpio_o[19]` | `bilin on/off` | 来源：`src/ps/main.c:1384`、`:216` |
| `zsel` | `cur_zsel` | 手动缩放档号 → cfg1 `[28:26]` | `zoom <倍率>` | 来源：`src/ps/main.c:1385`、`:224` |
| `zman` | `cur_zman` | 手动旗标 → cfg1[29] | `zoom auto` / `zoom <数>` | 来源：`src/ps/main.c:1385`、`:224` |
| `pub` | `pub_lvl` | 发布位 `gpio_o[18]`，**每帧翻一次** | 只能间接动（播/停/`fill`） | 来源：`src/ps/main.c:1385`、`:244` |
| `sd` | `sd_frame_total() ? 1 : 0` | 卡挂上了没有 | `sd` / `sd remount` | 来源：`src/ps/main.c:1386` |
| `frames` | `sd_frame_total()` | 当前可播片长（帧数），按构造是静态字段 | 只能换卡 | 来源：`src/ps/main.c:1386`、`src/ps/sd_play.c:811` |
| `playing` | `sd_is_playing()` | 回放状态机在不在跑 | `play` / `stop` | 来源：`src/ps/main.c:1386`、`src/ps/sd_play.c:826` |
| `sel` | `cur_sel & 0x1FF` | 九位效果选择 → cfg1 `[8:0]` | `pipe <九位>` | 来源：`src/ps/main.c:1387`、`:223` |
| `gm` | `cur_gamma / 100` 与 `% 100` | γ×100；`gm=0.00` 表示 gamma 关（PL 那一侧逐位旁路） | `gamma <数>` / `off` | 来源：`src/ps/main.c:1388`、`:1375` |
| 括号那句 | 字面 | 提醒 UDP 数据通路归 PL | 位置不许动 | 来源：`src/ps/main.c:1382` |
| `mode` | `cur_mode_ovr` | 请求侧模式码 → `gpio_o[24:23]` | `src auto/0/1/2` | 来源：`src/ps/main.c:1388`、`:510` |
| `geom` | `cur_split & GEOM_MASK` | 19 位几何控制字的**整字** | `split` / `rot` / `zoom fit` | 来源：`src/ps/main.c:1389`、`:225` |
| `osd` | `cur_osd ? 1 : 0` | 叠层（位是反相的 `gpio_o[20]`） | `osd on/off` | 来源：`src/ps/main.c:1389`、`:217` |

三条位置规矩写在注释里：字段顺序不许动，因为串口电池与 `uart_cmd_check.mjs` 都按前缀解析（来源：`src/ps/main.c:1372-1373`）；
老五位那个投影 `en=` 已经删掉，checker 反过来把"还在打 `en=`"当旧固件的反例（来源：`src/ps/main.c:1373-1375`）；
新字段照老规矩**只往后加**（来源：`src/ps/main.c:1380`），`osd=` 就是这样排在最后的（来源：`report/commands.md:170`）。
`geom=` 为什么必须进这一行：串口电池的"跑完必须回到初态"是比 `STAT` 元组的，而元组里以前看不见这些位 ⇒
电池可以把板子留在"自动旋转还开着、缩放还在 fit、缝贴着右边缘"而判绿（来源：`src/ps/main.c:1376-1379`）。
留档里那个 `geom=00400000` 拆得开：bit22 = 1 ⇒ 缝位 = 0x00400000 >> 13 = 512，正是"默认缝在正中 = 旧行为"的那个初值（来源：`src/ps/main.c:145`），
其余 18 位全 0（无 auto / 无 follow / 无 swap / 蓝线在 / 无 rot auto / speed=0 / 无 fit）——与同一行的 `mode=0 osd=1` 同源自洽（来源：`board/measured/health_20261005_1031.txt:10`）。

### 3.2 `[TEMP]`：八个字段是一行三方对账

格式串是 `[TEMP] degC=%s%d.%02d raw=0x%04x vccint=%dmv th=%dC over=%d sane=%d osd=%s gpio=0x%02x`（来源：`src/ps/main.c:881`）。
实物：`[TEMP] degC=60.20 raw=0xA955 vccint=998mv th=85C over=0 sane=1 osd=60C gpio=0x60`（来源：`board/measured/health_20261005_1031.txt:11`）。

| 字段 | 从哪来 | 出处 |
|---|---|---|
| `degC` | `XAdcPs_GetAdcData` 的 raw 经定点换算 | 来源：`src/ps/main.c:855`、`:754` |
| `raw` | 同一个 16 位左对齐字原样十六进制 | 来源：`src/ps/main.c:882` |
| `vccint` | `XADCPS_CH_VCCINT` 经满量程 3.0 V 换算 | 来源：`src/ps/main.c:856`、`:755` |
| `th` | 会话阈值 `temp_th_deg`，默认 85 | 来源：`src/ps/main.c:748`、`:882` |
| `over` | `mc >= th` | 来源：`src/ps/main.c:860` |
| `sane` | `mc > 0 && mc < 80000 && mv > 800 && mv < 1300` | 来源：`src/ps/main.c:861` |
| `osd` | 编码还原成的那三个字符，画不出时 `--` | 来源：`src/ps/main.c:873-880` |
| `gpio` | 从设备读回来的低字节 = PL 同步链正在采的值 | 来源：`src/ps/main.c:883` |

`osd=` 与 `gpio=` 是后加的（来源：`report/commands.md:219`）；加完之后这一行把三段账一次钉住——`degC`（驱动读数）↔ `osd`（编码器输出）↔ `gpio`（真的写到了 PL），
串口电池拿这三者做机器判据、不需要任何人看屏幕（来源：`src/ps/main.c:865-868`）。
上一节 A7 已经算过这两个读数自洽：raw 0xAA40 ⇒ 62.013 °C ⇒ 整度 62 ⇒ BCD 0x62，留档正是 `osd=62C gpio=0x62`（来源：`board/measured/health_20261005_1025.txt:11`）。
`temp` 这一条是**命令触发**的、不是周期打印：`degC=` 那句 `xil_printf` 在 `temp` 命令的处理路里，屏上那一格才是每秒由 `temp_poll` 刷的（来源：`build/board_verify.sh:168-170`）——
被动守 14 秒窗口一行 `[TEMP]` 都抓不到（同一处记的实测是 `CAPTURED_LEN 0`，来源：`build/board_verify.sh:170`）。这是 §6 那步判据必须发命令的原因。

### 3.3 `[HEALTH]`：只有失败与归零时才出现

| 行 | 什么时候打 | 出处 |
|---|---|---|
| `[HEALTH] xsdb(${tag}) 退出码 ${e.status}：` | `execSync` 抛异常（xsdb 自己非 0） | 来源：`src/host/health_read.mjs:302` |
| `[HEALTH] xsdb 报错，前几行：` | 回读前 8 行命中 `^error`、`no targets`、`cannot`、`invalid target` | 来源：`src/host/health_read.mjs:306-307` |
| `[HEALTH] 先确认：板子有电、bit 已下载、hw_server 在跑` | 与上一行成对，随后 `process.exit(1)` | 来源：`src/host/health_read.mjs:308` |
| `[HEALTH] 读不到 GPIO_0 的当前值，拒绝继续` | 第一步读回原值没匹配上，直接退出 | 来源：`src/host/health_read.mjs:319` |
| `[HEALTH] 已把帧间隔统计归零（gpio_o[26] 拉高 250 ms）` | 给了 `--gapclr` | 来源：`src/host/health_read.mjs:325` |

人读模式（不带 `--json`）打的是另外几类行：开场一行含 `（已还原）` 这个自证（来源：`src/host/health_read.mjs:479`）、
每条 lane 两行（数值行与含义行，来源：`src/host/health_read.mjs:499`）、
时延一段（来源：`src/host/health_read.mjs:530`）、缩放一段（来源：`src/host/health_read.mjs:559`）、
判读一行（来源：`src/host/health_read.mjs:571`）与结论一行（来源：`src/host/health_read.mjs:574`）。

### 3.4 这一站的数据形状 + 出错时看到什么

- **形状**：一次只读健康快照在串口上是三行——`[STAT]`、`[TEMP]`、`[STAT]`（命令表就是 `stat,temp,stat`，来源：`board/scripts/board_health.sh:62`），首末两行除 `pub=` 外应当逐字相同（来源：`board/scripts/board_health.sh:83-86`）。
- **形状**：那条"除 `pub=`"是修过的：第一次实跑就是被 `pub=1 / pub=0` 判红的，而其余逐字相同（来源：`board/scripts/board_health.sh:84-85`），红的那一份留档保留不删（来源：`board/scripts/board_health.sh:12-13`），它对应末行 `no-perturb(首末 STAT 逐字同)  = 0`（来源：`board/measured/health_20261005_1025.txt:63`）；修完的那一份是 `= 1`（来源：`board/measured/health_20261005_1031.txt:63`）。
- **出错**：`frames=4398` 两次同值**不说明冻帧**——它打的是"当前这个文件一共有多少帧"，按构造就是静态字段（来源：`board/README.md:123-123`）；要判断通路活不活，看能动的字段：`pub=`、`pc`、`degC`（来源：`board/README.md:124`）。
- **出错**：屏上 `SRC:` 那一格画的是屏幕真的那一路而不是意愿，`{fb_vis, owner_eth}` 取 11 印 `ETH`、10 印 `SD`、其余印 `TEST`（来源：`report/commands.md:45-47`）；想知道此刻为什么归某一路，读 `stat` 的 `mode=`（请求侧）与 lane30 的 `why=`（执行侧真值，来源：`report/commands.md:160-161`）。
- **出错**：`[HEALTH]` 一句都没打但输出全 0 —— 先怀疑 `mrd` 的解析而不是板子：不要在 Tcl 里 `lindex`/`split`，把整串打出来由 Node 侧解析（来源：`src/host/health_read.mjs:265-267`）。

---

## 4. `health_read.mjs`：lane 位域解码与 `why` 语义表

### 4.1 lane30 的 `why`：八种组合一张表

`decodeSrc` 把 16 位读回拆成 11 个具名字段（来源：`src/host/health_read.mjs:71-85`）：低 7 位是"输入现在长什么样"，高 3 位是"**做判决那一拍**看到了什么"（来源：`src/host/health_read.mjs:370-371`）。
`why_gray` 取 `(src >>> 8) & 7`（来源：`src/host/health_read.mjs:74`），三位各自的语义是 `{force_ps, ~eth_live, ~eth_tb_ok}`（来源：`src/rtl/top/pl_video_top.v:67`），
而那句人话是把置 1 的位按"手动锁 SD / 没有流 / 源时基不可信"的顺序接起来、全 0 时说 `无（ETH 想要总线）`（来源：`src/host/health_read.mjs:82`）。
八种组合的期望文本是**手抄**进自检的、不从 decode 反推（来源：`src/host/health_read.mjs:150`、`:174`）：

| `why_gray` | bit10 force_ps | bit9 ~eth_live | bit8 ~eth_tb_ok | 应当印成 |
|---|---|---|---|---|
| 0b000 | 0 | 0 | 0 | `无（ETH 想要总线）` |
| 0b001 | 0 | 0 | 1 | `源时基不可信` |
| 0b010 | 0 | 1 | 0 | `没有流` |
| 0b011 | 0 | 1 | 1 | `没有流+源时基不可信` |
| 0b100 | 1 | 0 | 0 | `手动锁 SD` |
| 0b101 | 1 | 0 | 1 | `手动锁 SD+源时基不可信` |
| 0b110 | 1 | 1 | 0 | `手动锁 SD+没有流` |
| 0b111 | 1 | 1 | 1 | `手动锁 SD+没有流+源时基不可信` |

上面这八行的顺序与文案逐条对 `src/host/health_read.mjs:175-177` 那张表，判据本身在 `src/host/health_read.mjs:178-181`（同时要求 `why_gray` 等于那个数）。
为什么要给到七位而不是三位：#28 第一次板级跑交接判据就红，而三位版本分不开"模式被钉住 / 时基不可信 / both_idle 从不成立 / 判据说谎"四种解释（来源：`src/host/health_read.mjs:367-368`）；
前三位说的是输入长什么样、后三位说的是判决那一拍看到什么，两者不一致就说明换手被 busy 挡住了而不是判据说谎（来源：`src/host/health_read.mjs:370-372`）。
屏上与人读两条出口共用同一个函数：人读那一支直接取 `s.why`，注释写着"与 `--json` 走同一个函数：两处各写一遍移位就会各说一套话"（来源：`src/host/health_read.mjs:508`、`:514`）。

### 4.2 lane23 的解码与"三支判据"

`decodeZoom` 的字段表（来源：`src/host/health_read.mjs:90-102`）：`alive` 取 bit31（来源：`src/host/health_read.mjs:94`）、`zoom_fit` 取 bit19（来源：`src/host/health_read.mjs:98`）、
`zman` 取 bit18、`zsel` 取 `[17:15]`、`zcode` 取 `[14:12]`、`zoom_active` 取 bit11、`zoom_dir` 取 bit10、`inv_scale` 取低 10 位（来源：`src/host/health_read.mjs:99-100`）。
`inv_scale` 是 Q8 的**倒数**，所以八档的期望值不查表而是从"倍率"这个定义算：`inv_exp_of = Math.min(1023, Math.round(25600 / ZOOM_X100[i]))`（来源：`src/host/health_read.mjs:110`），倍率表 `[25, 33, 50, 75, 100, 133, 150, 200]`（来源：`src/host/health_read.mjs:105`）。现算八档：

| 档 | 倍率 | 25600 ÷ x100 | 取整后 | 与 10 bit 天花板 |
|---|---|---|---|---|
| 0 | 0.25x | 25600 ÷ 25 = 1024 | 1024 | **夹到 1023**（来源：`src/host/health_read.mjs:110`） |
| 1 | 0.33x | 25600 ÷ 33 ≈ 775.76 | 776 | 未夹 |
| 2 | 0.50x | 25600 ÷ 50 = 512 | 512 | 未夹 |
| 3 | 0.75x | 25600 ÷ 75 ≈ 341.33 | 341 | 未夹 |
| 4 | 1.00x | 25600 ÷ 100 = 256 | 256 | 未夹 |
| 5 | 1.33x | 25600 ÷ 133 ≈ 192.48 | 192 | 未夹 |
| 6 | 1.50x | 25600 ÷ 150 ≈ 170.67 | 171 | 未夹 |
| 7 | 2.00x | 25600 ÷ 200 = 128 | 128 | 未夹（正好在下界） |

0.25x 那一档为什么要单独钉：0.25× 本该是 1024，而 `inv_scale` 只有 10 位 ⇒ 1024 会回绕成 0（来源：`src/host/health_read.mjs:107-108`），
自检里 `S5b` 就是钉"式子给 1024、期望必须是 1023"（来源：`src/host/health_read.mjs:228-229`）；这是板级"缩到最小反而变成无限大"的根（来源：`src/host/health_read.mjs:226`）。
`zoomJudge` 只有三支（这是"判决只写一遍"的那次收口，来源：`src/host/health_read.mjs:115-119`）：

| 支 | 进入条件 | 判什么 | 出处 |
|---|---|---|---|
| `fit_or_clamp` | `zoom_fit` = 1 | 只卡量程 `inv_scale >= 256 && <= 1023` 与"屏上档 == 最近档"，`inv_expected` 给 null | 来源：`src/host/health_read.mjs:121-130` |
| `manual_tier` | `zoom_fit` = 0 且 `zman` = 1 | `inv_scale === inv_exp_of(zsel)` 且 `zcode === zsel` | 来源：`src/host/health_read.mjs:132-139` |
| `breathing` | 其余 | 只卡量程 `128..1023` 与同档 | 来源：`src/host/health_read.mjs:141-146` |

bit19 从 r97 起念的是 `zoom_fit_en | rot_forced`，也就是"拟合或角度钳"同一件事 ⇒ 只要这一位是 1，倍率就是角度定的、不等于档号是应当的，不能判红（来源：`src/host/health_read.mjs:118-119`）；
板级那格活标本是 zsel=4（手动 1.00×）而 inv=472（屏上 0.50×），同一个数字，bit19 决定该不该判红（来源：`src/host/health_read.mjs:232-233`）。
`--selfcheck` 的 `S5c`/`S5d` 就是这一对的成对照：bit19=1 时必须走 `fit_or_clamp` 且两条都过（来源：`src/host/health_read.mjs:236-238`），
bit19=0 时**同一组数字**的 inv 必须判红且期望回到 256（来源：`src/host/health_read.mjs:239-241`）——少了反配对，"放松"就成了"永远不判红"（来源：`src/host/health_read.mjs:231`）。

### 4.3 `--selfcheck` 到底判了哪几件事

| 段 | 判据 | 条数 | 出处 |
|---|---|---|---|
| S1 | 逐位独热走查：每个 bit 只许动它该动的字段，硬件里恒 0 的 bit7 与 bit11..15 一个都不许动 | 16 条（bit0..15） | 来源：`src/host/health_read.mjs:168-173`，归属表在 `:154-159` |
| S2 | 八个 `why` 组合对**手抄**的语义表 | 8 条 | 来源：`src/host/health_read.mjs:178-181` |
| S3 | 变异对照：造两个"整体错移一位"的坏译码器，十个真实位每一个至少被一个方向抓到 | 按位判，不写总数 | 来源：`src/host/health_read.mjs:188-196` |
| S4 | lane23 逐位独热走查 32/32（20..30 是保留位，译码器不许被它们动） | 32 条 | 来源：`src/host/health_read.mjs:207-214` |
| S5 | 八档期望都在 10 bit 区间内且"最近档"回到自己 | 8 条 | 来源：`src/host/health_read.mjs:217-225` |
| S5b | 0.25x 的期望被天花板夹住 | 1 条 | 来源：`src/host/health_read.mjs:228-229` |
| S5c..S5f | `zoomJudge` 三支各自的正/反配对（含"屏上与 inv 不同档"必须红） | 5 条 | 来源：`src/host/health_read.mjs:236-249` |

S3 为什么按位判而不写"抓到 15/16"这种总数：恒 0 的位怎么移都"什么都没改"⇒ 天生抓不到，写总数就是抄数字；而 bit5/bit6 同属 `mode_gray`，右移后落进同一个字段集合 ⇒ 单向移位会漏（来源：`src/host/health_read.mjs:183-187`）。
最后一条总判定是 `PASS/FAIL health_read --selfcheck pass=N fail=M` 并按 `n_bad` 决定退出码（来源：`src/host/health_read.mjs:250-251`）。

### 4.4 `--json`：机器可读那一份与 `null` 的语义

`--json` 存在理由写在注释里：`metrics.mjs` 要把"推流 N 秒 → 读回计数器 → 算抖动/丢包"做成一条可复跑的命令，而去解析那些中文判读行会把两个工具焊死在一起（改一句文案就崩）（来源：`src/host/health_read.mjs:355-357`）。
`lat` 那一组里 `NS_PER_CYC = 10` 是唯一的换算点（fclk0 = 100 MHz ⇒ 1 拍 = 10 ns），换 fclk 频率只改这里、并同步改构建脚本的 `PCW_FPGA0_PERIPHERAL_FREQMHZ`，两处不一致就会报偏心数（来源：`src/host/health_read.mjs:392-394`）。
四条 `null` / `false` 语义必须看懂，否则会把"没判过"读成"过了"：

| 字段 | 为 null / false 的含义 | 出处 |
|---|---|---|
| `osd_ms_matches_tot` | `usable.length === 0` 时是 null——**没判过就不算绿**，一条永远红不了的判据是假判据 | 来源：`src/host/health_read.mjs:431`、`:441` |
| `osd_ms_lanes_aligned` | 六口没都读到 `PASSES` 个值 ⇒ 数组会错位，按下标配对会报假红，而假红比不判更糟 | 来源：`src/host/health_read.mjs:413-416` |
| `torn` | `tot < c1 + c2` ⇒ 恒等式破了，读回口又变回"各读各的"（ISSUES #59 的形状） | 来源：`src/host/health_read.mjs:443-447` |
| `zoom.verdict` | `NO_LANE`（老位流）或 `STALE`（200 ms 没像素心跳）⇒ 只报旧值、不下结论 | 来源：`src/host/health_read.mjs:383-385` |

屏上 Latency 那一格与回读是否同源这件事，人读那一支也照判：不一致时输出"屏上数字与回读不是同一轮，别把屏上那个数写进报告"（来源：`src/host/health_read.mjs:537`）。
缩放那一支的两条判据缺一不可：只判 inv 对不上档 ⇒ 抓不到"送错档但算得自洽"；只判屏上档 ⇒ 抓不到"屏上与寄存器一致但取数器还在用旧值"（来源：`src/host/health_read.mjs:543-544`）。
最后一行的结论只有四种：链路已断 / 入包链一个字都没丢 / eth_rxc 没有时钟 / 丢了 N 个字（来源：`src/host/health_read.mjs:572-580`）。

### 4.5 这一站的数据形状 + 出错时看到什么

- **形状**：默认读法是"lane0..9 这 10 条 + 25/26/27/28/29/24/23/30/31"共 19 条、每条两遍（来源：`src/host/health_read.mjs:334`、`:40`）；`--json` 只输出一个对象就退（来源：`src/host/health_read.mjs:362`）。
- **形状**：`n_meas` 是 16 位饱和计数，读到 65535 意思是"至少 65535 轮"（约 2 小时 @9 轮/秒），不是"正好 65535 轮"（来源：`src/host/health_read.mjs:451-453`）。
- **出错**：`lane23` 读回 0xDEADBEEF ⇒ 这个位流没有 lane23（r54 之前的位流），手动缩放只剩"寄存器写了"那一半证据（来源：`src/host/health_read.mjs:548`）。
- **出错**：`缩放：... 像素时基 200 ms 没心跳 ⇒ 这一组是旧值，不下结论（不是通过）`——"不下结论"不等于通过（来源：`src/host/health_read.mjs:550`、`:379`）。
- **出错**：`警告：${torn} 条单调 lane 出现「变小」，那是跨域采到刷新瞬间 —— 重读确认，别记进报告`（来源：`src/host/health_read.mjs:581`）。
- **出错**：脚本自己造成的假红有两种已知形状——读 24 排在 25 之前（来源：`src/host/health_read.mjs:329-331`），以及第一版在拿不到 GPIO_0 原值时继续往下写、把控制位清零（来源：`src/host/health_read.mjs:315-317`）。

---

## 5. 读回侧：JTAG 一次读的是哪几条 lane，每条一句话

读法只有两步：lane 号写进**已经存在**的 GPIO_0 的 `bit[31:27]`，数据从新加的 GPIO_1（只读 32 bit）读（来源：`src/host/health_read.mjs:9-12`）。
顶层那根取号的线是 `wire [4:0] lm_lane = gpio_o[31:27];`（来源：`src/rtl/top/system_top.v:219`），出口是 `assign gpio1_i = lm_rd;`（来源：`src/rtl/top/system_top.v:247`），组合 mux 在 `src/rtl/top/system_top.v:237-246`。
脚本动这 5 位之前先把 GPIO_0 原值读回来、只清高 5 位、最后一遍原样还回去：`const keep = cur & 0x07ffffff;`（来源：`src/host/health_read.mjs:324`），于是 `src_sel` / 阈值 / 特效位不受影响（来源：`src/host/health_read.mjs:10-11`）。

默认一次读 19 条、每条读两遍（来源：`src/host/health_read.mjs:334` 的 `const want = [...Array(10).keys(), 25, 26, 27, 28, 29, 24, 23, 30, 31];`），
遍数取 `const PASSES = get('once') ? 1 : 2;`（来源：`src/host/health_read.mjs:40`）——19 = 10 条基础号 + 9 条后加号，别按号段末项估（这一句先前在 §4.5 写成了"20 条"，2026-10-07 按 `want` 现数改齐，两处现在都是 19）。
两遍比对的分组按"这条 lane 是不是单调"来分（来源：`src/host/health_read.mjs:47`）：单调集 `const MONO = new Set([0, 1, 5, 6, 8, 9]);`（来源：`src/host/health_read.mjs:51`）、会回卷或被清零的那四条 `const LIVE = new Set([2, 3, 4, 7]);`（来源：`src/host/health_read.mjs:52`）；
单调 lane 只有"第二次比第一次小"才算撕烈，推流过程中两遍不等本来就是正常的（来源：`src/host/health_read.mjs:22-24`、`:48-49`）。
`want` 的**顺序也是判据**：`wire          lat_arm = (lm_lane == 5'd25);`（来源：`src/rtl/top/system_top.v:236`）——指到 lane25 这件事本身就是抄时延快照的触发，先读 24 会拿到上一遍武装的那一轮，与这一遍的 27 对不上、同源判据恒红（来源：`src/host/health_read.mjs:328-332`）。

### 5.1 lane 逐条：这一位是什么、谁置它、读到 0 说明什么

| lane | 名字（人读那一栏） | 谁在什么时候置它 | 读到 0 说明什么 | 出处 |
|---|---|---|---|---|
| 0 | `drop_words` | CDC 写口被 `fifo_full` 挡住的那一拍逐字累加；这是板上唯一真实丢数据的通道 | 自启动以来一个 16bit 字都没丢过（顶层 `p_good` 恒 1，坏包这条路量不到东西） | 来源：`src/host/health_read.mjs:54`、`src/rtl/eth/link_monitor.v:187`、`:4-5` |
| 1 | `bad\|err`（低 16 = 作废帧，高 16 = 坏包） | `frame_abort` 记一帧作废、收包链判坏包记高半；两半拼在 `wire [31:0] lane1 = {err16, bad16};` | 低半 0 = 没有帧被整帧作废；高半 0 = 上板 p_good 恒 1 时"坏包应为 0"（预期值，不是证据） | 来源：`src/host/health_read.mjs:55`、`src/rtl/eth/link_monitor.v:188` |
| 2 | `stall\|rows`（低 16 = 断流 ms，高 16 = 作废帧最多缺几行） | `ms_tick` 在没有完整帧时把 `stall_ms` 往上加；`rows_missed` 与 `frame_abort` 同拍有效 | 低半 0 = 这一拍刚收完一个完整帧；高半 0 = 作废的那些帧一行都不缺 | 来源：`src/host/health_read.mjs:56`、`src/rtl/eth/link_monitor.v:189`、`:27` |
| 3 | `gap_last`（最近一帧间隔 ms ≈ 1000/fps） | 每个 `frame_done` 把 `gap_cnt` 的直接计数抄进 `gap_last`；只统计自上次 `--gapclr` 以来 | 0 = 目前只见到一帧（第一个 `frame_done` 只建基准）或被 `gapclr` 清过 | 来源：`src/host/health_read.mjs:57`、`src/rtl/eth/link_monitor.v:190`、`:110-111`、`:138` |
| 4 | `gap_min\|max` | min/max 在 `have_base` 之后每次帧边界比较着更新；`gap_max` 终身保持 | 全 0 = `gapclr` 之后还没数出第二个间隔；min 有值而 max 也有值才是"至少两个间隔" | 来源：`src/host/health_read.mjs:58`、`src/rtl/eth/link_monitor.v:191`、`:138` |
| 5 | `gap_sum`（Σ间隔 ms） | 每个间隔 `gap_sum <= gap_sum + {16'd0, gap_new}`；均值 = `gap_sum / (frames_ok - 1)` | 0 = 一个间隔都没攒上；超过 65.5 s 的间隔会饱和在 0xFFFF（来源：`src/host/health_read.mjs:59`） | 来源：`src/host/health_read.mjs:59`、`src/rtl/eth/link_monitor.v:192`、`:140` |
| 6 | `cdc_episodes` | CDC 从"没满"跳到"满"时 `cdc_ep` 加一，lane6 取它的低 16 位 `ep16` | 0 = 从没灌满过写口——这条恰好是"读 0 才是好消息"的一条 | 来源：`src/host/health_read.mjs:60`、`src/rtl/eth/link_monitor.v:193`、`:160` |
| 7 | `flags`（bit0 丢过字 / bit1 作废过帧 / bit2 灌满过 / bit3 流活着 / bit4 间隔已校准） | 五个位都由 `flag5` 组合出来：bit4 `gap_valid`（来源：`src/rtl/eth/link_monitor.v:158`）、bit3 `(stall_ms < LIVE_MS)`（`:159`）、bit2 `(cdc_ep != 0)`（`:160`）、bit1 `(frames_bad != 0)`（`:161`）、bit0 `(drop_words != 0)`（`:162`） | bit3=0 是"距上一个完整帧超过 200 ms"（`LIVE_MS = 16'd200`，来源：`src/rtl/eth/link_monitor.v:13`），其余四位读 0 都是"从没发生过" | 来源：`src/host/health_read.mjs:61`、`src/rtl/eth/link_monitor.v:194` |
| 8 | `pkts` | 收包链每收一个包 `in_pkts` 加一，输入口就是 `frame_reasm.stat_pkts` | 0 = 一个包都没进过板子（与 lane9 一起用才是对账的两条腿） | 来源：`src/host/health_read.mjs:62`、`src/rtl/eth/link_monitor.v:195`、`:28` |
| 9 | `bytes` | 每包载荷逐字累加 `in_bytes`（不含 4 B 头，见 §2.3） | 0 = 没有任何有效字节落地；lane8 有值而 lane9 为 0 说明全被当成空包 | 来源：`src/host/health_read.mjs:63`、`src/rtl/eth/link_monitor.v:196`、`:29` |
| 23 | 像素域在用的缩放状态（`dbg_zoom`） | 像素域自己一路快照总线跨到 fclk0，不参与 `lat_arm` | 读回 `0xDEADBEEF` 是"这个位流没有 lane23"（r54 之前），不是"缩放倍率为 0"（来源：`src/host/health_read.mjs:548`） | 来源：`src/rtl/top/system_top.v:241`、`:232` |
| 24 | 屏上 Latency 那一格画的 ms，位序 `{14'd0, pair_ok, 本轮 sticky, ms[15:0]}`（来源：`src/rtl/top/system_top.v:231`） | 与 `q_tot` 同一轮、由 `dbg_lat[5*32 +: 32]` 取出 | 低 16 为 0 有两种：真的 0 ms 与"这个位流没有 lane24"，靠 `pair_ok` 与 25..29 是否全 `DEADBEEF` 分开 | 来源：`src/rtl/top/system_top.v:240`、`src/host/health_read.mjs:396` |
| 25 | `{n_meas[15:0], 15'd0, clamped}`，同时是武装位 | 指到 lane25 就把 25..29 五个字**同时**抄成快照（#59 的修法） | `n_meas`=0 = 一次都没量过；这一条读 0 会让 lane26 的"历轮最大"没有分母 | 来源：`src/rtl/top/system_top.v:242-243`、`:232-234`、`src/host/health_read.mjs:395` |
| 26 | 历轮最大（`max`） | 每一轮量完取 max | 0 = 从没量出过时延 | 来源：`src/host/health_read.mjs:395` |
| 27 | `tot`（提交→开始扫描） | 与 25 同一次武装抄下 | 0 要警惕恒等式：`tot < c1 + c2` 就说明读回口又变回各读各的（来源：`src/host/health_read.mjs:443-447`） | 来源：`src/host/health_read.mjs:394-395` |
| 28 | `c2`（整帧搬运段） | 同一轮武装抄的五个字之一 | 0 = 搬运段没量到 | 来源：`src/host/health_read.mjs:394` |
| 29 | `c1`（等消隐窗口段） | 同一轮武装抄的五个字之一 | 0 = 消隐窗口段没量到 | 来源：`src/host/health_read.mjs:394` |
| 30 | 仲裁看得见的全部输入（`{16'd0, dbg_src}`，`[10:8]` = `why_ps`） | axi 域电平直接接进来，十六位都在 axi 域 ⇒ 读回不交跨域的税 | 全 0 = 判决那三拍什么都没拦住（`无（ETH 想要总线）`，见 §4.1），不是"没人竞争" | 来源：`src/rtl/top/system_top.v:239`、`src/host/health_read.mjs:364`、`:82` |
| 31 | `{30'd0, lm_clk_slow, lm_clk_gone}`：bit0 源时钟没有、bit1 源时钟被拉慢 | `hb_edge` 每到一次把 `to_cnt` 重装为 `LIM`；归零且始终没边沿 ⇒ `hb_gone`，边沿来了但 `to_cnt < FAST_ENOUGH` ⇒ `hb_slow` | 全 0 = 心跳又准又勤；拔线时 RTL8211 不停供 RXC 而是拉到 ≈2.5 MHz ⇒ 只有 bit1 会亮 | 来源：`src/rtl/top/system_top.v:238`、`src/rtl/eth/snap_cross.v:55-65`、`src/rtl/top/system_top.v:209-211` |

`lane 10..22` 这一段的"0"永远不该出现：mux 的兜底是 `else if (lm_lane > 5'd9)       lm_rd = 32'hDEAD_BEEF;`（来源：`src/rtl/top/system_top.v:244`），越界号读回 `0xDEADBEEF` 的用意就是让脚本一眼看出自己写错了号（来源：`src/host/health_read.mjs:14`）。

### 5.2 快照链：一条 lane 为什么会两遍不等

计数器在源域（`eth_rxc` / 125 MHz）里拼成 320 bit 的**整拍**快照：`lm_bus <= {lane9, lane8, lane7, lane6, lane5, lane4, lane3, lane2, lane1, lane0};` 只在 `upd` 那一拍写（来源：`src/rtl/eth/link_monitor.v:201-204`）。`upd` 的来料是事件而不是周期：`wire        upd_w = frame_done | frame_abort | frame_err` 再加上"断流超过 `LIVE_MS` 后每毫秒滴一次"（来源：`src/rtl/eth/link_monitor.v:163-164`）——所以停流之后 `stall_ms` 还在动，这是 §5.1 里 lane2 能被读活的根。
两次写入之间要留 `SETTLE` 个源周期，节流只合并发布不丢计数（来源：`src/rtl/eth/link_monitor.v:165-166`），落在窗口里的事件靠 `pend_ev` 补发（来源：`src/rtl/eth/link_monitor.v:168-171`）。
过域靠 `snap_cross`：目的域把 `bus_tog` 三级同步后取异或，边沿那一拍才 `bus_q <= bus`（来源：`src/rtl/eth/snap_cross.v:41`、`:45`、`:69-72`），源总线至少保持到下一次写入（≥1 ms）所以采到的一定是完整值（来源：`src/rtl/eth/snap_cross.v:3-5`）。心跳与总线分开量是它的第二职责：只测"心跳有没有停"不够，时钟退化时心跳一直在、`hb_gone` 永不触发（来源：`:6-7`），于是 `FAST_ENOUGH = LIM - (DST_HZ/1000*SLOW_MS)` 把 1 ms 与 ~50 ms 分居两侧（来源：`:34`）。
顶层用这两个出口去做仲裁的与门（不在这里相与）：`wire eth_live   = lm_axi[7*32 + 3];`（来源：`src/rtl/top/system_top.v:255`）、`wire eth_tb_ok  = !(lm_clk_slow || lm_clk_gone);`（来源：`:256`），理由写在紧邻注释里——单看 lane7.bit3 会永远判"活着"（来源：`:252-254`）。屏上与人读共用同一个译码函数这件事在 §4.1 已经钉过（来源：`src/host/health_read.mjs:508`）。
`--gapclr` 走另一条口：`gapclr_sel(gpio_o[26])`（来源：`src/rtl/top/system_top.v:203`）、脚本侧 `const CLR_BIT = 26;`（来源：`src/host/health_read.mjs:45`），它只清 `gap_*`，lane0/1/2/6/8/9 的"自启动以来"语义不动（来源：`src/rtl/eth/link_monitor.v:24-26`）；清完撤销 `have_base`，下一个 `frame_done` 只重建基准、不把"空闲到现在"折进间隔（来源：`:114-118`）。

---

## 6. 串口命令通路：一条命令变成哪一个位

### 6.1 从敲下回车到 `Xil_Out32` 只有四跳

1. 行缓冲收满一个 `\n` 后切 token：`/* 一行输入 → 切 token → dispatch()。缓冲区现在 128（见 CMD_BUF 那行：老值 48 会**静默截断**）`（来源：`src/ps/main.c:1423`），调用点是 `nt = tokenize(cmd_buf, tk);`（来源：`src/ps/main.c:1465`），`tokenize` 本体在（来源：`src/ps/main.c:677`）。
   截断这件事本身是失败模式：`T_MAX` 的注释写着 `gamma auto 1.20 2.60 20 1500` 要 6 个 token，而 48 字节的缓冲"塞不下 9 个有内容的 token"（来源：`src/ps/main.c:620-625`）。
2. `static int dispatch(char **tk, int nt)`（来源：`src/ps/main.c:890`）的第一件事不是比字符串而是**把首 token 当位图**：`nb = parse_bits(tk[0], &en);`（来源：`src/ps/main.c:896`），单个九字符参数直接生效（来源：`src/ps/main.c:897`）。
3. 前缀匹配走 `ci_pre(tk[0], "TH")` 这类不区分大小写的前缀判定（来源：`src/ps/main.c:911`、`:921`、`:932`、`:983`、`:1005`），老写法"参数粘着"与新写法"参数分开"共用一条出口：`const char *arg = (nt >= 2) ? tk[1] : tk[0] + 2;`（来源：`src/ps/main.c:914`）——粘着那半必须整串是数字，`THE` 这种不再收（来源：`src/ps/main.c:912-913`）。
4. 所有开关最后落到两个写口：`Xil_Out32(GPIO_DATA, v);`（来源：`src/ps/main.c:219`）与 `Xil_Out32(CFG_DATA0, ...)`（来源：`src/ps/main.c:223`），前者是 `#define GPIO_DATA (AXI_GPIO_BASE + 0x00u)`（来源：`src/ps/main.c:49`）、`#define AXI_GPIO_BASE 0x41200000u`（来源：`src/ps/main.c:48`），后者是 BD 里的 `axi_gpio_2`（来源：`src/ps/main.c:16`）钉在 `#define AXI_GPIO_CFG_BASE 0x41220000u`（来源：`src/ps/main.c:77`）。
   两个字各自只有一处写者：`ctrl_write()` 一次写完整字（来源：`src/ps/main.c:208-227`），`ctrl_apply()` 在它后面补两行回声（来源：`src/ps/main.c:229-239`）；`ps_publish()` 每帧翻 `pub_lvl` 之后**只调 `ctrl_write()` 不出声**，因为 30 fps 的每秒约 2 KB 会把 115200 的串口打满（来源：`src/ps/main.c:205-207`、`:244-245`）。

### 6.2 九位控制字与两个字的完整位图

`cfg1` 低 9 位就是九位效果选择字：`(cur_sel & 0x1FFu)`（来源：`src/ps/main.c:223`），一位一级，位的含义从 `#define SEL_GRAY (1u << 0)` 排到 `#define SEL_DILATE  (1u << 8)`（来源：`src/ps/main.c:110-118`），位定义的唯一出处点名为 `src/rtl/process/proc_pipeline.v`（来源：`src/ps/main.c:109`）。
顶层的接法：`.stage_sel(gpio_cfg1_o[8:0]), .threshold(gpio_o[15:8]), .src_sel(gpio_o[16])`（来源：`src/rtl/top/system_top.v:264`），而 `gpio_o[4:0]` 那五位 V7 老使能位"保留但不接、PS 侧一律写 0"（来源：`src/rtl/top/system_top.v:262-263`），固件侧同一件事写在下标计算之前（来源：`src/ps/main.c:211-213`）。

| 命令 | 改的变量 | 最终落的那一位 | 顶层去处 | 出处 |
|---|---|---|---|---|
| `pipe <九位>` / `000000100` | `cur_sel` | `cfg1[8:0]` | `stage_sel` | 来源：`src/ps/main.c:899-908`、`src/rtl/top/system_top.v:264` |
| `th 120` / `TH120` | `cur_thr`（夹在 0..255） | `gpio_o[15:8]` | `threshold` | 来源：`src/ps/main.c:911-919`、`:214` |
| `src 1` / `SRC1` | `cur_src` | `gpio_o[16]` | `src_sel` | 来源：`src/ps/main.c:921-930`、`:214`、`src/rtl/top/system_top.v:264` |
| `src auto` | `cur_mode_ovr` | `gpio_o[24:23]` 模式码 + bit22 翻转 | 交给按键环/仲裁 | 来源：`src/ps/main.c:927`、`:218`、`:63-65` |
| `zoom on/off` | `cur_zoom` | `gpio_o[17]` | 右屏"要不要呼吸" | 来源：`src/ps/main.c:932-942`、`:173`、`:215` |
| `zoom auto` | `cur_zman = 0` | `cfg1[29]` | 手动旗标 | 来源：`src/ps/main.c:943`、`:224` |
| `zoom 1.5` | `cur_zsel`（取最近档） | `cfg1[28:26]` | 八档档号 | 来源：`src/ps/main.c:962-974`、`:174-177`、`:224` |
| `zoom fit` | `cur_split |= ZOOM_FIT_BIT` | `cfg1[31]` | 倍率交给角度定 | 来源：`src/ps/main.c:944-960`、`:158` |
| `bilin on/off` | `cur_bilin` | `gpio_o[19]` | 双线性/最近邻 A-B | 来源：`src/ps/main.c:983-1003`、`:52`、`:216` |
| `osd off` | `cur_osd`（**反相**写） | `gpio_o[20]`，`1 = 关掉` | `osd_overlay` 输出级 | 来源：`src/ps/main.c:1005-1015`、`:53-57`、`:217` |
| `split auto/manual` | `cur_split` 的 bit23 | `cfg1[23]` `auto_en` | 扫描开关 | 来源：`src/ps/main.c:1117`、`:1126`、`:137`、`:121` |
| `split px N` / `split video` / `split screen` | `cur_split` 的 `[22:13]` 与 bit24 | `cfg1[22:13]` pos_px、`cfg1[24]` follow | 缝位与量的单位 | 来源：`src/ps/main.c:1162-1163`、`:1178`、`:121-124` |
| `rot auto` / `rot speed N` | `cur_split` 的 bit9 与 `[12:10]` | `cfg1[9]`、`cfg1[12:10]` | 自动旋转与每帧几度 | 来源：`src/ps/main.c:1065-1067`、`:1051`、`:155-157` |
| `gamma 1.8` | `CFG_DATA1` 的地址/数据/wr 协议 | 不在 cfg1，走 +0x08 那个窗口 | gamma 表 | 来源：`src/ps/main.c:1204`、`:368-372`、`:221` |
| `--gapclr`（JTAG 侧） | 只有一位是上位机写的 | `gpio_o[26]` | `gapclr_sel` | 来源：`src/ps/main.c:56`、`src/rtl/top/system_top.v:203` |

`CFG_DATA1` 那一条要**两次写**才算一次写：先摆地址与数据不动 wr，隔 5 µs 再翻 `GM_WR` 写第二遍（来源：`src/ps/main.c:368-372`），上电自检拿 `GM_DATA(0x5A) | GM_IDX(0x3C)` 这个图案验的就是这条握手（来源：`src/ps/main.c:1555-1556`）。
写错的代价固件自己点破了：`CFG_DATA0` 就是 RTL 的 `gpio_cfg1_o`、gamma 窗口是 `CFG_DATA1(+0x08)`，"两个名字差一位，写错字的症状恰恰是『设了没反应』，最容易误判成 PL 坏了"（来源：`src/ps/main.c:221-222`）。

### 6.3 上电那一次回读把两个字各验一遍

自检先写 `Xil_Out32(CFG_DATA0, 0x1FFu);` 再把低 9 位读回来（来源：`src/ps/main.c:1536-1537`），然后写 `0x00780000u`（即 `[28:26]` 档号加 `[29]` 手动旗标那一块）并回读 masked 值（来源：`src/ps/main.c:1542-1543`），两次都对才印 `[CFG] axi_gpio_2 @%08x ok`（来源：`src/ps/main.c:1550`）；不一致时那行报的是 `rb` 与 `rb2 >> 12`（来源：`src/ps/main.c:1548`）。
这条自检的意义在"JTAG 读回侧看到的 `gpio_o` 是不是 PS 真的写下去的"：`[TEMP]` 行末尾那个 `gpio=0x%02x` 就是从设备读回来的低字节（见 §3.2，来源：`src/ps/main.c:883`），而 `uart_cmd_check.mjs` 按前缀解析这些行（来源：`src/ps/main.c:1372-1373`）。

### 6.4 这一站的数据形状 + 出错时看到什么

- **形状**：一条命令的回声固定两段——`[CTRL] AXI_GPIO=0x%08x sel=%03x thr=%d src=%d zoom=%d pub=%d bilin=%d osd=%d`（来源：`src/ps/main.c:232`）加一行 `zoom_step=`（来源：`src/ps/main.c:237`），后一行把"设进去的档"和"现在是手动还是呼吸"分开报（来源：`src/ps/main.c:235-236`）。
- **出错**：`pipe` 给 6/7/8 位一律拒，理由是过去被当 9 位补零、屏上对不上（来源：`src/ps/main.c:903-905`）。
- **出错**：`zoom 1` 不是"回到 1.00×"而是**开关**（沿用 V7 的 `ZOOM1`），要 1.00 倍必须写 `zoom 1.0`——r53 第一次跑电池就红在这一格（来源：`src/ps/main.c:933-936`、`:977-980`）。
- **出错**：`bilin` 在旋转态与 1.00 倍下按构造不改变任何一个像素，所以"切了没反应"是 ISSUES #86 而不是命令坏了，`bilin show` 会连这条一起印（来源：`src/ps/main.c:987-991`）。
- **出错**：`split px 1024` 会越位——字段只有 10 位而屏宽 1024，`1024 << 13` 恰好等于 bit23 那个 `SPLIT_AUTO_BIT`，两种写口分别给出"缝位变成 0"和"自动扫描悄悄开起来而回显还说 auto 开着"（来源：`src/ps/main.c:125-136`）；现在写口前先夹一道 `split_pos_clamp()`（来源：`src/ps/main.c:165-169`），而"夹了"必须由调用方在回声里说出来、与同一处报出的百分比同源（来源：`src/ps/main.c:162-164`）。
- **出错**：`rot speed` 有一条会**顺手改状态**的路：`rot auto` 时若 speed 为 0 就替用户设成 2 度/帧，并且必须印出来——"以前这条是静默的（19:59 板上撞见 —— `rot show` 报出 speed=2 而没人设过它）"（来源：`src/ps/main.c:1066-1070`）。

---

## 7. 包格式与限速：`[u32 LE 偏移][载荷]` 与 `--pace-mbps` 护的是哪一级缓冲

三份实现的分工表在 §1，这一节只补两件事：线上那 4 个字节到底怎么写出来的，以及限速那一档保护的缓冲在哪一级。

### 7.1 同一条协议的两种写法

协议的文件头版本：`每包 **[u32 小端 帧内偏移][RGB565 载荷]**`，载荷长度必须是 8 的倍数且 ≤1392 B（来源：`src/host/udp_push.py:4-5`）。
Node 侧的三步构造：切块 `const chunk = payload.subarray(off, Math.min(off + MTU, payload.length));`（来源：`src/host/video_sender.mjs:196`）、写头 `p.writeUInt32LE(off, 0);`（来源：`src/host/video_sender.mjs:198`）、接体 `chunk.copy(p, HDR);`（来源：`src/host/video_sender.mjs:199`），循环步长就是 `for (let off = 0; off < payload.length; off += MTU) {`（来源：`src/host/video_sender.mjs:195`）。
Python 侧把同样三件事压成一行：`sock.sendto(struct.pack("<I", off) + chunk, addr);`（来源：`src/host/udp_push.py:69`），`<I` 就是"小端 4 字节无符号"（来源：`src/host/udp_push.py:25` 的 `import struct`）。
`video_sender.py` 的同一件事在 §1.1 的常数表里（`HDR = 4` 来源：`src/host/video_sender.py:34`、`MAX_PAYLOAD = 1392` 来源：`:35`），文档口径也是那句 `[u32 小端 byte_offset]`（来源：`report/host_guide.md:90`）。
两处的偏移语义要认准：**头里给的是帧内偏移 `off`，不是 DDR 地址**——板端自己按帧基址加这个偏移落位，所以"每帧从 0 重数"是这条协议的隐含契约（来源：`src/host/video_sender.mjs:195`、`src/host/udp_push.py:63`）。
丢包时头也跟着一起不发：Node 是 `droppedPkts++` 之后 `continue`（来源：`src/host/video_sender.mjs:201-203`，注释写着制造的是"一个 1392B 的洞（= 一行的一部分）"，来源：`:202`），Python 同构（来源：`src/host/udp_push.py:66-68`）。

### 7.2 `--pace-mbps` 保护的是板端入包侧那一格 FIFO

匀速的存在理由写在 Node 的注释里：`// 绝对时间限速：帧内逐包匀速发出，避免 221 包以线速倾泻打爆板端入包 FIFO。`（来源：`src/host/video_sender.mjs:171`），紧跟着是那一档的量级：`15 MB/s 下每包只有 ~93 µs 预算，Date.now() 的 1 ms 精度不够，用 performance.now()。`（来源：`src/host/video_sender.mjs:172`）。被护住的东西在硬件侧只有一个：CDC 写口被 `fifo_full` 挡住而永久消失的 16 bit 字（来源：`src/host/health_read.mjs:54`），也就是 lane0（来源：`src/rtl/eth/link_monitor.v:187`）与它的历史事件位 lane6 的 `cdc_ep`（来源：`src/rtl/eth/link_monitor.v:193`、`:160`）——打爆的后果不是丢包而是丢字，且只有这两条 lane 能看见。
限速的开关与量级三份各不相同：Node 默认 15、`--no-pace` 关掉（来源：`src/host/video_sender.mjs:42-43`），`udp_push.py` 默认 15.0 且帮助文本明说 `0 = 不限速（用来找过载点，不是日常值）`（来源：`src/host/udp_push.py:43-44`），`video_sender.py` 默认 20.0 且帮助文本写"演示不要用它"（来源：`src/host/video_sender.py:47-48`）。`udp_push.py` 在 `pace=0` 时**连 fps 都不等**：`if not a.pace_mbps:` 之后直接 `continue`，注释给的理由是"让『过载』这件事成为被观察的对象而不是被节奏遮住"（来源：`src/host/udp_push.py:135-137`）——这一档是故意用来把 lane0 打出读数的。
帧内匀速的实现细节决定了它能不能当判据：Node 用 `Atomics.wait` 睡整段再尾部自旋对齐绝对时间线（来源：`src/host/video_sender.mjs:175`、`:183-184`），Python 的 `Pacer` 按累计字节数推时间戳而不是叠加 sleep，因为"sleep 会被调度抖动放大，而本项目要报的恰恰是帧间隔的抖动"（来源：`src/host/udp_push.py:75-76`）。这条差别对 §9 有直接后果：上位机的发送节奏本身就是抖动来源之一，所以帧间隔的读数只能拿板端 lane3/4/5 的计数当口径（来源：`src/host/health_read.mjs:57-59`），发送侧那句 `~15.1 fps` 是均值不是节奏（来源：`src/host/video_sender.mjs:227`）。

---

## 8. 测试图与图案选型：每种看得出什么、看不出什么

八种图案的入口是一个参数：`--test` 默认 `bars`（来源：`src/host/video_sender.mjs:45`），名单在 `src/host/video_sender.mjs:13`。
`move` `frameid` `hold` `blocks` `wordid` 各有专门的分支，`edge` `grad` `bars` 共用最后那个循环（来源：`src/host/video_sender.mjs:144-161`）。

| 图案 | 看得出什么 | 看不出什么 | 出处 |
|---|---|---|---|
| `bars`（默认） | 横条 `((y + phase) >> 3) & 1` 的错位、左侧 8 像素彩条 `if (x < 8)` 的列错位、黄块 `cx` 的拖影 | 看不出"这个字是哪一帧写进来的"：帧号只进 `phase = n % 64`，隔 64 帧的两次外观一模一样 | 来源：`src/host/video_sender.mjs:144`、`:154-157`、`:146` |
| `grad` | 行/列渐变 `put(x, y, (x + n * 2) & 255, (y * 2) & 255, 128);` 断一行就是一条硬边，缩放走样与缺行都在这一张上 | 无色块边界，看不出换帧是否原子（整屏都在缓变） | 来源：`src/host/video_sender.mjs:151-152` |
| `edge` | 换帧原子性：整屏逐帧黑白交替，"非原子会看到灰行或残影"；颜色不重要，重要的是每一帧都整屏一样，任何"半新半旧"都能被读出来 | 看不出洞在哪一行（整屏同值），也看不出缩放参数对不对 | 来源：`src/host/udp_push.py:10`、`:53-57`、`src/host/video_sender.mjs:145`、`:149-150` |
| `move` | 两件事同时判：方块只在白象限内往返、永不触边、永不跨参考线 ⇒ 重影/拖尾就是换帧不原子；蓝象限铺 4 像素粗网格 ⇒ 粗网格不闪说明先前细线闪烁是最近邻缩放的走样（1px 线落到采样间隙）而不是数据问题 | 看不出逐字归属，也判不了滞后几帧 | 来源：`src/host/video_sender.mjs:62-65`、`:73-74`、`:66` |
| `hold` | 内容与帧号完全无关 + 方块固定居中 ⇒ 屏幕上还撕裂就是显示数据通路问题（两帧相同不可能混出差异）；干净则说明之前的撕裂来自图案自身被裁切或只在运动时才有换帧混合；蓝象限 1 像素白网格（每 32 像素）专门查行级错位 | 看不出丢包，因为根本没有帧间差别 | 来源：`src/host/video_sender.mjs:95-98`、`:104-105` |
| `blocks` | 大色块 + 单像素参考线：纯色场不会产生手机摩尔纹 ⇒ 屏幕上看到的任何椒盐点都是真实数据问题；同时用来判断换帧是否原子、有没有拖影 | 自描述仍然没有，归因不靠它 | 来源：`src/host/video_sender.mjs:115-116`、`:122-124` |
| `wordid` | 自描述：每个 64 bit DDR 字（4 像素）填它自己的字号 ⇒ 回读 DDR 就能对上"这个字应该是几号"；`--wordid-add` 给相位偏移，用来区分"这一帧真丢了"和"上一帧碰巧写过同样的值" | 帧号不进图案，所以量不出换帧滞后（它只回答"字对不对"） | 来源：`src/host/video_sender.mjs:133-135`、`:137` |
| `frameid` | 每个 16 bit 像素 = 字号 + 帧号 ⇒ 回读能反解"这个字是第几帧写进去的"：`n_implied = (lane - w) & 0xffff`，用来定量测换帧滞后与逐字混合程度 | 看不出缩放/色彩类的观感问题（画面是噪声场） | 来源：`src/host/video_sender.mjs:84-86` |

### 8.1 归因实验为什么用 `frameid` 而不是 `bars`

`bars` 的帧号只以两种方式使用：`const phase = n % 64;` 和 `const cx = ((n * 7) % (W + 120)) - 60;`（来源：`src/host/video_sender.mjs:144`、`:146`）——前者是 64 帧一周期的模数、后者是 632 帧一周期的位置，两者都不是帧号本身；拿它当证据时"屏上这张是第 N 帧还是第 N+64 帧"在图案里不可区分。
`frameid` 把帧号**写进每一个字**：`const v = (w + n) & 0xffff;` 然后同一个 `v` 铺满这个 64 bit 字的四个像素（来源：`src/host/video_sender.mjs:87-90`），于是回读任意一个字都能解出帧号，而 `& 0xffff` 的量程是 65536 帧（约 73 min @15 fps，帧率来源：`src/host/video_sender.mjs:41`），一次实验不可能绕回去。
这一条正好接上 `--dump FILE`：落"最后两帧"供 `ddr_verify.mjs --ref` 比对（来源：`src/host/video_sender.mjs:222`），比对时参照物就是这份自描述图案。
`wordid` 与 `frameid` 是同一族的两步：前者只钉"字的编号对不对"（不含 `n`，来源：`src/host/video_sender.mjs:137`），后者把 `n` 加进去（来源：`:87`）才能回答"滞后几帧"；`--wordid-add` 那个偏移参数就是为了排除"上一帧恰好写过同样的值"这种误判（来源：`src/host/video_sender.mjs:133-135`）。

### 8.2 这一站的数据形状 + 出错时看到什么

- **形状**：图案模式的进度行是每 30 帧一条 `[TX] frames=${n} ~${(n/dt).toFixed(1)} fps`（来源：`src/host/video_sender.mjs:225-227`），选图案看的是屏幕，选读数看的是这一行与 §5 的 lane。
- **出错**：`--file` 与图案二选一：`udp_push.py` 不给 `--file` 又改了 `--pattern` 就报 `FATAL: 要么 --file 给裸帧流，要么 --pattern edge` 并退码 2（来源：`src/host/udp_push.py:101-103`）。

---

## 9. 指标是怎么算出来的：两次 `--json` 的差值与两格口径

### 9.1 一次采集只有四个动作

`metrics.mjs` 的存在理由写在文件头：一条命令做完"推流 N 秒 → 读回硬件计数器 → 算成指标"，并把原始读数一起存档（来源：`src/host/metrics.mjs:7`），三条动机分别是可复跑、采集与计算分不开就会出错、原始 JSON 与算出来的表一起入库（来源：`src/host/metrics.mjs:13-18`）。
读回走的是同一支脚本：`execFileSync('node', [join(HERE, 'health_read.mjs'), '--json', ...extra], ...)`（来源：`src/host/metrics.mjs:95-96`），取 JSON 的方式是"过滤出第一个 `{` 开头的行再 `JSON.parse`"（来源：`src/host/metrics.mjs:97`），拿不到就抛 `health_read 没吐出 JSON：` 加前 200 字符（来源：`src/host/metrics.mjs:98`）。
两次读回的身份不同：基线带 `const base = readHealth(['--gapclr']);`（来源：`src/host/metrics.mjs:171`），结束那次带 `const after = readHealth(['--once']);`（来源：`src/host/metrics.mjs:184`）——`--once` 意味着只读一遍，不做两遍撕烈比对（来源：`src/host/health_read.mjs:40`），因为这一路要的是差值而不是逐遍一致性。
中间那步是发脚本进程：`[join(HERE, 'video_sender.mjs'), '--ip', IP, '--fps', String(FPS), '--count', String(COUNT)]`（来源：`src/host/metrics.mjs:174-175`），`COUNT = Math.max(1, Math.round(FPS * SECONDS))`（来源：`src/host/metrics.mjs:167`），墙钟耗时在子进程返回后取 `wall`（来源：`src/host/metrics.mjs:181`），发送器非 0 退出只打一行不中断（来源：`src/host/metrics.mjs:182`）。
数据来源一句话讲清：`link_monitor` 的 10 条快照 lane 加 lane31 的时基标志，经 `health_read.mjs --json` 从 AXI GPIO 读回，基线用 `--gapclr` 把帧间隔统计归零，其余计数器是"自启动以来"的，所以全部按差值算（来源：`src/host/metrics.mjs:20-22`）。

### 9.2 算式的三条口径规矩

差值只有一式：`const d = (k) => (a[k] - b[k]);`（来源：`src/host/metrics.mjs:46`），注释点名"只认差值"以及哪几条已被归零（来源：`src/host/metrics.mjs:43`）。

| 指标 | 算法 | 为什么是这个分母/分子 | 出处 |
|---|---|---|---|
| `frames_recv` | `d('bytes') / FRAME_BYTES`，`FRAME_BYTES = 307200` | 交付的完整载荷字节折成帧；lane9 是载荷字节不含头（见 §2.3） | 来源：`src/host/metrics.mjs:47`、`:38` |
| `frames_ok` | `frames_recv - d('frames_bad')` | 被验收门作废的帧照样交付字节，但硬件的 `gap_sum` 只累加真正被接收的那些帧的间隔 | 来源：`src/host/metrics.mjs:48-53` |
| `gap_segments` | `Math.max(0, Math.round(frames_ok) - 1)` | `gap_sum` 是 N−1 段之和（第一帧只建立基准），分母必须是段数 | 来源：`src/host/metrics.mjs:15-16`、`:54-55` |
| `avg_gap_ms` | `d('gap_sum') / segs`，`segs = 0` 时给 `NaN` | 单帧没有间隔可算，必须是 NaN 而不是"0 ms ⇒ Infinity fps" | 来源：`src/host/metrics.mjs:56`、`:131-133` |
| `fps_from_gap` | `1000 / avg_gap_ms` | 由间隔反推的帧率，与墙钟那一路是两个口径 | 来源：`src/host/metrics.mjs:57`、`:84` |
| `fps_wall` | `frames_recv / wall_s` | 用子进程真实耗时，不靠 `--fps` 的标称值 | 来源：`src/host/metrics.mjs:85`、`:123` |
| `gap_min_ms` / `gap_max_ms` | 直接取 `a.gap_min` / `a.gap_max`，**不做差值** | 基线刚 `--gapclr` 归零，差值等于自己 | 来源：`src/host/metrics.mjs:79-80`、`src/host/health_read.mjs:42-43` |
| `rows_miss_max` | `Math.max(a.rows_miss_max \| 0, b.rows_miss_max \| 0)` | 这一条终身保持、`gapclr` 不清它，所以只能取前后较大值，不能算差值 | 来源：`src/host/metrics.mjs:72-73` |
| `verdict_no_word_lost` | `d('drop_words') === 0 && d('cdc_episodes') === 0` | 一个字都没丢 = 丢字增量为 0 **且** CDC 从未灌满 | 来源：`src/host/metrics.mjs:89-90` |

`--selftest` 把这些算式钉成不打板子的判据（来源：`src/host/metrics.mjs:103`、`:11-12`）：30 帧的账是"收满 9,216,000 B；间隔统计 29 段 × 33 ms = 957 ms"（来源：`src/host/metrics.mjs:115-117`），段数判据 `r.gap_segments === 29`（来源：`:120`）；
反面对照专门钉"曾经算错的那一版"——如果分母错用 N（30），`wrong` 与 `fps_from_gap` 的差必须大于 0.3（来源：`src/host/metrics.mjs:127-130`）；
分母用错总体的现场事故写在注释里：`--drop-every 200` 那次 597 帧全部作废，工具却报 `avg=22.4 ms / 44.7 fps`，而 `gap_min` 是 6667 ms（来源：`src/host/metrics.mjs:50-51`），对应的自测用例是"整轮都被作废 ⇒ 平均间隔/fps 必须是 NaN"（来源：`src/host/metrics.mjs:143-147`）；
自相矛盾检查是常驻的：平均间隔必然落在 `[min, max]` 里，越界就把矛盾直接印出来而不是等人肉眼发现（来源：`src/host/metrics.mjs:58-66`），两个方向的正反用例是 `gap_avg_impossible === true` 与"正常输入不许误报"（来源：`:151-154`）。
存档落两份：`metrics_${TAG}.md` 与 `metrics_${TAG}.json`，JSON 里是 `{ before, after, metrics, wall_s }` 四个键（来源：`src/host/metrics.mjs:210-211`），人读那份把原始 JSON 也整段贴进去（来源：`src/host/metrics.mjs:206-208`），屏幕上再打一遍时把 JSON 块换成一句"已写入文件"（来源：`src/host/metrics.mjs:212`）。
过载实验与演示工况不能混着念这件事写在参数旁边：`--no-pace` 让上位机尽最大能力发，用来量"链路+入包链在过载下怎么样"，与"限速 15 MB/s 的正常演示"是两个不同的问题（来源：`src/host/metrics.mjs:177-179`）。

### 9.3 `data/metrics.csv` 里那两格的口径差别

`入流帧间隔（PL 内）` 那一格给的是 33.34 ms、类别"核心"，测量条件写的是 PL 侧收包链量的**相邻两帧之间隔**：`gap_sum/gap_segments` 件内自报 33.3434 ms、8999 段，min/avg/max = 20 / 33.34 / 51 ms，同轮墙钟交付 29.79 fps（来源：`data/metrics.csv:25`）——分子分母就是 §9.2 那两式，8999 段对应 9000 帧那一轮（来源：`data/metrics.csv:25`、`src/host/metrics.mjs:55-56`）；同一句里明写了它**不含**上位机编码、网线与交换机排队（来源：`data/metrics.csv:25`）。
`端到端时延` 那一格是另一件事：类别"未报"、数值 `—`，理由是"这一格有读数出口（OSD 的 Latency lane 与 JTAG 回读），但本表不填没有复核过的数"，取到可信值之前不占权重也不宣称（来源：`data/metrics.csv:20`）。
所以两格不可互换：33.34 ms 是**入流侧的节奏**（两帧完整交付之间隔了多久），端到端时延是**像素进网线到像素上屏的滞后**，后者的读数出口在 lane24..29 那五段分解（`c1` 等消隐窗口、`c2` 整帧搬运、`tot` 提交→开始扫描，来源：`src/host/health_read.mjs:394-395`），而本仓库至今没有复核过的数填进那一格（来源：`data/metrics.csv:20`）；把前者当后者写会同时漏掉上位机与网络排队那一段、又把"两帧之间"的量当成"一帧之内"的量（`tot` 的起点是提交，来源：`src/host/health_read.mjs:394`）。
同表相邻两行各有口径：`ETH 入流 300 秒长跑` 报 0 丢帧/坏帧/重复帧、29.99 fps、平均 33.34 ms、9000 帧（来源：`data/metrics.csv:23`），`帧间隔抖动` 在 30 fps 限速工况给 min/avg/max = 22 / 33.33 / 45 ms 并注明抖动上界来自显示扫描与读口调度而不是调度器（来源：`data/metrics.csv:26`），`入流过载点` 是"未定 ≥116.7 fps"、因为那一版没顶到丢字那一点所以不给"PL 能扛多少 fps"的数字（来源：`data/metrics.csv:24`）。
两把尺子各管一段：`health_read.mjs --selfcheck` 管译码（来源：`src/host/health_read.mjs:250-251`）、`metrics.mjs --selftest` 管算式（来源：`src/host/metrics.mjs:11`），改一句文案不会崩算式（动机见 §4.4）；表里"帧间隔 min/avg/max"在 avg 是 NaN 时印 `—` 而不是 `NaN`（来源：`src/host/metrics.mjs:200`），看到 `—` 要顺着 §9.2 去读 `frames_ok`。

---

## 10. SD 那一路的旁路工具

### 10.1 上位机侧：`make_sd_video.mjs` 产的是"板子能直接顺序读"的帧库

一句话用途：把任意视频转成开发板能直接顺序读的 512×300 RGB565 帧库（来源：`src/host/make_sd_video.mjs:6`），命令行形态是 `node src/host/make_sd_video.mjs --in D:/path/a.mp4 --out E: [--chunks 512] [--preview]`（来源：`src/host/make_sd_video.mjs:8`），三个默认值 `./input.mp4` / `./sd_stage` / 512（来源：`src/host/make_sd_video.mjs:35-37`），输入不存在就 `找不到输入视频: ` 并退码 1（来源：`src/host/make_sd_video.mjs:38`）。
布局的四条理由都写在文件头，全为"PS 端固件的简单与可验证"（来源：`src/host/make_sd_video.mjs:10`）：每帧 `307200 B = 512*300*2`、行主序、小端 u16，和上位机 UDP 推流的字节序完全一致，所以固件读到缓冲区后可以整块 memcpy 进 DDR bank、不需要任何转换（来源：`src/host/make_sd_video.mjs:11-12`，常数在 `src/host/make_sd_video.mjs:26-27`）；文件名一律 8.3（`VIDEO000.BIN` / `META.TXT`），因为 FatFs 若未开 `_USE_LFN` 长文件名会读不到（来源：`:13`）；按 `--chunks` 帧切成多个文件，单文件小、顺序读友好，也避开 FAT32 的 4 GB 上限（来源：`:14`）；`META.TXT` 是唯一需要解析的文件（来源：`:15`）。
几何不变形靠 `force_original_aspect_ratio=increase` 加 `crop` 居中裁切，理由那句给的是数：512:300 = 1.7067 与 16:9 = 1.7778 不同，直接 scale 会横向拉伸（来源：`src/host/make_sd_video.mjs:16-17`）；片源本身的宽高/帧率/帧数由 `ffprobe` 取（来源：`src/host/make_sd_video.mjs:42-44`）。
`--preview` 把第 0 帧（和中间一帧）从 RGB565 反解成 PNG，人眼直接看出"行序/字节序/裁切"对不对，注释收在"不靠猜"（来源：`src/host/make_sd_video.mjs:19-20`），PNG 是零依赖的最小写出（来源：`src/host/make_sd_video.mjs:54`）。

### 10.2 板侧：`sd_play.c` 自己解析 FAT32

不用 FatFs 的理由在文件头：BSP 的 libsrc 里没有 xilffs（只有 sdps），而卡上的文件布局是自己用 `make_sd_video.mjs` 生成的——只有 8.3 名、只有簇链，一个只读目录扫描 200 行就够，引入 FatFs 反而多一层没人验过的代码（来源：`src/ps/sd_play.c:4-6`）。
它期望看到的东西与上位机侧对得上：`VIDEO000.BIN .. VIDEO008.BIN`，满块 512 帧 × 307200 B = **157 286 400 B = 150.0 MiB = 157.3 MB**（这一格先前写的是"153.6 MiB"：那个数只有把 1 MB 当成 1024×1000 B 才得到，即 `157286400 / 1024 / 1000 = 153.6`，是 MiB 与 MB 之间少除一次 1.024；2026-10-07 19:5x 用 `node` 现重算改对。同一句话的**源头在 `src/ps/sd_play.c:9` 的注释里**，那一处本轮没动——`ARCH/A7:392` 早就把这两个数标出来了），末块不满：本卡实测 `VIDEO008.BIN frames=302`，八满块 4096 + 302 = **4398** 与 `frames=4398` 对平（来源：`board/measured/qspi_selfboot_uart_capture_2026-10-07_1935.txt:202-210`）；`META.TXT` 的键是 `WIDTH/HEIGHT/FRAME_BYTES/FRAMES/FPS/CHUNK_FRAMES/FILES/SOURCE` 加每文件的 `FILEi=名字 FRAMES=n BYTES=b`（来源：`src/ps/sd_play.c:8-10`）——`CHUNK_FRAMES` 与 `--chunks` 的默认 512 是同一个数（来源：`src/host/make_sd_video.mjs:37`、`src/ps/sd_play.c:10`）。
帧的落地路径刻意做成零拷贝：SD 控制器的 DMA 直接写 PL 要读的那块 DDR（来源：`src/ps/sd_play.c:12`）。
解析规则只有一条：**行首匹配 `KEY=` 才认**，避免把 `FILE` 行里的 `FRAMES=` 当成全局帧数（来源：`src/ps/sd_play.c:291`）；这条判据本身曾经写错成指针比较、症状却是"这张卡的 META.TXT 不合格"，于是内置了"一段必须过、两段必须被拒"的三段样本自检（来源：`src/ps/sd_play.c:382-386`、`:433-436`）。
清单被缓冲区截断时的现象：`FRAMES=512` 被切成 `FRAMES=51` ⇒ 少算的帧数是**假缺口**、卡本身没坏，同时挂出 `META.TXT longer than the buffer read - file list truncated`（来源：`src/ps/sd_play.c:368-370`）。
`[STAT]` 里那三格 `sd=` / `frames=` / `playing=` 就是这一路的读数出口（来源：`src/ps/main.c:1386`，字段表见 §3.1）。

### 10.3 `sd remount` 为什么存在

驱动侧没有"卡被拔掉"这个事件：没有任何路径把 `mounted` 清 0（来源：`src/ps/sd_play.c:578`），而丢卡之后的清理也**故意不动** `Sd.IsReady`——那是 `sd_remount()` 的事，这里只把账本撕成"没挂载"（来源：`src/ps/sd_play.c:582`），函数本体是 `int sd_remount(void)`（来源：`src/ps/sd_play.c:565`）。
所以恢复有两条腿：自动那条一旦卡丢了（`mounted` 变 0）就每 2 s 试一次 `sd_remount()`（来源：`src/ps/sd_play.c:596`），试到 30 次仍不成则停手并打出那句人话——`[SD] 自动重挂 30 次没成功，停手：插上卡后敲 \`sd remount\`，或重下 elf`（来源：`src/ps/sd_play.c:627`）；播放中途失败也是同一句提示 `PLAY retries; if it keeps failing, \`sd remount\``（来源：`src/ps/sd_play.c:865`）。
"为什么需要人工那一下"有 A 侧凭据：卡在不插的状态下敲 `sd remount` 回的是 `[SD] remount failed: XSdPs_CfgInitialize failed`（来源：`src/ps/sd_play.c:561-562`）——它证明重挂走的是控制器初始化而不是只读一遍目录。
- **形状**：换卡的正确顺序是"插卡 → `sd remount` → `stat` 看 `sd=1` 与 `frames=` 的新值"，`sd=` 取 `sd_frame_total() ? 1 : 0`（来源：`src/ps/main.c:1386`）。

---

## 11. 完整性与失败模式：上位机侧会静默掉哪些错

| 静默点 | 静默的方式 | 现场判据（先看哪一行） | 出处 |
|---|---|---|---|
| 文件末尾的半帧 | 只打一行就 break，不发残帧，退出码仍是 0 | `[TX] 文件读完（最后一帧不完整，丢掉）`，且 `n` 应当等于 `文件字节数 // 307200` | 来源：`src/host/udp_push.py:127-129`、`src/host/video_sender.mjs:266` |
| 载荷不是 8 的倍数 | 打完警告**照样发** | 警告句 `--mtu-payload=%d 不是 8 的倍数，包边界会毁掉 64bit 字（规律黑点）`；板上唯一能看它的是 lane0 的 `drop_words` | 来源：`src/host/udp_push.py:95-97`、`src/host/video_sender.mjs:30`、`src/host/health_read.mjs:54` |
| `--src ""` / 绑不上本机地址 | `sock.bind` 抛错被吞，退回默认路由，脚本继续跑 | `[WARN] bind ... failed: ..., use default route`；开场行里**没有**源地址，只有 `[TX] ${IP}:${PORT}`，所以源 IP 是否真是 192.168.1.100 只能靠这条 WARN 反证 | 来源：`src/host/video_sender.mjs:166-169`、`:40`、`:212` |
| COM6 被别的终端占住 | PowerShell **照样返回 0**，空捕获以前会算绿 | 抓到的文件长度为 0（`CAPTURED_LEN 0`）⇒ 口被占或板子没在跑，两种都要红；判定只看文件内容不看退出码 | 来源：`build/board_verify.sh:42`、`:83`、`:62`、`:179`、`:190` |
| 一个口两个写入者 | 后打开的那边报错，前一份命令流水被冲掉 | checker 自己记着这条：既占了 COM6 又把钉在板上的那一态冲掉（2026-09-30 早上撞的） | 来源：`src/host/uart_cmd_check.mjs:298`、`演示流程-3分钟.md:26` |
| `mrd` 解析不到值 | 打出一片 0，看起来像"计数器都是 0" | 不要 `lindex`/`split`，整串打出来由 Node 解析；同族教训是"读回 0 就算对"不是判据——不存在的从设备常常也返回 0 | 来源：`src/host/health_read.mjs:265-267`、`src/ps/main.c:1532-1534` |
| 发送器非 0 退出 | 指标表照算、流程不中断 | `[M] 发送器退出码 N：` 那一行 + 表里 `发送帧数` 与 `frames_recv` 是否自洽 | 来源：`src/host/metrics.mjs:182`、`:195-196` |

三条串起来看的规矩：算式类红先怀疑分母总体（§9.2 的 `自相矛盾` 那一行，来源：`src/host/metrics.mjs:65-66`）、读数类红先怀疑解析而不是板子（来源：`src/host/health_read.mjs:265-267`）、
串口类红先确认"有没有第二个人开着这个口"（来源：`build/board_verify.sh:62`）；三类的原始件都落在同一个目录层级里，
`metrics.mjs` 落 `metrics_${TAG}.md` 与 `.json`（来源：`src/host/metrics.mjs:210-211`）、`board_verify.sh` 落 `$OUT.boot.txt` 与转码件（来源：`build/board_verify.sh:155`、`:190`）、
`health_read.mjs` 的失败行直接进 stdout（来源：`src/host/health_read.mjs:302-308`）。

---

## 12. 未证清单

本卷没能从仓库里读到正文、因此**没有**写进上面各节结论的东西，逐条列在这里：

1. `report/host_guide.md:141` 那句 COM6 / `UnauthorizedAccessException`：本卷只从 `LEARNING/04-ps-firmware-command-plane-and-boot.md:486` 的转引看到该句及其行号，`report/host_guide.md` 正文未读 ⇒ §11 那一行按转引写，不标 `host_guide.md` 的行号。
2. `src/host/arb_handover_test.mjs`、`src/host/geom_check.mjs`、`src/host/uart_cmd_check.mjs` 三份脚本各自判了哪几条：只读到调用行（来源：`build/board_verify.sh:245`、`:257`）与 `uart_cmd_check.mjs` 的用法行、默认端口行（来源：`src/host/uart_cmd_check.mjs:8`、`:38`）⇒ 判据清单未证，本卷不写"它测了 X"。
3. `make_sd_video.mjs` 真正写出 `META.TXT` 与分块文件的那一段（ffmpeg 调用行、`FILEi=` 行的拼装处）：只读到文件头的意图与 `ffprobe` 段（来源：`src/host/make_sd_video.mjs:10-20`、`:42-44`）⇒ "产什么格式"这一问的正面证据来自**读侧**的描述（来源：`src/ps/sd_play.c:8-10`）。
4. `video_sender.py` 的构包与发送循环：只读到常数区、参数区、开场行与 cost 式（来源：`src/host/video_sender.py:32-35`、`:42-53`、`:197`、`:233`），没有读到它写 4 字节头那一行 ⇒ 它与另外两份"同一套 `[u32 小端偏移][载荷]`"这件事，本卷只按 `src/host/udp_push.py:4` 与 `report/host_guide.md:90` 的口径写，不给 `video_sender.py` 的行号。
5. lane24..29 里 `pair_ok`、`sticky` 两个位的**产生条件**与 `c1`/`c2`/`tot` 三段起止点的 RTL 实现：只有注释级证据（来源：`src/rtl/top/system_top.v:230-231`、`src/host/health_read.mjs:394-396`），`frame_latency` 那颗模块本卷没读 ⇒ §5.1 那三行只写到"同一轮武装抄的五个字"这一层。
6. `data/metrics.csv:25` 里 `33.3434 ms / 8999 段` 那一次的原始 JSON：本卷没有把它对回任何 `metrics_*.json` 件（该行的证据列写的是 `report/perf_report.md`）⇒ §9.3 只复述 CSV 自述的口径，不声称复核过分子分母。
7. `sd_play.c:811`、`:826`（`sd_frame_total()` / `sd_is_playing()`）正文：本卷沿用 §3.1 的引用，没有再读那两个函数体 ⇒ "frames 是静态字段"这条在 §10.3 只作提示、不展开。
8. `ddr_verify.mjs` 与 `--dump` 的比对算法：只读到 `--dump FILE` 的一句用途（来源：`src/host/video_sender.mjs:222`）⇒ §8.1 只写"参照物是自描述图案"，不写它怎么比。

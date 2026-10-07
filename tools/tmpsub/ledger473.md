### #473 板子切到 QSPI 档之后的第一轮整机复验：命令层 105 条全过、冷上电自启带着 SD 自动播、网口收侧逐包逐字节对平（drop_words=0）

- **为什么这一笔值得单独记**：之前所有整机复验都是在 **JTAG 档 + 三步链刷板**之后跑的，而这一轮是**你把拨码切到 QSPI、断电重上**之后跑的——
  被测的是"从 flash 自己起来的那一份"，不是"我用 JTAG 刚塞进去的那一份"。凭据四件（逐字搬运、没加头、没改写）：
  `board/measured/qspi_selfboot_uart_capture_2026-10-07_1935.txt`（原始串口回显 364 行）、
  `board/measured/qspi_selfboot_uart_check_2026-10-07_1935.txt`（判据器 stdout 112 行）、
  `board/measured/eth_push_demo_2026-10-07_1939.txt`（PC 侧发送统计 2 行）、
  `board/measured/qspi_selfboot_lanes_2026-10-07_1950.txt`（PL 健康快照 JSON，`--json` 全 19 条 lane）。
- **① 冷上电自启（机器判）**：电池第一条 `STAT` 就有回显，且读 `sd=1 frames=4398 playing=1`
  ⇒ 上电自己挂载 FAT32 并**已经在自动回放**，全程没碰下载器。这把 r126 那句"断电自启整条成立"从
  "能出画面"升级到"起得来 + 自己挂卡 + 自己开播 + 命令层答得动 + 收侧计数器读得到"。
- **② 命令层电池 `RESULT PASS`（105 条、98.5 s）**：判据是逐条对回声（含 `!` 反判据），不是"看看有没有回应"。
  覆盖面按动词数：`split` 25 / `zoom` 13 / `src` 10 / `rot` 10 / `pipe` 9 / `temp` 7 / `gamma` 5 / `sd` 4 /
  `STAT` 3 / `th` 2 / `osd` 2 / `bilin` 2，另有 `frame` `autoplay` `help` 与老写法 `TH120`/`THE`/`ZOOM1`/`BILIN1`/`SRC2`/`TEMP`/`AUTOPLAY0`。
  **该拒的都拒且不改状态**：`src 9`、`zoom 9`、`sd file 99`（只认 0..8）、`split px 9999`（只认 0..512）、`BOGUS`；
  五位老写法 `pipe 11000` / 裸 `01010` 走的是**翻译**出口（回"等价的九位是：pipe 100001000 / 000011000"，且反判据 `!sel=` 要求一个寄存器都没写）——
  这正是 #66 那两条正判据 + 一条反判据在守的东西。
  **末态 = 初态**：`thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 sel=000 gm=0.00 mode=0 geom=00400000 osd=1`（`pub` 每位翻，判据本来就不比它），
  判据器另打一行 `NOTE 初态 = 文档默认档（zsel=4 zman=1 mode=0 AUTO）` ⇒ 这次"回到初态"是在**默认档上**证的，
  不是像 r75 之前那样在一个被上一轮钉过的状态上自证（#99 那一课的延续）。
- **③ 温度格**：同一次 stdout 里 `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`。
- **④ 网口那一路这次量到收侧了，而且是逐包逐字节对平**：
  发送侧 `python src/host/video_sender.py --demo --seconds 12` = **361 帧 / 12.05 s = 29.97 fps、79 781 个包**（512×300 RGB565、pace 20.0 MB/s）；
  接收侧 `health_read --json`（`pkts`/`bytes` 这些是**自启动以来**的计数，而这块板子上电后只被我推过这一次 ⇒ 总量就该等于这一次）：
  `pkts=79781`（= 发送侧包数，逐包对上；`79781 / 361 = 221.000` 包/帧，整除）、
  `bytes=110899200`（= 361 × 307200，一分不差）、**`drop_words=0`**、`frames_bad=0`、`pkt_err=0`、`rows_miss_max=0`、`cdc_episodes=0`；
  流内时延 `lat.tot_ms=10.206`（均值）/`max_ms=17.13`/`n_meas=361`（测量次数正好等于帧数）、`osd_ms=10` 与 `tot_ms` 同侧对齐（`osd_ms_matches_tot:true`）。
  `ping -n 3` **3/3、0% 丢**（往返 1/2/1 ms）。
  **读法两条要说清**：`src_state.eth_live=0 / why="没有流"` 与 `stall_ms=65535`（计数打满）都是**快照时刻流已经停了**的正常读数，
  不能反过来当"没收到"的证据——收到没收到看的是上面那组自启动以来的总量与零丢字。
  另一条：这次读 lane 走的是脚本自己的mux（只改 GPIO_0 的 bit[31:27] 选 lane、读完把原值写回，见 `src/host/health_read.mjs:11-14`），
  我起的 `hw_server` 用完已 `taskkill`（PID 22592），没留在后台占下载器。
- **⑤ QSPI 档下 JTAG 仍然读得到**（这条推翻了"要读 lane 就得把拨码切回 JTAG 档"的直觉）：
  模式拨码只在**断电上电那一刻**决定 BOOT 源，JTAG 口本身照常可挂；旧凭据 `board/measured/pl_config_state_qspimode_2026-10-06.txt` 早就是这个事实，
  今天第一次把它用在整机复验上。**仍不能做的是往 PL 重灌位流**——那一条会让正在跑 AXI 的 PS 楔死（DAP `0xF0000021`），与读计数器不是一回事。
- **⑥ 还欠的眼睛/手**：①推流那 12 秒里屏上 `SRC:` 那格是不是 `ETH`、`FPS:` 读多少；②现在在动的是哪一路画面；
  ③那颗 LED 每秒几下（≈1.5 下＝正常心跳，≈6 下＝出过 V-blank 拷贝超时，`src/rtl/top/pl_video_top.v:1038-1039`）；
  ④傍晚那格"灰度钉上之后右半是否变黑白、左半仍彩色"（本次快照 `mode_gray=0 / why_gray=2` ⇒ 现在灰度是关的，与 `sel=000` 自洽）。
- **⑦ 工具/编码两条小账**：判据器支持 `--out`，所以串口捕获写到 `Prj/pro/tmpsub` 再搬进 `board/measured/`，
  **没有覆盖跟踪件** `board/uart_script_capture.txt`（那一份是 #220 留给 `board_verify` 的）；
  四件新凭据里串口那份的字节形状与既有跟踪件**同一种**（UTF-8 BOM `efbbbf` + CRLF，`tr -cd '\r' | wc -c` 读 364），
  `src/host/doc_enc_check.mjs` 在这一支跑完仍读 `扫了 429 个手写文件：全部干净`。

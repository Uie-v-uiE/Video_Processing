# 采集条件卡 · 卡 B1：JTAG 回读板上 DDR（两份留档）

本文件的"卡 B1"是本文件内部编号（B 族），与同目录 `01-`/`02-` 那批卡的编号无关。

| 格 | 件 A：`data/measured/ddr_dump_20260921_15fps.out.gz`（+ 控制台 `data/measured/board_measure_15fps.txt`） | 件 B：`data/measured/ddr_dump.out` |
| --- | --- | --- |
| 激励 | `node src/host/measure_v63.mjs --fps 15 --count 200`：推 **frameid** 图案 200 帧 ⇒ 停止 ⇒ 回读两个 bank（`board_measure_15fps.txt:1`） | 同一支尺子的默认件（`src/host/ddr_stale.mjs:19` 的 `DUMP` 缺省值）。图案是 **wordid**（首行 `10000008: 00010001` 这种"值＝字序号"形状）⇒ 与件 A 不同口径，见"缺项"行 |
| 输入规格 | 512×300 RGB565 = 307200 B/帧 = 221 包/帧，负载 1392 B/包，目标 `192.168.1.10:5001`，源 `192.168.1.100`；节奏 15 fps（`pace=15 MB/s`） | 同上（`WORDS=38400` 个 64 bit 字 = 153600 个 16 bit lane；`src/host/ddr_stale.mjs:20-22`） |
| 时钟与功耗模式 | 收包域 `eth_rxc` 8 ns（125 MHz）；显示域 `clkout0_1` 20 ns。**推流结束到回读之间等 500 ms 让最后一帧落位**（`board_measure_15fps.txt:11`）。功耗档 `【待补】` | 同左，但**发送节奏与"是否在推流中回读"没有写进件 B**（件 B 没有配套控制台）⇒ `【待补】` |
| 软件版本 | `【待补】`：件 A/B 都没有自报 bit/elf 的 md5（`data/measured/README.md` 只给了日期与命令）。仓库里能查到的同期身份是 r70 前后（`report/log/issues.md:3616` 记 2026-09-26 的板子是 r70） | `【待补】`（同左） |
| 仪器量程 | JTAG `mrd`：bank0 `0x10000000`、bank1 `0x10080000`，各 76800 个 u32（`[DDR] dumping 2 bank(s) over JTAG (38400 words each)`）；**绕过 D-Cache 的注意事项写在 `src/host/ddr_verify.mjs:40`**（`mrd` 走 A9 端口会读到缓存旧数据） | 同左 |

本轮脚本重跑（不碰板子，只吃留档件）的读数见 `board/compare/ddr-stale-15fps-dump.txt` 与
`board/compare/ddr-stale-wordid-dump.txt`；两份都是 32 格统计（两个 bank × 六个包内偏移带 + 帧号分布），
件 A 的结论行是 `最新帧 100.0 % 命中、六带丢字率全 0.0 %、连续丢字带 2 个 lane`，
件 B 只有 BANK 10000000 一段被解析出（`=== BANK 10000000（76800 个 u32）===` 一行）。

**新读数的归因（铁律 8，先归因再谈设计缺陷）**：
件 A 的控制台末尾有一句 `[DDR] 两个 bank 都没读到有效 wordid 图案：帧没有写进 DDR`（`board_measure_15fps.txt:23`），
而同一份件里逐 bank 的 frameid 分析却报 `主导帧号=f198、十段新帧占比各 100 %`。
两句**不矛盾**，原因是**同一工具的两条路用了两把尺子**：那句话来自 wordid 检查器，而这一轮推的是 frameid 图案 ⇒
判为"检查器射程不符（口径/尺子）"，**不判为"DDR 没写进去"**，也不判为设计缺陷。
⇒ 引用件 A 时只能用 frameid 那一段的行；那句"没写进 DDR"不许单独摘出来当结论。

缺项后果：
- **软件版本 `【待补】`** ⇒ 这两份 100 % 命中**不能**与任何 r9x/r11x 的板级读数并列比（差的可能就是收包链那一刀，
  比如 `acceptance.md:20` 第 5 行 r94 的 `drop_words=0` 是另一把尺子（lane 计数）而非 DDR 逐字）。
- 件 B **只有单帧**（所有 lane 的"帧号"都是 0）⇒ 它证明"字落位对了"，**不证明**"连续 200 帧都无损"；
  把它当"入包链长期无损"用就是拿单帧冒充多帧（取样次数不同口径，铁律 4）。

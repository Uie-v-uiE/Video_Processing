# 演示与答问脚本（3 分钟版 + 追问弹药）

> 目的：明早板子起来后，**照着念就能演示**，并且每句对外说的话都能立刻指到仓库里的文件与数字。
> 纪律（也是比赛口径）：**只说板上演示过的**；没跑过的写"开发中/未验证"，不当成结论用。
> 出处一律给路径，别在台上凭记忆报数。

---

## 0. 起板（一次性，约 2 分钟）

```bat
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
set XSDBAT=D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat
%XSDBAT% build\tcl\ps_jtag_boot.tcl                               :: 拉 PS（ps7_init 自动从 xsa 解出）
%VIVADO% -mode batch -nojournal -source build\tcl\program_pl.tcl  :: 只配 PL（必须在上面那步之后）
%XSDBAT% build\tcl\ps_app_reload.tcl                              :: 只复位 A9 + 下 elf + con，串口出 [BOOT]
```
两条顺序上的硬规矩（都是板上撞过的，见 `OVERNIGHT_LOG.md` §18-R28-B、§19）：
`ps_jtag_boot.tcl` 里有 `rst -system`，它会**清掉 PL 配置** ⇒ 之后必须重下 bit；
反过来，换/重下 PS 应用只用 `ps_app_reload.tcl`（`rst -processor` 复位 Cortex-A9），
**位流、AXI GPIO 控制字、正在跑的视频流都不受影响**。
应用现在自己在开机时写 `0x41200000`（`[CTRL] AXI_GPIO=0x000A5000 …` 那行就是回显），
所以 `set_src.tcl` 只在"不跑 PS 应用、纯拿 JTAG 演 PL"时才需要；串口里 `SRC1` 是同一件事。
（elf 里没有 FSBL 也能跑：入口是标准启动 `_boot`，它开 CPACR/FPEXC、各模式栈、VBAR 与 MMU，
 见 ISSUES #42/#44；启动后寄存器状态可用 `board/pswhy.tcl` 一次采出来。）

**2026-09-24 06:4x 起本脚本用的是 #31 的位流 + #32 的固件**（`build/frozen_r32_sdfix/`，
12 个文件的 `md5sum -c` 全 OK）：`system.bit` 前缀 **`efc89779`**（与 `frozen_r31_srcmode/` 逐字节同一份），
`ps_app.elf` 前缀 **`c00b6553`**。下 bit / 下 elf 前各自 `md5sum` 一次再决定要不要重跑。
为什么 elf 必须取 #32 那份：**#31 的 elf 播 SD 会在第 3584 帧停住**（ISSUES #50，根因是 PS 固件把
FAT32 目录项的高簇字按大端拼 ⇒ 首簇 ≥65536 的文件才发作；卡与 FAT 都是好的，**不用重拷卡**）。
换了 #32 之后可以当场讲的新事实：**整卡 4398 帧播完并自动回绕**，串口 155 s 抓取零失败
（凭据 `build/frozen_r32_sdfix/sd_hotspot_fixed.txt`），且挂载时会自报
`[SD] dir map ok: 9 files, first clusters within 1946818` —— 没有这一行就是 elf 不对。

（历史口径，保留以免和旧报告对不上）下 bit 前 **先 `md5sum build/system.bit`，必须以 `18443ffd` 开头**（= build#23：V7.7 同一功能 +
R22 两笔 CDC + R23 `copy_abort` 翻转同步 + R24 厂商发送仲裁（#37）+ R26 自研收包链（#38）+
R27 参数集中化 + **R29 去掉挡在 PS 片源前面的那块红色占位（#47）** ⇒ 这一版起 **SD 卡回放在屏幕上看得见**，
WNS +0.740 / WHS +0.042 / 0 失败端点(23613) / LUT 7403(13.92%) / BRAM 64.64% / 2.178 W / L1 43/43；
**回退链**：build#22 `43b76e15`（`build/frozen_r22_param/`，功能与 #23 同、只是看不到 PS 片源）、
#21 `f39e2e78`、#19 `545a27a1`、#18 `534f7760`、#17 `11998af8`、#13 `0f46ec91`（都在各自 `build/frozen_*/` 里有实体）；同名文件会被构建原地覆盖，今晚真发生过两次 ——
判据与"冻结必须拷工件"的规矩见 `report/BUILD.md` §7 与 `report/OVERNIGHT_LOG.md` §9.5 第 1 步。
**注**：build#18 那一版冻结时只把校验和写进 MANIFEST、bit 留在活路径 `build/system.bit` 上，
被 #19 覆盖过 ⇒ 后来靠 `git show 7578217:build/system.bit`（md5 核对 = `534f7760`）复原进
`frozen_r18_abort/system.bit`。**这次救回来了是因为仓库恰好把 bit 入库，不是流程的功劳** ——
从 #19 起冻结一律实体拷贝，见 `report/BUILD.md` §7。

推流：`node src/host/video_sender.mjs --ip 192.168.1.10 --port 5001 --test move --fps 15`

---

## 1. 三幕（每幕 40 秒，每幕都有一句"可核对的数字"）

### 第一幕：一条完整的 PL 以太网视频链，不看屏幕也能判断健康
1. 推流 → HDMI 右半窗出画面（左半窗是**未旋转的原画面**，用来做对照）。
2. 敲 `STAT` / 跑 `node src/host/health_read.mjs`：屏上 OSD 与读回计数一致
   （`DROP`、`STALL`、帧序号）。
3. **拔掉网线**：OSD 的 `STALL` 立刻钉 **9999**，`hb_slow` 变 1；插回去自动恢复。
   讲法：*"很多人做'屏上有黑纹才算坏'，我们把链路健康做成运行期可读的两个计数。"*

可核对数字（`data/measured/board_measure_r09.md`、`report/OVERNIGHT_LOG.md` R08–R10）：
拔线/插线两轮共 **200 次健康采样零误报**；`--gapclr` 对账误差 **0.1%**。

### 第二幕：几何 —— 逐度旋转 + 无极缩放（右半窗）
1. 按 key1/key2：右窗**逐度**转（`angle_ctrl.v` 是 +1/−1、0..359 环绕），左窗不转。
2. 缩放是自动呼吸（`inv_scale` 256→512 循环，256=原始大小/最大，512=0.5×）；
   `ZOOM0` 停、`ZOOM1` 起（V7.7 起这条命令才真的生效）。
3. 讲法：*"缩放与旋转是同一条逆映射链，旋转用 4 个 ROM + 2 个 DSP48 乘加，
   不写浮点、不查表插值，因此每像素周期一次取数就够。"*

### 第三幕：SD 卡本地回放（证明不依赖 PC 也能出图）
1. `SD` → 期望打印 `FAT32 part_lba=2048 spc=32 rootclus=2 data_lba=34816` /
   `frames=4398 fps=30.000 files=9 frame=307200B` + 九个 `VIDEO00n.BIN frames=512`（末份 302），
   且**不再打 `WARN`**（只读 FAT32 解析，无文件系统库）。
   这里自带一段 20 秒很好用的故事："判据也要有人复查"。上一版固件只读清单的**第一个扇区**，
   而 `META.TXT` 有 712 B ⇒ 第 5 个 `FILE` 行的数字被切成 `51`，串口于是报
   `files=5 / playing 2099 frames only`，而**卡本身逐字节是对的**（PC 重生成后 md5 全等）⇒ ISSUES #48。
   现在固件两件事都做对：读满首簇内的 8 个扇区；并把"清单比缓冲区长"与"卡内容与清单不符"
   分成两条不同的 `WARN`，不再让截断伪装成拷贝不全。
2. `PLAY` 循环播、`STOP` 停、`FRAME123` 单帧跳。**每 100 帧自己报一次速率**：
   `frame NNNN: last 100 frames 29.999 fps` —— 现场就有人问"多少帧"的话，指着这行念。
   两条独立核对（同一张卡、同一次会话）：12 秒窗口里 `STOP` 回报 360 帧 ⇒ **30.0 fps**；
   150 秒连续跑 46 个窗口全 29.999。⇒ 卡片读带宽 ≈ 9.0 MB/s（300 KB/帧）。
3. **网线：不再要求"配 bit 之前拔掉"**——PL 里的片源仲裁已经过板级机器判据（#31 位流 + #32 固件，bit `efc89779`）。**可核对的数字**：停流→交回 PS 七次实测 **210 / 285 / 297 / 357 / 406 / 434 / 481 ms** ⇒ 对外只说 **0.2–0.5 s，并报采样分辨率 300 ms**，不说"立即"；接管 150–377 ms，七次都是 0 次意外翻转。现场要复现就一条命令 `node src/host/arb_handover_test.mjs`（约 2 分钟，打印 V1–V6 + V0 七条 PASS/FAIL）。
   演进过程本身就是最好的一段讲法（三步，每步都有凭据）：
   · 第一版 `eth_mode = 3FF(|s_pkts)`：ARP 就触发、拔线不回 0 ⇒ PS 片源被永久锁死（ISSUES #47）；
   · 第二版改成"最近真有帧"（`stall_ms < 200`）**并且**"量它的时基还准"（`eth_tb_ok`），
     因为板级发现断链时 RTL8211 不停 RXC 而是把它拉到 ≈2.5 MHz，那位"活着"能连着十几秒说谎（#49）；
   · 第三版（#31）修的是另一条**同症状不同根**的原因：长按事件的同步链复位值与源头不一致，
     上电白送一次"长按"，模式自己走到"锁 ETH" ⇒ 仲裁长占不放（#52）。
     它藏了一天的原因是**这段逻辑写在顶层、没有任何台架碰得到**。
   现在的可核对数字（`node src/host/arb_handover_test.mjs` 一条命令现场跑，约 40 秒）：
   推流→接管 **150–253 ms**，停流→交回 PS **210–434 ms**（四次独立测量），
   交回后 0 次回跳，再推流 180 ms 内可逆。设计预算 200 ms（判"没流"）+ 20 ms（让位静默）≈ 220 ms。
   **报数要说区间并报分辨率**：判据的时间分辨率就是采样周期（100 或 300 ms），
   所以"285 ms"不能念成硬件精度。
   还剩三条只能靠眼睛（已登记在 `board/README.md`）：交回之后画面确实活着、两路同时不闪、
   长按四态轮转与图卡会动。
   一句提醒：**回放跑着的时候别让调试器按住内核**（`arb_handover_test.mjs` 现在测前自动 `STOP`、
   测完 `PLAY`），否则会踩到 #45/#50 那一族——控制器被停在传输中间，本上电周期再也挂载不上。

4. **屏幕这一跳已经打通（build#23，`18443ffd`）**：板上眼睛确认屏幕出现 SD 卡视频画面
   （左窗原图、右窗同一帧的旋转+缩放）。在此之前 `pl_video_top.v` 显示前最后一级 mux 用
   粘性的 `eth_link_pix` 当"有没有片源"，网线一拔就把整块显存涂成红色，PS 片源在屏幕上不可达
   （ISSUES #47；判据与门禁见 `OVERNIGHT_LOG.md` §19）。
   撕裂的判据不是眼睛：`ps_publish` 的发布握手 + 每场只在 V-blank 内原子提交（`sim/tb_ps_publish.v` 逐相位）。
   讲法：*"片源选择是 PL 里一个 bit，PS 只翻转一根发布线；这块红让我发现'看不见的片源'和'没搬的片源'
   在两版 bit 上长得一模一样 —— 所以我先让 DDR 自己说话（JTAG 读回内容在变），再修显示。"*
5. 若 `SD` 报 `card absent or CMD sequence failed`：卡不在 BSP 那个 SDIO 控制器上，先查 PS 配置；
   若报 `XSdPs_CfgInitialize failed` 且此前挂载成功过：那是 ISSUES #45（每个上电周期只成功一次），
   重下一次 elf（`build/tcl/ps_app_reload.tcl`）即可，不用碰卡。
   讲法：*"PS 只负责把一帧的 DMA 目标地址准备好并翻转一根发布线，PL 只在帧尾取用一次。"*

### 第四幕（**只有 KU5P 板级验证通过之后才讲**）：第二块板自己说话
1. 另开一个窗口：`node src/host/ku5p_stats.mjs` → 应该看到每秒一行
   `frames=… pkts=… bytes=… bad=0 oob=0 rows_miss=0 …`。
   讲法：*"同一套自研以太网栈，在 UltraScale+ 上只换了 RGMII 那三个文件；
   它现在不光会应答，还会每秒主动上报自己收到了什么、有没有错。"*
2. 追问"错是怎么量的"：`bad`/`oob`/`rows_missed` 全部来自 `frame_reasm` 的硬件计数，
   不是软件统计；这包数据的**线上格式**由 `sim/tb_ku5p_telem.v` 逐字节钉住
   （Ethernet/IP/UDP 头字段 + 载荷 36 字节 + 用网卡同样的方法验 CRC）。
3. **板级没过之前**，这一幕的口径只能是："移植已综合/实现收敛（WNS +2.081 ns、0 违例），
   遥测与发送仲裁**有台架判据**，板级验证在路上" —— 不要说"板上已经在发包"。

---

## 2. 资源与时序（一句话 + 出处）

*"xc7z020 上，140 个 BRAM 用到 90.5（64.64 %），Slice LUT 7577（14.24 %）、寄存器 6026（5.67 %），
动态功耗 2.159 W，时序 WNS +0.764 / WHS +0.062、23840 个端点 0 个违例，
方法学 0 条 CRITICAL WARNING、0 根布线错误网线，约束全部满足。"*

出处：`build/timing_summary.rpt`、`build/utilization.rpt`、`build/power.rpt`、
`build/methodology.rpt`、`build/route_status.rpt`、`build/cdc.rpt`，
与 `build/system.bit`（md5 前缀 `efc89779`，成套冻在 `build/frozen_r31_srcmode/`）**同一次构建**。
每次重跑之后这一句要跟着换，别沿用旧数字（`bash build/gates.sh` 会先打印 bit 与报告的 mtime）。

| 说什么 | 数字 | 出处（现场可打开） |
|--------|------|--------------------|
| BRAM 都花在哪 | 90.5 tile 里 **80 片是显示帧缓存**、9 片是收包 CDC FIFO、2 片是模糊/Sobel 行缓 ⇒ 再省只能改架构 | `build/util_hier.rpt`、`report/PERF_REPORT.md` §4b |
| 帧缓存怎么从红变绿 | BRAM **98.93 % → 64.64 %**（按 2 的幂拆两块，省 48 个 tile） | `report/CHANGELOG_V7.md` V7.1(R04)；对照实验 `sim/probes/` |
| 打包缓冲不再吃触发器 | Slice Registers **51.30 % → 9.02 %**（打包 FIFO 改分布式 RAM） | 同上 V7.0(R02) |
| 入包链一个字不丢 | 30 fps × **9000 帧 / 1,989,000 包 / 302 s**，两次独立长跑：`drop_words=0`、CDC 灌满 0、验收门作废 0、平均帧间隔 33.34 ms（29.99 fps） | `board/evidence_r41/metrics_r41_soak300*.json` |
| 过载余量 | 上位机不限速时实测交付 **116.7 fps**（512×300，≈36 MB/s）仍 0 丢字 ⇒ **上限在上位机与网线**，所以不报"PL 能扛多少 fps" | 同上 `metrics_r41_nopause120.json` |
| 丢包记账对得上算术 | 每 2000 包丢 1 ⇒ 一帧 221 包 ⇒ 预测命中 11.05 %，实测作废 **66/597 = 11.06 %**；每 200 包丢 1（221 > 200）⇒ 597/597 全作废 | `report/PERF_REPORT.md` §6b |
| 仲裁交接时序 | 接管 150–253 ms、**停流后 210–434 ms 交回**、0 次回跳、可逆（预算 220 ms；分辨率=采样周期） | `build/frozen_r31_srcmode/arb_handover_green_r31.json` |
| SD 回放速率 | 4398 帧 / 9 文件，**29.999 fps** 连续 46 个 100 帧窗口（≈9.0 MB/s 卡读带宽）；上电自动开播，串口自己报速率 | `board/uart_r28_autoplay.txt`、`board/uart_50_probe.txt` |
| 时序瓶颈在哪 | 最差路径是 **OSD 字符行 → `u_osd/b_reg`**：26 级逻辑、66 % 是走线延迟 ⇒ 下一笔优化该动它，不是以太网 | `build/timing_summary.rpt`；`report/OPTIMIZATION_LOG.md` |
| 功耗 | Total ≈ **2.32 W**（Dynamic 2.159 W），vector-less 估算、置信度低 ⇒ 只做同口径相对比较 | `build/power.rpt` |

---

## 3. 被追问时的弹药

- **"丢了包怎么恢复？"** 每包带 32bit 全局偏移 + 16bit frameid，乱序/重传直接按偏移写；
  缺包不阻塞其它行，整帧缺一行就标 `bad_frame` 不提交。判据：`sim/tb_v6_ingress_integrity.v`；
  为什么不用"按序到达"：`skill/udp_offset_reasm.md`、`skill/frameid_loss_signature.md`。
- **"为什么不用 PS 跑协议栈？"** PS 只做控制面（GPIO + SD 回放），视频数据全程在 PL：
  `report/PS_VS_PL.md`；RGMII 收流在 125 MHz 域做解析、50 MHz 域拼帧，跨域只有显式 CDC。
- **"旋转时画质为什么不掉？"** 诚实答案：**目前右窗是最近邻**，斜向有栅格闪烁；
  双线性已经写完（组件 + 集成 + 台架全过；当时 L1 **37/37**，主线现在 **40/40** 里仍包含这两个 bilin 台架），但 250 MHz 分时读口差最后
  **0.327 ns** 没收口 ⇒ 没进主线，实现打在 tag `v7.8-bilinear-wip`。
  要现场给评委看一眼"插值长什么样"：临时下 `build/failed_r24/system_r24_WNS-0.327.bit`，
  串口 `BILIN0/BILIN1` 现场对比；**看完必须换回 `build/system.bit` 并重新校验 md5**
  （那块 bit 时序未收口，只作观察，不作交付）。
- **"换到 UltraScale+ 要改多少？"** 已经改完并收敛：`ku5p/README.md` +
  `study/02_架构/04_跨器件移植_Zynq到UltraScale.md`（`MMCME2_BASE→MMCME4`、
  `IDDR/ODDR` 单时钟、RGMII 用 `IDDRE1+BUFIO`、没有 `IDELAYE2`；
  同一套协议栈在 `xcku5p-ffvb676-2-i` 上 **WNS +1.840 / WHS +0.012 / 0 失败端点 / 0 CRIT WARN**，
  BRAM 72、LUT 2268）。上板项（ping/收流）留白天。
- **"这套东西的瓶颈在哪？"** HP0 带宽不是瓶颈（实测结论 `skill/zynq_ddr_bandwidth.md`）；
  真正卡住画质升级的是**显示帧缓存只有 1 个读口/每像素一次**，解法与代价见
  `skill/derived_clock_port_mux.md`（同相 5 倍时钟分时 5 次读、零新增 BRAM）。

---

## 4. 千万别说的五句

1. 不要说"板上已有双线性插值" ⇒ 主线 bit 没有；说"组件与集成已完成并通过台架，正在收最后一笔时序"。
2. 不要说"拔线能立刻看出" ⇒ 拔线后 PHY **不停发 RXC**，只是慢到约 **1/49**；
   所以判据是"沿够不够快"（`hb_slow`），这句本身就是我们的加分点，讲出来比吹"实时检测"更有说服力。
3. 不要说"时序余量很大"也不要说"WHS 快翻了" ⇒ build#22 是 **WNS +0.566 / WHS +0.044 / 0 失败端点**；
   口径是"全部约束满足、零失败端点；setup 余量 +0.566 ns（那条链所在时钟周期 20 ns 的约 2.8%），
   hold 余量小属于布局紧"。**别沿用旧数字**（#18 是 +1.002、#21 是 +0.770）—— 各次的最差路径是**同一条结构路径**
   （OSD `x_d_reg→b_reg`），差的那 0.4 ns 是布局布线轮次差异，不是逻辑退步（`eth_ctrl` 在另一个
   125 MHz 域、只多一级寄存；逐条对齐见 `build/frozen_r19_arb/MANIFEST.txt`）。
   **hold 不是 PVT 风险点**：低压高温时单元与布线一起变慢，数据延迟变大 ⇒ hold 反而更稳，
   会恶化的是 setup（`ku5p/README.md` §10 把这条讲清楚了，被问"PVT 怎么办"就用它）。
4. 不要说"KU5P 已经在板上发包了" ⇒ 今晚只有**台架级**证据（逐字节 + CRC 判据 + 门禁全绿的构建）；
   口径是"移植与遥测已完成并通过仿真与实现门禁，板级验证在路上"。
5. 不要把 KU5P 遥测里的 `bad≈0` 说成"没有错包" ⇒ 它目前是**构造性为 0**（顶层没接 FCS/ER 判定，
   ISSUES #38）；能当健康证据的是 `oob`、`rows_miss` 与 flags 里的 `abort_seen`。

---

## 4.5 两条命令就能做出的"今天新增能力"现场证据（各 10 秒）

| 演什么 | 命令 | 应该看到 | 为什么这算证据 |
|---|---|---|---|
| **三重提交门限**（丢包不撕裂，宁可停在上一帧） | `node src/host/video_sender.mjs --ip 192.168.1.10 --port 5001 --test move --fps 15 --drop-every 40` | 画面**不会**出现半新半旧的撕裂带；`health_read.mjs` 里 `frames` 增速掉下来但 `rows_miss`/`bad` 不说谎 | 确定性丢包（每 40 包丢 1 个）= 可重复演示，不是碰运气；这一条正是 V4 那次"累计字节数把空洞帧伪装成完整"的回归面 |
| **目的端口过滤**（V7.9.6 / ISSUES #38 刚进顶层） | 同上但 `--port 5002` | 画面**完全不动**，而 `health_read.mjs` 显示链路仍 up、`pkts` 不涨 | 说明"没画面"的原因是被过滤掉，而不是链路断了 —— 两者可分辨，这本身就是可观测性的卖点 |

> **别把第二条说过头**：`stat_drop_filt`（被过滤掉的包数）**还没有接到可读寄存器上**，
> 所以这条只能演"收不到"，不能报"我数到了几个被过滤的包"。接不接是个独立小决定，
> 记在 `report/ISSUES.md` #38 末尾。

---

## 5. 万一现场不对

| 现象 | 先查 | 依据 |
|------|------|------|
| 无输出/黑屏 | LED0 心跳在不在；`md5sum build/system.bit` 对不对；SRC 位是不是 1 | §9.5 第 1、5 步 |
| 画面撕裂/半新半旧 | `health_read.mjs` 读 `copy_overrun`；拷贝是否超出一场 V-blank | `pl_video_top.v` 的 VBLANK_AXI_CYC 注释 |
| **SD 播到第 3584 帧就停 / `STAT` 变 `sd=0`** | 先怀疑 **elf 不是 #32 那份**：`md5sum build/ps_app.elf` 应以 `c00b6553` 开头，且挂载横幅里要有 `[SD] dir map ok: 9 files, ...`。若已变 `sd=0`：重跑 `ps_jtag_boot → program_pl → ps_app_reload` 一遍就回来，**不用断电、不用拔卡**（卡是好的，见 ISSUES #50 结案段） | `build/frozen_r32_sdfix/MANIFEST.txt` |
| 停流后画面没交回 SD | `node src/host/health_read.mjs` 读 lane30：`owner_eth / eth_live / eth_tb_ok / mode` 四个位就能分清是"仲裁还占着"还是"模式被手动锁在 ETH"；`mode` 若是"锁ETH"就是被人长按锁住了 —— `KEY1` 长按 1.2 s 每按一次前进一格（自动→锁ETH→锁PS→锁图卡→回自动），最多按三次回自动 | `board/README.md` 无人值守交接判据 V1–V6 |
| 推流没画面但 PC 能 ping 通 | ARP：板子只有点对点直连验证过，过交换机不保证 | `skill/board_eth_uart.md` |
| SD 打不开 | `SD` 的报错文本（`card absent` 是控制器问题，不是文件系统问题） | `src/ps/sd_play.c` 的 `sd_err()` |

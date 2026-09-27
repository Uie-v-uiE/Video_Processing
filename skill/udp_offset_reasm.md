# S1 · 把上位机的原始帧收进 PL：分包按 offset 落位，加上手写 RX 链的五处隐性假设

> 四段式：适用场景 / 使用方法 / 已验证效果 / 失效条件。
> 本条合并了原 **S6 `pl_rgmii_udp_offload.md`**（同一条接收链的另一半：协议栈本身），两页原本
> 有两条失效条件写得一模一样（`p_good` 硬接、端口写死三处），现在只在这里写一次。

## 适用场景

- PC/上位机向 FPGA 推**原始帧**（视频、点云、矩阵），每帧远超一个包 ⇒ 必须切包；而切包顺序一旦与
  写入顺序耦合，网络抖动就直接变成画面错位。
- 数据面想彻底离开处理器：ARP / ICMP / UDP 全部由 RTL 应答，PS（或 MCU）只做控制面。
- 症状长这样：画面均匀黑点、拖影、"最新一帧没上来"，而你手里没有一条命令能说清**丢在哪一级**。
- **不适用**：需要可靠/有序的场景（本方案丢包就是丢包，靠下一帧自愈）；走 SoC 自带 MAC + lwIP
  那条通路的工程（下面所有结论都建立在"不经过 CPU 缓存与协议栈"上）；UltraScale+ 器件（失效条件 6）。

## 使用方法

### 一、协议侧的四个决定（按这个顺序做）

1. **包头带绝对偏移**：`[u32 LE byte_offset][payload]`，`byte_offset` 是**该载荷在目标帧内的字节偏移**；
   接收侧把它换算成写地址（`wr_addr <= off[18:1]` —— 注意单位是**存储字索引**还是字节地址，本工程是
   16bit 字索引）⇒ **按 offset 落位，绝不按到达顺序追加**。
   行号由 `off / 行字节数` 现算，用来记"本帧哪些源行被写过"（`src/rtl/eth/frame_reasm.v`）。
2. **提交门是两条与门**：`被写过的行数 == 总行数` **且** `帧内字节累计 == 帧长`，并且本帧没有坏包，
   才允许翻 bank；换页本身还要等跨域排空（`src/rtl/eth/ddr_bank_commit.v`）——
   把"换页"与"数据就绪"分成两件事，不然屏会在半帧上翻页。
3. **坏帧策略说死**：丢弃、不重传、屏上保留上一帧 —— 但事件必须被记成**数字**
   （`frame_abort` / `rows_missed` → `src/rtl/eth/link_monitor.v` → OSD 与 `health_read.mjs`），
   而不是留成屏幕上一条没人能计数的黑纹。
4. **载荷长度是量出来的，不是随手取的**：本工程 1396 B 分包时最新帧命中率 99.9%、每帧 **222 个**
   16bit 空洞（111 处 × 2，洞里是 0x0000 ⇒ 屏幕上均匀黑点）；改 1392 B 后 100.0%、0 洞；
   后来写侧按 16bit lane 生成 `WSTRB`，同 1396 B 复测也是 0 洞。
   ⇒ 换板 / 换位宽 / 换 burst 语义都要重量一次这条对齐边界，**别沿用别人的"8 的倍数"**。

### 二、手写协议栈的五处隐性假设（每一条都会静默改变行为）

1. **前导码状态机是一段隐性契约**：上板那一条是 `src/rtl/eth/gmii_rx_mac.v:96-113`
   （S_WAIT 吃掉第一个 `0x55`、S_PRE 数剩下的并等 `0xD5`）。动 DDR 相位、计数器位宽或状态编码，
   整链就收不到包，而它**不会报"为什么没包"** —— 现象与"对面没发"一模一样。
2. **ARP 只缓存一个对端**：`arp_rx.v:27-28` 的 `src_mac/src_ip` 是一对输出寄存器，
   被三个发送机直接当目的地址用 ⇒ 同网段多主机时回复目标会漂；`arp_rx.v:137` 还接受全 1 广播目的地址。
3. **"树里有这段代码"≠"板上有这个功能"**：厂商 `udp.v` / `udp_rx.v` 仍在仓库里、也有台架在跑它们，
   但顶层不再例化（收侧 V7.9.6 换成 `gmii_rx_mac` + `udp_rx_parser` 那一对）⇒
   引用"某某检查已经做了"之前，先确认**被例化的那条链**上有它
   （`bash build/orphan_rtl.sh` 就是干这个的：拿综合日志当可达性 oracle）。
   同一件事的另一半：目的端口过滤**现在确实在顶层**（`udp_rx_parser.v:151` 比 `UDP_PORT`），
   但被它丢掉的包只输出三个统计脉冲、**没接成可读寄存器** ⇒ "过滤掉了多少"板上看不到
   （`report/CONTEST_CHECKLIST.md` §2 第 4 条）。**功能与它的可观测性是两笔账。**
4. **被硬接的统计位**：`p_good` 曾经是 `1'b1`（厂商 `udp_rx` 不给错误标志），
   于是下游"坏包计数"**构造性为 0** —— 那一版所有关于坏包的遥测都是死数字。
   今天它由自研 FCS 检查给真值（`eth_udp_video_top.v:233` 的注释就写着"原来是 1'b1"），
   但"它真的会跳"目前**只有台架证据**（`tb_v795_rx_chain` 的 C2，见 `report/CONTEST_CHECKLIST.md` §2 第 5 条）。
   ⇒ 通用规矩不变：**任何"看起来恒真/恒 0"的输入都要 grep 它的驱动**，并在结论里写清它靠哪一级证据。
5. **端口/地址/IP 在几处各写了一份**：`UDP_PORT=16'd5001` 出现在 `eth_udp_video_top.v:8`、
   `udp_rx_parser.v:5`、`system_top.v:145`，上位机 `src/host/video_sender.mjs:34` 又独立写死一份 ⇒
   改一个不会报错，只会静默不通。全部结论只在**点对点直连 + 静态 IP** 下取过，
   换成交换机后上面第 2 条（单对端 ARP）与广播接受会让结论漂移；连线那一半在 [S7](board_eth_uart.md)。

### 三、怎么跑（脚本只有仓库根那一份，本目录不放副本）

```bash
bash sim/run_one.sh tb_udp_reasm            # 正常/乱序/丢包/重复/帧跳变/坏包 六类激励
bash sim/run_one.sh tb_v6_cover_gate        # 提交门：丢包的帧被拒绝、有洞的帧被计数、下一完整帧仍能提交
bash sim/run_one.sh tb_v6_ingress_integrity # SIM_ARGS="+FULL +MISALIGN"：整帧入包链的逐字判据
```

台架里把"行覆盖"与"字节覆盖"分开写是有意的：合在一起就复现不出 #27 那个误判。
上板那一半的分层顺序在 [S8](zynq-video-rtl-debug/SKILL.md)，不在本页。

## 已验证效果

- **协议必要性**：`report/ISSUES.md` #5（UDP 乱序错位 ⇒ 包头加 `[u32 LE offset]`、按 offset 写 BRAM）；
  #27 记录"只看累计字节"会把「丢一包 + 一包重复偏移」当成收满 ⇒ **空洞帧被 commit**，对策是加行覆盖门。
- **对齐是量出来的**：上面那组 1396/1392 的数字出自 `report/V6_BOARD_MEASUREMENT.md` §4.2；
  仿真侧同步判据 `tb_v6_ingress_integrity +FULL +MISALIGN` 修复前 `38290/38400`、
  `first bad word=174`（正是 `1396/8=174.5` 那个跨界字），修复后 `38400/38400`（`report/ISSUES.md` #29）。
  ⇒ 这条的价值在于：**"174"这个数字自己解释了机理**，不需要再猜。
- **提交门生效**：`sim/tb_v6_cover_gate.v` 五条断言（含"有洞的帧被计数""下一完整帧仍能提交"）
  在 `sim/results/regression_v77_r13.txt` 里是 `RESULT tb_v6_cover_gate PASS`。
- **交付工况的板级数字**：15/30 fps 与不限速 60 fps 三档，最新帧命中率 **100.0%**、
  u32 内两 lane 异帧 **0/76800**、包内六带丢字率全 **0.0%**、连续丢字带 **0 字**
  （`data/measured/board_measure_r06_r07.md`）；判据本身怎么写见 [S9](frameid_loss_signature.md)。
- **协议栈"活着"的不看屏判据**：`ping` 发送=3 / 接收=3 / **丢失=0**、RTT 1–2 ms，而此时 PS 完全不参与
  ARP/ICMP ⇒ 数据面确实与处理器无关（`report/OVERNIGHT_LOG.md` §「L4 执行」）。
- **卸载是有代价的，代价被量化过**：新增链路健康自诊断（一路计数 + 跨域快照 + 屏上两行 + 一路 GPIO 读回）
  **一个 BRAM tile 都没加**（占用率不变），代价是网口时钟域 WNS +0.974 → **+0.527**
  （`report/CHANGELOG_V7.md` V7.6 门禁表）。⇒ 说"不占资源"之前先把这两列数摆出来。

## 失效条件

1. **offset 头本身坏了就写飞**：链路层 FCS 有检查（`gmii_rx_mac.v` 自己数 crc32），
   但 **UDP/IP 头里的 checksum 不参与判定**（`udp_rx_parser.v` 只比 ethertype、IP 协议号与目的端口），
   于是"在范围内但错误"的 offset 无法被发现；越界的那一类才有计数
   （`frame_reasm.v:132` 的 `stat_oob_off`）。要防它得在应用层再加 magic/CRC，别指望协议栈替你验。
2. **两个提交判据都是分辨率相关的**：行覆盖要求 `IMG_W/IMG_H` 与实际推流一致，而帧长常数如果没被例化
   覆盖（`eth_udp_video_top.v:230` 只传 `.IMG_W/.IMG_H`，`frame_reasm.v:11` 的 `FRAME_BYTES` 默认 307200
   恰好等于 512×300×2）⇒ 改分辨率会静默失配（`report/OVERNIGHT_LOG.md` U12 —— 这一条是**读代码**读出来的，
   不是跑出来的，所以它没有台架凭据，只有失效条件）。
3. **不处理 IP 分片**：载荷超过 MTU 由网卡/协议栈分片，本链不重组 ⇒ 上位机必须自己控制包长。
4. **行覆盖门在稀疏载荷上会误判**：点云抽稀、稀疏矩阵这类"一行只写几个字节"的载荷，
   行门会把没写过的行也算进"覆盖"。那种形状要换成**包位图**，而不是把行门调松。
5. **片外时序没有约束**：位对齐靠固定抽头（`system_top.v:160` 传 `IDELAY_VALUE(15)`，
   而 `rgmii_rx.v:29` 的默认是 0），全仓库 `set_input_delay`/`set_output_delay` 为 0 条，
   发送侧被 `src/constraints/rk_zynq7020.xdc` 里那四条 `-to` false path 整条豁免 ⇒
   **时序报告全绿只说明片内满足**，片外只有板级证据（`report/OVERNIGHT_LOG.md` U10；
   `check_timing` 与 `methodology.rpt` 的 TIMING-18 会自己点名这些端口）。
   换板 / 换走线要重扫抽头。
6. **换到 UltraScale+ 整段失效**：收侧 `IDDR`/`IDELAYE2`/`IDELAYCTRL`（`IDELAYCTRL` 还要 200 MHz 参考，
   由 `src/rtl/clocks/clk_gen.v:15` 的 `MMCME2_BASE` 提供），HDMI 发送 `OSERDESE2`
   （`src/rtl/hdmi/tmds_serializer.v:15`），都是 7 系列专有原语，必须整体改写。
7. **FIFO 一律自研**这件事不在这里判对错（本工程 `sync_fifo`/`dc_fifo` 不用厂商 IP），
   但换工具版本后 `report_cdc` 对它们的归类可能变 —— 判"跨域写法"的部分见
   [S11](pulse_toggle_cdc.md) 与 [S16](cdc_pair_baseline_gate.md)。
8. 旧笔记里的编号与本仓库不一致 ⇒ 引任何编号前先核对（通用口径在
   [S5](llm_fpga_debug_workflow.md) 失效条件 5，本条不再复述）。

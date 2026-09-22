# S1 · UDP 乱序重组：带 offset 的拼帧协议

## 适用场景
- PC/上位机向 FPGA 推**原始帧**（视频、点云、矩阵），走 UDP：不保证到达顺序、不保证到达、不重传。
- 每帧大小远超一个包（本工程 512×300×2 = 307200 B / 帧），必须切包，而切包顺序一旦与写入顺序耦合，
  网络抖动就直接变成画面错位。
- 不适用：需要可靠/有序的场景（本方案丢包就是丢包，靠下一帧自愈）。

## 使用方法
1. 包格式：`[u32 LE byte_offset][payload]`，`byte_offset` 是**该载荷在目标帧内的字节偏移**。
   上位机：`src/host/video_sender.mjs`（默认 `--ip 192.168.1.10 --port 5001 --pace-mpbps 15`，
   载荷默认 1392 B）。
2. 板端接收：`src/rtl/eth/frame_reasm.v` 收完 4 字节头后 `wr_addr <= off[18:1]`（`:148`，
   单位是 **16bit 字索引**，不是字节地址）、`wr_data <= 16bit 字` ⇒ **按 offset 落位，绝不按到达顺序追加**。
   行号由 `off / (IMG_W*2)` 现算（`:103-104`），用于「本帧哪些源行被写过」的记账。
3. 提交判据是**两条与门**：`rows_hit == IMG_H` **且** 帧内字节累计到 `FRAME_BYTES`，
   且本帧没有坏包（`bad_frame`）才翻 bank（`report/ISSUES.md` §27）。
   换页本身还要等 CDC 排空（`src/rtl/eth/ddr_bank_commit.v`）。
4. 坏帧策略：丢弃、不重传、屏上保留上一帧；事件被记成数字而不是黑纹
   （`frame_abort` / `rows_missed` → `src/rtl/eth/link_monitor.v` → OSD / `health_read.mjs`）。
5. 台架：`SIM_TB=tb_udp_reasm vivado -mode batch -source sim/run_sim.tcl`
   （`sim/tb_udp_reasm.v:2` 覆盖 正常/乱序/丢包/重复/帧跳变/坏包 六类），
   验收门单独跑 `SIM_TB=tb_v6_cover_gate`，整帧入包链跑
   `SIM_TB=tb_v6_ingress_integrity` + `SIM_ARGS="+FULL +MISALIGN"`。

## 已验证效果
- 协议必要性：`report/ISSUES.md` §5「UDP 乱序错位 → 包头加 `[u32 LE offset]`，按 offset 写 BRAM」，
  §27 记录只看累计字节会把「丢一包 + 一包重复偏移」当成收满 ⇒ 空洞帧被 commit。
- 提交门生效（仿真）：`sim/tb_v6_cover_gate.v` 5 条断言全过，其中
  「丢包的帧被拒绝」「有洞的帧被计数」「下一完整帧仍能提交」——见
  `sim/results/regression_v77_r13.txt` 的 `RESULT tb_v6_cover_gate PASS`。
- **载荷必须 8 的倍数**这一条是板级量出来的：1396 B 分包时最新帧命中率 99.9%、
  每帧 **222 个** 16bit 空洞（111 处 × 2、洞里是 0x0000 = 屏幕上均匀黑点）；
  1392 B 时 100.0%、0 洞（`report/V6_BOARD_MEASUREMENT.md` §4.2）。
  v6.4 改成按 16bit lane 生成 `WSTRB` 后硬件免疫：同 1396 B 复测 100.0% / **0** 洞。
  仿真侧同步判据：`tb_v6_ingress_integrity +FULL +MISALIGN` 修复前 `38290/38400`、
  `first bad word=174`（正是 `1396/8=174.5` 的跨界字），修复后 `38400/38400`（`report/ISSUES.md` §29）。
- 交付工况板级数字：15/30 fps 与不限速 60 fps 三档，最新帧命中率 **100.0%**、
  u32 内两 lane 异帧 **0/76800**、包内六带丢字率全 **0.0%**、连续丢字带 **0 字**
  （`data/measured/board_measure_r06_r07.md`）；另在 1396 B 非 8 倍数载荷下 3 轮 180 帧同样 100.0%
  （`report/OVERNIGHT_LOG.md` §「L4 执行」补充表）。

## 失效条件
1. **offset 头本身坏了就写飞**：整条 RX 链不做 UDP/IP 校验和验证
   （`src/rtl/eth/udp_rx.v`、`udp_rx_parser.v` 里 grep 无 checksum 逻辑），只有
   `off >= FRAME_BYTES` 的越界检查会计数 `stat_oob_off`（`frame_reasm.v:155`）⇒
   一个「在范围内但错误」的 offset 无法被发现。要防它得在应用层再加 magic/CRC。
2. **两个判据是分辨率相关的**：`rows_hit` 要求 `IMG_W/IMG_H` 与实际推流一致，
   而 `FRAME_BYTES` 的默认值 307200 **没有被例化覆盖**（`eth_udp_video_top.v:196` 只传 IMG_W/IMG_H），
   现在恰好等于 512×300×2 ⇒ 改分辨率会静默失配（`report/OVERNIGHT_LOG.md` U12）。
3. **不处理 IP 分片**：载荷超过 MTU 由网卡/协议栈分片，本链不重组 ⇒ 上位机必须自己 ≤1392 B。
4. `p_good` 上板恒 `1'b1`（`eth_udp_video_top.v:200`）⇒ 坏包统计只有 `bad_frame` 这条
   「越界/长度不符」路径会走到；FCS 错包不会被计入。此结论本轮只按 RTL 读，未上板复测。
5. 「累计字节」型覆盖率判据在有空洞时会误判收满 —— 本工程的对策是**加行覆盖门**；
   如果换到「行很稀疏」的载荷（点云抽稀、稀疏矩阵），行门也会误判，要改成包位图。
6. 旧版笔记里的编号对不上本仓库：`ISSUES#16` 在这里是「效果挂载位置」，offset 协议是 **#5**、
   覆盖门是 **#27**、分包长度是 **#29/#33**。引编号前先 `grep "^### " report/ISSUES.md` 核对。

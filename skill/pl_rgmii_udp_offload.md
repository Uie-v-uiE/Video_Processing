# S6 · PL RGMII UDP 硬件卸载最小闭环

## 适用场景
- Zynq-7020 上要把视频流从 **PL 侧第二个网口**收进来、PS 只做控制面：本工程 PS 固件不挂 lwIP
  （`report/ETH_BRINGUP.md` §PS / Vitis），ARP / ICMP / UDP 全部由 RTL 应答。
- 需要逐层定位「ping 不通」与「ping 通但没画面」：前导码、ARP、ICMP、UDP、拼帧各是一个模块，
  可以单独仿真、单独替换。
- 不适用：走 PS GEM 的通路；UltraScale+ 器件（见失效条件 1）。

## 使用方法
1. 管脚：PHY2 RGMII 在 **BANK33**（`report/BOARD_PINS.md` §「PL ETH PHY2 RGMII（BANK33）」），
   约束在 `src/constraints/rk_zynq7020.xdc:20-34`（`eth_rxc`=Y19 … `eth_rst_n`=Y21）。
2. 接收链按 `src/rtl/eth/eth_udp_video_top.v` 里的实际例化名读：
   `u_rgmii`(gmii_to_rgmii → rgmii_rx：IDDR + IDELAYE2) → `u_arp` / `u_icmp` / `u_udp`
   （各含 *_rx / *_tx，FCS 由 `crc32_d8` 加）→ `u_ctrl`(eth_ctrl 发送仲裁) →
   `u_reasm`(frame_reasm) → `u_cdc`(dc_fifo，36bit × 8192) → `u_saver`(axi_frame_saver64)。
3. FIFO 一律自研：同钟 `sync_fifo`、跨钟 `dc_fifo`（Gray 指针 + 双级同步），不用厂商 FIFO IP。
4. 台架：`vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl`；
   只跑一个：`SIM_TB=tb_udp_reasm vivado -mode batch -source sim/run_sim.tcl`；
   `SIM_ONLY=1` 只编译；plusargs 走 `SIM_ARGS="+FULL"`。
   新模块想在上全流程之前先看结构链：
   `OOC_ONLY=link_monitor vivado -mode batch -source build/tcl/ooc_newmods.tcl`。
5. 上板：`xsdb.bat build/tcl/ps_jtag_boot.tcl <ps7_init.tcl>` →
   `vivado -mode batch -source build/tcl/program_pl.tcl` → `xsdb.bat build/tcl/set_src.tcl`
   （现写 `0x00030000`）→ `ping 192.168.1.10`。

## 已验证效果
- 台架规模：基线 28/28（`report/OVERNIGHT_LOG.md` §1.5，命令即 §4 那条）→ 本轮加
  `tb_link_monitor` / `tb_osd_lines` / `tb_fb_roundtrip` / `tb_bilin_lerp` / `tb_ps_publish`
  后 **34/34**（`sim/results/regression_v77_r13.txt` 末行 `SIM DONE pass=34 fail=0`）。
- 「协议栈活着」的不看屏判据：`ping 192.168.1.10` 发送=3 / 接收=3 / 丢失=0、RTT 1–2 ms，
  而此时 PS 只做控制面 ⇒ ARP/ICMP 由 RTL 应答（`report/OVERNIGHT_LOG.md` §「L4 执行」）。
- 入包链数据完整性（同一 bit、三档激励）：15 fps×200 / 30 fps×300 / 不限速 60 fps×400 帧，
  最新帧 16bit 命中率 **100.0%**、u32 内两 lane 异帧 **0/76800**、包内六带丢字率 **全 0.0%**、
  连续丢字带 **0 个 16bit 字**（`data/measured/board_measure_r06_r07.md`）。
- 三次「只改综合形态」的改造（R02 打包 FIFO→LUTRAM、R04 帧缓存分块、R05 skid→LUTRAM）之后
  上面这组板级数字逐项不变（`report/OVERNIGHT_LOG.md` §「L4 执行」19 轮）。
- 卸载的代价被量化过：新增链路健康自诊断（`link_monitor` + `snap_cross` + OSD 两行 + 一路
  GPIO 读回）**一个 BRAM tile 都没加**（64.64% 不变），代价是 `eth_rxc` 域
  WNS +0.974 → **+0.527**（`report/CHANGELOG_V7.md` V7.6 门禁表）。

## 失效条件
1. **换到 UltraScale+ 整段失效**：`src/rtl/eth/rgmii_rx.v` 用 `IDDR`/`IDELAYE2`/`IDELAYCTRL`，
   且 `IDELAYCTRL` 要 200 MHz（`:71` `REFCLK_FREQUENCY(200.0)`，由
   `src/rtl/clocks/clk_gen.v:15` 的 `MMCME2_BASE` OUT2 提供）；`src/rtl/hdmi/tmds_serializer.v:15`
   用 `OSERDESE2`。这些都是 7 系列专有原语，必须整体改写。
2. `USE_IO_PRIMS`（旧版笔记里的综合开关）**在本仓库不存在** —— 全树 grep 无此参数，本设计是无条件
   例化 IDDR/IDELAY。此条本轮复核为「不成立」，不要照抄去加编译开关。
3. **RGMII 位对齐靠固定抽头且未被约束**：`src/rtl/top/system_top.v:133` 传 `IDELAY_VALUE(15)`
   （`rgmii_rx.v:29` 默认为 0）；全仓库 `set_input_delay`/`set_output_delay` 为 0 条，TX 侧被
   `rk_zynq7020.xdc:42-44` 三条 `-to` false path 整条豁免 ⇒ 报告全绿只说明**片内**满足，
   片外只有板级证据（`report/OVERNIGHT_LOG.md` U10）。换板/换走线要重扫抽头。
4. **前导码 FSM 有 1 字节的隐性偏移**：IDLE 态 `udp_rx.v:132` 的 `skip_en` 吃掉 1 个 `0x55`，
   `st_preamble` 再数 6 个（`:137`）后验 `0xD5`（`:141`）⇒ 动 IDDR 相位或计数器位宽就会整链收不到包。
5. **端口/拓扑是写死的假设**：`UDP_PORT=16'd5001` 同时出现在 `eth_udp_video_top.v:8`、
   `udp_rx_parser.v:5`（未上板）、`system_top.v:130`，上位机又独立写死一份
   （`src/host/video_sender.mjs:33`）；网线必须插 **PL 口**（`board/README.md` §Hardware），PC 侧静态 `192.168.1.100/24`，
   全部结论只在**点对点直连**下取过。
6. **上板的那条 RX 链没有目的端口过滤**：`src/rtl/eth/udp_rx.v` 不比较 UDP 目的端口；带端口比对的
   `src/rtl/eth/udp_rx_parser.v:119` 未被 `eth_udp_video_top.v` 例化（全树 grep 无实例）⇒
   「广播包恰好打到 5001」这条暴露面仍在，旧记录里「已有端口检查」的结论只对那个未上板的模块成立。
7. **ARP 只缓存一个对端**：`arp_rx.v:27-28` 是一对输出寄存器 `src_mac/src_ip`，
   `eth_udp_video_top.v:135,149,162` 把它直接当三台发送机的 `des_mac/des_ip` ⇒ 同网段多主机时
   回复目标会漂；`arp_rx.v:137` 还接受全 1 广播目的地址。
8. `p_good` 在 `eth_udp_video_top.v:200` 硬接 `1'b1` ⇒ `frame_reasm` 的坏包统计上板恒 0，
   唯一真实的丢数据通道是 `cdc_wr` 被 `fifo_full` 挡住那一拍（靠 `link_monitor` 才可见）。

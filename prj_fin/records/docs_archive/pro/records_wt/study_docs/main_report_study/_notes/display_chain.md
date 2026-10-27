# 显示 / DDR 回读链 · 取证笔记（display_chain）

> 覆盖：`system_top` → `pl_video_top` 的显示侧（时序发生器 → 逆映射 → 帧缓存读 → 效果链 →
> split_display → OSD → TMDS），以及 `ddr_bank_commit` / `frame_commit_lock` /
> `axi_frame_writer_gated` 这条「DDR → 显示 BRAM」的回读链。
> 全部结论带 `file:line`。凡是我的推算而非代码/报告原文，标 **〔推断〕**；标 **〔报告〕** 的
> 数字来自 `report/*.md`、`build/*.rpt`（这些是实测/工具输出，不是 RTL 声明）。
> 阅读顺序建议：先 §1 时钟 → §5 门控窗口 → §7 帧缓存 → §11 死代码清单。

---

## 1. 时钟清单（来源 / 频率 / 各域装了哪些模块）

全设计 8 个 BUFGCTRL、2 个 MMCM（`build/utilization.rpt` §6 Clocking：**BUFGCTRL 8/32 = 25.00%、MMCME2_ADV 2/4 = 50.00%、BUFIO 1/16**；**〔报告〕** 同 `build/clock_util.rpt:43-49`）。

| # | 时钟 | 物理来源 | 频率 / 周期 | 谁活在这个域 |
|---|------|----------|-------------|--------------|
| 1 | `sys_clk` | 板载晶振 **管脚 W17**，`create_clock -period 20.000`（`src/constraints/rk_zynq7020.xdc:5-6`）→ IBUF → BUFG（`build/clock_util.rpt:62` g3，`sys_clk_IBUF_BUFG_inst`） | 50 MHz / 20 ns | `key_debounce`×2（`src/rtl/top/pl_video_top.v:68-73`）、`angle_ctrl`（同文件 `:76-80`）、PHY 上电复位计数器（`src/rtl/top/system_top.v:98-102`）、心跳 LED（`pl_video_top.v:512-518`）、FPS 计数器（`pl_video_top.v:465-480`）、两个 MMCM 的 CLKIN1（`build/clock_util.rpt:81-85`） |
| 2 | `fclk0` = `clk_fpga_0` | PS7 `FCLKCLK[0]` → `FCLK_CLK0_BUFG`（`build/clock_util.rpt:59` g0；端口连接 `system_top.v:76`） | **100 MHz / 10.000 ns**（`build/clock_util.rpt:59`、`build/timing_summary.rpt:164`；`report/V6_ROOT_CAUSE.md:62` 亦写「实测 FCLK=100」） | 全部 AXI 事务：`axi_frame_writer_gated u_row`、`axi_frame_writer64 u_aw`、`axi_frame_saver64`、`dc_fifo` 读侧、`ddr_bank_commit`、`frame_commit_lock` 的 axi 半区、AXI GPIO（`system_top.v:77` → `effect_en/threshold/src_sel`） |
| 3 | `clk_pix` = `clkout0_1` | `u_pl/u_clk` MMCM **CLKOUT0** → `u_bufg_pix`（`src/rtl/clocks/clk_gen.v:21` `CLKOUT0_DIVIDE_F=20.0`，`:54` BUFG） | **50 MHz / 20.000 ns**（`build/clock_util.rpt:61` g2；VCO=1000 MHz，`clk_gen.v:19` `CLKFBOUT_MULT_F=20`，输入 50 MHz） | 整个显示光栅与像素通路：`video_timing_1024x600`、`zoom_ctrl/zoom_mapper/rotate_mapper`、16 级像素流水、`frame_buffer_w64` 读口、`proc_pipeline`、`split_display`、`osd_overlay`、3×`tmds_encoder` |
| 4 | `clk_pix5x` = `clkout1_1` | 同一 MMCM **CLKOUT1** → `u_bufg_5x`（`clk_gen.v:24` `CLKOUT1_DIVIDE=4`，`:55`） | **250 MHz / 4.000 ns**（`build/clock_util.rpt:63` g4） | **没有任何用户逻辑**：只挂 8 个 OSERDESE2 的 CLK 引脚（`build/clock_util.rpt:220`：Slice Loads **0**、IO Loads **8**） |
| 5 | `clk_200m` = `clkout2` | **第二个** MMCM `u_idelay_clkgen` 的 CLKOUT2 → `u_bufg_200`（`clk_gen.v:27` `CLKOUT2_DIVIDE=5`；实例化 `system_top.v:108-112`） | 200 MHz / 5.000 ns（`build/clock_util.rpt:64` g5） | IDELAYCTRL 参考时钟，1 个负载（`build/clock_util.rpt:243`），送 `eth_udp_video_top.idelay_clk`（`system_top.v:135`） |
| 6 | `eth_rxc`（gmii 域） | 管脚 **Y19**，`create_clock -period 8.000`（`rk_zynq7020.xdc:36`）→ IBUF → `BUFG_inst`（`src/rtl/eth/rgmii_rx.v:42-52`，`assign gmii_rx_clk = rgmii_rxc_bufg`；另有一路 `BUFIO_inst` 供 IDDR 双沿采样，`rgmii_rx.v:52`） | **125 MHz / 8.000 ns** | 入包侧全部：`arp/icmp/udp/eth_ctrl/frame_reasm/dc_fifo 写侧`（`src/rtl/eth/eth_udp_video_top.v:109-232`）。**注意综合后这条全局时钟网线被命名成 `u_eth/u_rgmii/u_rgmii_rx/gmii_tx_clk`**（`build/clock_util.rpt:60,151`），因为 `gmii_to_rgmii.v:39` 有 `assign gmtx = grx` —— 看报告时别以为是两个钟 |
| 7/8 | `clkfbout`、`clkfbout_1` | 两个 MMCM 各自的 CLKFBOUT 经 **BUFG** 回到 CLKFBIN（`clk_gen.v:53`，`build/clock_util.rpt:65-66` g6/g7） | 20 ns，各 1 个负载 | 反馈时钟；**各吃掉一个 BUFGCTRL** |

**要点 / 易错处**

- **两个 MMCM、两套 clk_pix**：`system_top.v:108` 的 `u_idelay_clkgen` 也生成了 `clk_pix/clk_pix5x`，但被显式接到名为 `clk_pix_unused / clk_pix5x_unused` 的空线（`system_top.v:106-112`），**只有 `clk_200m` 与 `locked` 被用**。综合器把这两个没负载的 BUFG 优化掉了（`build/clock_util.rpt:402-409` 的 BUFG LOC 列表里 `u_idelay_clkgen` 只剩 `u_bufg_fb` 与 `u_bufg_200`），但 **MMCM 本体的 CLKOUT0/1 端口仍占着一整个 MMCME2**（2/4）。
- 显示像素钟来自 `u_pl/u_clk`（`pl_video_top.v:61-64`），入包 IDELAY 钟来自 `u_idelay_clkgen`（`system_top.v:108`）——**两者不同源**（不同 MMCM 实例），彼此异步。
- 时钟分组只声明了三组异步：`eth_rxc` / `clk_fpga_0` / `sys_clk 及其所有生成钟`（`rk_zynq7020.xdc:53-56`，用了 `-include_generated_clocks`）。**`clk_pix` 与 `clk_pix5x` 被有意留在同一组内**（同源、5:1 固定相位），所以 TMDS 并串转换是**按时钟同步路径做 setup 分析**的，不是假路径 —— 见 §10。
- `clk_fpga_0`（100 MHz，来自 PS）与 `clkout0_1`（50 MHz，来自 sys_clk 的 MMCM）**不同源**，是真正异步的一对；CDC 报告把它们列为 Critical 条目：`clk_fpga_0 → clkout0_1` 16 个端点、14 safe / 1 unsafe / 1 unknown / **13 个没有 ASYNC_REG**（`build/cdc.rpt` 表格行 `clk_fpga_0  clkout0_1`）。
- 时序余量（`build/timing_summary.rpt:181-188`）：**clk_fpga_0 WNS +1.776 ns、clkout0_1(pixel) WNS +3.084 ns、eth_rxc WNS +0.499 ns、sys_clk WNS +14.289 ns**；`clkout1_1`(250 M) 只有 10 个端点、全部是脉宽检查（WPWS +2.408），**没有任何组合路径** —— 再次证明 250 MHz 域里没有逻辑。

---

## 2. 复位树与异步复位的分发

- **全局没有外部复位**：`system_top.v:162` 把 `sys_rst_n` 绑成 **`1'b1'`**；`system_top.v:109` 把 `clk_gen.rst_n` 也绑 `1'b1`。所以 `clk_gen.v:49` 的 `.RST(~rst_n)` **恒为 0 —— 两个 MMCM 从不下电复位**，`locked` 只在上电锁定过程里有一次 0→1。
- 像素域复位 = **MMCM 锁定标志本身**：`pl_video_top.v:65` `wire rst_pix_n = sys_rst_n & locked;`，而 `sys_rst_n` 恒 1（`system_top.v:162`）⇒ **`rst_pix_n ≡ locked`**（`clk_gen.v:50` 的 LOCKED 输出）。它是**异步复位**：所有像素域触发器都写成 `always @(posedge clk_pix or negedge rst_pix_n)`（例：`pl_video_top.v:92,134,166,274,296,310,359,425`；`video_timing.v:32,53`；`split_display.v:34`；`osd_overlay.v:186`；`tmds_encoder.v:42`；`zoom_mapper.v:76`；`rotate_mapper.v:45`）。
  - 但**没有做「复位去毛刺/同步释放」**：`locked` 是 MMCM 的组合输出直接分发给整个像素域的所有 CLR 端。〔推断〕这是一条典型的「异步复位、异步释放」结构，释放时刻相对 clk_pix 不确定；设计依赖 `ASYNC_REG` 触发器与后续几拍稳定，板级看不出问题。
- AXI 域复位 = PS 的 `FCLK_RESET0_N`：`system_top.v:76` `.FCLK_RESET0_N(fclk0_rst_n)` → `system_top.v:134`（eth）与 `:163`（pl）的 `axi_rst_n` → 各 axi 域模块的 `negedge rst_n`（`axi_frame_writer_gated.v:91`、`frame_commit_lock.v:32,62,69,80,85,97,113`、`ddr_bank_commit.v:51,62`、`axi_frame_saver64.v:99,123,157`）。
- 入包域复位是**三者的与**：`system_top.v:132` `.rst_n(eth_rst_n & mmcm_locked)`，其中 `eth_rst_n = phy_rst_cnt[23]`（`system_top.v:98-102`，24 bit 计数器在 50 MHz 下 **2^23/50e6 ≈ 167 ms** 后拉高）〔推断：由代码算得，非报告原文〕，`mmcm_locked` 是**第二个 MMCM** 的锁。`ddr_bank_commit` 同时吃 `rst_n`(gmii 域) 与 `axi_rst_n`(axi 域)：`eth_udp_video_top.v:263-264`。
- **跨域复位（真实存在，值得记住）**：FPS 计数器跑在 `sys_clk`，却用**像素域**的 `rst_pix_n` 做异步复位 —— `pl_video_top.v:471-473` `always @(posedge sys_clk or negedge rst_pix_n)`。〔推断〕一个域的复位脚去清另一个域的触发器，释放瞬间该域的恢复时间没有约束（Vivado 会按 `sys_clk` 的恢复检查处理，实测 WNS 14.289 ns 很宽裕，故未暴露）。
- 有意**不复位**的时序（为了让数组推断成 RAM，见 §12）：`pl_video_top.v:385-389`（colorbar 延迟链）、`:392-395`、`:461-463`、`:469`、`:483-487`；`frame_buffer_w64.v:46,64`；`dc_fifo.v:46`；`axi_frame_writer_gated.v:84`；`axi_frame_saver64.v:115`；`zoom_mapper.v:31,42`；`rotate_mapper.v:25,32`。

---

## 3. DDR 地址映射与常量所在

- **bank 基址**：`BANK0 = BASE_ADDR`、`BANK1 = BASE_ADDR + 32'h0008_0000` —— `src/rtl/eth/eth_udp_video_top.v:55-56`。默认参数化入口：
  - `system_top.v:125`（eth 侧 `.BASE_ADDR(32'h1000_0000)`）、`system_top.v:161`（pl 侧同名同值）；
  - 模块内默认值也是 `32'h1000_0000`：`eth_udp_video_top.v:7`、`pl_video_top.v:9`、`axi_frame_writer_gated.v:10`、`axi_frame_writer64.v:7`、`axi_frame_writer.v:7`、`ddr_bank_commit.v:17-18`（`:18` 直接写死 `32'h1008_0000`）。
  - 复位/兜底常量另写两份：`frame_commit_lock.v:34` `pending_base <= 32'h1000_0000`、`:99` `copy_base <= 32'h10000000`；`axi_frame_writer_gated.v:96` `base_r<=BASE_ADDR`；`axi_frame_saver64.v:100` `pack_base <= BASE_ADDR`。
- **bank 间隔 0x80000 = 524 288 B**，而一帧只有 **512×300×2 = 307 200 B = 0x4B000**（=38400 个 64bit 字）⇒ 两 bank 不重叠，**每 bank 留了 ~71% 余量**〔推断：由 `eth_udp_video_top.v:55-56` + `frame_reasm.v:8` 算得〕。整条链只用到 1 MiB（0x1000_0000–0x10100000）。
- **帧几何常量**：`IMG_W=512, IMG_H=300` 由 `system_top.v:124`（eth）与 `system_top.v:161`（pl）分别传入 —— **同一个 (512,300) 写了两遍**，改一处不会联动。
- **帧字节数 307200 只出现在一个地方**：`frame_reasm.v:8` `parameter FRAME_BYTES = 307200`，而 `eth_udp_video_top.v:185` 例化时**只覆盖 IMG_W/IMG_H，没有传 FRAME_BYTES** ⇒ 完整性判据（`frame_reasm.v:122` `bytes_all >= FRAME_BYTES`）依赖的是「默认值恰好等于 512×300×2」这个巧合。**〔推断/风险〕改 IMG_W/IMG_H 就会静默失配。**
- **行距**：`frame_reasm.v:47` `ROW_STRIDE = IMG_W*2 = 1024`，行号用 `off / ROW_STRIDE`（`:48`，注释 `:44-46` 明确解释为什么不能用 `off[16:1]` 截断）。
- **入包侧 AXI 地址生成**：`axi_frame_saver64.v:117` `q_addr <= pack_base + {10'd0, cur_widx, 3'b000}` ⇒ 64bit 字索引 ×8；`cur_widx = wr_addr[18:2]`（`:95`）。
- **回读侧地址**：`axi_frame_writer_gated.v:124` `m_axi_araddr <= base_r + burst_idx * (BEATS*8)` ⇒ 每个突发 128 B；`TOTAL_BURSTS = (38400+15)/16 = 2400`（`:43`）。
- **像素号 ↔ 字号**：`r_pix` 计的是**像素**（每拍 +4，`:39 PIX_PER_BEAT=4`、`:139/:147/:152`），出 BRAM 地址时右移 `fb_wr_addr <= r_pix[18:2]`（`:145`）；skid 里存的是**完整像素号** `sk_addr <= r_pix[18:0]`，出队时再 `[18:2]`（`:86`、`:134`）。
- **帧内显示 BRAM 的地址映射**：见 §7（`frame_buffer_w64.v:34-49,55-60`）。
- **PS DDR 可访问性旁证**：`report/V6_BOARD_MEASUREMENT.md:37`（xsdb `mwr/mrd 0x1000_0000` 回环 OK）、`report/V6_ROOT_CAUSE.md:287`（把两个 bank 整块读回逐 lane 比对）、`src/host/ddr_verify.mjs:18`、`src/host/ingress_probe.mjs:64`。

---

## 4. 提交握手：frame_reasm → dc_fifo → saver → ddr_bank_commit → 显示侧

按「谁驱动 / 谁采样 / 持续几拍」逐段拆：

1. **帧完整判定**（gmii 125 MHz 域，驱动者 `frame_reasm`）
   - 条件：`rows_hit >= IMG_H && bytes_all >= FRAME_BYTES`，二者缺一不提交（`src/rtl/eth/frame_reasm.v:122`）；行覆盖用 300bit 位图 `row_ok`（`:41`、`:97-100`），跨帧累计字节 `cover`（`:54`、`:131`）。
   - 输出 `frame_done`：**单拍脉冲**（`:69` 每拍先清 0，`:123` 置 1）；同拍清位图并 `stat_frames+1`（`:124-127`）。
   - `flush`：每包结束（`p_eof && pkt_active`）拉一拍（`:113-114`），它和 `wr_en` 一起进 CDC，用作「凑半截字」的推土信号。
2. **gmii → axi 的 CDC**（驱动者 `eth_udp_video_top`）
   - 36bit 打包 `{flush_bit, addr[18:0], data[15:0]}`：`eth_udp_video_top.v:212-214`；`flush_pend` 用于「同一拍既有 wr_en 又有 flush」时把 flush 排队（`:216-220`）。
   - `dc_fifo`：**BRAM 实现、深 8192**（`:225` `ADDR_W(13)`；`dc_fifo.v:20` `ram_style="block"`），格雷码指针 + 2FF 同步（`dc_fifo.v:33,54,68-81`），**读出口是打了一拍的寄存器**（`dc_fifo.v:60-61`）⇒ `rd_data` 比 `rd_en` 晚 1 拍。
   - 读侧限流：`fifo_rd <= !fifo_empty && !sv_full`（`:239`），即**打包器满就反压**（v6.2 语义，注释 `:205,207-211`）。
   - **这里有一条 1 拍错位**：`cdc_d1 <= fifo_dout` 与 `cdc_d1_v <= fifo_rd` 同在 `:240-241`，但 `fifo_dout` 自己已经比 `fifo_rd` 晚一拍 ⇒ `cdc_d1_v` 相对 `cdc_d1` **提前 1 拍**。**〔推断〕** 之所以没坏：地址和数据同在一个 36bit 字里（`:245-246` 一起取），整体只是把数据流相对标记**平移一拍**；代价是每次复位后第一拍会写一个 `{addr=0,data=0}` 的假字进打包器，以及最后一拍的搬运推迟到下一次 CDC 排空。**这一条正好是 `ddr_bank_commit` 注释里「帧尾 4 字节」现象的机制邻居**（`ddr_bank_commit.v:11-15`）。
3. **提交/换页**（axi 100 MHz 域，驱动者 `ddr_bank_commit`，被 `eth_udp_video_top.v:258-278` 例化）
   - `frame_done` → `frame_done_tog` 翻转（`ddr_bank_commit.v:45-49`，gmii 域）→ axi 域 3FF `fd0/fd1/fd2`（`:50-54`，`ASYNC_REG=TRUE`）→ 边沿 `fd_axi = fd1^fd2`（`:55`），**一拍**。
   - 置 `switch_req` 与 `force_flush`（`:71-74`），直到 `commit_ok` 才提交（`:75-81`）：`completed_base <= sav_base`（**这就是交给显示侧的基址**）、`bank <= ~bank`、**`commit_pulse <= 1'b1` 且只保持 1 个 axi 周期**（`:70` 每拍先清 0）。
   - `commit_ok` 的两级判据（这就是 TAIL_GUARD=1 的全部）：`saver_idle && tail_drained`，其中 `tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush`（`:58-59`）；`TAIL_GUARD=0` 退回 v6.4 的「只看 saver_idle」（`:59`）。`saver_idle` 的定义在 `axi_frame_saver64.v:93`：`enable && !cur_dirty && fifo_empty && !beat && outst==0` —— 注释 `ddr_bank_commit.v:11-14` 明确说这一项对 8192 深的 CDC 与其后读流水**完全不可见**，所以要加 `tail_drained`。
   - `pack_flush = sav_flush | (force_flush && tail_drained)`（`:88`）：flush 标记永远让路给真实数据。
   - 该模块被**从 `eth_udp_video_top` 里抽出来**的唯一理由写在头注释：让 TB 例化上板实现而不是手抄副本（`ddr_bank_commit.v:4-6`）；例化时 `.switch_req()`、`.force_flush()` 两个输出**留着不接**（`eth_udp_video_top.v:276-277`）。
4. **提交 → 显示侧拷贝**（跨 axi→axi，**同域，不需要 CDC**）
   - `eth_commit`（=`commit_pulse`，`system_top.v:120/149/181`）→ `frame_commit_lock.commit_req`（`pl_video_top.v:234`）→ **axi 域打一拍存进 `pending/pending_base`**（`frame_commit_lock.v:32-40`），`start_copy` 发出时清 `pending`（`:37-39`）。
   - `eth_ddr_base`（=`completed_base`）→ `commit_base`（`pl_video_top.v:234`）→ `pending_base` → `copy_base`（`:106`）→ `u_row.base_addr`（`pl_video_top.v:259`）→ 拷贝开始时锁进 `base_r`（`axi_frame_writer_gated.v:108`），**整帧期间不再改变**（换页只发生在下一次 commit）。
   - `start_copy`：**单拍**（`frame_commit_lock.v:101` 每拍先清 0，`:105` 置 1），触发 `u_row` 的 `active/busy`（`axi_frame_writer_gated.v:106-108`）。
   - 回授：`copy_busy = row_busy`、`copy_done = row_done` 都在 axi 域（`pl_video_top.v:237-238` ↔ `axi_frame_writer_gated.v:108/159`，`busy` 持续整帧、`done` 单拍），门条件 `:103-104`：`!copy_active && !copy_busy && !copy_done && !start_copy && !copy_abort` ⇒ **同一时刻只允许一帧在搬**，新提交只能排队（`pending` 覆盖 `pending_base`，**旧的基址被丢弃 = 中间帧被跳过**〔推断〕）。
   - 完成回执：`copy_done` 翻转 `ready_tog`（`frame_commit_lock.v:112-116`）→ 3FF 进像素域（`:117-124`）→ **`frame_ready_pix` 是「置 1 后不清」的电平**，只有 `copy_abort` 会在显示侧把 `eth_has_frame` 清零（`pl_video_top.v:281-284`）。
   - **注意**：`frame_ready_pix / eth_has_frame / eth_ready` 这一整条最终只进了 `status`（`pl_video_top.v:288,520`），而 `status` 在顶层无人消费（见 §11-13）⇒ 它**不参与任何画面选择**，`src_use` 直接决定彩条 or BRAM（`:398-401`）。
5. **拷贝窗使能反向跨域**（pix → axi）：见 §5。

---

## 5. 消隐窗门控：谁开窗、实测多宽、搬不完会怎样

- **开窗信号（像素域产生）**：`disp_quiet` —— `pl_video_top.v:210-211`
  `wire disp_quiet = (y >= DISP_V_LINES) && ((y < DISP_V_LAST) || (x <= VB_X_GUARD));`
  常量：`DISP_V_LINES=600`（`:207`）、`DISP_V_LAST=624`（`:208`）、`VB_X_GUARD=1279`（`:209`，注释 `// H_TOTAL(1344) - 65`）。`x/y` 来自 `video_timing_1024x600`（`:105-109`），而 `video_timing.v:63-64` 里 `x<=h_cnt; y<=v_cnt` ⇒ 它们是**打过一拍的光栅坐标**，与 `de/hs/vs` 同槽。
- **传播路径与延迟**：`disp_quiet → blank_safe`（`pl_video_top.v:236`）→ 像素域 3 级 `bs_d0/1/2`（`frame_commit_lock.v:43-54`）→ `allow` 进 axi 域 3FF `d0/d1/d2`（`:68-72`，`ASYNC_REG=TRUE`）→ **`allow_copy_axi = d1 & d2`**（`:73`）⇒ 相对 `disp_quiet` 共延迟约 **3 个 pix 拍 + 2 个 axi 拍**。设计注释自己给的口径是「**lag ~5 pix cycles through the CDC**」（`pl_video_top.v:205-206`）。
- **宽度（代码算得，〔推断〕标注；报告口径另附）**
  - V_TOTAL = 600+3+6+16 = **625 行**，V_ACTIVE=600 ⇒ 消隐 **25 行**（`video_timing_1024x600.v:18-20` + `video_timing.v:26-27`）；H_TOTAL = 1024+44+88+188 = **1344**（同前 `:19`）。
  - 名义窗口 = 25×1344 = **33600 pix 拍 = 67200 axi 拍**（100/50 MHz = 2:1）—— 这是 `pl_video_top.v:199-200` 注释与 `report/V6_ROOT_CAUSE.md:62`、`report/PERF_REPORT.md:152-153` 用的数。
  - **RTL 实际窗口 = 24×1344 + 1280 = 33536 pix 拍 = 67072 axi 拍 = 670.72 µs**：因为第 624 行只放 1280 个像素（`pl_video_top.v:209-211`）⇒ 比名义少 **64 pix = 128 axi 拍**。〔推断，由代码算得〕
  - **观测门限反而用的是「未扣保护带」的 67200**：`localparam [31:0] VBLANK_AXI_CYC = 32'd67200;`（`pl_video_top.v:248`），比较对象 `row_copy_cycles` 是 `axi_frame_writer_gated.v:101` 里 `if (active) cyc <= cyc+1` 从 `active=1` 起计的 axi 拍。⇒ **判据比真实窗口松 128 拍**；且 `cyc` 把「等 AR/R 首拍」也算进去、但不把 `allow` 未开的问题单独剥离。〔推断〕
- **搬不完会怎样（逐条引用代码路径）**
  1. **绝不会在有效期写 BRAM**：直写与排空两条路都要求 `allow_wr` —— `axi_frame_writer_gated.v:77` `wire do_direct = r_hit && allow_wr && sk_empty;`、`:79` `wire sk_drain = active && allow_wr && !sk_empty && !do_direct;`；发新 AR 也要求 `allow_wr`（`:71-74` `can_issue`）。窗口一关，写 BRAM 立刻停，**画面继续显示上一整帧**（设计意图见 `pl_video_top.v:198-204`：v5 的「固定位置黑线」正是拷贝追上电子枪造成的）。
  2. **流水线只被 skid 吸收，不丢数**：`m_axi_rready = active && !sk_full`（`:69`）—— `allow_wr` 掉了也**继续收 R**，直到 63 深的 skid 满（`:57`），随后 rready 拉低、`can_issue` 也因 `!allow_wr` 关门 ⇒ 拷贝**平摊到后续若干个消隐窗**继续。
  3. **越窗会被点亮**：`pl_video_top.v:250-254` `else if (row_done && (row_copy_cycles > VBLANK_AXI_CYC)) copy_overrun <= 1'b1;`（粘滞，只有 `axi_rst_n` 能清），现象是 `led[0]` 从 1.5 Hz 心跳变 6 Hz 快闪（`pl_video_top.v:516-517`，`hb[24]` vs `hb[22]`，50 MHz 下分别 0.336 s / 0.084 s 半周期）。注释 `pl_video_top.v:244-246` 直接写明越窗 = 屏幕上同一帧新旧两半并存 = 拖影。
  4. **硬兜底是看门狗，不是窗口**：`frame_commit_lock.v:8` `WD_CYC = 32'd2_000_000`（axi 拍 ≈ **20 ms ≈ 1.19 个显示帧**〔推断〕），`:85-95` 计数到点则 `copy_abort <= 1`（**单拍**，`:88` 每拍清）。
     - abort 进拷贝机：`axi_frame_writer_gated.v:118-121` —— 清 `active/busy/m_arvalid/outstanding/sk_w/sk_r/r_pix/wr_words`、`done` 保持 0（**永远不发 done**），**注意 `burst_idx`/`base_r`/`cyc` 不清**（下次 start 时 `:108` 会重置 `burst_idx`）。
     - abort 进 `frame_commit_lock`：`:102` `if (copy_done || copy_abort) copy_active <= 0;` ⇒ 允许下一次启动。
     - abort 进显示侧：`pl_video_top.v:283` `else if (copy_abort) eth_has_frame <= 1'b0;`（**被像素域直接采样，未同步**，见 §12）。
  5. **实测数（〔报告〕`report/V6_ROOT_CAUSE.md:69-73`，`tb_v6_vblank_copy` 生产几何 + 限速 slave）**：

     | slave 速率 | copy_cycles | 结果 |
     |---|---|---|
     | 10/10 (800 MB/s) | **38441** | 一个 V-blank 内完成 |
     | 7/10 (560) | 54894 | 同上 |
     | 6/10 (480) | **64036** | 贴着 67200 预算 |
     | 4/10 (320) | **1708873** | 溢出到后续多个消隐窗才完成；「不写有效行、不重复、不越界，看门狗(20ms)不误杀」 |

     板级：`report/PERF_REPORT.md:154-156` —— `copy_cycles ≤ 67200`、`copy_overrun` 从未置起、`led[0]` 保持 1.5 Hz。
- **另一条启动触发**：`vsync_req`（`frame_commit_lock.v:56-66`，vs_rise 翻转 → axi 3FF → `b1^b2`）与 `allow_rise` 并联作为 start 条件（`:103`）。注释 `:75-77` 说明为什么要 `allow_rise` —— 1024x600 的 V_FP=3+V_SYNC=6 使 vsync 只在窗口开始 9 行后才上升，会白扔三分之一预算；`vsync_req` 留着只为兼容旧 TB。**注意 `allow` 与 `start_copy` 都在 axi 域，靠 `allow_rise`（`:78-83`）打拍取边沿。**

---

## 6. AXI 主端口、位宽、突发、在途深度、skid 尺寸

- **端口 = HP0（不是 GP0）**：`system_top.v:78-93` 只连了 `M_AXI_HP0_*`；PL 侧 PS 的 `S_AXI_HP0_DATA_WIDTH = 64`（`vivado_system/.../design_1.bd:1038-1039`）；BD 端口 `M_AXI_HP0_arlen` 是 **`[3:0]`**、`awlen` 亦 `[3:0]`（`vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v:104,115`）⇒ **AXI3 HP0，单突发上限 16 拍**，这就是 `BEATS=16` 的来源（`axi_frame_writer_gated.v:40`）。
- **位宽**：R/W 数据 64bit（`system_top.v:51/62`，`pl_video_top.v:38/42`）。
- **回读突发参数**：`m_axi_arsize = 3'b011`（8 B/拍 = 全宽）、`m_axi_arburst = 2'b01`（INCR）、`m_axi_arlen = BEATS-1 = 15`（`axi_frame_writer_gated.v:36-37,112,125`）。写入侧同参数：`awsize=3'b011`、`awburst=INCR`、`awlen=8'd0`（**每字一拍单拍写**，`axi_frame_saver64.v:46-48`）、`wlast` 恒 1（`:50`）、`wstrb` 按 16bit lane 生成（`:90-91`，注释 `:86-89` 说明旧实现恒 8'hFF 造成每帧 111 处 4 字节黑洞）。
- **8→4 bit 的裁剪点**：`system_top.v:66` `wire [3:0] m_awlen_axi3 = m_awlen[3:0];`、`:96` `assign m_arlen_axi3 = m_arlen8[3:0];`。因为 arlen 恒 15，裁剪无害。〔推断〕
- **在途深度**：`MAX_OUT = 3'd4` 个突发（`axi_frame_writer_gated.v:46`）⇒ **4×16 = 64 拍在途**，注释 `:44-45` 说明目的是盖住 HP0/DDR 读延迟、在 25 行窗口内维持 ~1 拍/周期。`outstanding` 计数器在 `:114/128` 递增、`:140/148/153` 在 `rlast` 时递减（且 `outstanding!=0` 保护）。
  - **写方向**的在途是另一套：`OST = 4'd8` beat（`axi_frame_saver64.v:72`），且 B 通道永不反压（`:163`）、计数「只减不回绕」（`:165-167`）。
- **skid 缓冲尺寸**：`SK = 6` ⇒ 64 项（`axi_frame_writer_gated.v:47,52-53`），但 `sk_full` 用 `level >= 63`（`:57`）⇒ **有效深度 63**；`can_issue` 另要求 `sk_level <= 63-16 = 47`（`:74`）以保证一整包突发装得下。两个数组 `sk_addr[0:63] (19b)`、`sk_data[0:63] (64b)` 显式 `(* ram_style="distributed" *)`（`:51-53`），读口是**异步**的（`:61-63`），注释 `:49-51` 记录动机：原写法触发 `Synth 8-4767`「Block RAM or DRAM implementation is not possible」，64×83bit 全掉进触发器（约占当时剩余寄存器一半）。〔报告旁证〕`report/OVERNIGHT_LOG.md:109`（R05：Reg 9.02%→4.08%、Slice 36.05%→18.03%）。
- **握手细节**：AR 只在 `m_axi_arvalid && m_axi_arready` 时撤（`:130`）；`r_hit = rvalid && rready`（`:76`）；`done` 的条件是 `wr_words >= TOTAL_WORDS && sk_empty && !arvalid && outstanding==0 && !sk_drain && !fb_wr_en`（`:157-158`）⇒ **「每个 64bit 字都真写进 BRAM 之后」才算完成**（头注释 `:6`）。`wr_words` 由 `fb_wr_en` 递增（`:102`）。
- **两个读突发机共用一个 AR/R**：`pl_video_top.v:340-345` 用 `eth_mode ? row_xxx : fill_xxx` 逐个 mux，`arready`/`rvalid` 也反过来按模式给门（`:267-268`、`:334-335`）。**〔推断〕模式位在握手中途翻转会把 `arready`/`rvalid` 凭空掐掉**；`eth_mode` 来自 `eth_link`（`|stat_pkts`，`eth_udp_video_top.v:301`）的 3FF 同步（`pl_video_top.v:225-230`），链路断流时才可能翻转。
- `m_axi_arid` 恒 6'd0（`pl_video_top.v:321`）、`awid/wid` 恒 6'd0（`system_top.v:85,92`）、`arcache/awcache = 4'b0011`、`arprot/awprot=0`、`arqos/awqos=0`、`arlock/awlock=2'b00` 全为常量（`system_top.v:79-87`）；BD 侧 `bid/bresp` **输出悬空**（`system_top.v:89`）⇒ 写响应错误不回读。

---

## 7. 显示帧缓存 BRAM：阵列组织 / 地址映射 / 读延迟 / 越界保护

被例化的只有 **`frame_buffer_w64`**（`pl_video_top.v:369-373`，实例名 `u_fb`）。`frame_buffer.v`、`frame_buffer_db.v` **在整个 `src/rtl` 里没有任何例化点**（只有文档与 `frame_buffer_db` 的资源失败记录，见 §11）。

- **为什么拆两块**：非 2 的幂深度会让 BRAM 推断把地址空间向上填到 2^16 ⇒ 512×300 吃掉 128 个 RAMB36（全片 140），而数据量只需 67 tile；拆 32768+8192 后实测 80。文件头注释 `frame_buffer_w64.v:5-10` 明确指向对照实验 `sim/probes/fbtest.v`（v0 单阵列=128 / v5 分块=80）。〔报告旁证〕`report/CHANGELOG_V7.md:110-135` + `report/OVERNIGHT_LOG.md:295-305`：v0/v1/v2/v3 全 128（与深度声明写法无关，是「地址空间被取到 2^16 个字」决定），v4 32bit 宽=64，v5 分块=**80**。当前 `build/utilization.rpt` §3 Memory：**Block RAM Tile 90.5/140 = 64.64%**（RAMB36 89 + RAMB18 3）；`build/util_hier.rpt:53` 里 `u_fb = 128 RAMB36 / 266 LUT / 2 FF` 是 **R04 修复前的快照**（该文件时间戳 09-21 23:56），别当成现值。
- **深度/位宽**：`WORDS = (W*H+3)/4 = 38400` 个 64bit 字；`D_LO = 32768`、`REM = 5632`、`D_HI = 8192`（`frame_buffer_w64.v:34-37`，由常量函数 `bitsof()` `:25-32` 推导，不硬编码 512×300）。两个数组 `lo[0:32767]`、`hi[0:8191]` 各 64bit、都标 `(* ram_style="block" *)`（`:39-40`）。总容量 40960 字 > 38400 ⇒ 富余 6.7%。
- **写口（axi_clk 域）**：`wr_addr[18:0]` 是 **64bit 字索引**（注释 `:17`），`wr_hi = (widx >= D_LO)`、`w_off = widx - D_LO`（`:43-44`）；写保护 `if (wr_en && widx < WORDS)`（`:47`）⇒ **越界写被忽略**（`report/OVERNIGHT_LOG.md:301-305` 的 TB `sim/tb_fb_roundtrip.v` 专门验过「越界写不污染」）。`hi` 侧索引还额外 `& (D_HI-1)` 掩码（`:48`）。
- **读口（clk_pix 域）与地址映射**：`rd_addr` 是 **像素号**（`:21`），`ridx = rd_addr[18:2]`、lane = `rd_addr[1:0]`（`:55,68`）⇒ 一个 64bit 字里 4 个 RGB565，`{p3,p2,p1,p0}`（`:18`）。
  上游地址由 `pl_video_top.v:363` 生成：`rd_addr_q <= {sy_fb[8:0], 9'b0} + {7'b0, sx_fb}` ⇒ **行距被硬编码成 512（移位 9）**〔推断：只有 IMG_W=512 时正确；IMG_W 一改地址图就错，且 `sy_fb[8:0]` 只能表达到 y=511〕。
- **读延迟 = 1 拍（模块内）**：`:64-70` 一个无复位的 `always @(posedge rd_clk)` 里**两个块每拍都读**（`:65-66` 各带掩码，越界一侧地址被夹住不会产生 X，注释 `:53-54`），同时打拍 `sel_hi`/`sel_lane`/`blank`；组合 2:1 + 4:1 lane mux 在 `:72-81`。加上 `pl_video_top.v:359-367` 的 `rd_addr_q` 一级，**从逆映射输出到 `fb_rd` 共 2 拍**（这也是 `frame_buffer_w64.v:3` 「读延迟仍是 1 拍」的 v6.4 契约，`report/OVERNIGHT_LOG.md:303-305` 说 TB 用「流水一拍一像素」把它变成了可判据）。
- **「越界 → 黑」保护有两处（双保险）**：
  1. BRAM 内：`blank <= (rd_addr >= (W*H))`（`:69`，注释「越界仍回黑，保持 v6.4 行为」）+ `assign rd_data = blank ? 16'd0 : lane`（`:82`）。
  2. 顶层：`oob_fb` → `oob_fb_d0/d1`（`pl_video_top.v:355,361,364,393`）→ `pix_left/pix_right` 里 `oob_fb_d1 ? 16'h0000 : ...`（`:398-401`）。
- **没有任何读写仲裁**：写口 `wr_clk=axi_clk`、读口 `rd_clk=clk_pix`，同一阵列两套时钟、无握手 —— **正确性完全外包给 §5 的消隐门控**（`pl_video_top.v:3-4` 头注释就是这个契约）。
- **顶层的读像素保持逻辑**：`pl_video_top.v:294-305` —— `ac0/ac1` 是 `allow_copy` 的 2FF（带 `ASYNC_REG`），`if (!ac1) fb_pix_hold <= fb_rd`（拷贝窗口打开前最后一拍锁存），`fb_out = (ac1 && !de_d[11]) ? fb_pix_hold : fb_rd`（`:305`）⇒ **只在拷贝机可能碰 BRAM 的消隐期保持最后一个像素**，有效行始终显示活的 BRAM（注释 `:292-293`）。`bram_or_hold = eth_link ? fb_out : 16'hF800`（`:307`）：**只有无链路才红屏**（注释 `:306`）。

---

## 8. split_display 几何与像素选择

- **显示格式**：1024×600，H_TOTAL 1344 / V_TOTAL 625，`H_POL=1`（HS 正有效）、`V_POL=0`（VS 负有效）—— `video_timing_1024x600.v:17-26`；发生器的 x/y/de/hs/vs 全部寄存一拍（`video_timing.v:63-67`），`frame_start = de_act && h_cnt==0 && v_cnt==0`（`:68`，**1 pix 拍**），`frame_done` 在最后一行最后一列（`:69`）。
- **两个窗的 x 区间**：`PANE_W=512`（`system_top.v:161` 传入），`left_pane = (x < PANE_W)`（`pl_video_top.v:111`）⇒ **左窗 x=0..511，右窗 x=512..1023**；`cx = left_pane ? x : x - PANE_W`（`:112`）⇒ 两窗各自的源 x 都是 0..511。
- **纵方向 2× 最近邻**：`cy = ((y >> 1) < IMG_H) ? (y >> 1) : (IMG_H - 1)`（`:113`）—— **丢掉 y 的最低位 = 2 倍垂直放大、无插值**；消隐期（y≥600）被夹到最后一行 299（不产生越界读）。
- **源像素选择的三岔**：
  - 左窗：`rot_on` 为真 → `rotate_mapper`（`:125-130`，**3 级流水**：`rotate_mapper.v:25-28/32-37/45-64`）；否则 → `cx_q3/cy_q3` 纯 3 拍延迟（`pl_video_top.v:132-148`），与逆映射流水深度对齐。`oob_q1 <= (cx >= IMG_W) || (cy >= IMG_H)`（`:142`）。
  - 右窗：恒走 `zoom_mapper`（`:154-160`，**3 级**：`zoom_mapper.v:31-36/42-55/76-96`），`inv_scale` 为 **Q8**（256=1.0×，512=0.5×，`zoom_mapper.v:2-3,10`）；缩放取整是 **`>>>8` / `>>>16` 的算术右移 = 向下截断（floor），没有任何舍入或插值**（`:63-66`），中心平移 `+IMAGE_W/2`、`+IMAGE_H/2`（`:68-71`）。旋转叠加时走 `xr_pix/yr_pix`（`>>>16`）并把 Y 翻回数学系（`:28-29,70`）。
  - 选择器：`fb_sel_right = ~left_d[2]`（`:351`，`left_d[2]` 正好是 3 拍 ⇒ 与两个 mapper 的 3 级流水同槽），`sx_fb/sy_fb/oob_fb` 三选一（`:352-354`）。
  - **图像外**：`oob_fb_d1` 为真 → 该窗显示 **纯黑 `16'h0000`**（`:398-401`）；BRAM 内部还会再黑一次（§7）。右窗缩放/旋转出现四周空边就是这个路径（`zoom_mapper.v:57` 注释「inv>256 时边缘 OOB 填黑」）。
- **中缝蓝线**：`sep = (x == PANE_W-1) || (x == PANE_W)`（`split_display.v:32`）⇒ **x=511、512 两列**，且 `if (sep && de) r,g,b = 8'h40,8'h40,8'hFF`（`:42-43`）—— **优先级高于 oob 与像素选择**（`:28` 的 `sel` 被它覆盖），所以中缝永远蓝、不受源影响。
- **RGB565 → RGB888 扩展**：`r={r5,r5[4:2]}`、`g={g6,g6[5:4]}`、`b={b5,b5[4:2]}`（`split_display.v:45-47`，复制高位补位）。
- **左右两路的喂数与时序对齐**（重要且极易读错，逐项列出）：
  - `pix_left` 只在 `left_pix` 时有效、否则 0；`pix_right` 反之（`pl_video_top.v:398-401`）⇒ **效果链只看到右窗像素**：`u_pipe` 的 `din(pix_right)`、`de_in(de_d[3] && !left_d[3])`、`x_in(cx_d[3])`、`y_in(cy_d[3])`、`hs_in/vs_in = hs_d[3]/vs_d[3]`（`:410-419`）。
  - 左窗像素走一条 `LEFT_TAIL = PROC_LAT = 7` 深的 skid（`:405-406,421-443`）以补齐效果链延迟；`PROC_LAT=7` 是**手写的魔数**（注释里没有推导）。
  - **〔推断〕din 与 de/x 差 1 拍**：逐拍数下来 `fb_rd(T)` 对应 `cx(T-5)`（3 拍 mapper + `rd_addr_q` 1 拍 + BRAM 1 拍），`oob_fb_d1`、`left_pix(=left_sel_d1)` 都落在 `T-5` 一致；但 `de_d[3](T)=de(T-4)`、`cx_d[3](T)=cx(T-4)`，**比 `pix_right(T)` 早 1 拍**。板级看不出来是因为效果链内部（blur/sobel）本身还各有 de/数据延迟：`proc_box_blur.v:65-72`、`proc_sobel.v:53-66` 的 de 是 3 拍而数据通道另有安排，最终 `PROC_LAT=7` 是在板上标定出来的。
  - **彩条的两条延迟链不同深**：左路 `bar_l0 → bar_l_d4`（4 拍，`:386-388`）合计 5 拍，正好等于 BRAM 读路的 5 拍；右路 `bar_r0`（x 用 `sx_r`、de 用 `de_d[2]`，`:381-384`）之后只取 `bar_r_d2`（2 拍，`:388`）⇒ **右窗彩条比右窗视频晚 1 拍**。〔推断；8 条 64px 宽的竖条 + 32px 对角暗纹（`color_bar.v:20-37,52-54`）下肉眼不可见。〕
  - 送进 `split_display` 的是 `de_d[11]/hs_d[11]/vs_d[11]/x_d[11]/y_d[11]`（`:445-446,450-458`），而 16 级移位数组 `de_d/x_d/...` 在 `:162-181`；`split_display` 自身再加 1 拍寄存输出（`split_display.v:34-50`），`osd_overlay` 再加 1 拍（`osd_overlay.v:186-200`）⇒ **光栅到 TMDS 编码共有 13 拍延迟**（11 + 1 + 1）。

---

## 9. OSD 叠加

- **位置与实例化**：`pl_video_top.v:489-502` 的 `u_osd`，**没有任何参数覆盖** ⇒ 全部用默认值：`X0=16, Y0=12, SCALE=3, CHAR_W=18, CHAR_H=21, LINE_GAP=10, MAX_CHARS=10, N_LINES=3`（`osd_overlay.v:8-15`）。
  ⇒ 文字盒 `BOX_W = 10*18 = 180`、`BOX_H = 3*(21+10) = 93`（`:42-44`）⇒ 覆盖 **x=16..195、y=12..104**（`:46-47`），**完全落在左窗内**（左窗 0..511）。〔推断：由参数算得〕
- **插入点在流水线里的位置**：`split_display` **之后**、`rgb2dvi` **之前**（`pl_video_top.v:450-458 → 489-502 → 504-510`），叠加的是 **RGB888 + hs/vs/de**，不碰左右窗像素选择通路；坐标取 `x_d11/y_d11`、`de` 取 `de_o`（`:493`）。
  - **〔推断〕此处有 1 拍错位**：`split_display` 的输出 `r/g/b` 与 `de_out` 都是寄存后的（`split_display.v:39-48`），即 `r_in(T)` 对应 `x_d11(T-1)`，而 OSD 在同一拍用 `x(T)=x_d11(T)` 去判窗（`osd_overlay.v:46-54`）⇒ 文字盒在屏幕上比名义位置**右移 1 像素**。y 方向不受影响（一行内 y 恒定），所以看不出问题。正确写法应是再延一拍 `x_d12/y_d12`。
- **文本行**（固定串 + 运行时数字，头注释 `osd_overlay.v:2-6`）：
  - L0 `FPS=xx`（`:81-87`，fps 饱和到 99：`:64-66`）
  - L1 `ANG=xxx`（`:89-96`，0..359 三位十进制，`:68-72` 用常量除法/取模拆位）
  - L2 `EN=xxxxx`（`:98-106`，`effect_en[0..4]` 逐位显示成 '1'/'0'）
  - `chars[]` 数组在**组合块 `always @(*)`** 里整体重写（`:75-107`，未使用位置先填 `8'h20` 空格）。
- **字模来源**：模块内 **5×7 点阵**，`reg [4:0] font [0:31][0:6]`（`:110`），**只在 `initial` 里初始化**（`:112-163`，`font[31]` 全 0 = 空位），读口是组合的 `font[gi][fy]`（`:183`）⇒ 综合成 LUT-ROM（`build/util_hier.rpt:56`：`u_osd = 313 LUT / 22 FF / 0 BRAM`）。ASCII→字模索引由函数 `glyph_idx` 做**稀疏映射**（`:165-177`）：`0-9`→0..9、`A-F`→10..15、`G`→16、`N`→20、`P`→22、`S`→24、`=`→27、**其余一律 31=空白**（注释 `:6` 特别强调「Space = 空字模，不是数字 0」）。
- **放大与取整**：`SCALE=3` ⇒ `fx = pix_x/3`、`fy = (pix_y<21) ? pix_y/3 : 6`（`:181-182`），即**整数除法 = 最近邻放大 3 倍**；`fy` 的钳位让最后一行点阵被多扫 1 个缩放行（`pix_y=18..20` 都落在 `fy=6`）。〔推断〕
- **非 2 幂除法**：`line = ly/31`、`cidx = lx/18`、`pix_x = lx%18`、`pix_y = ly - line*31`（`:50-53`），除数是 localparam 常量 ⇒ 综合期折叠成移位+加减，不占 DSP。〔推断〕
- **颜色**：命中笔划时 **rose 洋红 `r=8'hFF, g=8'h00, b=8'h90`**（`:195`，注释 `// rose`），未命中则原样透传 `r_in/g_in/b_in`（`:197`）；`pixel_on = in_char && (fx<5) && font_row[4-fx]`（`:184`，**行内位序左右翻转**）。命中判定要求 `de` 为真（`:46`）⇒ OSD 不会画进消隐期。
- **输入端与文档不符的死输入**：`src_sel / eth_link / net_pkts / net_bad / bg_pix`（`:25-29`）**在模块体内一次都没出现**，而顶层仍然驱动它们（`pl_video_top.v:495-497`：`.bg_pix(16'h0)`）。⇒ 想加「LINK/PKTS/BAD」行必须改 RTL，不是改参数就行。

---

## 10. HDMI / TMDS：原语、时钟域交叉、像素钟与串行钟的关系

- **通道映射**：`rgb2dvi.v:20-32` —— **channel0 = Blue 且携带 hs/vs（`c0=hs, c1=vs`）**，channel1 = Green，channel2 = Red；`u_ser0/1/2` 分别输出 `tmds_data_p[0]/[1]/[2]`（`:34-45`）。**时钟通道 = 常量 10bit 图案 `1111100000` 的循环串行化**（`:47-51`）。
- **编码器**：标准 DVI 8b/10b，`tmds_encoder.v:13-36` 计算 `q_m`（`use_xnor` 判据 `n1>4 || (n1==4 && din[0]==0)`，`:21`），`:42-74` 做 DM 平衡（`cnt` 为 `reg signed [5:0]`，`:38`）。**消隐期直接发三种控制字符**（`:46-53`，`{c1,c0}` → `1101010100 / 0010101011 / 0101010100 / 1010101011`），`cnt` 同步清零。〔推断〕`cnt` 的加减里混用了 4bit 无符号 `n0q-n1q` 与 6bit signed `cnt`，Verilog 会把整式按无符号算，靠模 64 回绕得到正确的有符号结果 —— 结论对，但写法脆弱。
- **串并转换原语**：`tmds_serializer.v:15-89` —— **`OSERDESE2` 主从级联**，`DATA_RATE_OQ="DDR"`、`DATA_WIDTH=10`、`SERDES_MODE="MASTER"`/`"SLAVE"`（`:18-19,56-57`）；**主片用 D1–D8，从片只用 D3/D4**，从片 `SHIFTOUT1/2 → 主片 SHIFTIN1/2`（`:26-27,64-65,81-82`），文件头 `:2-3` 引 UG471 说明 `DATA_WIDTH=10` 必须配 `DATA_RATE_OQ=DDR`。两片 `OCE=1'b1`、`TCE=1'b0`、T1–T4/TBYTEIN=0（`:41,45-50`），输出经 **`OBUFDS`**（`:91`）走 `TMDS_33` 电平管脚（`rk_zynq7020.xdc:12-19`：W16/Y16 时钟对，AA17/AB17、U17/V17、U15/U16 三对数据）。
- **像素钟与串行钟关系**：`OSERDESE2.CLK = clk_pix5x (250 MHz)`、`.CLKDIV = clk_pix (50 MHz)`（`:31-32,69-70`）⇒ 每 CLKDIV 周期装 10 bit、DDR 每 CLK 周期出 2 bit ⇒ **250×2 = 500 Mbit/s = 50 MHz × 10**，即 **TMDS 字符率 = 像素率 = 50 Mpx/s，线路速率 500 Mbps/lane**（1024+1344 行 × 625 行 = 59.52 Hz 帧率〔推断〕）。50 MHz ≪ HDMI 1.0 的 165 MHz 上限。
- **时钟域交叉（CDC）到底做了什么 —— 答案是「什么都没做，而且这是对的」**
  - `din`（`tmds_encoder` 的 `dout`，**clk_pix 域寄存**，`tmds_encoder.v:42-74`）直接进 `OSERDESE2` 的并行脚，而该原语的装载沿是 **CLKDIV = clk_pix**（CLK 只负责移出）⇒ **不存在真正的异步跨钟**；两个钟来自**同一个 MMCM 的 CLKOUT0/CLKOUT1**（`clk_gen.v:21,24`，5:1 整数比、0° 相位）。
  - 佐证：`build/cdc.rpt` 的 CDC 矩阵里**根本没有 `clkout0_1 ↔ clkout1_1` 这一对**；`build/clock_util.rpt:220` 显示 `clk_pix5x` 只有 **8 个 IO 负载、0 个 slice 负载**；`build/timing_summary.rpt:187` 里 `clkout1_1` 没有 setup/hold 路径，只有 WPWS `+2.408 ns`（10 个端点）。
  - `rk_zynq7020.xdc:53-56` 的 `set_clock_groups` 把它们留在同一组，正是让 Vivado **按时钟同步路径去分析**这条跨钟（若按异步处理反而会漏检）。
- **真正危险的跨钟不在 HDMI，而在链路状态与网络计数上（`build/cdc.rpt` 原文条目）**
  - `eth_rxc → clkout0_1`：**33 个端点，16 unsafe / 17 unknown / 0 标 ASYNC_REG**。对应 `pl_video_top.v` 里 `eth_link` 被**原样采样**用在 `:282`（`frame_ready && eth_link`）、`:288`（`eth_ready`）、`:307`（`bram_or_hold`）、以及 `:482-487` 的 2 拍（**无 `ASYNC_REG`**）链。
  - `pkts_s1/bad_s1` 是**16bit 计数器总线**只过 2 个 FF（`:484-485`）⇒ 必然可能读到撕裂值；好消息是它们最终送进 `osd_overlay` 的**死输入**（§9），所以只是死逻辑。
  - 与之对照，设计里做对了的三处：`eth_link → eth_mode`（`:225-230`，3FF + `ASYNC_REG`）、`eth_commit/pending`（axi 同域，§4）、`src_sel`（`:273-278`，3FF + `ASYNC_REG`）。
  - `angle[8:0]` 从 `sys_clk` 域（`angle_ctrl`，`:76-80`）**未同步**直接进像素域（`rotate_mapper.v:12`、`zoom_mapper.v:11`、`split_display.v:455` 取 `angle[1:0]`、`:520` status）——`build/cdc.rpt` 把它归为 **`sys_clk → clkout0_1` “Safely Timed”，347 端点全 safe**，因为 `clk_pix` 是 `sys_clk` 的**同 MMCM 生成钟**（DIVCLK 20），二者固定相位、真做 setup 分析（`build/timing_summary.rpt:199`：`sys_clk→clkout0_1` WNS **+8.401 ns**，347 端点）。〔推断〕多位同时翻转仍可能在 1 个像素周期内读到中间角值，按键瞬间可能出现 1 像素毛刺。

---

## 11. 死代码 / 未连端口 / 常量绑定 / 参数覆盖清单（显示链范围内，逐条给位置）

**A. 顶层常量绑定（等于把「可复位设计」变成「只上电有效」）**
1. `system_top.v:162` `.sys_rst_n(1'b1)` —— pl 侧全无复位；`system_top.v:109` `.rst_n(1'b1)` —— 第二个 MMCM 的 `RST=~rst_n` 恒 0（`clk_gen.v:49`）。
2. `system_top.v:165` `.zoom_en(1'b1)` —— 右窗缩放**永远在跑**，配合 `pl_video_top.v:10,94-98`（`ZOOM_DEFAULT_ON=1` 作为复位值）⇒ `zoom_run` 恒 1。
3. `system_top.v:103-104` `eth_mdio = 1'bz`、`eth_mdc = 1'b0` —— **完全没有 MDIO/PHY 寄存器配置**，靠 PHY 硬件默认（注释 `system_top.v:39-40` 仍保留了这两个端口）。
4. `system_top.v:89` `M_AXI_HP0_bid()`、`.M_AXI_HP0_bresp()` 悬空；`:85,92` `awid(6'd0)`、`wid(6'd0)`；`:79,86` `arcache/awcache = 4'b0011`、`:81,87` `arqos/awqos = 4'b0000`、`:80,86` `arlock/awlock = 2'b00`、`:81,87` `arprot/awprot = 3'b000` —— 全常量。
5. `system_top.v:52-53` `m_rid/m_rresp` 连到 BD 但下游无人读；对应 `pl_video_top.v:39-40` 两个输入端口在体内**零引用**。
6. `system_top.v:117` `eth_frames`、`eth_bytes` 接了 `stat_frames/stat_bytes` 却不再使用；`:44` 的 `status` 只被 `pl_video_top` 驱动（`system_top.v:184`），**顶层没有对应输出端口** ⇒ 整条 `status`（含 `eth_ready`、`locked`、`inv_scale` 等 32 位可观测量，`pl_video_top.v:520-521`）在综合后会被裁掉。〔推断〕

**B. 显示链里的死输入/死输出**
7. `pl_video_top.v:45-50`：`eth_wr_clk`、`eth_wr_en`、`eth_wr_addr`、`eth_wr_data`、`eth_frame` 五个输入**在体内一次都没引用**，而 `system_top.v:142-145,146,174-179` 认真地把 `frame_reasm` 的 BRAM 写口与 `frame_done` 送了过来 —— **v5 已经改成「BRAM 只由拷贝机在消隐期写」**（`pl_video_top.v:3-4` 头注释），这条直写通路是历史残留。
8. `pl_video_top.v:153,159` `zfrac_x/zfrac_y`（zoom_mapper 的小数部分输出）接了不用 ⇒ **本可支持双线性插值，实现是最近邻**（另见 `zoom_mapper.v:18-19,73-74,93-94` 也算了没人用）。
9. `pl_video_top.v:104,108` `video_timing_1024x600` 的 `frame_done` 输出接了不用（只有 `frame_start` 用于 `:119,312`）。
10. `pl_video_top.v:290` `assign copy_hold = 1'b0;` —— 常量，经 `system_top.v:121,136,185` 送进 `eth_udp_video_top.v:18` 的 `copy_hold` 输入，该输入在体内**零引用**：三级死端口。
11. `pl_video_top.v:127` `rotate_mapper` 的 `.enable(1'b1)` ⇒ `rotate_mapper.v:50-53` 的「不旋转旁路」分支**永不执行**（旁路是在 `pl_video_top.v:147-148` 外面用 mux 做的）。
12. `split_display.v:9,16`：`y` 与 `angle_idx` 两个输入在体内未使用；顶层仍传 `.angle_idx(angle[1:0])`（`pl_video_top.v:456`）。
13. `osd_overlay.v:25-29`：`src_sel / eth_link / net_pkts / net_bad / bg_pix` 五个输入未使用（详见 §9）。
14. `frame_commit_lock.v:6-7,16`：参数 `IMG_H`、`DISP_H` 与输入 `de` 在体内**完全未引用**；顶层却传了 `#(.IMG_H(IMG_H), .DISP_H(600))` 和 `.de(de)`（`pl_video_top.v:232,236`）。文件头 `:3-4` 还写着「allow = ALL blanking after de_d4→de_d[11]」，**与现在的 `blank_safe` 实现不符**（注释过期）。
15. `axi_frame_writer_gated.v:10` 的 `BASE_ADDR` 参数只用作 `base_r` 的复位值（`:96`），真实基址走端口 `base_addr`（`:108`）⇒ `pl_video_top.v:256` 传 `.BASE_ADDR(BASE_ADDR)` 属于双写。
16. `axi_frame_writer64`（`pl_video_top.v:323-338`）：`.frame_busy()`（`:330`）、`.copy_cycles()`（`:337`）悬空；`.base_addr(BASE_ADDR)`（`:329`）与参数同值双写；`.enable(eth_mode ? 1'b0 : src_sel)`、`.frame_start(eth_mode ? 1'b0 : ps_frame_start)` ⇒ **入包模式（eth_mode=1）下这台机器永远不启动**，只服务「无网口 demo」。
17. `ddr_bank_commit.v:41-42` 的 `switch_req`、`force_flush` 两个输出在 `eth_udp_video_top.v:276-277` 留着不接（但内部 `pack_flush` 仍用 `force_flush`，`:88`）。`axi_frame_saver64.v:31` 的 `busy` 在 `eth_udp_video_top.v:287` 悬空；`sync_fifo` 的 `.full()/.empty()/.level()` 三个状态输出也不接（`eth_udp_video_top.v:112`）；`eth_ctrl` 的 `.arp_tx_type()`、`.icmp_tx_data()`、`.udp_tx_data()` 悬空（`:160,165,169`）。
18. `pl_video_top.v:69,73` `key_debounce .key_stable()` 悬空。

**C. 整模块级死码**
19. `src/rtl/axi/axi_frame_writer.v`（16bit 逐像素解包 FSM）：**`src/rtl` 内零例化**；只有 `sim/run_sim.tcl:18` 注释与 `report/MODULES.md:65,125` 提到它（"备份：FILL 可写 DDR，axi_frame_writer 回读"）。
20. `src/rtl/video/frame_buffer.v`、`frame_buffer_db.v`：**`src/rtl` 内零例化**。`frame_buffer_db` 的双缓冲方案在 `report/VERSION_LINEAGE.md:56` 被记为「**7020 BRAM/LUT 爆资源，实现失败**」，`report/OVERNIGHT_LOG.md:118`（P09）把这类模块统一登记为「10 个未综合/仅 TB 使用的死模块，删除有回滚风险，暂不动」。
21. `report/MODULES.md:125` 明说「第三版的 `axi_frame_saver` / `axi_frame_writer` / `frame_buffer` 已被替换」，但文件仍在树里 —— 读代码时注意别把三版当现行版。

**D. 参数覆盖 / 未覆盖（改一下就会不一致的地方）**
22. `IMG_W/IMG_H` 在 `system_top.v:124` 与 `:161` **两处重复写**；`BASE_ADDR` 在 `:125` 与 `:161` 两处；`PANE_W=512` 只在 `:161` 给；`video_timing_1024x600` 的 1024×600 **完全不参与 IMG_*，写死**（`video_timing_1024x600.v:18-20` + `pl_video_top.v:207-208` 的 600/624 再写一遍）。
23. `frame_reasm` 例化时 `FRAME_BYTES` **未覆盖**（§3）。
24. `ddr_bank_commit #(.TAIL_GUARD(1'b1))`（`eth_udp_video_top.v:258-259`）在板上恒为 1；`:19` 的 0 值只供 A/B 复现 v6.4 丢帧尾。
25. `frame_commit_lock` 的 `WD_CYC` **从未被覆盖**（`pl_video_top.v:232`）⇒ 看门狗恒 2_000_000 拍 ≈ 20 ms。
26. `zoom_ctrl #(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd2))`（`pl_video_top.v:117`）—— 缩放下限 1.0×、上限 0.5×，Q8 语义在 `zoom_mapper.v:2-3` 说明。

---

## 12. 多重驱动 / 缺失复位 / 数组推断风险

- **同一信号在两个 always 块里被写**：**显示链内未发现这种写法**。对 `pl_video_top.v / axi_frame_writer_gated.v / frame_commit_lock.v / frame_buffer_w64.v / osd_overlay.v / split_display.v / ddr_bank_commit.v / eth_udp_video_top.v / axi_frame_saver64.v / frame_reasm.v / axi_frame_writer64.v` 做过「按 always 块归属统计被 `<=` 赋值的左值」的脚本扫描，**无输出 = 无重复**。
  - 真正存在的是**数组级别的双块分工**（不是多重驱动，但读代码时容易误判）：
    - `frame_buffer_w64.v`：`lo/hi` **写在 `wr_clk` 块**（`:46-51`）、**读在 `rd_clk` 块**（`:64-70`）—— 跨两套时钟的真双端口，无仲裁（§7）。
    - `axi_frame_writer_gated.v`：**数组元素写**在 `:84-89` 的**无复位独立块**，**指针 `sk_w/sk_r` 写**在 `:91-164` 的带异步复位块。注释 `:81-83` 直说这是「R02 探针实测出的唯一能被推断成 RAM 的形状」，并要求 `sk_addr/sk_data` 的读口保持**异步**（`:59-63`，同地址读写返回旧值，与原语义一致）。
    - `axi_frame_saver64.v:104-121` 同一论述：`q_addr/q_data/q_keep` 独占无复位块，注释给了量化对照「task 写法 FF=32904/LUTRAM=0，本写法 FF=85/LUTRAM=864」，并点名 `Synth 8-7186`。
    - `dc_fifo.v:44-49`：`mem` 写单独一块、注释 `// memory write: no reset → BRAM-friendly`，指针与格雷码同步器在另两块（`:36-43,56-65,68-81`）。
  - 合并写脉冲的痕迹（原本是两处、现被证明等价而合并）：`axi_frame_writer_gated.v:81-83`（`A&&do_skid | !A&&do_skid = do_skid`）、`axi_frame_saver64.v:104-108`（两处 push 内容完全相同）。
- **「必须推断成 BRAM 的数组不能带复位」这一条在本设计里是被违反过、已修**：`README.md:62-65`、`report/OVERNIGHT_LOG.md:109`（`Synth 8-4767`）、`CHANGELOG_V7.md:162`。现状检查：`frame_buffer_w64`（`ram_style="block"`，写读两块均无复位 ✓）、`dc_fifo`（`block`，无复位 ✓）、`frame_buffer_w64` 的输出寄存器 `q_lo/q_hi/sel_hi/sel_lane/blank` 也在**无复位块**里（`:64-70` ✓ —— 若给它们加异步复位，RAMB36 输出寄存器模式会被破坏〔推断〕）、`sk_addr/sk_data`、`q_addr/q_data/q_keep` 全标 `distributed` 且无复位 ✓。
- **反过来，被故意保留复位因而吃触发器的**（有意为之、不是 bug）：16 级像素流水数组 `de_d/hs_d/vs_d/left_d/x_d/y_d/cx_d/cy_d`（`pl_video_top.v:162-181`，`SB=16`）与 7 级 skid `orig_skid/oob_l_skid/oob_r_skid`（`:421-440`）—— 它们是移位链，带复位才能整链归零；`build/utilization.rpt` 显示 LUT as Shift Register 仅 113，说明这些链基本落在 FF 上。〔推断〕
- **缺同步器 / 复位缺失的真实风险点（值得在文档里被点出来）**
  1. `copy_abort` 是 **axi 域信号被像素域直接采样**：`frame_commit_lock.v:92`（`axi_clk`）→ `pl_video_top.v:283`（`always @(posedge clk_pix ...)`，**无 ASYNC_REG、无 2FF**）；同文件里 `allow_copy` 却走了 2FF（`:294-301` 带 `ASYNC_REG=TRUE`）。同一跨域、两种待遇。
  2. `eth_link` 在像素域被裸用 4 处（`pl_video_top.v:282,288,307,486`），正是 `build/cdc.rpt` 里 `eth_rxc → clkout0_1` 的 16 unsafe / 17 unknown 端点。
  3. `effect_ctrl.v:15-30` 的 3 级捕获链（`en_meta/en_sync/effect_en`）**没有 `ASYNC_REG` 属性**，`pl_video_top.v:82-89` 的实例名 `en_sync` 也就是这条链的末级 —— 对比设计里其他同步器全都显式打了 `ASYNC_REG`（`pl_video_top.v:91,225,273,294,314,468`；`frame_commit_lock.v:61,68,117`；`ddr_bank_commit.v:50`），这一处是**漏标**；`build/cdc.rpt` 的 `clk_fpga_0 → clkout0_1` 行「No ASYNC_REG = 13」把它算进去了。
  4. `pl_video_top.v:483-487` 三对 16bit 总线（`pkts_/bad_/link_s0/s1`）在像素域**无复位**且只有 2 拍 —— 不过这些总线的唯一去向是 `osd_overlay` 的死输入（§9/§11-13），所以是「不可达但会综合」的死逻辑。
  5. `pl_video_top.v:469` `{vt2,vt1,vt0}` 整条 `always @(posedge sys_clk)` **完全无复位**（有意给 `ASYNC_REG` 三链；但注释没写，容易被后来人加复位而破坏成对性）。

---

## 13. 一页速览（数据流与握手，含全部关键常量）

```
ETH(RGMII 125M) frame_reasm[307200B/帧, row_ok 位图] --frame_done(1拍)--> ddr_bank_commit
   |  wr:{flush,addr19,data16} --> dc_fifo(8192×36, BRAM) --> (100M) cdc_d1/sav_* 3级流水
   v
axi_frame_saver64 (packer 512×{addr,data,keep} LUTRAM, AWLEN=0, 8 beat 在途, wstrb 按 lane)
   --> HP0(AWI) --> DDR bank0=0x1000_0000 / bank1=0x1008_0000  (乒乓, completed_base)
                                   | commit_pulse(1拍 @100M) + completed_base
                                   v
frame_commit_lock: pending --> start_copy(1拍) / copy_base / allow_copy_axi=d1&d2 / WD_CYC=2e6
                                   |                                    ^
                                   v                                    | blank_safe=disp_quiet(y>=600 且 (y<624 或 x<=1279))
axi_frame_writer_gated @100M: ARLEN=15 ARSIZE=8B INCR, MAX_OUT=4(64拍在途), skid 63(LUTRAM, 异步读)
   --> HP0(AR/R) 读 38400×64bit --> fb_wr_en/addr/word --> frame_buffer_w64(32768+8192, 写=axi/读=pix, 无仲裁)
                                                        只在消隐窗写；越界写忽略、越界读回黑
                                   v  (clk_pix 50M, 读延迟共 2 拍)
逆映射(left: cx_q3/rotate_mapper(3级); right: zoom_mapper(3级, Q8, floor 截断)) → oob→黑
   → pix_right → proc_pipeline(PROC_LAT=7 手标) ‖ pix_left → 7 级 skid
   → split_display(1拍): x511/512 蓝线, oob→0000, RGB565→888
   → osd_overlay(1拍): x16..195 y12..104, FPS/ANG/EN 三行, 5x7字模×3, rose FF0090
   → rgb2dvi: 3×tmds_encoder@50M → 4×(OSERDESE2 MASTER+SLAVE)@250M/50M → OBUFDS → 500Mbps/lane
```

关键数（★ = RTL 直接声明，☆ = 由代码算/〔推断〕，◆ = 报告实测）：
- ★ 一帧 = 512×300 px = 307 200 B（`frame_reasm.v:8`）= 38 400 个 64bit 字（`axi_frame_writer_gated.v:41-42`、`frame_buffer_w64.v:34`）= 2400 个 16 拍突发（`:43`）；bank 间隔 512 KiB（`eth_udp_video_top.v:55-56`）。
- ★ 消隐窗：V-blank 25 行 × H_TOTAL 1344（`video_timing_1024x600.v:18-20`）；RTL 实际放行 33 536 pix 拍（`pl_video_top.v:207-211`）。
- ☆ 33 536 pix 拍 = 67 072 axi 拍 ≈ 670.7 µs；观测门限 67 200 axi 拍（`pl_video_top.v:248`）偏松 128 拍。
- ☆ 帧周期 1344×625 = 840 000 pix 拍 @50 MHz = 16.8 ms ⇒ 59.52 Hz。
- ◆ `copy_cycles` = 38 441 / 54 894 / 64 036 / 1 708 873（对应 slave 10/7/6/4 × 10，`report/V6_ROOT_CAUSE.md:69-73`）；板级 ≤ 67 200、`copy_overrun` 从未置起（`report/PERF_REPORT.md:154-156`）。
- ◆ BRAM 90.5/140 = 64.64%、LUT 6313 = 11.87%、Reg 4345 = 4.08%、LUT-as-Distributed-RAM 1228（`build/utilization.rpt` §1、§3）；`u_fb` 现值 ≈80 tile（`report/CHANGELOG_V7.md` v5 变体），修复前 128.03（`build/util_hier.rpt:53`）。
- ◆ WNS：clk_fpga_0 +1.776、clkout0_1 +3.084、eth_rxc +0.499、sys_clk +14.289（`build/timing_summary.rpt:181-188`）；`clk_pix5x` 无数据路径（同文件 `:187`）。

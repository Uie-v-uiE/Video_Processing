# 02 片源、采集与 HDMI 输出：三路像素如何变成屏上那一条串行差分

本章的被测对象是"画面从哪儿来"与"画面到屏上去"这两头，中间的效果链与几何属于第 05/06/07 章。
读的文件（全部实际打开过）：

* 片源侧：`src/rtl/util/src_mode.v`、`src/rtl/util/src_arb.v`、`src/rtl/util/src_life.v`、
  `src/rtl/util/shown_rate.v`、`src/rtl/util/ps_publish.v`、`src/rtl/util/key_long.v`、
  `src/rtl/video/test_card.v`、`src/rtl/video/color_bar.v`、`src/rtl/eth/frame_reasm.v`、
  `src/rtl/eth/ddr_bank_commit.v`、`src/rtl/eth/link_monitor.v`、`src/rtl/video/frame_commit_lock.v`、
  `src/rtl/axi/axi_frame_writer_gated.v`、`src/rtl/axi/axi_frame_writer64.v`、
  `src/rtl/video/frame_buffer_w64.v`
* 输出侧：`src/rtl/video/video_timing.v`、`src/rtl/video/video_timing_1024x600.v`、
  `src/rtl/clocks/clk_gen.v`、`src/rtl/hdmi/rgb2dvi.v`、`src/rtl/hdmi/tmds_encoder.v`、
  `src/rtl/hdmi/tmds_serializer.v`、`src/rtl/top/pl_video_top.v`、`src/rtl/top/system_top.v`
* 控制侧：`src/ps/main.c`、`src/ps/sd_play.c`
* 约束与读数：`src/constraints/rk_zynq7020.xdc`、`src/constraints/clock_groups_impl.xdc`、
  `src/constraints/r119_hdmi_source_window.xdc`、`src/constraints/r119b_hdmi_tp1_pinclk.xdc`、
  `build/timing_summary.rpt`、`build/utilization.rpt`、`build/check_timing_verbose.rpt`、
  `build/evidence/r119_window_check.txt`、`build/evidence/r119_pin_skew_probe2.txt`、
  `build/evidence/r119_xdc_loads_probe3.txt`、`build/evidence/r119_xdc_loads_probe4_pinclk.txt`、
  `build/evidence/r119_ser_clock_probe.txt`、`data/metrics.csv`

读完要能答上这六件事：① 屏上此刻这一路是怎么被选出来的，"选"这个词在这里其实拆成三个独立的判决；
② OSD 那三行字里跟片源有关的每一格读的是什么判据；③ 这块设计真正发给面板的行/场消隐是多少纳秒，
以及为什么拷贝一帧的许可证只有那一段；④ 片源到达的节奏为什么是一个真杠杆，
59.5 Hz 这一档上"对节奏"与"错节奏"分别是什么后果，仓里哪一条是有凭据的、哪一条只是对照实验；
⑤ TMDS 的 10:1 串化在器件里是哪几个原语、`clk_pix5x` 那 250 MHz 到底买了什么；
⑥ 输出侧的时序声明今天停在什么状态，那两个 −3.48 / −4.90 ns 的"违例"为什么不是设计的失败。

---

## 1 前置知识

### 1.1 三路片源的物理形态完全不同，"片源"这个词盖住了三件事

| 片源 | 像素住在哪 | 谁写进去 | 提交凭证 | 搬进显示缓存的引擎 |
|---|---|---|---|---|
| ETH（网络） | DDR 两个乒乓 bank，`0x1000_0000` / `0x1008_0000` | PL 自己的收包链（占 HP0 写口） | `eth_commit` 脉冲 + `eth_ddr_base` | `axi_frame_writer_gated`（`u_row`） |
| SD（卡回放 / FILL 诊断帧） | DDR 第三个 bank `0x1010_0000` | PS 的 SD 控制器 DMA（不经过 PL） | `ps_publish` 翻转位（`gpio_o[18]`） | `axi_frame_writer64`（`u_aw`） |
| TEST（片内图卡） | 不落地，按坐标现算 | 没有写者 | 不需要 | 没有搬运这一步 |

三个要点：

1. **bank 地址分三份是因为仲裁管不到写侧**。`src/rtl/top/pl_video_top.v:13-16` 把这件事写死了：
   仲裁只决定"谁用 DDR→帧缓存这台搬运机"，而 SD 的 DMA 走 PS 的 HP0、根本不经过 PL，
   所以两路同时跑时"重叠"只能靠地址分开。`PS_BASE_ADDR = 32'h1010_0000`
   （`src/rtl/top/pl_video_top.v:16`）必须与固件的 `FRAME_ADDR` 逐字节相同
   （`src/ps/sd_play.c:35`），不改另一边的症状是"PS 片源在屏上不动"
   （`src/rtl/top/system_top.v:140-144`）。
2. **ETH 的两个 bank 间距是 512 KB 而一帧是 300 KB**：`BANK0/BANK1` 的算式在
   `src/rtl/eth/ddr_bank_commit.v:9-10`，帧字节数在 `src/rtl/eth/frame_reasm.v:9-11`
   （`512*300*2 = 307200`）。`src/rtl/top/system_top.v:140-141` 那句注释给的就是这个余量。
3. **图卡是唯一"不需要搬运"的片源**，因此它也是唯一在任何时刻都能出画的片源——
   这个性质决定了它是"两路都不活"时的兜底（见 3.5）。

### 1.2 "谁拥有屏幕"与"谁拥有总线"是两件事，且判据不同

设计里有三个彼此独立的判决，把它们混成一个"片源选择"是读这套代码最容易倒的地方：

* **模式**（人要哪一路 / 按键环走到哪一格）：`src/rtl/util/src_mode.v`，像素域，格雷码四态。
* **总线归属**（这台搬运机此刻归谁）：`src/rtl/util/src_arb.v`，axi 域，只看"活着 + 能不能安全换手"。
* **可见性**（屏上这一格该画缓存还是画图卡）：`src/rtl/top/pl_video_top.v:595` 的 `fb_vis`，
  像素域，模式 + 存在性判据的合取。

三者的输入分别是"人的意愿"、"总线的物理状态"、"这一路到底还有没有货"，
所以它们可以合法地不一致（例如锁 ETH 且当下没有流：模式=ETH、总线=PS 侧、屏上=缓存里冻结的最后一帧）。
这种不一致被刻意做成语义，代价是必须有一格说明——见 3.11 的 `no_sig`。

### 1.3 消隐窗口是"往显示缓存里写"的唯一许可证

显示读口每拍都在读同一块 BRAM，而搬运机每拍可能写它。两条硬约束：

1. **不能读写同拍同一块**：单口 BRAM 的读写冲突会把读出的值变成未定义，
   这是 `src/rtl/axi/axi_frame_writer_gated.v:4` 那句 "BRAM writes ONLY when allow" 的第一层理由。
2. **不能在半帧中途换内容**：一旦读指针（电子束）被写追上，屏上就会同时存在同一帧的新旧两半。
   `src/rtl/top/pl_video_top.v:392-396` 记的是 v6 的决定：整帧只在一个 V-blank 里搬完，
   于是"每个可见行期间缓存里都是一整帧完整的画"，v5 那条固定位置的黑线
   （搬运机在帧中途追上电子束）从结构上消失。

许可证的生成在 `src/rtl/video/frame_commit_lock.v`：像素域判"现在在消隐里"（`blank_safe`），
经 3 级同步 + 双位相与成 `allow_copy_axi`（`src/rtl/video/frame_commit_lock.v:45-76`），
再在 axi 域找上升沿起 copy（`:78-86`，v6 那条"从窗口开头而不是从 vsync 沿起"的修正：
`V_FP=3 + V_SYNC=6` 意味着 vsync 上升时 25 行窗口已经用掉 9 行，白丢三分之一预算）。

### 1.4 "活着"必须两级判据，因为量它的那把尺子自己会坏

`src/rtl/util/src_arb.v:10-14` 把这段板级实测写成了本模块的存在理由：
2026-09-23 断链时 RTL8211 不停供 RXC，而是把它拉到 ≈2.5 MHz，
于是 `link_monitor` 里那个以 RXC 为时基的 `stall_ms`（`src/rtl/eth/link_monitor.v:36` 的
`TC = CLK_HZ/1000`）以约 1/48 的速度爬，`stall_ms < 200` 这条判据会连着骗人十几秒，
仲裁死死占住 ETH、SD 接不回画面。因此这里必须"先确认量它的时钟还算准，再信那个读数"，
判据落在 `src/rtl/util/src_arb.v:51` 的 `eth_wanted = … (eth_live & eth_tb_ok)`，
而 `eth_tb_ok` 的来源是 `src/rtl/top/system_top.v:252-256`（快照的慢/停标志）。

### 1.5 TMDS 的字符结构：三条数据 + 一条钟，每字符 10 bit，三态

输出侧只有四个差分对（`src/constraints/rk_zynq7020.xdc:12-19`，全部 `IOSTANDARD TMDS_33`）：
一条钟 + 三条数据。每条数据线上流的是一串 10 bit 字符，字符有两种身份：

* **视频字符**：8 bit 像素经 8b/10b 变化最小化 + 游程平衡（`src/rtl/hdmi/tmds_encoder.v:20-75`）。
* **控制字符**：消隐期发四个固定码，由 `de=0` 那支给出（`src/rtl/hdmi/tmds_encoder.v:46-53`），
  四个码按 `{c1,c0}` 选：`1101010100`(0x354)、`0010101011`(0xAB)、`0101010100`(0x154)、
  `1010101011`(0x2AB)。本设计把 HS/VS 只放进**通道 0**（蓝）：
  `src/rtl/hdmi/rgb2dvi.v:21-24` 的 `.c0(hs), .c1(vs)`，另外两条数据道 `c0=c1=0`（`:28`、`:32`）。
  也就是说同步信息是随消隐期的控制字符一起被接收端读走的，不是额外线。
* **钟道**：永远发同一个字符 `10'b1111100000`（`src/rtl/hdmi/rgb2dvi.v:49-52`）。
  这里要按代码念：那个字面量的值是 992 = **0x3E0**，而它上面的注释写的是
  "constant 0x3FF pattern"（`src/rtl/hdmi/rgb2dvi.v:48`）——注释里的数与代码不符，
  代码给的形式与 DVI 钟字符（五个 1 后五个 0）一致。

字符速率 = 像素速率，位速率 = 10×字符速率。本档：50 Mchar/s ⇒ 500 Mbit/s/对，
字符周期 `Tcharacter = 20.000 ns`、位周期 2.000 ns（这组关系与它在规范里的位置见
`屏侧窗口取证` 第 1.1 节那张速率折算表，50 MHz 那一行加粗）。

### 1.6 10:1 串化为什么要 5× 而不是 10× 的钟

`OSERDESE2` 在 `DATA_RATE_OQ = "DDR"` 下每个快钟周期出 **2** bit（上升沿一个、下降沿一个）。
所以 10 bit 一个字符、快钟与分频钟之比是 `10 / 2 = 5`。
`src/rtl/clocks/clk_gen.v:21` 给 `CLKOUT0_DIVIDE_F (20.000)` = 50 MHz（VCO 1000 MHz），
`:24` 给 `CLKOUT1_DIVIDE (4)` = 250 MHz，两者之比正好 5 ⇒ `clk_pix5x` 就是 `clk_pix` 的 5 倍，
这正是 10 bit DDR 串化所需的比值（`src/rtl/hdmi/tmds_serializer.v:2` 那句
"DATA_WIDTH=10 requires DATA_RATE_OQ=DDR"说的是同一件事）。
反过来问"为什么不能只用 250 MHz 单端串行"：7 系列的 `OSERDESE2` 一只最多出 8 bit
（`DATA_WIDTH` 8），第 9/10 bit 必须由一只 SLAVE 通过 `SHIFTOUT1/2 → SHIFTIN1/2` 续进来
（`src/rtl/hdmi/tmds_serializer.v:26-27`、`:64-65`、`:73-74`）——这就是"级联"两个字的来由，
实现里 8 只 `OSERDESE2` = 4 条线 × 主+从（`build/utilization.rpt` 的 `OSERDESE2` 那一行给 8，
`OBUFDS` 给 4，`build/utilization.rpt:215`、`:221`）。

---

## 2 原理拆解（把数代进去）

### 2.1 设计真正发出去的面板节奏

参数正本：`src/rtl/video/video_timing_1024x600.v:17-22`（数值），
注释算式在 `:3-4`；发生器内部 `H_TOTAL/V_TOTAL` 由 `src/rtl/video/video_timing.v:26-27` 相加。

| 量 | 算式 | 数值 | 出处 |
|---|---|---|---|
| H_ACTIVE | — | 1024 | `src/rtl/video/video_timing_1024x600.v:18` |
| H 消隐 | 44 + 88 + 188 | 320 | 同上 |
| H_TOTAL | 1024 + 320 | 1344 | `src/rtl/video/video_timing_1024x600.v:3` |
| 一个显示行 | 1344 × 20 ns | 26.88 µs | `build/timing_summary.rpt:169`（`clkout0_1` 周期 20.000） |
| 行消隐占比 | 320/1344 | 23.81 % | 1344/1024 相减 |
| V_ACTIVE | — | 600 | `src/rtl/video/video_timing_1024x600.v:18` |
| V 消隐 | 3 + 6 + 16 | 25 行 | 同上 `:19-20` 那一行的加法（`:4`） |
| V_TOTAL | 600 + 25 | 625 | `src/rtl/video/video_timing_1024x600.v:4` |
| 一帧 | 1344 × 625 = 840 000 拍 | 16.800 ms | 两式相乘 |
| **场频** | 50 MHz ÷ 840 000 | **59.524 Hz** | `data/metrics.csv:3`（"场频 59.5 Hz，#153：不是 50 Hz"） |
| 一个场的消隐时间 | 25 × 1344 × 20 ns | 672 µs | 上面两行相乘 |
| HS 脉宽 | 88 拍 | 1.76 µs | `H_SYNC(88)`，`src/rtl/video/video_timing.v:49` |
| VS 脉宽 | 6 × 1344 拍 | 161.28 µs | `V_SYNC(6)`，`src/rtl/video/video_timing.v:50` |
| 极性 | HS 正、VS 负 | — | `src/rtl/video/video_timing_1024x600.v:21`（`H_POL=1`、`V_POL=0`） |

**每行消隐排在有效像素之后**这一点要从代码读，不能靠惯例猜：
`de_act = (h_cnt < H_ACTIVE)`（`src/rtl/video/video_timing.v:51`）说明 `h_cnt` 从 0 开始就是有效段，
`hs_act` 落在 `[H_ACTIVE+H_FP, H_ACTIVE+H_FP+H_SYNC)` = `[1068, 1156)`（`:49`），
于是每行的顺序是 **有效 1024 → 前肩 44 → 同步 88 → 后肩 188**。
垂直方向同理：`vs_act` 落在 `v_cnt ∈ [603, 609)`（`:50`），`V_POL=0` ⇒ `vs` 在这 6 行是**低**电平，
`vs` 的上升沿出现在 `v_cnt = 609`，即后肩第一行的开始；从那里到第一个有效像素还有 16 行
= 16 × 1344 = 21 504 个像素拍 = 430.08 µs。
这条距离有实感：图卡的帧计数与相位就在这个沿上更新
（`src/rtl/video/test_card.v:23-29`、`:66-74`），也就是"新的一帧的球心"早在电子束落到第一行之前
430 µs 就已经定下来了，所以整帧不会在中间出现"上半旧下半新"。

`frame_start` 的落点是被专门钉过的一件事：`src/rtl/video/video_timing.v:68` 把它与 `de_act` 相与，
因此它落在**第一个有效像素**那一拍而不是行首空歇里；
顶层那句"#167 的这一刀"整段（`src/rtl/top/pl_video_top.v:286-314`）之所以要把换角的翻转拍点
从 `frame_start` 挪到"最后一个不绕回的行的行尾"，前提就是这条落点定义。

### 2.2 拷贝预算：窗口 67 200 axi 拍，货是 38 400 个字

一段 V-blank 能给的搬运时间：

```
25 行 × 1344 像素拍 = 33 600 个像素拍 = 672 µs
像素拍 20 ns / axi 拍 10 ns ⇒ 33 600 × 2 = 67 200 个 axi 拍
```

`src/rtl/top/pl_video_top.v:446` 写的正是这个数（`VBLANK_AXI_CYC = 32'd67200`），
旁边的注释 `:442-443` 给的推导口径是"25 行 × 1344 像素 × 2 axi 拍"。
货：`512 × 300 = 153 600` 像素 ÷ 4 像素/字 = **38 400** 个 64 bit 字
（`src/rtl/axi/axi_frame_writer_gated.v:42-44`），按 INCR 16 拍/burst 分成 **2400** 个 burst（`:44`），
在途上限 4 个 burst（`:45-47`，`MAX_OUT = 3'd4`，注释的理由是"够盖住 HP0/DDR 读延迟并在这 25 行里维持约 1 拍/字"）。

于是三个可以直接检查的比值：

* 38 400 / 67 200 = **57.1 %**：即使 axi 域一拍一个字不停，也要吃掉窗口的一半多；
  也就是说**没有任何余量把两帧塞进同一个消隐窗口**。
* 一帧的字节数 307 200 B ÷ 672 µs = **457 MB/s** 是窗口内的平均需求，
  而 axi 域 8 B/10 ns 的上限是 800 MB/s ⇒ 靠"占空比 57 %"过关，不是靠带宽富余。
* `copy_cycles` 与 67 200 的比较是板载诊断：超过就粘滞置位 `copy_overrun`
  （`src/rtl/top/pl_video_top.v:447-452`），`led[0]` 从心跳闪成快闪
  （`src/rtl/top/pl_video_top.v:1038-1039`）。心跳/快闪的频率可以直接算：
  `hb` 是 `sys_clk` 上的 25 位自由计数器（`:1034-1037`），
  `hb[24]` 翻转周期 = 2²⁵ 拍 ⇒ 50 MHz ÷ 2²⁵ = **1.49 Hz**；
  `hb[22]` ⇒ 50 MHz ÷ 2²³ = **5.96 Hz**，与注释说的 1.5 Hz / 6 Hz 对上。

`VB_X_GUARD = 1279`（`src/rtl/top/pl_video_top.v:399`）是这一节里唯一需要"为什么是 65"的地方：
窗口在**最后一行**（`y == 624`）提前 64 个消隐像点关上（1344 − 65 = 1279，`:400-401`），
理由是 `allow_copy_axi` 从像素域过 `frame_commit_lock` 的 CDC 要晚约 5 个像素拍，
如果让许可期一直开到下一帧的第一个有效像素，那几拍延迟就会把写落到有效行上。
这是一个"用 64 拍的护栏换 5 拍的相位差"的取舍，写在这一行的注释里。

### 2.3 片源到达的节奏是真杠杆：这里的算术、仓里的凭据、以及不能外推的那一半

**(a) 结构上限：每帧最多换一次内容。** 两条提交链都只在帧的固定时刻消费一次凭证：

* PS 侧：`pub_consume = frame_start && src_use && !owner_eth_pix`
  （`src/rtl/top/pl_video_top.v:559`），且 `ps_publish` 的语义是**电平不是计数**——
  连着发两次、PL 只消费一次，第二次被合并（`src/rtl/util/ps_publish.v:6-8`、`:27-32`）。
* ETH 侧：起 copy 只在 `allow_rise || vsync_req` 那一拍（`src/rtl/video/frame_commit_lock.v:82-86`），
  而 `allow` 每帧只有一个上升沿。

结论：显示能吸收的新内容速率上限就是场频 **59.52 帧/秒**，与源能送多快无关。
`src/rtl/util/shown_rate.v:5-7` 记的就是这条上限带来的旧口径错误——屏上 `FPS:` 那格原来数显示场，
所以"片源是 30 fps、15 fps 还是根本没有片源都看不出来"，读数恒在 59/60。

**(b) 节奏不整除时发生什么。** 场频的精确值只有一个来源：一帧 840 000 拍 @ 50 MHz ⇒

```
场频 = 50 000 000 / 840 000 = 1250/21 Hz = 59.5238… Hz      // 与 data/metrics.csv:3 的 59.5 同一个数
每帧源被显示几场 = 场频 / f
```

| 源节奏 f | 场频/f（精确分数） | 拍频循环 | 每循环里"只给 1 场"的次数 |
|---|---|---|---|
| 29.7619 Hz = 1250/42 | 2（整数） | 不存在 | 0 |
| 30 Hz | 125/63 | 63 帧源 = 125 场 = **2.100 s** | 1（因为 2×63 − 125 = 1） |
| 15 Hz | 250/63 | 63 帧源 = 250 场 = **4.200 s** | 2 |

也就是说 30 fps 的源在这块面板上**不可能**逐帧等长显示：`125/63` 不是整数，
每 2.1 s 里有一帧只被显示一场而不是两场——这就是"错节奏"在数学上的具体形状。
反过来 29.7619 Hz 是唯一在 30 fps 附近能把比值钉成整数的节奏（正好 2 场/帧），
`开发台账` 那句 `59.52 / 2 = 29.76` 算的就是这一个点。
**上表那一列"每循环 1 次短显示"是算术结论，仓里没有对它的肉眼或仪器复现记录 ⇒ 现象级别是未量。**

**(c) 仓里真正被量过的两条。**

1. **#153 的两把尺子**（`开发台账`）：交付文档曾经把像素钟 50 MHz 念成"50 Hz 面板"，
   纠正后的算术是 `50e6 ÷ 1344 ÷ 625 = 59.52 Hz`；
   独立对照是板上 SD 播放实测 **29.8–30.0 fps**（`data/metrics.csv:12`，
   原始两行 `build/evidence/r87_boot_stat_drain.txt:4-5` 逐字 `29.956 / 29.815`），
   档案里给的说法是"×2 垂直展开 ⇒ 一帧源占两个显示场 ⇒ 59.52/2 = 29.76，与实测同向"，
   并补了一句"如果面板真跑 50 Hz，那里应该量到 ≈25 fps"。
   **按代码读，这条 /2 不是硬上限**：`cy = (y >> 1) < IMG_H ? (y >> 1) : (IMG_H-1)`
   （`src/rtl/top/pl_video_top.v:243`）在一个显示帧里就把 300 个源行全部扫了一遍，
   所以 30 fps 与 59.52 Hz 之间不整除（见 (b)），SD 的 29.8–30.0 是 **PS 自己的定时器喂出来的**
   （`src/ps/sd_play.c:846-854` 用 `COUNTS_PER_SECOND × fps_den / fps_num` 定间隔），
   不是被面板除以二。这一点要分开念：#153 那一处是"排除 50 Hz 面板"的量级对照，
   不是速率机制的描述。
2. **节奏被用作对照实验**（`board/acceptance.md:90` 的 E2 行）：一次"隔一段距离的两条白线"的报告，
   处置是**只改推流节奏**做对照——29.76 fps 一次、复推 25 fps 一次——现象不变，
   于是判为"切换瞬间的暂态，不记缺陷"。这条记录的两半都要念：
   片源节奏确实是一个可操作的杠杆（脚本侧 `--fps`/`--pace-mbps`，`src/host/README.md`），
   但**这一次它没有复出现象**，所以不能拿 E2 当"错节奏就会出花纹"的凭据。

**(d) 真正有机理、也有板载读数的那一条：拷贝超出消隐窗。**
`src/rtl/top/pl_video_top.v:442-444` 写的是后果的形状：
换帧跨了两个消隐期 ⇒ 屏上同一帧的新旧两半并存 ⇒ 运动物体被一条水平缝切开 + 拖影；
判据是 `copy_overrun` 粘滞位、出口是 `led[0]` 变 6 Hz 快闪（`:1038-1039`）。
这一条与"源节奏"的耦合是结构性的：`frame_commit_lock` 的看门狗
`WD_CYC = 2_000_000` axi 拍 = 20 ms（`src/rtl/video/frame_commit_lock.v:8`、`:88-98`）
一超时就把这帧判为不可信并 `copy_abort`，所以"帧来得太急/总线太挤"在屏上的表现是**掉帧**，
而不是花屏——`src/host/health_read.mjs` 读 lane28/29 能把 `c2`（搬运耗时）单独拎出来看
（端口口径在 `src/rtl/top/pl_video_top.v:69-72`，`frame_latency` 的分段定义在
`src/rtl/video/frame_latency.v:14-16`，`c3` 的分辨率是一个显示帧 ⇒ 报数带 ±1 帧）。

**(e) 已经量到的入流速率**（用来给上面的算术钉一个"源真的能跑多快"的地板）：
演示工况 30 fps / 限速 15 MB/s 下 600 帧 0 丢帧 0 坏帧、实测 30.007 fps（`data/metrics.csv:22`）；
300 s 长跑 9000 帧、29.99 fps、帧间隔平均 33.34 ms（`:23`）；
不限速推到目标 120 fps 仍未丢字（`:24`，`≥116.7 fps`，明确写"不给 PL 能扛多少 fps 的数字"）；
第 116 批那一轮是 512×300@60 不限速 ≈ 147 Mbps、3001 帧 / 50 s
（`report/measurements.md:64`，随包 console 件 `build/evidence/r118_board/bitcycle_console.txt`）。
60 fps 已经**超过**场频 59.524 ⇒ 按 (a) 的结构上限，多出来的那部分不是"更流畅"而是被合并/丢弃，
这一句是从 (a) 推的，仓里没有专门量过 60 fps 输入时的屏上读数（未量）。

### 2.4 图卡的几何：把参数全代成数

`src/rtl/video/test_card.v` 的分区与波形参数都是 `H_ACTIVE/V_ACTIVE` 的函数，
顶层传的是 `#(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H))` = 512×300（`src/rtl/top/pl_video_top.v:759`）。

| 量 | 算式（源码行） | 512×300 下的值 |
|---|---|---|
| `Y_FIELD` 主画面下沿 | `V − V/12 − V/12`（`:32`） | 250 |
| `Y_BAND` 细色带下沿 | `V − V/12`（`:33`） | 275 |
| `BW` 格宽 | `H/8`（`:34`） | 64 |
| `RAD` 球半径 | `V/14` 与 12 取大（`:38`） | 21 |
| `GLO` 光晕外沿 | `RAD + RAD/2`（`:39`） | 31 |
| `AX` 横向步长 | `(H − 2·GLO)/31`（`:46`） | 14 |
| `AY` 纵向步长 | `(Y_FIELD − 2·GLO)/49`（`:47`） | 3 |
| `MX` / `MY` 居中偏移 | `GLO + 余量/2`（`:48-49`） | 39 / 51 |
| `SW` 扫光带半宽 | `H/24` 与 6 取大（`:129`） | 21 |
| 角括号臂长/臂宽 | `H/32`、`V/75`（`:123`） | 16 / 4 |

代入之后能验的三件事：

1. **球完整留在主画面里**：横向 `MX + 31·AX = 39 + 434 = 473`，加 `GLO` = 504 ≤ 512 ✓；
   纵向 `MY + 49·AY = 51 + 147 = 198`，加 `GLO` = 229 ≤ 250 ✓。
   这正是 `:40-45` 那三条约束里第一条的落地形式（第一版的 `(H−2·GLO+30)/31` 会把球推过右边界）。
2. **底部有一条干净带**：纵向可活动区的下沿 229 与 `Y_FIELD` = 250 之间留 21 行
   —— 这一段里没有球、没有光晕、没有扫光（扫光带只在 x 方向移动，`band_c = MX + tri47(phs)·AX`
   落在 39…361，`:130`），台架量背景渐变就取在这一带（`:42-43` 写的是这条理由）。
3. **钳位必须写成"先比较再取"**：`:46-47` 的 `AX/AY` 用条件式而不是 `(H − 2·GLO) / 31` 直接减，
   因为台架用 256×150 的小几何（`sim/tb_v81_test_card.v` 的 `H=256, V=150`），
   那时减法会变负，12 bit 无符号回绕成一个巨大步长；
   注释 `:44-45` 特别点出"`> 0` 那种写法挡不住回绕"。

**相位与重复周期**：三个计数器 `phx/phy/phs` 的周期是 64 / 99 / 47（`:66-74`），两两互质。
于是球心 `(cx0, cy0)` 的轨迹周期 = lcm(64, 99) = **6336 帧** ÷ 59.524 = **106.4 s**；
加上扫光带的 47 周期，整卡内容周期 = 64×99×47 = **297 792 帧** ≈ **83.4 min**。
`:63` 那句"合成轨迹要几千帧才重复一次"讲的是这个量，但按参数算少了一个数量级——
念的时候以乘积为准。`frame` 是 16 bit（`:21`），屏上只印低 8 位（`:140` 的 `frame[7-ci]`）⇒
**读图口径是 256 帧一圈**，跨圈的连续变化看不出来源（这条在
`背景与创新` 有同样的表述）。

**"拖影塌进球心"为什么成立**：三个拖影中心是上一、二、三帧的球心（`:104-113` 的寄存器链，
在场边界搬一次），半径分别是 `RAD−RAD/8 = 19`、`RAD−RAD/4 = 16`、`RAD−RAD/2 = 11`（`:118-120`）。
重复帧时 `cx1..cx3 == cx0` ⇒ 三个小圆全部落在 `ball0`（半径 21，纯白）的圆内，
而优先级链是 ball3→ball2→ball1→ball0 逐层覆盖（`:171-174`）⇒ 拖影在屏上整体消失。
反过来，"拖影可见"就等价于"每帧真的换了新内容"，这就是这张卡存在的理由
（`:2-4` 的 ①，以及 `sim/tb_v81_test_card.v` 文件头第 ③ 条：拖影必须比光晕亮且不是白）。

**为什么一律给绝对色**：`:163-174` 两段注释记的是两次改口。
先是不给绝对色的光晕蓝通道 0x5C 比背景 0x60 还暗（看着是一圈深色方框）；
然后是五层相加（背景 + 光晕两级 + 拖影三级）在 8 bit 上加溢出回绕，
台架 T13 实测到"拖影比背景还暗"，屏上是黑洞。最终形式是**阶梯式绝对色**，
从外到内 `glow0 → glow1 → ball3 → ball2 → ball1 → ball0` 一路变亮，球心纯白。

**与 `color_bar` 的时序契约必须逐位一致**：`de` 有效时打一拍（`:196-199`），
顶层的 `PROC_LAT` 与延迟抽头按 1 拍配好（`:6-7` 的第三条纪律）；
`color_bar` 的对应分支在 `de=0` 时把输出清成 0（`src/rtl/video/color_bar.v:65-68`），
而 `test_card` 保持（`src/rtl/video/test_card.v:196-199` 没有 else 支）——
这一处差异不改变有效行的行为（消隐期的输出没人采），但它说明"逐位一致"指的是
**有效段的一拍延迟契约**，不是两个模块的每一支都相同。
`color_bar` 自己声明的处境也值得读一眼：它不在综合树里（`src/rtl` 内无人例化），
但仍被台架当"静止对照"用（`src/rtl/video/color_bar.v:3-6`，指向
`src/rtl/top/pl_video_top.v:752` 那句"位置原来是静止彩条"）。

### 2.5 输出侧规范窗口数与本档的对应

这一节只做"数与量纲"的映射，判断在 3.13。

| 规范量（源端 TP1） | 表达式 | 本档（50 MHz） | 出处 |
|---|---|---|---|
| 钟↔数据互对偏斜 max | 0.20 × `Tcharacter` | **4.000 ns** | `屏侧窗口取证` 表行 #1（HDMI 1.4 Table 4-24 / 1.3 Table 4-16 / 1.1 Table 4-13 三版一致） |
| P/N 对内偏斜 max | 0.15 × `Tbit`，`Tbit = Tchar/10` | **0.300 ns** | 同上 #2 |
| 上升/下降 | 75 ps ≤ t ≤ 0.4 `Tbit` | 75 ps…0.800 ns | 同上 #3 |
| 钟抖动 max | 0.25 × `Tbit` | 0.500 ns（相对 4 MHz −3 dB 理想恢复钟） | 同上 #4、#11 |
| 钟占空比 | 40 / 50 / 60 % | 与 SDC 无关 | 同上 #5 |

`src/constraints/r119_hdmi_source_window.xdc:19-27` 把前两行代成 4.000/0.300，
并且明确"半窗 4.000 是从 `0.20 × 20.000` 算出来的，不是抄来的第三个数"；
这两处一致性由只读尺子 `build/r119_window_check.mjs` 判（判据 W1「半窗可推导」，
件 `build/evidence/r119_window_check.txt` 第 1 行 `期望=0.20×20.000ns=4ns 实读=[4] PASS`）。

---

## 3 代码逐段分析

### 3.1 模式寄存器：`src_mode`

编码是格雷码环 `00 AUTO → 01 ETH → 11 SD → 10 TEST`（`src/rtl/util/src_mode.v:24`）。
三段设计决定：

1. **下一状态按位写** `{ring[0], ~ring[1]}`（`:89`）。理由在 `:20-21`：
   下游 `pl_video_top` 会用 `ms0 <= mode` 这对同步器去跨到 axi 域，
   "每一位只依赖一个源触发器"才安全；写成 `if (mode == …)` 的比较式会被综合认成 FSM
   并重编为 one-hot，格雷码的意义在实现层被抹掉。
2. **离开 AUTO 时按 `eth_now` 挑目标**（`:88`，配合 `:22-23`）：AUTO 下屏幕本来就是 ETH，
   若固定走一格会是个"看不出变化"的空动作；现在两个去向都只翻 1 位。
3. **命令覆盖的采样时刻**：`ov_tog` 与 `ov_code` 都来自 axi 域，
   码走一条**与翻转位等长**的 3 级延迟线 `{ovc2,ovc1,ovc0}`，在沿到链尾那一刻取延迟线尾部
   （`:33`、`:61`、`:77`）。`:29-32` 讲清了为什么不能直接采 `ov_code`：
   PS 是两笔相邻的 32 位写（先码后沿，见 `src/ps/main.c:508-515`），只差几十 ns，
   而沿要被 3 级链认下来才是采样时刻——中间那段时间里 `ov_code` 早就是新值了，
   采到的其实是"沿之后写的码"。**也不许**把 2 位码各自打 3 拍再拼（`:14`，会读到半新一半旧）。
4. 复位纪律：链的复位值必须与源头一致（`key_long` 的 `tog` 复位为 0，链也复位 `3'b000`，
   `:49-50`），否则"上电"本身就是一次边沿 ⇒ 一块没被按过的板子白走一步 AUTO→锁 ETH。
   这段是 ISSUES #49 的根，`src/rtl/top/pl_video_top.v:153-155` 有对应的顶层叙述。
   `settle` 计数（`:36`、`:62-66`）负责复位后的灌满期，让 `prev/oprev` 跟住链尾，
   别把"复位前那次命令写"当事件收下。
5. `mode` **必须是一个触发器**而不是 `ov_en ? ov_act : ring` 的组合式（`:40-45`、`:98-101`），
   否则等于在同步器前面挂一级 LUT，`report_cdc` 会立刻把整对 `clkout0_1→clk_fpga_0` 提成
   Critical（实测 27 个端点 / 2 个 unsafe，`:42-43`）。

按键语义的另一半在 `src/rtl/util/key_long.v`：`HOLD_CYC = 30_000_000` @50 MHz = 0.6 s、
`ARM_CYC` = 0.2 s（`:9-10`，顶层例化在 `src/rtl/top/pl_video_top.v:148-150`）；
短按改到**松手时**发（`:31-34`，ISSUES #55 的处置：以前在按下沿发 ⇒ 每次长按必先进 1°），
`holding` 那一位驱动 LED 告诉操作者"还在计"（`:17-18`，没有反馈时人只能重按，
而重按在环里会多走一格到 TEST）。

### 3.2 四态模式 → 仲裁的两位 `sel`：一处适配器

`src/rtl/top/pl_video_top.v:165-171`：模式先过 3 级 `ms0/ms1/ms2` 进 axi 域（复位值 `M_AUTO`），
再一行翻译成 `arb_sel = (ms2==M_ETH) ? 1 : (ms2==M_SD) ? 2 : 0`。
这行存在的原因是两套编码**不同**：`src_mode` 里 SD=3、TEST=2（`src/rtl/util/src_mode.v:24`），
`src_arb` 里 `sel=2` 才是"强制看 fb（=SD 回放）"（`src/rtl/util/src_arb.v:26-28`）。
`:27-28` 那句警告写的就是这件事：**TEST 不参与仲裁**（保持 AUTO），
因为"图卡只是显示什么，不是谁在搬"（`src/rtl/top/pl_video_top.v:170` 的注释同样）。

### 3.3 仲裁：换手只发生在两个引擎都空闲那一拍

`src/rtl/util/src_arb.v` 一共 79 行，核心只有四行，但每一行都有反对意见被写下来：

```
force_eth / force_ps  ← 手动锁（只改"谁想要总线"）
eth_wanted = force_eth ? 1 : force_ps ? 0 : (eth_live & eth_tb_ok)
both_idle  = ~row_busy & ~fill_busy
if (both_idle) begin why_ps <= {force_ps, ~eth_live, ~eth_tb_ok}; … end
```

* `:41-45` 明确拒绝"在输出上加一个 mux"的写法：那会在一次拷贝中途把选择位翻掉，
  留下半开的 AXI 读突发——正是本模块要消灭的老毛病（`:4-8` 记录了老写法
  `eth_mode = 3FF(|s_pkts)` 的两个问题：ARP 就触发、拔线不回 0）。
* `:62-64` 的静默计数 `quiet` 只服务"往 PS 让位"一个方向，ETH 一活就清零（回抢不等）；
  门限 `T_OFF_CYC = 2_000_000` 在 100 MHz 域 = **20 ms**（`src/rtl/top/pl_video_top.v:421`），
  与第一级滞回 `stall_ms > 200 ms`（`src/rtl/eth/link_monitor.v:13` 的 `LIVE_MS`）串联。
* `why_ps` 与 `owner_eth` 必须在**同一个决定点**一起写（`:68-73`）。
  挂在无条件那一支会导致"拷贝期间主人被冻住、但输入翻了 → 屏上/上位机读到的原因跟着变，
  而主人一次都没换"。台架 `sim/tb_src_arb_why.v` 的 W5 钉这件事、W7 是它的反配对。
* 复位值 `why_ps = 3'b011`（`:59`，"没有流 + 时基还没验"）而不是 000（"一切正常、是被人钉住的"），
  理由是刚上电时最不该撒后面那个谎。

顶层把仲裁的可见性一次做全：`dbg_src` 的位序在 `src/rtl/top/pl_video_top.v:66-68` 给出、
唯一驱动是 `:603` 那一行 `assign`，`system_top` 把它映到健康 GPIO 的 lane30
（`src/rtl/top/system_top.v:239`）。为什么值得做：`owner_eth` 决定屏幕归谁，
以前只有眼睛看屏幕才知道，"停流不交回"这类板级红夜里既看不见也没法记账（`:62-64`）。

### 3.4 片源存在性：一条看门狗与 PS 的心跳

`src/rtl/util/src_life.v` 是把"永久冻在最后一帧"这个故障类别消掉的那一刀
（`:3-7` 记的是原来的写法：`have_src = eth_link_pix | ps_src_seen`，两个位都只置不清）。

```
HB_CYCLES = (CLK_HZ/1000) * HB_TIMEOUT_MS        // :31，先除后乘
HB_FRAMES = HB_CYCLES / 840_000 + 1              // :32，一帧 = 1344×625
```

代入 `CLK_HZ = 50_000_000`、`HB_TIMEOUT_MS = 500`（顶层例化
`src/rtl/top/pl_video_top.v:586-592`）：
`(50e6/1000)*500 = 25 000 000` 拍 = 500 ms；`25 000 000/840 000 = 29.76` ⇒ **`HB_FRAMES = 30`**。
`:29-30` 特别写了"先除后乘"：`500 × 50e6 = 2.5e10` 在 32 位 integer 里回绕，
500 ms 会变成一帧——第一版就是共用了那个回绕的乘积，所以台架 `sim/tb_v102_src_life.v`
的期望值写成手算字面量（`:12-14`，同一算式的两处独立记录见 `:37` 的 29.76）。

`ps_no_pub` 的复位值是 **1**（`:26`、`:40`）：上电时谁都没发过帧，屏上就该是图卡。
心跳吃 `ps_publish` 同步出来的 `new_tog`（`src/rtl/top/pl_video_top.v:561-566`），
因此**零新增异步配对**——`:55` 写的是这条判据："cdc.rpt 不该因为 #94 多出任何东西，多出就是接错了"。
PS 侧的配合是 100 ms 一次的重发（`src/ps/main.c:260-269`），
100 ms : 500 ms = 1 : 5 由 `sim/tb_v102_src_life.v` 的 S12 钉住（`:257-258` 的理由段）。
`mode_eth` 不参与看门狗（`src/rtl/util/src_life.v:51-57`）：
锁网络时"停在最后一帧"是语义而不是故障，代价是应用侧必须持续声明"这一屏还要留着"（重发同一帧）。

### 3.5 那第五级 mux：`fb_vis` 与 `pix_raw`

```
fb_vis = (mode_card ? 0 : (mode_eth | mode_ps) ? 1 : src_use) && have_src   // :595
pix_raw = oob_fb_d1 ? 16'h0000 : (fb_vis ? fb_out : bar_d2)                  // :772
```

`src_use` 是 `gpio_o[16]` 的像素域同步值（`:471-476`）——AUTO 态下"画缓存还是画图卡"
交回给 PS 的 `SRC0/SRC1` 命令（`:593-594`）；`oob_fb_d1` 是 mapper 的越界标签跟着像素
一路带到这一拍的（`:731`、`u_bilin` 的 `.oob_out`，`:749`）⇒ 画面外的格子给黑而不是给图卡。
图卡与缓存两个抽头在此**共用同一份源坐标** `(sx, sy)`：
`u_bar` 的 `.x(sx), .y(sy), .de(de_d[2])`（`:759-762`），
`:752-756` 记的是这次统一删掉的旧遗产（`u_bar_l` 吃 `cx/cy`、`u_bar_r` 吃 mapper 输出的"两屏各画一整幅"）。

### 3.6 ETH 提交链：验收门 → 换页 → 消隐许可 → 搬运

按数据的顺序走：

1. **验收门**（`src/rtl/eth/frame_reasm.v:2-4`）：一帧只有当**每一条源行都被写过**才提交。
   文件头给的理由很具体——缺行会留下旧像素/零像素，
   "于是冻结帧在缩放时看起来是几条会动的黑纹"。字节门是 `cov == FRAME_BYTES`，
   而 `FRAME_BYTES` 现在由 `src/rtl/eth/eth_udp_video_top.v:235` 显式传
   `IMG_W*IMG_H*2`；`开发台账`（#158）记的是这行以前没传、
   现值靠 512×300 **偶然**等于默认 307200 的那段。
2. **换页与提交**（`src/rtl/eth/ddr_bank_commit.v`）：`frame_done` 是 125 MHz 域的一拍，
   先转翻转位再过 3 级（`:37-47`）；提交条件不止看打包器 `saver_idle`，
   还要看 `tail_drained`（CDC 空 + 地址已发 + 两级读流水都空，`:49-51`）。
   `:6-7` 给的是这条 `TAIL_GUARD` 的病：旧判据对 8192 深的 CDC 完全不可见 ⇒
   帧尾几个 16 bit 被写进**下一帧**的 bank，板上症状是"HDMI 右下角少 2 像素"。
3. **消隐许可 + 看门狗 + abort**（`src/rtl/video/frame_commit_lock.v`）：
   像素域把 `disp_quiet` 打 3 级、双位相与成 `allow_copy_axi`（`:71-76`），
   `vs` 沿另外转成翻转位跨过去（`:59-69`），起搬在 `allow_rise`（`:82-86`）。
   20 ms 无进展 → `copy_abort` 一拍 + `abort_tgl` 翻转（`:88-109`）。
   `:100-105` 这段值得抄进任何"跨域清单"：`copy_abort` 在 axi 域只有一拍（10 ns），
   而两路时钟**同源同相**（同一 MMCM 的 100/50 MHz），沿正好压在像素域的采样沿上 ⇒
   **电平型 3 级同步修不好它**（实测与裸采逐相位一模一样），
   正确形式是翻转式脉冲同步器；证据是相位扫描台架 `sim/tb_v79_abort_toggle.v`
   （错开 4 ns 时裸采 0/3、翻转式 3/3）。顶层照此消费（`src/rtl/top/pl_video_top.v:484-489`）。
   `frame_ready_pix` 从"只置不清的电平"改成"恰好一拍"是 #171（`src/rtl/video/frame_commit_lock.v:136-143`），
   改之前顶层的 `else if (copy_abort_pix)` 那一支根本不可达。
4. **搬运机**（`src/rtl/axi/axi_frame_writer_gated.v`）：三条写路径
   `do_direct`（R 拍直接落 BRAM，`skid` 空时）/ `do_skid`（进缓冲）/ `sk_drain`（排空缓冲），
   `:86-89` 是这三条的谓词。#170 那一刀（`:69-79`、`:115-122`）讲的是
   abort 之后必须**排空在途 burst**：AXI 不许 master 撤回已经举起的 `rvalid`，
   那些拍会等在下一帧门口，下一帧收下的头几拍其实是上一帧的数据
   （整帧平移 + 帧尾越界写，台架 `sim/tb_writer_abort.v` 的 B3/B5/B6）。
   `skid` 那两片数组必须写成带 `(* ram_style = "distributed" *)` 的形式（`:50-54`），
   否则同一个数组写在带异步复位的控制块里 ⇒ 综合报 `Synth 8-4767`、
   64×83 bit 全掉进触发器（约占当时整机剩余寄存器的一半）。

### 3.7 PS 提交链：零拷贝 DMA + 一次翻转

`src/ps/sd_play.c:12-18` 那段协议说明是这条链的规范文本：
SD 控制器 DMA **直接写 PL 要读的那块 DDR**（`FRAME_ADDR = 0x10100000`，`:35`），
写完只翻一次 GPIO bit18 ⇒ PS 不需要 300 KB 的 memcpy、也不需要第二块 DDR 双缓冲。
"复制一次"而不是"每帧都复制"是关键：前者让 PS 有整个帧周期可以安全覆写 DDR，
后者会在 PS 写到一半时把半张新图 + 半张旧图搬上屏（撕裂）。

PL 侧的消费点与生产者点分别在这里：

* `pub_consume` 在帧首取一次（`src/rtl/top/pl_video_top.v:559`）；取到了就翻 `fs_tog`（`:568-572`），
  `fs_tog` 再过 3 级异拍还原成 axi 域的一拍 `ps_frame_start`（`:573-578`）——
  脉冲不直接跨域，这是 #36 那一课的第二次应用。
* 搬运机 `axi_frame_writer64` 的 `enable` 与 `frame_start` 都被 `eth_mode ? 1'b0 : …` 门住
  （`src/rtl/top/pl_video_top.v:692-707`）：ETH 拥有总线时这台机器整体静默，
  而且 `pub_consume` 那一支把 pend 留着等轮到 PS 再消费（`:512-516` 的理由段）。
* 它与 `u_row` 的区别值得对比：`u_row` 逐行有 `allow` 门（消隐外一格都不写），
  而 `u_aw` **没有** `allow` 端口，它只在 `ps_frame_start` 起、把整帧连续写完
  （`src/rtl/axi/axi_frame_writer64.v:60-111`，逐行 `BURSTS_ROW` 个 burst 接着发）。
  这一处的不对称说明 PS 片源的"不撕裂"完全依赖**每帧只起一次**这个握手，
  而不是依赖消隐窗；读侧靠什么挡住写？见 3.9 的 `fb_pix_hold`。

### 3.8 一台搬运机、一个 AXI 读口、一个 BRAM 写口

`src/rtl/top/pl_video_top.v:709-718` 是那 6 + 3 个 mux（`araddr/arlen/arsize/arburst/arvalid/rready`
与 `wr_en/wr_addr/wr_data`）。`:426-427` 的注释说明这 14 处 mux 在 #47 的修复中一个字都没动——
变的只是判据从"收过包"换成"仲裁过的 owner"。
`m_axi_arready / rvalid / rdata / rlast` 也带 `eth_mode ? … : 1'b0` 的门（`:465`、`:467`、`:703-705`），
所以两个引擎在总线上是**互斥可见**的，不是"都挂着看谁抢赢"。

### 3.9 显示缓存本体与它的时间标签

* 结构：`frame_buffer_w64` 写侧 64 bit（4 像素）、读侧 16 bit 随机 + 原始 64 bit 字
  （`src/rtl/video/frame_buffer_w64.v:1-3`）。
* **必须按 2 的幂拆两块**：`:4-7` 给的是实测——
  直接声明 38 400 深的数组，BRAM 推断会把非 2 的幂向上填到 2¹⁶ ⇒ 512×300 的缓存吃掉 **128** 个 RAMB36
  （整片才 140 个），拆成 32768 + 8192 两块实测 **80** 个；对照实验的记录也在那几行里。
  拆分的算术在 `:32-35`（`bitsof()` 取不超过 n 的最大 2 的幂位宽），
  读侧"两块每拍都读一次、真正选择由 `sel_hi` 完成"（`:51-68`）⇒ 读延迟仍是 1 拍，
  越界一侧地址用掩码夹住不产生 X，越界像素仍回黑（`:67`、`:80`）。
* 地址算式在 `src/rtl/process/bilin/fb_bilin.v:34`、`:42-46`：
  `pxl = sy*IMG_W + sx`，`w_a = pxl[18:2]` 是字下标、`lane = pxl[1:0]` 选字内哪一路，
  `w_b = w_a + ROW_WORDS`（一行 128 个字）是纵向抽头。
  `IMG_W` 是 2 的幂 ⇒ `sy*IMG_W` 综合成连线；是 4 的倍数 ⇒ 整除（`:34` 的注释）。
* 有效行期间的读改写安全由一层"保持上一个像素"处理：
  `src/rtl/top/pl_video_top.v:540-553`——`allow_copy` 同步两拍后为真的那段时间里，
  只要 `de` 不在有效段就输出 `fb_pix_hold`，有效段直接输出 `fb_rd`。
  `:540-541` 那句 "Active video always shows live BRAM" 说的是同一个意思。

### 3.10 时序发生器的逐拍关系

`src/rtl/video/video_timing.v:32-47` 是一个自由运行的 `h_cnt/v_cnt` 计数器，
`:49-51` 用组合比较得出 `hs_act/vs_act/de_act`，`:53-70` 再统一打一拍输出。
逐拍关系里有三处容易读错：

1. `x/y/de/hs/vs/frame_start/frame_done` **都是同一拍的寄存输出**（都从同一个 `h_cnt/v_cnt` 打出来），
   所以 `de=1 且 x=k` 就是"第 k 列正在被画"，不存在 `de` 与坐标差一拍的问题。
   顶层与图卡都建立在这条上（`src/rtl/video/test_card.v:196-199` 用 `de` 门住输出）。
2. `frame_start <= de_act && h_cnt==0 && v_cnt==0`（`:68`）：
   由于三个信号同步打拍，`frame_start` 与 `de=1, x=0, y=0` 出现在**同一拍**。
3. `frame_done <= (h_cnt==H_TOTAL-1) && (v_cnt==V_TOTAL-1)`（`:69`）：
   它落在最后一个消隐拍**之后**的一拍，也就是新的 `frame_start` 那一拍之前的 840 000 周期里
   只出现一次；顶层不用它做搬运判决（搬运用的是 `frame_commit_lock` 里的窗口与沿）。

发生器只有 12 bit 的 `x/y` ⇒ 上限 4095，本档 1344/625 都在范围内（`:18-19`、`:29-30`）。

### 3.11 OSD 上跟片源有关的那几格

五行字的正本在 `src/rtl/video/osd_overlay.v:256-329`，与本章有关的三处：

* **L0 的 `SRC:`**：`put_src(src_eff, mode)`（任务体 `:243-254`），
  `src_eff = {fb_vis, owner_eth_pix}`（`src/rtl/top/pl_video_top.v:1014`）。
  编码：`11 → "ETH"`、`10 → "SD"`、其余 → `"TEST"`，`mode != AUTO` 时紧跟一个 `*`。
  `:239` 那句是这一格的定义——**画的是屏幕上真的这一路，意愿只用尾部星号**。
  词表只有这三个词的理由在 `:240`（CARD 在板上同时被念作"SD 卡"与"测试图卡"，PS 既指处理器也指片内自绘）。
  一个实现层的坑记在 `:241-242`：`se/md` 必须是**任务入参**而不在任务体里直接读，
  因为 Verilog-2001 的 `always @(*)` 不把任务体内读的信号列进敏感表，
  直接读会导致"切了片源但这个块不会被叫醒，屏上永远留着旧名字"。
* **L0 的 `FPS:`**：换成数"写进屏的新帧"是 #128（`src/rtl/util/shown_rate.v:2-14`）。
  三个片源各用自己的凭据、且**只用顶层现成的线**：ETH = `frame_ready && eth_link_pix`、
  PS/SD = `pub_consume && pub_pend`、图卡 = `frame_start`；
  顶层例化那一处的三根输入就是这三条（`src/rtl/top/pl_video_top.v:941-950`）。
  两个细节：`eth_pend` 那一位是"帧到了"与"帧上屏"的区分（`src/rtl/util/shown_rate.v:11-12`），
  窗口 `WIN_LAST = 49_999_999` @50 MHz = 正好 1.000 s（`:19-21`），
  以及 `frame_start` 与 `eth_new` 同拍时按"仍然欠一帧"算（`:16-17`，优先级写反会让读数在满速时偏高）。
  OSD 侧还有一层钳位：`fps_v = (fps > 99) ? 99 : fps`（`src/rtl/video/osd_overlay.v:129`）。
* **L4 的"ETH IS NO SIGNAL"**：`no_sig = (mode_eth | owner_eth_pix) & ~eth_live_pix`
  （`src/rtl/top/pl_video_top.v:510`），判据用**活**的 `eth_live` 而不是
  "自配置以来只置不清"的 `eth_link`（`:498-507` 把这条区别写完了）；
  AUTO 态不判，因为那时仲裁已经把屏交回 PS/图卡，屏上画的不是冻结帧。
  这行的存在理由写在 `src/rtl/video/osd_overlay.v:46-47`：
  冻住的最后一帧没有任何说法就会看上去像"板子卡死"。

`src/rtl/top/pl_video_top.v:956-961` 那段"撤掉一条没人读的跨域路"的处置也归本章：
链路断了在屏上有三个长相（`SRC:` 退回 TEST、`FPS:` 掉到 0、`Latency:` 变 `--`），
所以不需要第三份读数；功能没有删，lane0~lane9 在 axi 域由脚本机器可读。

### 3.12 TMDS 编码链：编码器 → 通道映射 → 10:1 串化 → 差分缓冲

**`src/rtl/hdmi/tmds_encoder.v`（每通道一份，共 3 份）**

* 变化最小化：`q_m[0] = din[0]`，其余位按异或/异或取反链，选择规则
  `use_xnor = (n1 > 4) || (n1 == 4 && din[0] == 0)`（`:20-36`），
  `q_m[8]` 是那一位"是否取反"的标志（XOR 支给 1、XNOR 支给 0）。
* 游程平衡：`cnt` 是 signed 6 bit 的累计不平衡度（`:38`），
  三个分支（`:55-73`）按 `cnt` 与 `n1q/n0q` 的符号决定第 9 位发 1 还是 0、
  第 7..0 位发 `q_m` 还是它的反；两个"补偿"分支的计数式里各带一个 `±2`
  （`{2'b00, q_m[8], 1'b0}`），这就是标准算法里"用第 9/10 位把不平衡拉回来"的那一步。
* 消隐期清 `cnt` 并按 `{c1,c0}` 发四个控制码之一（`:46-53`），复位值也是控制码
  `10'b1101010100`（`:44`）。
* 输出是一个寄存的 10 bit（`dout`）⇒ 它必须在一整个 `clk_pix` 周期里稳定，
  因为串化器在 `CLKDIV` 的两个边沿分别取 D1..D4 与 D5..D8（这一级级联形式见
  `src/rtl/hdmi/tmds_serializer.v:2-3` 的 UG471 指路）。

**`src/rtl/hdmi/rgb2dvi.v`（通道映射）**
`channel0 = Blue + HS/VS`、`channel1 = Green`、`channel2 = Red`（`:21-33`），
钟道是常值字符（`:48-52`）。四个 `tmds_serializer` 分别驱动
`tmds_data_p[0..2]` 与 `tmds_clk_p`（`:35-46`）。

**`src/rtl/hdmi/tmds_serializer.v`（10:1）**
主片吃 `din[0..7]`（`:33-40`）、从片吃 `din[8..9]` 放到它的 D3/D4（`:73-74`），
从片的 `SHIFTOUT1/2` 回接主片的 `SHIFTIN1/2`（`:26-27`、`:64-65`）；
两片都用 `CLK = clk_pix5x`、`CLKDIV = clk_pix`（`:31-32`、`:69-70`）；
`OCE = 1'b1`、`T1..T4 = 0` 且 `TCE = 0` ⇒ 输出三态恒为驱动（`:41`、`:45-50`），
最后一只 `OBUFDS` 出 P/N（`:91`）。`RST(~rst_n)` 是**两个**片都接（`:42`、`:80`），
而 `rst_n` 用的是像素域的 `rst_pix_n = sys_rst_n & locked`
（`src/rtl/top/pl_video_top.v:132`）⇒ MMCM 没锁定的那段时间串行器是复位态。

**位序**（从代码而不是从规范推）：`din[0]` 进主片 D1 ⇒ 它是这四个差分对上是**第一个**出现的 bit，
`din[9]` 最后。而编码器里 `dout[0]` 由 `q_m[0] = din[0]` 得来 ⇒ 像素的最低有效位先出脚。
`report/study/_notes/display_chain.md` 第 207 行给的正是这条链路的速率式
（CLK 250 MHz × DDR 2 bit = 500 Mbit/s = 50 MHz × 10 ⇒ 字符率 = 像素率）。

顶层的接入只有一个消费者：`src/rtl/top/pl_video_top.v:1026-1032`，
喂进去的就是 OSD 之后那一路 RGB888 + 同步，与"面板看到的内容"是同一份。

### 3.13 输出侧的时序声明：两次 load、一次量对方向

**(a) 今天的默认状态。** 构建默认只加载两份约束（正本在 `src/constraints/`：
`src/constraints/rk_zynq7020.xdc` 与只在实现阶段生效的
`src/constraints/clock_groups_impl.xdc`，加载动作在 `build/tcl/build_system_axigpio.tcl:31-37`）。
TMDS 那 8 个脚只有 `PACKAGE_PIN` + `IOSTANDARD TMDS_33`（`src/constraints/rk_zynq7020.xdc:12-19`），
**没有任何 `set_output_delay`**。`check_timing` 在已布线成品上的原话是
"There are 6 ports with no output delay specified. (HIGH)"，名单是
`led[0] led[1] tmds_clk_p tmds_data_p[0..2]`（`build/check_timing_verbose.rpt:71-78`，
文件头 `:6` 那一行写明 `Design State : Routed`）。
`时序债务账`、`:121` 记的就是这笔债与"没有来源就不写数"的纪律。

**(b) 候选件与它用的数。** `src/constraints/r119_hdmi_source_window.xdc:51-52` 是那两行：

```
set_output_delay -clock clkout1_1 -max  4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]
set_output_delay -clock clkout1_1 -min -4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]
```

参考钟的身份不是猜的：四条串行器的 CLK 脚在实现网表里同属 `clkout1_1`（周期 4.000），
逐脚读数在 `build/evidence/r119_ser_clock_probe.txt:49-52`。
这个文件必须是**纯 SDC 子集**（`:3-11`）：早先在 .xdc 里写的 Tcl 守卫被解析器整块跳过
（`Designutils 20-1307`）而 `read_xdc` 仍返回 0，"防呆变成防呆失效且不报错"，
检查因此挪回构建脚本 `build/tcl/build_system_axigpio.tcl:75-82` 的开关块。
默认不加载的理由写在 `src/constraints/r119_hdmi_source_window.xdc:36-38`：
新增约束会改变实现看出去的边界，必须先用一轮构建量它对逐时钟名册的影响，
"量完之前塞进默认构建就等于用声明代替测量"。

**(c) 那两个 −3.48 / −4.90 ns。** 件 `build/evidence/r119_xdc_loads_probe3.txt:113-125`：
load 之前 4 个端口的 `Slack: inf`、`Path Group: (none)`；load 之后三条数据道变成

```
Slack (VIOLATED) : -3.482 / -3.458 / -3.474 ns
Path Group: clkout1_1
Requirement: 4.000ns  (clkout1_1 rise@4.000ns - clkout1_1 rise@0.000ns)
```

第二版把参考钟定在 TMDS 钟脚上（`src/constraints/r119b_hdmi_tp1_pinclk.xdc:24-26`），
件 `build/evidence/r119_xdc_loads_probe4_pinclk.txt:113-127` 给的是
`-4.897 / -4.873 / -4.890 ns`，并且工具自己把要求展开成
`Requirement: 4.000ns (r119b_tmclk rise@20.000ns - clkout1_1 rise@16.000ns)`。
`tmds_clk_p` 在两版里都仍是 `Slack: inf / Path Group: (none)`——钟道自身不挂窗，
这一条是设计有意（`src/constraints/r119_hdmi_source_window.xdc:48-49`：源端的钟就是参考）。

**为什么说这是量纲用错而不是设计失败**（判据文本在
`屏侧实测记录` 第三节，两处理由都要念）：

1. 规范那一行的原文是 **`Inter-Pair Skew at Source Connector, max`**，
   约束的是**两个输出脚到达时刻之差的上限**，一条单边散布；
   HDMI 1.3 第 45 页还专门写了源端眼图掩码"specifies the clock to data jitter indirectly"，
   即规范里**不存在**第三个"钟↔数据 setup/hold 窗"的数
   （取证文档 `屏侧窗口取证` 表行 #13 就是这条否定式结论）。
2. `set_output_delay` 的语义恰好是另一个东西：它把参考钟的沿当**外部采样沿**。
   于是那条 `Requirement: 4.000ns` 是把"20 % 的散布"当成"±窗内的稳定"来检查，
   第一版还叠了一层错误——`clkout1_1` 的周期是 4 ns 而 `Tcharacter` 是 20 ns，
   拿它当参考等于把窗口压缩成 1/5（`src/constraints/r119b_hdmi_tp1_pinclk.xdc:6-11` 明写了这一句）。
3. 因此两条推论都不许写："挂窗后名册变红 ⇒ 设计不满足 CTS"、"把窗放宽 ⇒ 满足"。

**(d) 与规范同量纲、且工具真能答的那一种问法。**
`build/tcl/probe_tmds_pin_skew.tcl` 在已布线检查点上逐脚问 `report_timing` 的
`Data Path Delay`，读数在 `build/evidence/r119_pin_skew_probe2.txt:69-129`：

| 引脚 | max (ns) | min (ns) |
|---|---|---|
| `tmds_clk_p` | 2.074 | 1.034 |
| `tmds_clk_n` | 2.075 | 1.035 |
| `tmds_data_p[0] / _n[0]` | 2.033 / 2.034 | 0.994 / 0.995 |
| `tmds_data_p[1] / _n[1]` | 2.009 / 2.010 | 0.970 / 0.971 |
| `tmds_data_p[2] / _n[2]` | 2.025 / 2.026 | 0.986 / 0.987 |

偏差是把每一道减去钟道：`2.033 − 2.074 = −0.041`、`2.009 − 2.074 = −0.065`、
`2.025 − 2.074 = −0.049`（max 角）；min 角同理得 `−0.040 / −0.064 / −0.048`；
P/N 对内差都是 `0.001`。判据与限值对回：
`build/evidence/r119_window_check.txt` 的 W7/W8/W9/W10 四行——
最差 **0.065 ns vs 上限 4.000 ns**（互对，余量 61×）、
最差 **0.001 ns vs 上限 0.300 ns**（对内，300×），
`GATES r119 窗件：判定 10 项 红=0 未测=0 PASS`（同一件第 11 行）。
那一份件里的 `CLKINFO| clkout1_1 period=4.000` 在
`build/evidence/r119_pin_skew_probe2.txt:147`。

**(e) 这三行能说什么、不能说什么。** 只能说 FPGA 内部（串行器时钟脚 → 封装脚）的离散；
不能说连接器（TP1）上的总离散——板级走线、连接器与线缆不在这条路径里，
而规范那一句写的对象是 Source Connector，本板走线失配的减项**未量**。
也不能说"过了 CTS"：CTS 的判据是眼图掩码 + 抖动 + 占空比 + 上升下降，
这几条在 SDC 里没有容器（`屏侧实测记录` 第六节 D3 标 `【未实测】`）。
第一版探针之所以十脚全打 `NO_ARRIVAL_LINE`，是因为找了 `data arrival time` 这个**不存在的行**，
"尺子没量形状"这件事本身也留了件（`屏侧实测记录` 第三节末）。
尺子的可信度另有对照：`node build/r119_window_check.mjs --self` 造 10 条畸形输入，
10 条各自动红，另 2 条"缺输入"报 `NOT_MEASURED` 而不是通过。

**(f) LED 那两脚。** `led[0]/led[1]` 是 `LVCMOS33` 直驱（`src/constraints/rk_zynq7020.xdc:10-11`），
HDMI 连接器引脚表里没有这类信号 ⇒ 没有可引用的对外窗
（`src/constraints/r119_hdmi_source_window.xdc:45-47`），
把它们登记成"不查"属于一次放宽，必须先进放宽账本（当前 0 条）。
探针在成品上给它们读到的 `Data Path Delay` 是 8.880/8.613 ns（max 角，
`build/evidence/r119_pin_skew_probe2.txt:133-145`），但启动钟是 `sys_clk` 另一条域 ⇒
不参与、也不能拿去比 TMDS 的窗。

---

## 4 整体架构：这两头是怎么咬合的

### 4.1 端到端的一张表

| 段 | 在哪个域 | 谁做的 | 拍/时间 | 关键条件 |
|---|---|---|---|---|
| 收包 → 验收 | `eth_rxc` 125 MHz | `frame_reasm` | 一整帧的包 | 每条源行都被写过（`cov == FRAME_BYTES`） |
| 提交换页 | axi 100 MHz | `ddr_bank_commit` | 3 级同步 + 排空 | `saver_idle && tail_drained` |
| 等消隐窗 | axi 100 MHz | `frame_commit_lock` | `c1`，最长一帧 | `allow_rise`（窗口开头，不是 vsync 沿） |
| 整帧搬运 | axi 100 MHz | `axi_frame_writer_gated` | `c2`，预算 67 200 拍 | 38 400 字 / 2400 burst / 在途 4 |
| 换帧生效 | `clk_pix` 50 MHz | 显示读口 | 下一个 `frame_start` | 缓存里整个可见期间只有一帧 |
| 读 + 几何 + 链 | `clk_pix` | `fb_bilin` + `proc_pipeline` | `MIX_D = 3+1+1+15` | 行提前量 `OFF_LINES + BILIN_ROWS` |
| 叠字 | `clk_pix` | `osd_overlay` | 2 拍 | 内容与坐标同拍（`:75-108`） |
| 8b/10b | `clk_pix` | `tmds_encoder` ×3 | 1 拍（寄存） | 消隐期发控制码 |
| 10:1 | `clk_pix5x`/`clk_pix` | `OSERDESE2` 主从级联 | 5:1 DDR | 500 Mbit/s/对 |
| 差分 | — | `OBUFDS` ×4 | — | `TMDS_33` + 50 Ω 上拉（板级） |

### 4.2 三条不变量（改动任何一段之前要自己先核这三条）

1. **搬运只在许可窗里落 BRAM**（ETH 路）。许可来自像素域的窗口信号跨过去再双位相与，
   所以护栏 `VB_X_GUARD` 必须比窗口早关，早关量 ≥ CDC 延迟（`src/rtl/top/pl_video_top.v:399`）。
2. **每帧最多消费一次提交凭证**（两条路都是）。任何把"多来几次"当改进的改动
   （例如把 `ps_publish` 改成计数器）都要先回答"PS 写到一半时谁来挡住搬走"。
3. **屏上那一路、上位机读到的那一路、以及"为什么是这一路"三个说法必须同源**。
   `why_ps` 与 `owner_eth` 同一决定点（`src/rtl/util/src_arb.v:68-73`）、
   `SRC:` 取 `src_eff`（`src/rtl/top/pl_video_top.v:1014`）、
   lane30 的位序唯一出处在 `src/rtl/top/pl_video_top.v:66-68`——
   这三处任何一处被"各写一遍"就是 #55/#66 那一族病的复发。

### 4.3 本章留着的缺口（不许在别处当已完成念）

| 缺口 | 状态 | 已有出口 |
|---|---|---|
| TP1 眼图 / 抖动 / 占空比 / 上升下降 | 未实测（需要仪器与批准） | `屏侧实测记录` 第六节 D3 |
| 板级走线与连接器的离散（从 FPGA 内部到连接器的减项） | 未量 | 同上第四节"不能说"那一栏 |
| 候选件的处置（保留当反例还是删） | 待裁决 | `问队伍清单`（D2） |
| 一次带 `VP_R119_TMDS_WINDOW=1` 的量名册构建 | **量过了，判 DECLINE**：窗把 HIGH 缺口 6→3、零违例，但同生成器的名册差分四个域同时掉（`eth_rxc/setup` 0.739→0.471），件 `build/evidence/1006d_*`，读法见第 13 章 5.6 | `src/constraints/r119_hdmi_source_window.xdc:36-38`（那份件里"为什么不进默认构建"当时是预判，现在是实测） |
| 30 fps 源在 59.52 Hz 面板上的拍频现象（每 63 帧源 = 2.1 s 出现一次单场短显示） | 算术成立，肉眼/仪器未复现 | 本章 2.3(b) |
| 60 fps 输入（超场频）时的屏上观感与读数 | 未量 | 本章 2.3(e)，入流侧 0 丢字有件 |
| `data/metrics.csv:11` 那句"DSP 用在 gamma 计算" | 与 `gamma_lut.v` 不符（那里没有乘法） | 第 04 章 §2.6 |

### 4.4 与其他章的接缝

* 几何（`(cx,cy) → (sx,sy)`、Q8 倒数步长、行环）在第 05 章；本章只用到 `cy_r` 的提前量
  作为"读侧地址"这一事实（`src/rtl/top/pl_video_top.v:276-284`）。
* 效果链的九级与 `shown_rate` 之外的 OSD 内容在第 06/07 章；本章只讲 `SRC:`/`FPS:`/`no_sig` 三格。
* RGMII 收口的输入窗（与本章 3.13 的输出窗是同一族问题的另一半）在第 11/12 章的时序与验证部分，
  正本件是 `src/constraints/r116_rgmii_input_window.xdc` 与
  `收口输入窗模型`。

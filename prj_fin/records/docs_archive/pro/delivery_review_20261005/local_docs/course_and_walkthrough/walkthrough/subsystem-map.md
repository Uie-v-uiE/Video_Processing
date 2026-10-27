# subsystem-map.md · 层次拆解、每块职责与边界

读完这篇你能回答哪三个问题：

1. 从 `system_top` 往下数，一共有哪些实例、每只实例归哪个子系统、在哪个时钟域？
2. 数据线与控制线分别走哪几只实例？两条线在哪里交叉？
3. 一篇没读过的代码，我怎么用"实例名 + 端口名"把它重新拼出这张图（辨认方法）？

## 目录

- 第 1 节 读图约定与覆盖率口径
- 第 2 节 层次图
- 第 3 节 `system_top` 的 5 只实例
- 第 4 节 收包子系统 `u_eth` 的 14 只实例
- 第 5 节 显示子系统 `u_pl` 的 32 只实例
- 第 6 节 三条边界：时钟域 / 协议 / 位宽
- 第 7 节 六个关键模块的六件套（W12 抽验）
- 第 8 节 遗留件与"没被例化"的件
- 第 9 节 覆盖率账（全量，打印未覆盖比例）
- 第 10 节 小结与下一步
- 第 11 节 自测题

## 第 1 节 读图约定与覆盖率口径

- 图里的**节点名一律是实例名**（`u_reasm`、`u_pipe` 这种），不是模块名。理由：一个模块可以被例化多次
  （`key_debounce` 有 `u_k1`、`u_k2` 两只，`snap_cross` 在整个工程里有五只），只有实例名能定位到线上。
- 每只实例后面括号里是**例化处的文件与行**，形如（`pl_video_top.v:800`）。这张表里全部 51 个行号
  都是本次逐条 grep 出来的，不是抄的。
- "域"这一栏只写**这只实例自己跑在哪个时钟上**，不写它的输入来自哪里 —— 跨域点在 `clocking-and-reset.md` 第 3 节成表列。
- 分母口径：本仓库自己的接线检查器 `build/check_ports.py` 全树数到 `instances=222`（读数见 `build/ports_check.txt:1`）。
  本篇逐只点名的是**三份顶层文件里的 51 只**，剩下 171 只在叶子模块内部，第 9 节给清单与原因。

小结 1：这张图的节点是实例名、边是线，任何一个节点都能 grep 到；这就是 W3 的可核对形式。
小结 2：51 只是"顶层三棵树"的全部，不是全树 222 只 —— 这个差别第 9 节明算。下一步：第 2 节。

## 第 2 节 层次图

```
system_top                      ← 板上顶层（构建脚本认的 top，build/tcl/build_system_axigpio.tcl:258）
├── u_bd            design_1_wrapper   PS7 + 三条 AXI GPIO + HP0 互联（Block Design 生成物）
├── u_idelay_clkgen clk_gen            只为 IDELAYCTRL 与 IDELAY 参考钟存在的第二只 MMCM
├── u_eth           eth_udp_video_top  ── 收包子系统（14 只，本图第 4 节）
├── u_lm_axi        snap_cross         健康快照 eth_rxc→fclk0（320 bit）
└── u_pl            pl_video_top       ── 显示子系统（32 只，本图第 5 节）
```

`u_eth` 内部（数据面从左到右，控制面在上）：

```
 rgmii_rxc ─► u_rgmii ─► u_rx_mac ─► u_rx_par ─► u_reasm ─┬─► u_cdc ─► u_saver ─► AXI 写 ─► HP0
 (板级输入)   (IDDR/IDELAY) (算FCS)   (端口过滤)  (重组+验收) │  (格雷码FIFO) (打包64bit)
                     │                ▲                └─ 16bit 写口 ─────────────┐
                     └── gmii 总线 ──┘                                            ▼
                                              （u_arp / u_icmp / u_ctrl / u_udp_tx / u_crc_tx 在控制面）
   u_lm(link_monitor) 吃 u_reasm 与 u_cdc 的探针 ─► 320bit 快照 ─► system_top 的 u_lm_axi
   u_commit(ddr_bank_commit) 吃 frame_done 与 u_cdc/u_saver 的排空状态 ─► commit_pulse + bank
```

`u_pl` 内部主链（一条像素流 + 一条搬运流）：

```
 u_t(video_timing) ─► 坐标 ─► u_zmap(zoom_mapper) ─► u_bilin(fb_bilin) ─► u_pipe(proc_pipeline)
                        ▲            │                                        │
      u_zctrl/u_zfit ───┘            └─ oob ─► u_raw(raw_line_delay) ─► 原图抽头 │
                                                                              ▼
        u_dvi(rgb2dvi) ◄─ u_osd(osd_overlay) ◄─ u_split(split_display) ◄─── 两抽头混合
  搬运：u_cmt(frame_commit_lock) ─► u_row / u_aw（两台 AXI 读回机）─► u_bilin 的写口
```

小结 1：`u_pl` 有两条互不相同的流：**像素流**（每 20 ns 一拍往前推）与**搬运流**（一帧一次、只在消隐里跑）。
小结 2：图里出现的每个 `u_*` 都能在第 3~5 节的表里找到它的例化行。下一步：逐只点名的三张表。

## 第 3 节 `system_top` 的 5 只实例

| 实例名 | 模块 | 域 | 职责与边界 |
|---|---|---|---|
| `u_bd` | `design_1_wrapper` | PS | Vivado Block Design 的生成物：PS7、三条 AXI GPIO、GP0 与 HP0 互联都在这里（`src/rtl/top/system_top.v:75`）。本工程不手写它的内部，只按端口对账 |
| `u_idelay_clkgen` | `clk_gen` | sys_clk 进、出三路 | 第二只 MMCM，只为 IDELAY 提供参考钟；`clk_pix`/`clk_pix5x` 两只输出在本层**故意不接**（`src/rtl/top/system_top.v:119-125`） |
| `u_eth` | `eth_udp_video_top` | eth_rxc + fclk0 | 收包子系统整体（`src/rtl/top/system_top.v:154`）。几何与 DDR 基址在这里一次性传给两边（`src/rtl/top/system_top.v:136-145`） |
| `u_lm_axi` | `snap_cross` | fclk0 收 | 320 bit 健康快照从 eth_rxc 跨到 fclk0（`src/rtl/top/system_top.v:214`） |
| `u_pl` | `pl_video_top` | sys_clk/clk_pix + fclk0 | 显示通路整体（`src/rtl/top/system_top.v:258`） |

本层还有一段**不是实例**的逻辑：lane 读回口的组合选择（`src/rtl/top/system_top.v:237-247`）与
`eth_live`/`eth_tb_ok` 两位的取法（`src/rtl/top/system_top.v:255-256`）。 PHY 复位计数器也在这一层
（`src/rtl/top/system_top.v:108-112`）：24 位计数器到顶才放开 `eth_rst_n`。

小结 1：顶层只做四件事 —— 连线、把 lane 号译成一条 32 位、给 PHY 造上电复位、把几何常量收在一处。
小结 2：任何"逻辑写在顶层"的例外都会在这张表里露出来；上面那三条就是全部例外。下一步：第 4 节。

## 第 4 节 收包子系统 `u_eth` 的 14 只实例

域一栏：`eth_rxc` = PHY 恢复出来的 125 MHz（`src/rtl/eth/eth_udp_video_top.v:5-6` 声明的规矩），`fclk0` = PS 给的 100 MHz。

| 实例名 | 模块 | 域 | 职责 | 例化处 |
|---|---|---|---|---|
| `u_rgmii` | `gmii_to_rgmii` | eth_rxc | 4bit DDR → 8bit SDR；里面含 IDDR/IDELAY/BUFG | （`src/rtl/eth/eth_udp_video_top.v:73`） |
| `u_rx_mac` | `gmii_rx_mac` | eth_rxc | 逐字节算 FCS-32，自己造"这个包坏没坏" | （`src/rtl/eth/eth_udp_video_top.v:186`） |
| `u_rx_par` | `udp_rx_parser` | eth_rxc | 剥头 + 目的端口过滤，给 `p_sof/p_eof/p_good` | （`src/rtl/eth/eth_udp_video_top.v:197`） |
| `u_reasm` | `frame_reasm` | eth_rxc | 按帧内偏移重组、逐行覆盖验收、出 16bit 写 | （`src/rtl/eth/eth_udp_video_top.v:235`） |
| `u_cdc` | `dc_fifo` | eth_rxc→fclk0 | 36bit×8192 的 BRAM 异步 FIFO（格雷码指针） | （`src/rtl/eth/eth_udp_video_top.v:298`） |
| `u_saver` | `axi_frame_saver64` | fclk0 | 两个 16bit 拼一个 64bit，突发写 HP0 | （`src/rtl/eth/eth_udp_video_top.v:354`） |
| `u_commit` | `ddr_bank_commit` | 两域 | 提交脉冲 + 乒乓 bank 换页，带帧尾排空门 | （`src/rtl/eth/eth_udp_video_top.v:330`） |
| `u_lm` | `link_monitor` | eth_rxc | 丢字/作废帧/帧间隔/断流 ms 计数，出 320bit 快照 | （`src/rtl/eth/eth_udp_video_top.v:284`） |
| `u_arp` | `arp` | eth_rxc | ARP 应答（板子能被 ping 到靠它） | （`src/rtl/eth/eth_udp_video_top.v:126`） |
| `u_icmp` | `icmp` | eth_rxc | ICMP echo 应答 | （`src/rtl/eth/eth_udp_video_top.v:140`） |
| `u_icmp_fifo` | `sync_fifo` | eth_rxc | 应答前把请求载荷先存住 | （`src/rtl/eth/eth_udp_video_top.v:119`） |
| `u_ctrl` | `eth_ctrl` | eth_rxc | 发送侧多路选择 + GMII 输出 | （`src/rtl/eth/eth_udp_video_top.v:206`） |
| `u_udp_tx` | `udp_tx` | eth_rxc | UDP 发送时序机，**使能恒 0** | （`src/rtl/eth/eth_udp_video_top.v:163`） |
| `u_crc_tx` | `crc32_d8` | eth_rxc | 发送链的 CRC 计算 | （`src/rtl/eth/eth_udp_video_top.v:180`） |

`u_udp_tx`/`u_crc_tx` 这一对今天的状态是"接着但没人启动"：`src/rtl/eth/eth_udp_video_top.v:166` 把 `tx_start_en`
接成 `1'b0`，同文件 `:154-158` 的注释交代了原因与判据。**这不是缺陷，但是"看起来能用、实际不发包"的坑**，
`myths.md`（本批未开始）会收它。

小结 1：收包链的"数据面"只有 6 只实例（`u_rgmii`→`u_rx_mac`→`u_rx_par`→`u_reasm`→`u_cdc`→`u_saver`），其余 8 只都在控制面与观测面。
小结 2：这条链上唯一的存储是 `u_cdc`（`src/rtl/eth/dc_fifo.v:20` 那句 `ram_style = "block"`），帧本身在 DDR 里。下一步：第 5 节。

## 第 5 节 显示子系统 `u_pl` 的 32 只实例

| 实例名 | 模块 | 域 | 职责 | 例化处 |
|---|---|---|---|---|
| `u_clk` | `clk_gen` | sys_clk | 出 50/250/200 MHz 三路 + `locked` | （`src/rtl/top/pl_video_top.v:128`） |
| `u_k1` | `key_debounce` | sys_clk | KEY1 消抖（`CNT_MAX` = 1_000_000 ⇒ 20 ms @50 MHz） | （`src/rtl/top/pl_video_top.v:136`） |
| `u_k2` | `key_debounce` | sys_clk | KEY2 消抖 | （`src/rtl/top/pl_video_top.v:139`） |
| `u_k1l` | `key_long` | sys_clk | 同一键的短按/长按两种语义，长按出翻转位 | （`src/rtl/top/pl_video_top.v:148`） |
| `u_mode` | `src_mode` | clk_pix | 片源模式四态环 + 串口覆盖，出格雷码 `mode` | （`src/rtl/top/pl_video_top.v:157`） |
| `u_ang` | `angle_ctrl` | sys_clk | 角度累加与自动旋转节拍 | （`src/rtl/top/pl_video_top.v:183`） |
| `u_eff` | `effect_ctrl` | clk_pix | 效果/阈值/gamma/缩放档那条 sel 同步链 | （`src/rtl/top/pl_video_top.v:198`） |
| `u_t` | `video_timing_1024x600` | clk_pix | 面板栅格：`x,y,hs,vs,de,frame_start` | （`src/rtl/top/pl_video_top.v:226`） |
| `u_zfit` | `zoom_fit` | clk_pix | 由角度定"刚好装得下"的倍率 | （`src/rtl/top/pl_video_top.v:322`） |
| `u_zctrl` | `zoom_ctrl` | clk_pix | 倍率三来源（呼吸/手动/拟合）的选择与钳制 | （`src/rtl/top/pl_video_top.v:325`） |
| `u_zmap` | `zoom_mapper` | clk_pix | 逆映射：显示坐标 → 源坐标 + 小数部分 | （`src/rtl/top/pl_video_top.v:343`） |
| `u_arb` | `src_arb` | fclk0 | 谁拥有 AXI 读口 + 帧缓存写口 | （`src/rtl/top/pl_video_top.v:421`） |
| `u_cmt` | `frame_commit_lock` | 两域 | 把提交锁进消隐窗口、开拷、看门狗 | （`src/rtl/top/pl_video_top.v:430`） |
| `u_row` | `axi_frame_writer_gated` | fclk0 | ETH 路：整帧从 DDR 拉回帧缓存 | （`src/rtl/top/pl_video_top.v:454`） |
| `u_aw` | `axi_frame_writer64` | fclk0 | PS 路：同一件事，由 `ps_frame_start` 触发 | （`src/rtl/top/pl_video_top.v:692`） |
| `u_pub` | `ps_publish` | clk_pix | PS 发布脉冲的跨域 + 挂起 | （`src/rtl/top/pl_video_top.v:564`） |
| `u_life` | `src_life` | clk_pix | "此刻到底有没有片源"的活判据 | （`src/rtl/top/pl_video_top.v:588`） |
| `u_bilin` | `fb_bilin` | clk_pix（写口 fclk0） | 帧缓存唯一读口 + 双线性/最近邻 | （`src/rtl/top/pl_video_top.v:732`） |
| `u_bar` | `test_card` | clk_pix | 会动的自绘图卡（第三路片源） | （`src/rtl/top/pl_video_top.v:759`） |
| `u_raw` | `raw_line_delay` | clk_pix | 原图抽头的行环形延迟（把原图延后 4 行） | （`src/rtl/top/pl_video_top.v:788`） |
| `u_pipe` | `proc_pipeline` | clk_pix | 九位控制字的效果链，15 拍固定 | （`src/rtl/top/pl_video_top.v:800`） |
| `u_split_ctrl` | `split_ctrl` | clk_pix | 分割线位置发生器（手动/扫描/跟随/交换） | （`src/rtl/top/pl_video_top.v:885`） |
| `u_seam_src` | `seam_src` | clk_pix | 把缝从显示列搬进图像列（线跟着画面转） | （`src/rtl/top/pl_video_top.v:904`） |
| `u_split` | `split_display` | clk_pix | 逐像素二选一 + 标记线 + 越界涂黑 | （`src/rtl/top/pl_video_top.v:911`） |
| `u_fpsr` | `shown_rate` | clk_pix | 数"真的写进屏的新帧" | （`src/rtl/top/pl_video_top.v:941`） |
| `u_osd` | `osd_overlay` | clk_pix | 五行状态叠字 | （`src/rtl/top/pl_video_top.v:999`） |
| `u_dvi` | `rgb2dvi` | clk_pix + clk_pix5x | TMDS 并串转换 | （`src/rtl/top/pl_video_top.v:1026`） |
| `u_lat` | `frame_latency` | fclk0 | 链路内时延三段计数 | （`src/rtl/top/pl_video_top.v:624`） |
| `u_zsnap` | `zoom_snap` | clk_pix | 像素域缩放状态在帧首打快照 | （`src/rtl/top/pl_video_top.v:652`） |
| `u_zoom_axi` | `snap_cross` | clk_pix→fclk0 | lane23 那一路跨域 | （`src/rtl/top/pl_video_top.v:674`） |
| `u_split_x` | `snap_cross` | fclk0→clk_pix | 19 位几何控制字跨域 | （`src/rtl/top/pl_video_top.v:876`） |
| `u_lat_x` | `snap_cross` | fclk0→clk_pix | 算好的 ms 跨给 OSD 那一格 | （`src/rtl/top/pl_video_top.v:980`） |

32 只之外，`u_pl` 里还有**不成为实例的逻辑**：十一段打拍同步链（十段三级：`src/rtl/top/pl_video_top.v:165-169`、
`:212-221`、`:254-261`、`:267-274`、`:471-475`、`:484-489`、`:491-496`、`:502-507`、`:517-522`、`:573-578`；一段两级：`:542-552`）、
五个翻转位发射触发器（`:179` 声明、驱动在 `:304-314`，另有 `:568-572`、`:607-611`、`:665-669`、`:975-979`）、混色对齐用的两条打拍链
（`:356-374` 的 `de_d/x_d/...`、`:831-847` 的 skid）与那条缝的发射计数（`:865-875`）。
这几段是本项目 CDC 结构的全部载体，`clocking-and-reset.md` 第 3 节按它们列全表。

小结 1：32 只实例里真正"每个像素都要动"的只有 5 只（`u_t`、`u_zmap`、`u_bilin`、`u_pipe`、`u_split`），
再加两只按节奏动的 `u_osd` 与 `u_dvi`；其余 25 只都是控制、观测与搬运。
小结 2：读 `u_pl` 的正确顺序是"先认域、再认流、最后认观测口"，因为 6 处三级同步器全在流的中途。下一步：第 6 节。

## 第 6 节 三条边界：时钟域 / 协议 / 位宽

**边界一：时钟域。** 本工程的四个域是 `sys_clk`(50 MHz 输入)、`clk_pix`/`clk_pix5x`/`clk_200m`(MMCM 生成)、
`eth_rxc`(125 MHz)、`fclk0`(100 MHz)。跨域点的完整清单在 `clocking-and-reset.md` 第 3 节；
这里只给一条辨认规则：**任何一根线穿过两只 MMCM/PS 时钟，就必须在它身上找到 `ASYNC_REG`、
格雷码、或 `snap_cross` 三者之一**（写法见 `src/rtl/eth/dc_fifo.v:27`、`src/rtl/eth/snap_cross.v:36-46`）。

**边界二：协议。** 三条硬协议线：
① 上位机 ↔ PL 是 UDP，包形如 `[4 字节小端帧内偏移][RGB565 载荷]`（`src/host/video_sender.py:4-6`）；
② PS ↔ PL 是 AXI GPIO 寄存器 + 共享 DDR，地址表在 `interface-contract.md` 第 2~5 节；
③ PL 内部 ↔ DDR 是 AXI4 读/写突发，读写两条线分别从 `u_row`/`u_aw` 与 `u_saver` 出去，
汇到 `u_bd` 的同一个 HP0 端口（`src/rtl/top/system_top.v:88-103`、`:193-199`、`:298-302`）。

**边界三：位宽。** 三个"名字对得上但宽度会吞人"的位置：
19 位帧缓存地址（`src/rtl/eth/frame_reasm.v:21`）、16 位像素写数据（同一文件 `:22`）、
320 位健康总线（`src/rtl/top/system_top.v:151`）。为什么这里要单列：
`src/rtl/top/system_top.v:224-226` 记录了"名字连对、宽度被吞"真实发生过一次，
而它的修法是把位宽判据做进门禁第 14 项（`build/gates.sh:252-260`）。

小结 1：三条边界各对应一种"不会编译失败但板上会错"的错法，所以它们才是边界。
小结 2：新接一根线时先问它穿哪条边界，答案决定你必须用哪种跨域/对齐写法。下一步：第 7 节。

## 第 7 节 六个关键模块的六件套（W12 抽验）

六件 = 为什么存在 / 取值范围与非法值 / 对外部时序的要求 / 失败时以什么形式暴露 / 与谁共享状态 / 怎么确认它活着。

### 7.1 `frame_reasm`（`src/rtl/eth/frame_reasm.v`）

1. **为什么存在**：把"乱序到达、每包带一个帧内偏移"的 UDP 载荷，重组成一块连续写入的帧，
   并且**只有整帧每一行都被写过才提交**（`:2-3` 的文件头就是这个判据的表述）。
2. **取值范围与非法值**：`FRAME_BYTES` = IMG_W×IMG_H×2 = 307200（`:11`），偏移字段是 4 字节小端；
   越界偏移计入 `stat_oob_off`（`:35`）。非法值 = 没凑满字节预算的短帧：它**不**脉冲 `frame_abort`，
   由 `stall_ms` 抓到（`:26-28` 明写这条分工）。
3. **对外部时序的要求**：上游 `u_rx_par` 必须先给出 `p_sof/p_eof/p_good`；本模块的输出全部寄存
   （`:4` 声明 "all outputs are registered"），下游 `link_monitor` 因此可以直接吃它（`src/rtl/eth/link_monitor.v:18` 的口径）。
4. **失败暴露**：`frame_abort` 与同拍的 `rows_missed`（`:29-30`）→ `link_monitor` 的 `frames_bad`/`rows_miss_max`
   → 快照 lane1/lane2（`src/rtl/eth/link_monitor.v:188-189`）。
5. **共享状态**：与 `u_cdc`/`u_saver` 共享"这一帧的字节是否全部穿过 CDC"这件事 —— 由 `u_commit` 收口
   （`src/rtl/eth/ddr_bank_commit.v:49-51`）。
6. **怎么确认它活着**：台架 `sim/tb_reasm_bounds.v`、`sim/tb_udp_reasm.v`（本目录只点名，跑法见 `hands-on.md` 第 4 节）；
   板级看 lane8 `in_pkts`、lane9 `in_bytes` 单调增长。【未实测】本目录未在本机跑过台架。

### 7.2 `dc_fifo`（`src/rtl/eth/dc_fifo.v`）

1. **为什么存在**：全设计唯一的"数据必须穿过时钟域"通道，用 BRAM + 格雷码指针吸收 HP0 被独占期间的入流
   （`src/rtl/eth/eth_udp_video_top.v:295-297` 给了容量账：8192 条 = 4096 个 64bit 字 = 16 KB）。
2. **取值范围**：深度 = `1<<ADDR_W`，本工程 `ADDR_W=13` ⇒ 8192；满/空是**保守判定**，多算一格比少算一格坏。
   非法输入 = 满时继续写：被 `wr_en && !wr_full` 挡掉（`src/rtl/eth/dc_fifo.v:53`），
   这件事本身被数出来（`src/rtl/eth/eth_udp_video_top.v:283` 的 `cdc_wr_req`）。
3. **时序要求**：两侧复位各自独立，但**上电必须两边都复位过**，否则指针初值不一致（`:82-95` 的两级链复位值都是 0）。
4. **失败暴露**：满了还在要写 → `drop_words`（`src/rtl/eth/link_monitor.v:69`）→ 快照 lane0；
   进入满态的次数 → `cdc_ep` → lane6（同一文件 `:72`、`:193`）。
5. **共享状态**：`u_commit` 读它的 `fifo_empty` 与读流水状态来判断帧尾排空（`src/rtl/eth/ddr_bank_commit.v:25-29`）。
6. **怎么确认活着**：台架 `sim/tb_cdc_capacity.v`（容量账由它钉，见 `src/rtl/eth/dc_fifo.v:43-44` 的注释）；
   板级看 `drop_words == 0` —— `board/ACCEPTANCE.md` 机器判据表第 5 条（r94 那一版）读到的就是这个 0。

### 7.3 `axi_frame_writer_gated`（`src/rtl/axi/axi_frame_writer_gated.v`，实例 `u_row`）

1. **为什么存在**：把刚提交的一帧从 DDR 拉回显示帧缓存，且**只在消隐窗口里落笔**（`:2-4` 的文件头）。
2. **取值范围**：`base_addr` 是 32 位 DDR 地址；`start`/`allow_wr`/`abort` 都是单拍或电平请求。
   非法值 = 在 `allow_wr` 为 0 时期待它写：结构上不可能，写使能被 `allow_wr` 门住。
3. **时序要求**：AR 通道只在 `allow` 窗口里发起；从机 `m_axi_arready` 可以任意时刻拖住它（`:29-33` 的端口形状）。
   `abort` 之后必须先**排空在途突发**再收新请求，那段时间 `rready` 不许撤回（`:69-75` 记录了这条）。
4. **失败暴露**：一次拷贝跨过一整个消隐窗口 → `copy_cycles > VBLANK_AXI_CYC` → `copy_overrun`
   → `led[0]` 从 1.5 Hz 心跳变 6 Hz 快闪（`src/rtl/top/pl_video_top.v:446-452`、`:1039`）。
5. **共享状态**：与 `u_aw` 共享**同一个** AXI 读口与同一个帧缓存写口，靠 `u_arb` 的 `owner_eth` 分（ mux 见
   `src/rtl/top/pl_video_top.v:709-718`）。
6. **怎么确认活着**：`row_copy_cycles` 与 `copy_done` 都是 `dbg_lat` 的原料（lane28 = 搬运段，
   `src/rtl/top/pl_video_top.v:636-642`）；台架 `tb_v5_gated`/`tb_v6_vblank_copy`。【未实测】同上。

### 7.4 `frame_commit_lock`（`src/rtl/video/frame_commit_lock.v`，实例 `u_cmt`）

1. **为什么存在**：把"提交一帧"这件事锁进显示消隐窗口，避免新旧两半同屏（`:2` 的文件头）。
2. **取值范围**：`WD_CYC` 默认 2_000_000 拍 = 20 ms @100 MHz（`:8`）就是看门狗预算；
   `blank_safe` 必须是**已经**在消隐里的电平（顶层算法在 `src/rtl/top/pl_video_top.v:400-401`）。
3. **时序要求**：`commit_req` 与 `commit_base` 必须同拍有效（源在 `src/rtl/eth/ddr_bank_commit.v:67-72`）；
   起拷只在 `allow_rise || vsync_req` 且 `!copy_busy` 时发生（`src/rtl/video/frame_commit_lock.v:117-122`）。
4. **失败暴露**：看门狗到期 → `copy_abort` 一拍 + `abort_tgl` 翻转（`:106-109`）→
   像素域 `copy_abort_pix` 把 `eth_has_frame` 清零（`src/rtl/top/pl_video_top.v:531`）。
5. **共享状态**：与 `u_row` 共享 `copy_busy`/`copy_done`；与 `u_cmt` 自己在两个域间的契约是
   "窗口开启沿必须晚于请求"，注释在 `:78-80`。
6. **怎么确认活着**：台架 `tb_v5_lock`、`tb_v6_vblank_copy`、`tb_v79_abort_toggle`（第三支专门扫相位，
   理由见 `src/rtl/video/frame_commit_lock.v:100-105`）。【未实测】本目录没跑过。

### 7.5 `link_monitor`（`src/rtl/eth/link_monitor.v`，实例 `u_lm`）

1. **为什么存在**：把"板上唯一真实的丢数据通道"（FIFO 满挡住的那一拍）变成可读数（`:3-5` 文件头）。
2. **取值范围**：16 位字段一律**饱和不回卷**（`:88-92`），因为回卷会把"很糟"读成"没问题"；
   `stall_ms` 上限 0xFFFF（`:151`）。
3. **时序要求**：输入必须已经是寄存器输出（`:3-4` 明写"本模块内不许再插组合逻辑进关键路径"）。
4. **失败暴露**：它本身就是暴露通道 —— 快照 lane0..lane9（`:187-196`）与 `flag5` 五位（`:158-162`）。
5. **共享状态**：与 `snap_cross` 的契约是"两次发布之间留出 `SETTLE` 个源周期"（`:165-166`、`:171-184`）。
6. **怎么确认活着**：`lm_hb` 每毫秒翻一次（`:58-64`），目的域用 `hb_gone`/`hb_slow` 反查它有没有停
   （`src/rtl/eth/snap_cross.v:55-65`）；板级 `--demo` 推流中读回 `drop_words=0`、`stall_ms=0`
   就是这一路的读数（`board/ACCEPTANCE.md` 机器判据表第 5 条）。

### 7.6 `src_arb`（`src/rtl/util/src_arb.v`，实例 `u_arb`）

1. **为什么存在**：老写法用"自配置以来收过没有包"决定谁占屏，拔线不回 0 ⇒ PS 片源被永久锁死
   （`:4-8` 把这两条病写清楚了）。
2. **取值范围**：`sel` 是 2 位，`00` 自动 / `01` 强制 ETH / `10` 强制 PS / `11` 按自动处理（`:26-28`）；
   ⚠ 这份编码**与 `src_mode` 的四态码不同**（同一段注释明确警告），中间有一行适配器在
   `src/rtl/top/pl_video_top.v:171`。
3. **时序要求**：`eth_live`/`eth_tb_ok` 必须已经在本域同步好（`:24-25`），换手只在 `both_idle` 那一拍（`:67`）。
4. **失败暴露**：`why_ps` 三位 = 判决那一拍的输入快照（`:35-39`、`:73`），屏上/回读看到的主人必须与它同源。
5. **共享状态**：`row_busy`/`fill_busy` 两台搬运机的忙位；输出 `owner_eth` 被 `u_pl` 拿去切 14 处 mux。
6. **怎么确认活着**：lane30 的 16 位（`src/rtl/top/pl_video_top.v:603`）+ `board/ACCEPTANCE.md` 机器判据表第 3 条的
   `geom_check`；台架 `sim/tb_src_arb_why.v`（`:71-72` 点名它钉 W5/W7 两件事）。【未实测】同上。

小结 1：六件套里最容易空着的是第 6 件"怎么确认它活着"—— 本仓库每个模块都指向一份台架或一个 lane，
第 7 节里六条全部有落点。
小结 2：第 4 件（失败暴露）全部落在**可读数**上，没有一条落在"人看屏幕"上；这是这套代码的硬规矩。下一步：第 8 节。

## 第 8 节 遗留件与"没被例化"的件

`src/rtl/` 里有 13 个文件不出现在综合的孤儿清单里（口径与名单在 `report/modules.md:6-13`）：
`axi_frame_saver`、`axi_frame_saver_burst`、`axi_frame_writer`、`color_bar`、`fb_rd5x`、`frame_buffer`、
`frame_buffer_db`、`line_cache`、`pl_demo_top`、`rotate_mapper`、`tap_sched`、`udp_rx`、`video_timing_720p`。
本篇第 3~5 节的 51 只实例里**没有**这些名字，读者按图找它们会找不到 —— 这一节就是为了让"找不到"有解释。

两个容易误判的例子：

- `frame_buffer` 有完整的 16bit 双端口写法（`src/rtl/video/frame_buffer.v:20`），但它的文件头第二行就写着
  "**本树无人例化**"（`src/rtl/video/frame_buffer.v:2-3`）。现役帧缓存是 64bit 写口的 `frame_buffer_w64`，
  它被 `fb_bilin` 例化（`src/rtl/process/bilin/fb_bilin.v:65`）。
- `pl_demo_top` 是**不在正式位流里**的另一棵顶层树；`snap_cross` 的位流初值那一段
  专门讨论了它为什么对当前时序读数无感（`src/rtl/eth/snap_cross.v:27-28`）。

小结 1：若按图找不到某个模块，先查本节名单 —— 那 13 个文件在这棵顶层树里不可达，"找不到"是预期而不是图的错。
小结 2：遗留件不影响功能但会误导阅读顺序；本目录任何一篇引用它们都必须带"未例化"这三个字。下一步：第 9 节。

## 第 9 节 覆盖率账（全量，打印未覆盖比例）

| 分母 | 数 | 点名 | 未点名 | 未覆盖比例 |
|---|---|---|---|---|
| 三份顶层文件的实例（`src/rtl/top/` + `src/rtl/eth/eth_udp_video_top.v`） | 51 | 51（第 3~5 节逐只） | 0 | **0 %** |
| 全树实例点（`build/check_ports.py` 的扫描面，读数 `build/ports_check.txt:1`） | 222 | 51 | 171 | **77.0 %（171/222）** |

171 只未逐一点名的部分，全部是**叶子模块内部的例化**（例如 `proc_pipeline` 里的 8 只子模块
`src/rtl/process/proc_pipeline.v:102`、`:109`、`:113`、`:119`、`:125`、`:132`、`:140`、`:146`，
`gmii_to_rgmii` 里的 `rgmii_rx`/`rgmii_tx` `src/rtl/eth/gmii_to_rgmii.v:28`、`:42`）。
原因：本篇的定位是"顶层可导航"，叶子级全量点名归 `code-reading.md` 与本篇的后续批次。
**这项未覆盖是已登记状态，不是"已经完整"**（`_progress.md` 有对应行）。

小结 1：全量覆盖率两栏分开报：顶层实例 100 %、全树实例 23.0 %（51/222）。
小结 2：要升到 100 % 需要把 171 只叶子实例逐只登记，排进 `_progress.md` 的下一批。下一步：第 10 节。

## 第 10 节 小结与下一步

三句话：从 `system_top` 往下是 5 → 14 → 32 的三层树；数据线只有像素流与搬运流两条，
其余全是控制与观测；边界三条（域/协议/位宽）各对应一类"编译过但板上错"的故障。
下一步去 `clocking-and-reset.md`：那里把第 6 节"边界一"展开成每个时钟的产生者与消费者（W10）。

## 第 11 节 自测题

题目：**`u_lat_x` 与 `u_zoom_axi` 都是 `snap_cross`，但它们的方向相反。哪个方向是"给 PS 读"、哪个是"给 OSD 画"？依据是什么端口？**
本文不答。去查这两行的端口连接并说出判据：`src/rtl/top/pl_video_top.v:674`（`u_zoom_axi`）与
`src/rtl/top/pl_video_top.v:980`（`u_lat_x`），对照 `src/rtl/top/system_top.v:214`（第三只，方向与 `u_zoom_axi` 同）。

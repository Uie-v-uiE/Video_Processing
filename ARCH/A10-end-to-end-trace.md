# 端到端逐拍全景、失败模式与"量过并否决"的优化

本卷是这套拆解的最后一卷，不引入新模块，只做三件事：把三条端到端路径（入流、出流、命令）按拍走通并把每一处缓冲深度与级间拍数落到具体行号；把散在 `report/` 与代码注释里的失败模式与"量过并否决"的优化收拢成可核对的两张表；明确声明这一卷没能从仓库里读到证据的东西。凡本卷给出的数字，句末都点名了文件与行号；凡引用某行代码，反引号里的片段逐字抄自该条引用所指行附近。阅读顺序建议：先读 `ARCH/A1-architecture-and-clocking.md` 建立时钟与顶层分工，再读本卷把链路接起来；各模块内部细节在 A2—A7，约束与时序验证在 A9。

## 目录

- 1. 范围与读法
- 2. 一包到一帧：入流侧逐拍
- 3. 一帧到一屏：出流侧逐拍
- 4. 一条命令的完整旅程
- 5. 跨时钟域与数据/控制边界的完整清单
- 6. 失败模式表
- 7. 量过并否决的优化
- 8. 未证与边界

## 1. 范围与读法

三条路径与两张表的覆盖范围：

- §2 从 `rgmii_rxc` 上一个 UDP 包进来，到 `frame_reasm` 拼出完整帧、`axi_frame_saver64` 把 64 bit 字写进 DDR，逐级给缓冲深度与"为什么是这个深度"。
- §3 从消隐期搬帧开始，经过帧缓存读口的 5 槽调度、六级效果链、行环与 skid、混色、OSD，到 TMDS 并串化，逐级给级间拍数与跨域点。
- §4 从串口一个字节进来到某个位驱动某个 MUX，含 PS 侧寄存器写与 PL 侧同步拍数。
- §5 只列名册与约束，展开在 A2/A9。
- §6 失败模式表，只写仓库里有凭据的项，每行给出现场判据（可回读的数或可见图形）。
- §7 "量过并否决"的优化，每条五段：假设 / 刀法 / 读数 / 判负理由 / 凭据。
- §8 未证与边界。

三处口径要先说清，否则读数会被念歪。第一，本卷凡是"拍"都点名是哪个域：入流侧的拍是 125 MHz 的 `gmii_rx_clk`，AXI 侧是 100 MHz 的 `fclk0`/`axi_clk`，像素侧是 50 MHz 的 `clk_pix`，序列化侧是 250 MHz 的 `clk_pix5x`。第二，链路内时延在 PL 里只报拍数不换算时间，因为换算规则是一个 host 侧常量（来源：`src/rtl/top/pl_video_top.v:69`—`71`）。第三，"WNS 没动"在异步组排除的语境下不构成收益也不构成否决证据，本卷凡涉及采纳/否决的判断都跟着名册差分走（来源：`src/constraints/r114_io_async.xdc:51`—`54`，`report/log/issues.md:12198`）。

## 2. 一包到一帧：入流侧逐拍

链路的模块顺序在文件头就写死了：`gmii_to_rgmii → gmii_rx_mac(自算 FCS) → udp_rx_parser → frame_reasm → dc_fifo(BRAM CDC) → axi_frame_saver64 → ddr_bank_commit`（来源：`src/rtl/eth/eth_udp_video_top.v:3`）。本节按拍走这条链，并逐级交代缓冲深度与"为什么是这个深度"。展开各模块内部实现见 `ARCH/A2-ingress-datapath.md` 与 `ARCH/A3-framebuffer-and-ddr.md`，本节只关心相位与深度。

### 2.0 一拍 = 哪个时钟

入流侧有两个时钟：`gmii_rx_clk`（RGMII 恢复出的 125 MHz，`gmii_rx_clk` 与 `gmii_tx_clk` 在本工程里是同一根，来源：`src/rtl/eth/eth_udp_video_top.v:5`）与 `axi_clk`（HP0 的 100 MHz）。下面标"125 拍"的计数单位是前者，标"100 拍"的是后者。

### 2.1 RGMII / GMII 侧（125 拍域，无缓冲）

RGMII 是 DDR + 4 bit，一个 GMII 字节要 2 个 `eth_rxc` 周期；`gmii_to_rgmii` 只做串并化，不带 FIFO（来源：`src/rtl/eth/gmii_to_rgmii.v` 全文 52 行，模块内无存储阵列）。`gmii_rx_mac` 在这一级逐字节自算 FCS-32，产生真正的 `p_good`：RGMII 只有 4 数据 + 1 控制、板上没有 `RX_ER` 这根线，早期版本 `p_good` 只能硬接 1，"坏包"统计是构造性为 0 的死数字（来源：`src/rtl/eth/eth_udp_video_top.v:155`—`157`），现在接的是 `udp_rx_parser` 出来的真值（来源：`src/rtl/eth/eth_udp_video_top.v:238`）。

### 2.2 `frame_reasm`：头部 4 拍 + 每 2 字节 1 拍

`udp_rx_parser` 直接把 UDP payload（4 字节偏移头 + 像素字节）交给 `frame_reasm`，边界由 `p_sof`/`p_eof` 给出——V7.9.6 之前要用"上一个字节没到、这一字节到了"自己凑 sof，parser 给边界后那段推导删掉了（来源：`src/rtl/eth/eth_udp_video_top.v:225`—`226`）。

偏移头是小端 4 字节，状态机 `S_OFF0`→`S_OFF3` 逐字节填 `off`，第 4 拍同时把整字 `hdr = {p_data, off[23:0]}` 结算为 `pkt_start` 与 `pend`（来源：`src/rtl/eth/frame_reasm.v:126`—`132`）。也就是说一个包在拼像素之前先吃掉 4 个 125 拍（收侧无缓冲，这 4 拍纯流水准备）。

`S_DATA` 之后是 2 字节拼 1 个 16 bit 字：第一个字节进 `pix_lo`、`have_lo<=1`，第二个字节那拍才出 `wr_data<={p_data,pix_lo}`、`wr_addr<=off[18:1]`、`off<=off+2`（来源：`src/rtl/eth/frame_reasm.v:141`—`163`）。所以本级的"缓冲"只有 1 个 8 bit 寄存器 `pix_lo` + 1 位 `have_lo`——深度 2 字节，刻意不做深：拼接是纯组合对齐问题，深缓冲只会把丢字从"看得见"变成"看不见"。

写入与行覆盖共用同一个上界门（#201）：`wr_en <=(off < FRAME_BYTES)`，越界包原本能把字写到帧缓存之外，因为 `off[18:1]` 最大 131071 而一帧只有 153600 字节 = 76800 个字（来源：`src/rtl/eth/frame_reasm.v:144`—`152`）。

### 2.3 验收门：三级 AND，深度全在 5×64 位行图上

`frame_done` 需要三个条件同时成立：`rows_hit >= IMG_H && bytes_ok && !bad_frame`（来源：`src/rtl/eth/frame_reasm.v:182`）。只用行图会放过"整行丢包"——一个从没写过的 BRAM 字是 0，流停住后就在屏上留一条黑纹（来源：`src/rtl/eth/frame_reasm.v:178`—`181`）。

行图不是 300 bit 的独热比较，而是 5 个 64 bit bank：`rok0..rok4`，`IMG_H=300 <= 320`（来源：`src/rtl/eth/frame_reasm.v:75`—`81`）。原因是"这一字节开启新行"那根网原本驱动全部 300 个覆盖 FF 加 16 个 `rows_hit` FF，r106 布线后报告显示扇出 316，最后这一跳独占 6.879 ns 数据路径里的 1.980 ns，布线占比 81.2 %（来源：`src/rtl/eth/frame_reasm.v:76`—`78`）。分行后每个 bank 最多 64 个负载、行计数器的使能只 16 个（来源：`src/rtl/eth/frame_reasm.v:78`）。bank 数写死在 5，`IMG_H` 一旦超过 320 行覆盖就记丢、`frame_done` 永不成立，仿真里 `initial` 当场 `$error`（来源：`src/rtl/eth/frame_reasm.v:217`—`219`）。

`rows_hit` 与 `off / ROW_STRIDE` 一起构成第二处"深度即正确性"的坑：行号必须走 32 bit 除法，不能用 `off[16:1]`——16 bit 像素索引会截断约 172/300 行，导致 `frame_done` 永不成立、SRC1 全黑（来源：`src/rtl/eth/frame_reasm.v:84`—`87`）。

字节计数在 v5.1 从三操作数 32 bit 加式（`cover + pkt_pay + 1 >= FRAME_BYTES`）改成两个饱和计数 `cov`/`pend` + 常量比较，因为那一个加法器独占本 125 MHz 分组全部十条最差路径，WNS +0.499（来源：`src/rtl/eth/frame_reasm.v:5`—`7`）。注意这里"改成饱和"无损：单调计数下 `cov + 1 >= FRAME_BYTES` 与 `== FRAME_BYTES` 是同一个问题（来源：`src/rtl/eth/frame_reasm.v:52`—`54`）。

### 2.4 CDC：8192 条 36 bit BRAM

`frame_reasm` 的字与 flush 标记合成 36 bit 送 `dc_fifo`：`{1'b0, addr[18:0], data[15:0]}` 或 `{1'b1, 19'd0, 16'd0}`，写使能 `cdc_wr = (fb_wr_en || reasm_flush || flush_pend) && !fifo_full`，其中 `flush_pend` 保证同拍的 flush 不丢（来源：`src/rtl/eth/eth_udp_video_top.v:263`—`270`）。

深度 `ADDR_W=13` → 8192 条 = 4096 个 64 bit 字 = 16 KB，`ram_style="block"`（来源：`src/rtl/eth/eth_udp_video_top.v:298`—`299`，`src/rtl/eth/dc_fifo.v:20`）。为什么是这个深度：够吸收"显示拷贝独占 HP0 一整个 V-blank"期间到达的入包数据，15 MB/s × 672 µs ≈ 1260 字，8192 条留了 3 倍余量（来源：`src/rtl/eth/eth_udp_video_top.v:296`—`297`）。为什么不能更浅：一个 1392 B 的包在 125 MHz 下是连续线速进来的，每包 698 个 16 bit 写；读侧曾限成"每 3 个 axi 周期取 1 条" = 66 MB/s < 125 MB/s，单包就能灌满 512 深的 CDC，稳定丢约 46 % 的字，屏上是"每隔一个 16 bit 空洞"的黑纹（来源：`src/rtl/eth/eth_udp_video_top.v:258`—`261`）。现在 1 条/周期 = 200 MB/s。

跨域机制只有格雷码指针：二进制指针永不跨域，`wgray`/`rgray` 各在对方域打两拍（来源：`src/rtl/eth/dc_fifo.v:81`—`95`），满判据用当前写指针而不是下一个（#105 第二刀，r88），副作用是可用深度从 DEPTH−1 变 DEPTH，由 `sim/tb_cdc_capacity` 的 C1 钉住，改前 8191、改后 8192（来源：`src/rtl/eth/dc_fifo.v:40`—`44`）。同一段还记着第一刀的失败读数：给 `wr_full` 加 `max_fanout=12` 后 WNS 从 r81 的 −0.062 掉到 −0.192、失败端点 28 → 34，注释点名的是 r83 那一轮的门禁件与同一轮的 timing_summary（后者在盘上、前者已不在，登记进 §8 第六条）（来源：`src/rtl/eth/dc_fifo.v:37`—`39`）——详见 §7。四颗同步 FF 打 `ASYNC_REG`，注释写"改前 A2 RED missing=2"，并点名一支扫描器与一份扫描件；这两件在盘上都不存在（本卷数过：`git ls-files` 与 `ls build/evidence/` 都没有这两个名字），所以这条读数按**注释转述**记，不当盘上凭据（来源：`src/rtl/eth/dc_fifo.v:23`—`27`）。

### 2.5 CDC 之后：3 拍寄存器延迟

`axi_clk` 侧读出后有一串 1 拍级联：`fifo_rd <= !fifo_empty && !sv_full`，然后 `cdc_d1`/`cdc_d1_v`，再 `sav_en`/`sav_flush`/`sav_a`/`sav_d`（来源：`src/rtl/eth/eth_udp_video_top.v:312`—`320`）。即"条目离开 FIFO 到打包器看到"要 2 个 100 拍，读请求本身再 1 拍。反压来源 `sv_full` 是打包器 FIFO 满（来源：`src/rtl/eth/eth_udp_video_top.v:256`），所以这条链上唯一的丢字通道就是 CDC 满，`link_monitor` 把 `cdc_wr_req && fifo_full` 做成可读数（来源：`src/rtl/eth/eth_udp_video_top.v:283`—`288`）。

### 2.6 `axi_frame_saver64`：512 深分布式 RAM 打包 + 8 在途 beat

打包器 FIFO 是 `FW=9` → 512 条 `{addr[31:0], data[63:0], keep[3:0]}`，显式 `ram_style="distributed"`（来源：`src/rtl/eth/axi_frame_saver64.v:10`—`13`，`48`—`50`）。深度 512 的依据不是吞吐而是资源：早先它被综合成触发器，512×100 bit ≈ 5.1 万 FDRE，占整机 Slice Register 的 94 %，`FW=11` 直接 DRC UTLZ-1；分布式 RAM 只要约 800 个 LUT-RAM（来源：`src/rtl/eth/axi_frame_saver64.v:11`—`13`，`46`—`47`）。存储写必须独占一个不带异步复位的 always 块，否则 Vivado 报 Synth 8-7186 拒绝推断 RAM，实测 task 写法 FF=32904/LUTRAM=0，本写法 FF=85/LUTRAM=864（来源：`src/rtl/eth/axi_frame_saver64.v:104`—`107`）。

打包本身是"当前 64 bit 字的 4 个 16 bit lane 哪些已有数据"：`cur_keep` 按 `wr_addr[1:0]` 选 lane，索引变化或 flush 时把 `cur_*` 推 FIFO（来源：`src/rtl/eth/axi_frame_saver64.v:122`—`140`，`101`—`102`）。写选通按 lane 展开 `{ {2{keep_r[3]}}, ... }`（来源：`src/rtl/eth/axi_frame_saver64.v:83`—`84`）；旧实现恒 `8'hFF`，分包长度不是 8 的倍数（如 1396）时每帧 111 处 = 222 个 16 bit 黑洞，屏上均匀散布的黑点（来源：`src/rtl/eth/axi_frame_saver64.v:80`—`82`）。

AXI 侧 `AWLEN=0`、`AWSIZE=3'b011`、`INCR`、`WLAST` 恒 1（来源：`src/rtl/eth/axi_frame_saver64.v:40`—`44`）。流水化的关键常数是在途上限 `OST = 4'd8`（来源：`src/rtl/eth/axi_frame_saver64.v:66`），装载条件 `have = (rptr != wptr) && !beat && (outst < OST)`（来源：`src/rtl/eth/axi_frame_saver64.v:74`），`m_axi_bready` 恒 1 即 B 永不反压（来源：`src/rtl/eth/axi_frame_saver64.v:156`）。为什么必须流水化：v6.2 之前每字走 `S_AW→S_W→S_B`，在途深度恒 1，HP0 写延迟约 40 拍（被显示拷贝抢端口时上百拍）直接成为吞吐上限，约 20 MB/s，板上表现是"每包固定从第 48 字节起丢字"（来源：`src/rtl/eth/axi_frame_saver64.v:5`—`6`）。为什么加深缓冲治不了它：瓶颈是平均排空速率不是深度，v6.2 把 CDC 做到 8192 时上板毫无改善（来源：`src/rtl/eth/axi_frame_saver64.v:7`）——见 §7。

`outst` 只减不回绕：万一上游多回一个 B，回绕成 15 会让 `have` 永不成立，整条入包链就此卡死（来源：`src/rtl/eth/axi_frame_saver64.v:158`—`160`）。

### 2.7 入流侧深度总表

| 级 | 介质 | 深度（字/条目） | 时钟 | 一拍宽度 | 容量上限的凭据 |
|---|---|---|---|---|---|
| RGMII 并化 | 无（组合/单拍） | 0 | 125 MHz | 4 bit DDR | `gmii_to_rgmii.v` 全文无阵列 |
| 字节→16 bit 字 | 触发器 | 2 字节（`pix_lo`+`have_lo`） | 125 MHz | 1 拍/2 字节 | `frame_reasm.v:141`—`143` |
| 行覆盖图 | 触发器 | 5×64 = 320 行 | 125 MHz | 每拍 1 bit | `frame_reasm.v:81` |
| CDC | BRAM | 8192 条 × 36 bit = 16 KB | 125→100 MHz | 1 条/拍 | `eth_udp_video_top.v:298` |
| 打包器 | 分布式 RAM | 512 条 × 100 bit | 100 MHz | 1 条/拍 | `axi_frame_saver64.v:10`—`13` |
| AXI 在途 | 寄存器 | 8 beat（`OST`） | 100 MHz | 8 B/beat | `axi_frame_saver64.v:66` |

稳态速率核算：AXI 侧 ≤2 拍/字 = 400 MB/s（来源：`src/rtl/eth/axi_frame_saver64.v:3`），CDC 出流 200 MB/s（来源：`src/rtl/eth/eth_udp_video_top.v:262`），入流线速 = 125 MHz × 2 B = 250 MB/s 峰值但一帧只有 307200 B（`IMG_W*IMG_H*2`，来源：`src/rtl/eth/eth_udp_video_top.v:235`），所以整条链的最窄处是 CDC 出口的 200 MB/s，而不是 DDR。

## 3. 一帧到一屏：出流侧逐拍

出流侧的模块顺序：消隐期搬帧（`axi_frame_writer_gated`）→ 帧缓存读口（`fb_bilin`/`tap_sched`）→ 几何映射 → 六级效果链（`proc_pipeline`）→ 行环 + skid → `split_display` 混色 → `osd_overlay` → `rgb2dvi`（TMDS）。出流侧内部相位见 `ARCH/A4-geometry-internals.md`、`ARCH/A5-effect-chain-internals.md`、`ARCH/A6-osd-and-hdmi-output.md`。

### 3.1 三个频率：50 / 250 / 100 / 125

一颗 MMCM 从 50 MHz 输入出三路：`CLKOUT0_DIVIDE_F=20.000` → 50 MHz 像素钟，`CLKOUT1_DIVIDE=4` → 250 MHz 5x，`CLKOUT2_DIVIDE=5` → 200 MHz IDELAY 参考；VCO = 50 × 20 = 1000 MHz（来源：`src/rtl/clocks/clk_gen.v:2`—`3`，`19`，`21`—`28`）。`tap_sched` 明确写它吃的是 `clk_pix5x`，与 `clk_pix` 同一个 MMCM、同相、整数 5:1（来源：`src/rtl/process/bilin/tap_sched.v:8`）。另外两域是 PS 侧的 `fclk0` = 100 MHz（`axi_clk`）与 PHY 恢复的 125 MHz（`gmii_rx_clk`）。

面板时序 1024×600，H_TOTAL 1344、V_TOTAL 625，活动 1024/600（来源：`src/rtl/top/pl_video_top.v:397`—`399`，`446`）。一帧 = 1344 × 625 = 840000 个 50 MHz 像点周期。

### 3.2 消隐期搬帧：67200 个 axi 拍的窗口

整帧只在 V-blank 内拷贝（v6 ATOMIC SWAP）：V_TOTAL 625 − active 600 = 25 空白行 = 33.5k 像点周期 = 67k 个 axi(100 MHz) 周期，而一帧是 38.4k 个 64 bit 字，所以拷贝在第一行活动像素被画出来之前就结束，显示 BRAM 在每个可见行上持有一份完整帧（来源：`src/rtl/top/pl_video_top.v:392`—`396`）。窗口判据 `disp_quiet = (y >= DISP_V_LINES) && ((y < DISP_V_LAST) || (x <= VB_X_GUARD))`，`VB_X_GUARD = 12'd1279` = H_TOTAL(1344) − 65，早关 64 个消隐像点，因为 `allow_copy_axi` 过 `frame_commit_lock` 的 CDC 要晚这个窗口约 5 个像素拍（来源：`src/rtl/top/pl_video_top.v:399`—`401`）。

搬帧机是 DDR→BRAM 的读侧引擎 `axi_frame_writer_gated`，`start`/`allow_wr`/`abort` 全部由 `eth_mode`（= 仲裁判出的 `owner_eth`）门控（来源：`src/rtl/top/pl_video_top.v:454`—`460`）。总线归属由 `src_arb #(.T_OFF_CYC(2_000_000))` 决定，AXI 域 100 MHz ⇒ 20 ms 静默才让给 PS（来源：`src/rtl/top/pl_video_top.v:421`—`425`）。

超窗是可读数：`row_done && (row_copy_cycles > VBLANK_AXI_CYC)` 置粘滞位 `copy_overrun`，`VBLANK_AXI_CYC = 32'd67200`（来源：`src/rtl/top/pl_video_top.v:442`—`451`）。超出意味着换帧跨了两个消隐期，屏幕上同一帧新旧两半并存，运动物体被一条水平缝切开 + 拖影，用 `led[0]` 看（来源：`src/rtl/top/pl_video_top.v:443`—`444`）。

提交握手在 `frame_commit_lock`：`commit_req` 在 axi 域、`de`/`vsync`/`blank_safe` 在像素域，`copy_abort`/`abort_tgl` 回像素域（来源：`src/rtl/top/pl_video_top.v:430`—`440`）。`frame_ready` 现在是一拍脉冲而不是永久电平，因此 `#171` 把两支 always 换了顺序：abort 排在"刚提交"之前，万一提交沿与 abort 沿同拍（看门狗与 copy_done 同时到），赢的必须是"这一帧不可信"（来源：`src/rtl/top/pl_video_top.v:526`—`532`）。

### 3.3 读口：一个像素周期 5 个快槽

几何映射每请求一拍，`tap_sched` 在 250 MHz 上把一个像素周期切成 5 个快槽：右窗 4 个 RGB565 抽头 `p00/p10/p01/p11` + Q8 小数 `ofx/ofy`，左窗 1 个字号 → 1 个 64 bit 字 `aux_q` 与同拍 `aux_lane_q`；`vld` 落在下一周期 s1 那一拍（来源：`src/rtl/process/bilin/tap_sched.v:2`—`5`，`11`—`14`）。"4 + 1 恰好占满"的硬约束是不新增任何 BRAM：同一组阵列上再加一个逻辑读口实测把帧缓存从 80 块 RAMB36 顶到 160 块，全片才 140（来源：`src/rtl/process/bilin/tap_sched.v:12`—`13`，同一句话在 `src/rtl/top/pl_video_top.v:777`—`778` 独立记了一次）。地址摆出后帧缓存数据延迟 1 个快周期（来源：`src/rtl/process/bilin/tap_sched.v:35`）。

`fb_bilin` 对外形状与旧的 `rd_addr_q + frame_buffer_w64` 逐位同深（请求 → 2 拍到数据），所以顶层的打拍束没动（来源：`src/rtl/top/pl_video_top.v:721`—`722`）。暂存/结果缓冲索引必须是显示列对号而不是源列 `sx`：旋转时 `sx` 沿一行会停滞/倒退，用 `sx` 当地址会让同一个格子被别的源行重写，结果是满屏噪点（来源：`src/rtl/top/pl_video_top.v:745`—`746`）。顶层送进去的 `jd(x_d[2][9:1])`、`req_vld(de_d[2])` 站在第 2 级，第一版接的是 `[3]`，导致地址与列奇偶错一拍、"每源像素的 4 拍"跨到相邻源像素，屏上四分之一格子错列（来源：`src/rtl/top/pl_video_top.v:742`，`747`—`749`）。

### 3.4 效果链：`LATENCY = 15`，且它是唯一的定义处

六级效果由 `stage_sel` 的位选：`[0]` 灰度、`[1]` 反色、`[2]` 均值模糊、`[3]` 锐化、`[4]` Sobel、`[5]` 二值 + `[6]` 极性、`[7]`/`[8]` 腐蚀/膨胀互斥（两位同时为 1 时都不做，因为开/闭要两遍 3×3 窗口而这里只有一遍）（来源：`src/rtl/process/proc_pipeline.v:52`—`60`）。

链子的固有延迟 `parameter integer LATENCY = 15`，声明的是本模块固有延迟、不许外部覆盖；级 0 的 gamma 是分布式 RAM 组合读出不占拍，谁改成寄存读出 LATENCY 必须同时改成 16（来源：`src/rtl/process/proc_pipeline.v:20`—`22`）。顶层不再抄字面量：`localparam PROC_LAT = u_pipe.LATENCY`、`LEFT_TAIL = PROC_LAT`（来源：`src/rtl/top/pl_video_top.v:816`—`817`），以前这里是字面量 7，于是"链上加一级"必须同时记得改这里，忘了不是编译错而是左窗与右窗错开 N 个像素；`tb_v86` 的 T2 实测 `de_in→de_out` 与 LATENCY 对账，两处任一处漂移就有测试可红（来源：`src/rtl/top/pl_video_top.v:812`—`815`）。

链子的"一行"宽度是显示列 1024 而不是源列 512：`proc_pipeline #(.H_ACTIVE(2*IMG_W))`（来源：`src/rtl/top/pl_video_top.v:800`）。代价写死在注释里且不许算作免费：行缓存宽度翻倍（约 +8 块 BRAM），而且 3x3 滤波的空间尺度从源像素变成显示像素（横向覆盖 1.5 个源列），横方向的模糊/边缘比旧版略宽（来源：`src/rtl/top/pl_video_top.v:796`—`799`）。

链子天生滞后 `OFF_LINES = 4` 行，顶层用提前读坐标补偿：`pipe_off_rows` 输出 = `OFF_LINES`（来源：`src/rtl/process/proc_pipeline.v:25`—`27`，`44`，`48`），帧缓存是随机地址的，把右窗读坐标对应的显示行提前 OFF_LINES 行。

### 3.5 混色级 `MIX_D = 20`：两个抽头必须同深

混色发生的级数 `localparam MIX_D = 3 + 1 + 1 + u_pipe.LATENCY`（来源：`src/rtl/top/pl_video_top.v:354`），即 3 + 1 + 1 + 15 = 20 级，与"3(`cx/cy` 打到 mapper 与左路的打拍) + 1(`rd_addr_q`) + 1(BRAM 读出) + PROC_LAT = 20 级"同一条账（来源：`src/rtl/top/pl_video_top.v:352`—`353`）。打拍束宽度 `SB = (MIX_D > 16) ? (MIX_D + 1) : 16` = 21（来源：`src/rtl/top/pl_video_top.v:355`）。

原图抽头走一条行环：`raw_line_delay #(.LINES(RAW_LINES), .W(2*IMG_W), .DW(17))`，`RAW_LINES = u_pipe.OFF_LINES`（来源：`src/rtl/top/pl_video_top.v:781`，`788`—`791`）。补偿方式不是再开一个读口，而是把原图抽头整体延后 OFF_LINES 个显示行：第 r 行写进去的内容是源行 `(r+OFF)>>1`，第 r+OFF 行读出来，落在显示行 r+OFF 上，而那一行要的正是它，列号由环按 x 寻址一格都不偏（来源：`src/rtl/top/pl_video_top.v:776`—`780`）。环在 `de_d[5]/x_d[5]/y_d[5]` 这一级取样（来源：`src/rtl/top/pl_video_top.v:790`）。

环之后再做 15 拍 skid（`orig_skid[0] <= raw_ring[15:0]`，循环到 `LEFT_TAIL`）：行与列都才对得上（来源：`src/rtl/top/pl_video_top.v:840`—`845`）。#92 第一笔记的就是"两个抽头必须同深，否则缝上错开一整列"：原图那一路 = `raw_line_delay`(1 拍 RAM 读出) + `orig_skid`(PROC_LAT 拍) = PROC_LAT+1 拍，而链子自己只有 PROC_LAT 拍 ⇒ 处理抽头比原图早一整拍 = 混色级早一整列；1.00x 时铺满整屏看不出，一缩小左边界就把画面最左那列甩进背景带。凭据 `tb_v98` 的 C1c 与 C2：在 inv=512 与 inv=1023 两档都量到"内容左右沿 = 定义左右沿 − 1"，恒为一列不随倍率变，所以是整拍之差而不是取整偏差（来源：`src/rtl/top/pl_video_top.v:819`—`824`）。修法是给处理抽头补一拍 `pipe_dout_q`（来源：`src/rtl/top/pl_video_top.v:825`—`829`）。

#92 第三笔：越界标签与像素打包过同一条环（环宽 `DW(17)` = `{oob_raw, pix_raw}`）。以前 `pix_raw` 过环而 `oob_raw` 绕开环只走等长 skid ⇒ 到混色级两者差 (4 行, 1 列)：画面右沿最后一列被别的格子的越界位按黑，上边缘有东西闪。17 位仍在 RAMB36 的 18 位宽度模式里，所以 BRAM 一块不多要，而这句要在 utilization.rpt 上核、不许停在注释（来源：`src/rtl/top/pl_video_top.v:782`—`785`，`841`）。

`split_display` 拿的整束标签必须与像素同一级：`.x(x_d[MIX_D]), .y(y_d[MIX_D]), .de(de_d[MIX_D]), .hs(hs_d[MIX_D]), .vs(vs_d[MIX_D]), .x_sel(x_d[MIX_D])`（来源：`src/rtl/top/pl_video_top.v:919`—`920`）。#92 第二笔的记录：r59b 修 #68 时只把选路的 `x_sel` 提到 `MIX_D`，而 `x/y/de/hs/vs` 留在第 11 级 ⇒ 面板上的 `de` 比同一拍的像素早 9 列（MIX_D − 11），屏上最左 9 列画的是上一行末尾那 9 格，最右 9 列落进消隐丢掉，而 OSD 一格都不动（它的 x/y 与 de 同源、跟着一起错）——三条观察同一件事。凭据 `tb_v98` 的 C3/C3a（来源：`src/rtl/top/pl_video_top.v:913`—`918`）。

缝的位置由 `split_ctrl` 算，`seam_src #(.TAPS(SEAM_TAPS))`，`localparam integer SEAM_TAPS = MIX_D + 1 - 3`，因为内容站在 `x_d[MIX_D]` 那一拍而 `sx` 是 mapper 第 3 级输出 ⇒ 从 `sx` 到混色级要走 MIX_D+1−3 拍；TAPS 由流水线深度推出来、不抄字面量（来源：`src/rtl/top/pl_video_top.v:899`—`908`）。

### 3.6 OSD：最后一级，比输入晚 2 拍

`osd_overlay` 是像素通路最后一级，叠 5 行状态文字（尺寸/FPS/片源、Pipe/Th/Gamma、Rot/Zoom、Split/Latency、Temp/无信号），输入 `x/y/de` + 背景 `r_in/g_in/b_in`，输出叠字后的 RGB 与 de/hs/vs，比输入晚 2 拍，内容与坐标仍同一拍（来源：`src/rtl/video/osd_overlay.v:2`—`5`）。字格账：`CHAR_W = 18`（5*3+3 gap）、`CHAR_H = 21`（7*3）、`LINE_GAP = 10`、`N_LINES = 5`，高度 5×(21+10) = 155 px < 600（来源：`src/rtl/video/osd_overlay.v:11`—`19`）。顶层递进来的是面板那份 `OUT_W(2*IMG_W)`/`OUT_H(2*IMG_H)`，与 `proc_pipeline.H_ACTIVE`、`raw_line_delay.W` 同一个 ×2 关系，屏上画的数与真实扫描的列/行数同源（来源：`src/rtl/video/osd_overlay.v:22`—`26`，`src/rtl/top/pl_video_top.v:999`）。OSD 单域 clk_pix 50 MHz，`lat_ms` 由 axi 域按翻转位跨进来（`snap_cross`），`temp_disp` 是 PS 侧算好的两位十进制 BCD（来源：`src/rtl/video/osd_overlay.v:7`—`8`）。

### 3.7 TMDS：8b/10b + 10:1 OSERDESE2

`u_dvi` 与面板吃同一份 RGB888+同步（来源：`src/rtl/top/pl_video_top.v:4`，`1026`）。每通道 encoder 做 8b/10b：`ones()` 数 1 的个数，`use_xnor = (n1 > 4'd4) || (n1 == 4'd4 && din[0] == 1'b0)`（来源：`src/rtl/hdmi/tmds_encoder.v:13`—`20`），输出 10 bit。串行化是 10:1 级联，`DATA_WIDTH=10` 要求 `DATA_RATE_OQ("DDR")`，Master D1-D8 + Slave D3/D4，Slave `SHIFTOUT` → Master `SHIFTIN`（来源：`src/rtl/hdmi/tmds_serializer.v:2`—`4`，`16`—`20`），时钟对是 `clk_pix`/`clk_pix5x`，即 50 MHz 与 250 MHz 严格同相 5:1（来源：`src/rtl/hdmi/tmds_serializer.v:6`—`7`，`src/rtl/clocks/clk_gen.v:2`）。

### 3.8 出流侧级间相位总账

| 段 | 起点 → 终点 | 拍数 | 时钟 |
|---|---|---|---|
| 消隐搬帧窗口 | `disp_quiet` 起 → 首行活动 | 67200 axi 拍（来源：`pl_video_top.v:446`） | 100 MHz |
| 早关窗口 | `VB_X_GUARD` | 1344−1279 = 65 像点（来源：`pl_video_top.v:399`） | 50 MHz |
| `allow_copy` 同步 | axi → pix | 2 拍 + 约 5 像点（来源：`pl_video_top.v:399`，`549`） | 跨域 |
| 读口 | 请求 → `vld` | 1 像素周期（5 快槽）+1 拍（来源：`tap_sched.v:4`） | 250/50 MHz |
| 效果链 | `de_in` → `de_out` | 15（来源：`proc_pipeline.v:22`） | 50 MHz |
| 原图路 | 环 4 行 + 1 拍 + 15 拍 skid | 与链同深（来源：`pl_video_top.v:840`） | 50 MHz |
| 混色级 | `x_d[0]` → `x_d[MIX_D]` | 20（来源：`pl_video_top.v:354`） | 50 MHz |
| OSD | 输入 → 输出 | 2（来源：`osd_overlay.v:4`） | 50 MHz |
| 并化 | 8b/10b + 10:1 | 2 拍编码 + 10 快槽（来源：`tmds_encoder.v:20`—`23`，`tmds_serializer.v:2`） | 50→250 MHz |

## 4. 一条命令的完整旅程

以最常用的一条为例：串口敲 `pipe 010000000`（开灰度级）到 `stage_sel[0]` 驱动 `proc_gray` 的那一 mux。

### 4.1 字节进 PS：轮询，不是中断

UART 器件是 `xuartps.h`（来源：`src/ps/main.c:30`），波特率在开机串里写明 115200（来源：`src/ps/main.c:1572`）。接收是主循环轮询：`while (1) { uart_poll(); ... }`（来源：`src/ps/main.c:1587`—`1588`），`uart_poll()` 第一件事是 `rx_fill()`（来源：`src/ps/main.c:1431`），而 `rx_fill()` 用 `XUartPs_IsReceiveData(STDIN_BASEADDRESS)` 逐字节搬（来源：`src/ps/main.c:1480`）。分工是硬的：`rx_fill()` 只把人来的字节搬进 `cmd_buf`、顺手回显，不切不派发；派发在主循环的 `uart_poll()`（来源：`src/ps/main.c:308`—`312`）。这样设计的原因是长流程（例如 gamma 表 256 项要写约 2.6 ms）里反复调 `rx_fill()` 而不派发，避免中途改参数造成重入（来源：`src/ps/main.c:412`，`1511`—`1513`）。

缓冲是 `static char cmd_buf[CMD_BUF]` 配 `cmd_len`（来源：`src/ps/main.c:312`—`313`）。CR/LF 在存入时归一成 `'\n'`，所以"按行切"与终端换行风格无关（来源：`src/ps/main.c:1476`—`1477`，`1457`）。

### 4.2 残包与半行：时间基在 PS 侧

每圈主循环比较 `XTime_GetTime(&now)` 与 `rx_t`，`(now - rx_t) * 1000 >= RX_IDLE_MS * COUNTS_PER_SECOND` 判超时（来源：`src/ps/main.c:1435`—`1437`）。超时不整段清空，而是先扫最后一个 `'\n'` 算出 `keep`，只丢"行尾之后"的残段，写完的行照旧执行（来源：`src/ps/main.c:1439`—`1445`）。提示语改成 ASCII 打头，因为中文提示在 cp936/GBK 的 Windows 控制台里渲染不出来、看着就是一长串空白（来源：`src/ps/main.c:1441`—`1443`）。

### 4.3 切词与派发

按行首 `'\n'` 一条条切出来，`cmd_buf[n-1] = 0` 把行尾换成语义上的 0，`tokenize()` 出 `tk[]`，`dispatch(tk, nt) < 0` 才打 `[CMD] 不认` 并 `cmd_help()`（来源：`src/ps/main.c:1466`—`1469`）。一次可以攒下好几行（粘贴或长流程连发），所以是 `for(;;)` 循环逐条派发（来源：`src/ps/main.c:1456`）。位序解析入口一例：`else if (strict_int(arg, &v)) cmd_src(v);`（来源：`src/ps/main.c:928`）。

### 4.4 寄存器写：两个字、各一次 `Xil_Out32`

`ctrl_write()` 先组 `GPIO_DATA`：`v = ((u32)cur_thr << 8) | ((u32)cur_src << 16) | ((u32)(cur_zoom ? 1 : 0) << 17) | (pub_lvl << PUBLISH_BIT) | ((u32)(cur_bilin ? 1 : 0) << BILIN_BIT) | ((u32)(cur_osd ? 0 : 1) << OSD_OFF_BIT) | ((cur_mode_ovr & 3u) << MODE_CODE_BIT) | (mode_tog_lvl << MODE_TOG_BIT);` 然后 `Xil_Out32(GPIO_DATA, v)`（来源：`src/ps/main.c:214`—`219`）。`AXI_GPIO_BASE` = `0x41200000`，`GPIO_DATA` = base+0x00（来源：`src/ps/main.c:48`—`49`）。低 5 位 `[4:0]` 是 V7 那五位效果的旧位置，保留但恒写 0，因为 BD 里 `gpio_o` 是 32 位整字，位序一改 `set_src.tcl`/`health_read.mjs` 这些按位写的工具就全错位（来源：`src/ps/main.c:210`—`211`）。

第二个字 `CFG_DATA0` = `0x41220000`（来源：`src/ps/main.c:77`—`78`）一次整字写：低 9 位效果选择 + `[28:26]` 缩放档 + `[29]` 手动旗标 + split 的 14 位与 V9 的 5 位（来源：`src/ps/main.c:223`—`226`）。这里有一条写在代码里的症状判据：`CFG_DATA0` 就是 RTL 的 `gpio_cfg1_o`，而 gamma 窗口是 `CFG_DATA1(+0x08)`，"两个名字差一位，写错字的症状恰恰是『设了没反应』，最容易误判成 PL 坏了"（来源：`src/ps/main.c:221`—`222`）。

开机时还会自测这条地址：往 `CFG_DATA0` 写 `1ff`/`780000` 读回比对，不对就打 `[CFG!]`——因为地址是硬编码的，位流里没有 `axi_gpio_2` 时不会有编译错误（来源：`src/ps/main.c:1519` 段的开机自测，见 `[CFG!]` 那条 `xil_printf`，来源：`src/ps/main.c` 中 `CFG!] %08x 写 1ff/780000 读回` 那一段）。

### 4.5 进 PL：AXI GPIO 的 GP0 是 100 MHz 侧，控制字在 `axi_clk`/`fclk0` 域被驱动

PS 写完后，`axi_gpio_2` 的输出寄存器在 PL 侧组合可用，但工程规定所有下游都必须按"异步"处理：`effect_ctrl` 的文件头写着它的两件活就是"AXI GPIO(GP0, 100 MHz) → 像素域(50 MHz)"的同步与"只有一套控制源"（来源：`src/rtl/process/effect_ctrl.v:2`—`7`）。

### 4.6 PL 侧同步拍数：2 拍（40 ns）到 `stage_sel`

`sel_meta`/`sel_sync` 是 13 bit 一条链：`{manual, zsel[2:0], stage[8:0]}`，两级 `(* ASYNC_REG = "TRUE" *)`（来源：`src/rtl/process/effect_ctrl.v:33`—`34`，`54`—`56`）。为什么三个字段并成一条而不是分组同步：PS 用一次整字写同时改 `stage_sel`/`zsel`/`manual`，而 `zoom_ctrl` 把 `manual` 与 `zsel` 当一对用（manual=1 时必须看见对应档号），分两组同步就会出现"旗标到了、档号还是上一次的"，那正是 #58/#59 一路在防的错拍（来源：`src/rtl/process/effect_ctrl.v:35`—`39`）。gamma 那 32 bit 同理一起过一对同步器，因为协议要求 `idx/data` 在 `wr` 翻转之前已稳定至少一次 AXI 写（来源：`src/rtl/process/effect_ctrl.v:41`—`45`）。`temp` 的复位值低字节是 `0xFF` 而不是 0——两位都不是十进制数字 = 还没有可信读数，OSD 据此画 `--`；复位成 0 会在 PS app 起来之前画出 `Temp:00C`，那是一条没人测过的数（来源：`src/rtl/process/effect_ctrl.v:48`—`52`）。

所以：一次 `Xil_Out32` 之后，`stage_sel` 在本域可见是 2 个 50 MHz 拍（来源：`src/rtl/process/effect_ctrl.v:54`—`55` 的两级链）；`proc_pipeline` 直接把 `w_gray = stage_sel[0]` 当 mux 使能（来源：`src/rtl/process/proc_pipeline.v:52`），于是这一位到 mux 生效的总深度就是这条 2 拍链加链子本身 15 拍（来源：`src/rtl/process/proc_pipeline.v:22`）——画面在下一行扫到该列时才必然带上新效果。

### 4.7 另外两条命令通道：3 拍与"帧沿采"

`src_sel` 走 3 级同步：`(* ASYNC_REG = "TRUE" *) reg ss0, ss1, ss2`，`{ss2,ss1,ss0} <= {ss1, ss0, src_sel}`，`wire src_sel_pix = ss2`（来源：`src/rtl/top/pl_video_top.v:471`—`476`）。OSD 总开关 `osd_off_axi` = `gpio_o[20]`（反相，1 = 关掉叠层）也走独立 3 级同步得 `osd_en = ~oo2`（来源：`src/rtl/top/pl_video_top.v:38`，`263`—`275`）。

宽总线（分割位置等 19 位）不是同步器而是快照握手：源域每 ~1.3 ms 整拍抄一次总线并翻 toggle（`sp_ref == 17'h1FFFF` 时 `sp_bus <= split_ctl; sp_tog <= ~sp_tog`，来源：`src/rtl/top/pl_video_top.v:865`—`875`），目的域用 `snap_cross #(.W(19), .DST_HZ(50_000_000), .HB_TO_MS(200))` 等 3 级同步过来的跳变沿再采一次，源总线至少保持到下一次写入（本项目 ≥1 ms）所以采到的一定是完整值（来源：`src/rtl/top/pl_video_top.v:876`—`880`，`src/rtl/eth/snap_cross.v:2`—`6`）。

发布脉冲（`pub`）走翻转位 + 帧沿消费：`wire pub_consume = frame_start && src_use && !owner_eth_pix`（来源：`src/rtl/top/pl_video_top.v:559`），握手单独成模块好被 `sim/tb_ps_publish.v` 逐相位验（来源：`src/rtl/top/pl_video_top.v:556`—`558`）。ETH 拥有搬运机时 PS 的发布不被消费，`pend` 留着等轮到 PS 那一帧（来源：`src/rtl/top/pl_video_top.v:514`—`515`）。

### 4.8 命令延迟账

| 段 | 深度 | 凭据 |
|---|---|---|
| UART 字节 → `cmd_buf` | 主循环一圈（轮询） | `main.c:1480` |
| 行完整 → `dispatch` | 1 圈 `uart_poll` | `main.c:1458`—`1466` |
| `dispatch` → `Xil_Out32` | 组合调用链 | `main.c:219`，`223` |
| AXI GPIO 输出寄存器 | PS AXI 写，非 RTL 计拍 | `main.c:48`—`78` |
| 100 MHz 侧 → 50 MHz 侧（控制字） | 2 拍 = 40 ns | `effect_ctrl.v:33`—`34` |
| 100 MHz 侧 → 50 MHz 侧（单电平位） | 3 拍 = 60 ns | `pl_video_top.v:471`—`476` |
| 宽总线快照 | 1.3 ms 整拍抄 + 3 级同步 + 1 采 | `pl_video_top.v:865`—`880` |
| 生效到像素 | 链 15 拍 + 混色 20 级 | `proc_pipeline.v:22`，`pl_video_top.v:354` |

## 5. 跨时钟域与数据/控制边界的完整清单

本节只给"谁跨、怎么跨、被什么兜住"的名册。同步器的内部波形与逐拍分析在 `ARCH/A2-ingress-datapath.md`（CDC FIFO 一侧）与 `ARCH/A9-constraints-timing-verification.md`（约束与 WNS 一侧），此处不重复展开。

### 5.1 四个时钟组

`set_clock_groups -asynchronous -group [get_clocks eth_rxc] -group [get_clocks -quiet clk_fpga_0] -group [get_clocks -include_generated_clocks sys_clk]`（来源：`src/constraints/clock_groups_impl.xdc:28`—`31`）。三组分别是 125 MHz `eth_rxc`（周期 8.000 ns）、100 MHz `clk_fpga_0`（10.000 ns）、由 `sys_clk` 派生的 50 MHz `clkout0_1`（20.000 ns）与 250 MHz `clkout1_1`，周期数值来自 `build/timing_summary.rpt` 的 Clock Summary（来源：`src/constraints/r114_io_async.xdc:55`）。

两条写死在约束里的坑：`-include_generated_clocks` 不能省——少了这个后缀 `clk_pix` 会被当成独立时钟去和 `eth_rxc` 做 setup 分析，历史上是 WNS≈−6.7 的假违例，issues.md #18（来源：`src/constraints/clock_groups_impl.xdc:16`—`17`）。`clk_pix` 与 `clk_pix5x` 有意留在同一组内，同 MMCM、5:1、0° 相位，让 TMDS 并串转换按同步路径做 setup 分析，声明成异步反而会漏检（来源：`src/constraints/clock_groups_impl.xdc:25`—`26`）。约束对象名写错的后果也记着：`get_clocks` 取不到的名字会连带把 `eth_rxc`/`sys_clk` 那几组一起废掉，现场只留下一句 warning，`set_clock_groups` 的 CRITICAL WARNING [Vivado 12-4739] 就是这件事（来源：`src/constraints/rk_zynq7020.xdc:43`—`45`，`68`—`70`）。

### 5.2 跨域名册

`src/rtl` 里带 `ASYNC_REG` 的文件共 12 个（来源：`src/rtl/eth/dc_fifo.v`、`src/rtl/eth/ddr_bank_commit.v`、`src/rtl/eth/eth_udp_video_top.v`、`src/rtl/eth/snap_cross.v`、`src/rtl/process/effect_ctrl.v`、`src/rtl/process/rotate/angle_ctrl.v`、`src/rtl/top/pl_video_top.v`、`src/rtl/top/system_top.v`、`src/rtl/util/ps_publish.v`、`src/rtl/util/src_mode.v`、`src/rtl/video/frame_commit_lock.v`、`src/rtl/video/frame_latency.v`）。按机制分四类：

| # | 跨界内容 | 方向 | 机制 | 深度 | 兜它的约束 |
|---|---|---|---|---|---|
| 1 | CDC FIFO 格雷码指针（36 bit 数据过 BRAM） | 双向 `eth_rxc`↔`clk_fpga_0` | 格雷码 + 2FF | 2 拍（来源：`dc_fifo.v:81`—`95`） | `set_max_delay ... 10.000` / `8.000`（来源：`r114_io_async.xdc:57`—`59`） |
| 2 | DDR 帧提交事件（`frame_done` 等） | `eth_rxc`→`clk_fpga_0` | 翻转 + 3FF 边沿检测 | 3 拍 + XOR（来源：`clock_groups_impl.xdc:21`） | 同 #1 |
| 3 | 消隐窗 / `allow_copy`、`copy_abort` | `clk_pix`→`clk_fpga_0` 及反向 | 3 级像素 + 3FF；abort 走翻转式脉冲同步器 | 3 拍（来源：`clock_groups_impl.xdc:22`，`pl_video_top.v:482`—`489`） | `set_max_delay clkout0_1→clk_fpga_0 10.000`（来源：`r114_io_async.xdc:63`） |
| 4 | 控制字（`stage_sel`/`zsel`/`manual`、gamma 32 bit、`threshold`） | `clk_fpga_0`→`clk_pix` | 整字并链 2FF | 2 拍（来源：`effect_ctrl.v:33`—`34`） | `set_max_delay clk_fpga_0→clkout0_1 20.000`（来源：`r114_io_async.xdc:61`） |
| 5 | 单电平控制位（`src_sel`、`eth_link`、`osd_off_axi`、`owner_eth`、`eth_live`） | `clk_fpga_0`/`eth_rxc`→`clk_pix` | 3FF 电平同步 | 3 拍 = 60 ns（来源：`pl_video_top.v:471`—`522`） | 同 #4 |
| 6 | 宽总线（split 19 bit、健康快照、`lat_*`） | `clk_fpga_0`→`clk_pix` | 整拍抄 + toggle + `snap_cross` 帧沿采 | 1.3 ms 采样周期 + 3 级（来源：`pl_video_top.v:858`—`880`，`982`） | 同 #4 |
| 7 | 心跳（`hb_tog`） | 源域→目的域 | 间隔测量而不是边沿计数 | 3 级 `ts`/`hs`（来源：`snap_cross.v:36`—`40`） | 组排除 |

### 5.3 三条写在源码里的规矩

一、`eth_rxc` 与 `axi_clk` 之间只准过 `dc_fifo` 的格雷码指针与 `ddr_bank_commit` 的 3 级同步器，其余一律禁止组合跨域（来源：`src/rtl/eth/eth_udp_video_top.v:5`—`6`）。

二、脉冲不能用电平型同步器。`copy_abort` 在 `axi_clk` 上只有 1 拍（10 ns），电平型 3 级同步会整拍漏掉它，比裸采样更糟，所以要的是翻转式脉冲同步器 `abort_tgl`，链 = 3 级 + 异拍出沿，`wire copy_abort_pix = ab1 ^ ab2` 每次 abort 恰好一拍（来源：`src/rtl/top/pl_video_top.v:482`—`489`）。

三、准静态控制位同步后当电平用，不需要握手。`gapclr_sel` 是 `fclk0` 域的电平，进 `eth_rxc` 域必须先 3FF，与工程里 `src_sel`/`allow_copy` 同一套路；它是准静态控制位、不是脉冲（来源：`src/rtl/eth/eth_udp_video_top.v:275`—`281`）。

反例也记着：`eth_link` 是 `eth_rxc` 域的电平，原来在像素域被裸采样 4 处，而同一个文件里 `src_sel` 早就走了 3 级同步，一处对一处错，现在统一成 3 级，多 60 ns 对毫秒级的"链路断"不可见。证据只是行级的：`cdc.rpt` 里 `eth_rxc→clkout0_1` 那一行端点数 84→51、被标记 16→1，而这份报告不点名信号，所以它只能证明"这一类端点变少了"，逐信号凭据要写台架（来源：`src/rtl/top/pl_video_top.v:478`—`481`）。同类的一处真错：发布握手原来用 `src_sel`（`axi_clk` 域的未同步电平）而同文件里 `src_sel_pix` 早就存在，帧起始那拍采它会采到亚稳态（来源：`src/rtl/top/pl_video_top.v:557`—`558`）。

### 5.4 组排除的代价与补法（#266）

`set_clock_groups -asynchronous` 把三组钟两两排除，这四条跨域路在任何尺子里都不出现（`report/timing_global.md` §4c），也就是说"格雷码/翻转同步器最多跨几个周期"这件事没有任何约束兜着，全靠布线碰运气。UG949 的口径是同步器这类路不该完全 false path，应该给 `set_max_delay -datapath_only`，把数据路径限制在目的钟一个周期内、不参与时钟偏斜/不确定度的加倍计算，必要时再配 `set_bus_skew`。界值 = 目的钟周期，这不是收益声明，也不指望它改 WNS——组排除下的路本来就不进 WNS，所以"WNS 没动"是预期而不是证据，看的是名册里别的域没被挤、以及这四条界在 `report_exceptions` 里数得出条数（来源：`src/constraints/r114_io_async.xdc:46`—`54`）。

`set_bus_skew` 这一条仍然挂着：它需要点到同步器单元名，而 r114 的对象探针在 `get_false_paths` 上死了（该命令在本工具不存在），异常换成 `get_timing_exceptions` 之后若数不到对象，这一条就不写成已完成（来源：`src/constraints/r114_io_async.xdc:65`—`68`）——对应 §8。

### 5.5 数据/控制边界

数据面与控制面的分界只有一处：像素流走 `dc_fifo`(BRAM) → 打包器(分布式 RAM) → AXI，控制字一律走 AXI GPIO 的寄存器输出 + `ASYNC_REG` 同步器或 `snap_cross` 快照，两条路不共享任何 FIFO。`effect_ctrl` 的"只有一套控制源"是这条边界的另一半：V7 那五位 `effect_en` 的兜底合流与"反翻五位给 OSD"的第二出口已一起删（#66），留着它，`pipe 00111` 与 `pipe 000000111` 就是两种答案（来源：`src/rtl/process/effect_ctrl.v:5`—`7`，`28`—`29`）。同理 `dbg_src` 的 bit[10:8] 是"判决那一拍的 `{force_ps, ~eth_live, ~eth_tb_ok}`"，只有 bit2=0 时才有"为什么"的意思（来源：`src/rtl/top/pl_video_top.v:67`），像素域要的是仲裁结果而不是第二份判据，否则会出现"ETH 那一位还在说谎、SD 帧却永远不被消费"的死锁，板上的 STALL 钉在 9999 正是它（来源：`src/rtl/top/pl_video_top.v:512`—`515`）。

## 6. 失败模式表

只列仓库里有凭据的项。"现场判据"一栏给的是可回读的数或可见图形，出处为写该判据的文件行。

| # | 现象 | 根因 | 现场判据 / 可回读的数 | 是否已修（凭据） |
|---|---|---|---|---|
| F1 | 每包固定从第 48 字节起丢字 | 打包器每字走 `S_AW→S_W→S_B`、在途深度恒 1，HP0 写延迟约 40 拍（被抢端口时上百拍）成为吞吐上限 ≈20 MB/s | 上游 `link_monitor` 的 `cdc_wr_req && cdc_full` 计数（来源：`src/rtl/eth/link_monitor.v:105`、`src/rtl/eth/eth_udp_video_top.v:283`—`293`） | 已修：写通道流水化 + `OST=8`（来源：`src/rtl/eth/axi_frame_saver64.v:5`—`6`，`66`） |
| F2 | 加深缓冲无效（症状原样复现） | 瓶颈是平均排空速率不是深度 | 把 CDC 做到 8192 条后上板毫无改善（来源：`src/rtl/eth/axi_frame_saver64.v:7`） | 认知已入文档（ISSUES #32，来源同上）；深度只用于吸收 V-blank 独占（来源：`src/rtl/eth/eth_udp_video_top.v:296`—`297`） |
| F3 | 屏上"每隔一个 16 bit 空洞"的黑纹，与上位机速率无关 | 读侧限成每 3 个 axi 周期取 1 条 = 66 MB/s < 125 MB/s，单包把 512 深 CDC 灌满，稳定丢约 46 % 的字 | `fifo_full` 挡住的那一拍被做成可读数（来源：`src/rtl/eth/eth_udp_video_top.v:258`—`261`，`273`） | 已修：1 条/周期 = 200 MB/s（来源：`src/rtl/eth/eth_udp_video_top.v:262`） |
| F4 | 屏上均匀散布的黑点，分包长度有关 | 写选通恒 `8'hFF`，同一个 64 bit 字被相邻两包分两次写时后一次把前一次的半字覆盖成 0；分包长度不是 8 的倍数（如 1396）时每帧 111 处 = 222 个 16 bit 黑洞 | 分包长度扫描（同一帧换 `-l` 即复现） | 已修 v6.4：按 16 bit lane 生成 `wstrb`（来源：`src/rtl/eth/axi_frame_saver64.v:80`—`84`） |
| F5 | 帧缓存被写到帧外、画面出现不该有的改动 | `wr_en` 与行覆盖统计不吃同一个边界，`off[18:1]` 最大 131071 而一帧只有 76800 个字，下游 `axi_frame_saver64` 自己没有上界检查 | `stat_oob_off` 递增（来源：`src/rtl/eth/frame_reasm.v:160`—`161`）；尺子 `sim/tb_reasm_bounds.v` 的 R1，改前红凭据 `build/r98_201_before.txt`（越界包发了 2 次写、最大字索引 145 > 128）（来源：`src/rtl/eth/frame_reasm.v:148`—`149`） | 已修 #201：`wr_en <=(off < FRAME_BYTES)`（来源：`src/rtl/eth/frame_reasm.v:152`） |
| F6 | 帧提交后画面有"移动的黑条纹"，缩放时更明显 | 缺行没被写过，DDR 里留旧/零像素：`frame_reasm` 只在每源行本帧都写过才提交 | `rows_missed` = 还差多少源行（黑纹行数），与 `frame_abort` 同拍（来源：`src/rtl/eth/frame_reasm.v:2`—`3`，`26`—`28`，`201`—`202`）；`rows_missed=0` 而仍作废 = 缺的不是行而是最后一包的字节（来源：`src/rtl/eth/frame_reasm.v:199`—`200`） | 行为即设计（验收门），观测口 v7.6 P0-A 加入（来源：`src/rtl/eth/frame_reasm.v:26`—`30`） |
| F7 | SRC1 全黑、`frame_done` 永不成立 | 用 `off[16:1]` 当 16 bit 像素索引算行号，约 172/300 行被截断 | 提交计数 `stat_frames` 恒 0（来源：`src/rtl/eth/frame_reasm.v:84`—`87`） | 已修：行号走 32 bit `off / ROW_STRIDE`（来源：`src/rtl/eth/frame_reasm.v:86`—`87`） |
| F8 | 改分辨率后提交半幅黑帧或永不出 `frame_done` | `FRAME_BYTES` 在实例化处没传，用默认 307200，只在 `IMG_W=512 且 IMG_H=300` 时偶然等于 `IMG_W*IMG_H*2` | `bytes_ok` 判据（来源：`src/rtl/eth/eth_udp_video_top.v:231`—`234`） | 已修 #158：显式传参，现值与默认逐字节相同 ⇒ 这一刀对今天免费（来源：`src/rtl/eth/eth_udp_video_top.v:235`） |
| F9 | 入流链整体卡死 = 板上"冻结"类症状 | 上游偶尔多回一个 B 时 `outst` 回绕成 15，`have` 永不成立 | `busy` 恒 1、`idle` 恒 0（来源：`src/rtl/eth/axi_frame_saver64.v:158`—`160`，`86`） | 已修：只减不回绕，宁可少计也不锁死（来源：`src/rtl/eth/axi_frame_saver64.v:159`—`160`） |
| F10 | 帧尾 4 字节偶发丢失、换页与数据不同步 | 换页没等本帧数据全部穿过 CDC | `saver_idle` 与 `cdc_empty` 的与门（来源：`src/rtl/eth/eth_udp_video_top.v:328`—`341`） | 已修 v6.4，glue 抽成 `ddr_bank_commit` 以便 TB 例化上板实现（来源：`src/rtl/eth/eth_udp_video_top.v:328`—`331`） |
| F11 | 屏幕上一物被一条水平缝"切开" + 拖影，同一帧新旧两半并存 | 换帧跨了两个消隐期，拷贝超出一个 V-blank 窗口 | `copy_overrun` 粘滞位，`row_copy_cycles > 67200`，`led[0]` 看，直到重载位流（来源：`src/rtl/top/pl_video_top.v:442`—`451`） | 结构性防治：只在 V-blank 原子换帧 + `VB_X_GUARD` 早关 65 像点（来源：`src/rtl/top/pl_video_top.v:392`—`401`） |
| F12 | 满屏噪点（旋转时） | 暂存/结果缓冲索引用了源列 `sx`，旋转时 `sx` 沿一行停滞/倒退，同一格子被别的源行重写 | 只在旋转态出现；索引改成显示列对号 `jd(x_d[2][9:1])`（来源：`src/rtl/top/pl_video_top.v:745`—`747`） | 已修（2026-09-26 用户报，见 `fb_bilin` 头，来源：`src/rtl/top/pl_video_top.v:746`） |
| F13 | 贴在屏幕左边缘的一条线 / 最左 9 列画的是上一行末尾 | 面板 `de` 比同拍像素早 9 列（MIX_D − 11），最右 9 列落进消隐丢掉，而 OSD 跟着一起错所以看不出来 | `tb_v98` 的 C3 用**输出引脚**建立坐标系、不引用内部标签，改前量到"画面左右沿 = 定义 +8 列"；C3a 排除"消隐窗口不匹配"（来源：`src/rtl/top/pl_video_top.v:913`—`919`） | 已修 #92 第二笔：整束标签提到 `MIX_D`（来源：`src/rtl/top/pl_video_top.v:919`—`921`） |
| F14 | 缩小后画面左右各少一列、边界甩进背景带 | 原图抽头与处理抽头差一整拍（PROC_LAT+1 vs PROC_LAT），恒为一列不随倍率变 | `tb_v98` 的 C1c 与 C2 在 inv=512/inv=1023 两档都量到"内容左右沿 = 定义 − 1"（来源：`src/rtl/top/pl_video_top.v:819`—`824`） | 已修 #92 第一笔：处理抽头补一拍 `pipe_dout_q`（来源：`src/rtl/top/pl_video_top.v:825`—`829`） |
| F15 | 上边缘有东西闪、右沿最后一列被按黑 | 越界标签绕开行环只走等长 skid，到混色级与像素差 (4 行, 1 列) | 环宽 `DW(17)` = `{oob, pix}` 同写同读；`utilization.rpt` 上核 BRAM 块数没涨（来源：`src/rtl/top/pl_video_top.v:782`—`786`，`841`） | 已修 #92 第三笔（来源同上） |
| F16 | 一条 `ping -l 0` / `ping -s 0` 之后 ICMP 应答器永久变哑，ARP 仍活，现场像"链路好但 ping 不通" | 0 字节 echo request 把应答器状态机楔住，并毒死后面所有包 | 刚复位后 `ping -n 4` = 4/4；先发一条 `-l 0`，随后所有包（含 32 字节）全不答；`BOARD_IP` 见 `src/rtl/eth/arp.v:30`（来源：`report/known_issues.md:354`—`361`，`931`—`933`，`902`） | 已修（2026-10-01 当晚，bit `bf11b78fe45d`）：`-l 0` 3/3 回复字节=0，随后 `ping -n 4` 仍 4/4；台架 `sim/tb_icmp_ping0.v` 五条（来源：`report/known_issues.md:372`—`374`，`339`）。注意台架只看发侧字节数，在未改动树上就 PASS（来源：`report/known_issues.md:367`） |
| F17 | 演示中途打死应答器的恢复办法只有重配 PL（三步 JTAG），链路本身不断 | 同一根 F16 根因，且未修版本上任何一条 `-l 0` 都会打死 | 规程要求演示机器上先确认一次 `ping`（来源：`report/known_issues.md:937`—`938`） | 同上已修；未修前留下的另一课是"探针自己污染被测对象"（来源：`report/known_issues.md:923`—`926`） |
| F18 | SD 播放中拔卡，画面永久冻帧、插回不恢复 | "这一路片源还在不在"没有任何计时器（`#94`） | 与 `report/known_issues.md:295` 记的"边界条件下没人对账"同族；工程里另有 `src_life`/`src_mode` 一族判据（来源：`report/known_issues.md:871`） | 本卷只读到根因、没读到该条的板上闭环读数 ⇒ 修复状态未证，见 §8 |
| F19 | 片源被抢、SD 帧永远不被消费，STALL 钉在 9999 | 像素域另复制了一份"活着"的判据，与 `src_arb` 的两套判据互相等 | `dbg_src[10:8]` = 判决那一拍的 `{force_ps, ~eth_live, ~eth_tb_ok}`；AUTO 模式不判 `no_sig`（来源：`src/rtl/top/pl_video_top.v:67`，`508`—`515`） | 已修：像素域只消费仲裁结果 `owner_eth_pix`（来源：`src/rtl/top/pl_video_top.v:512`—`522`） |
| F20 | OSD 在 PS app 起来之前画 `Temp:00C` | 复位值 0 是合法 BCD，被当成读数 | OSD 那一格 `--` 才是"无可信读数"（来源：`src/rtl/process/effect_ctrl.v:48`—`52`） | 已修：复位低字节 `0xFF`，两位都不是十进制数字（来源同上） |
| F21 | 串口里一大长串空白 | 残包丢弃提示是中文，cp936/GBK 的 Windows 控制台渲染不出来 | `[CMD!] dropped N trailing byte(s)` ASCII 打头（来源：`src/ps/main.c:1441`—`1449`） | 已修（来源同上）；同时修掉"写完的行陪残包一起被扔"（来源：`src/ps/main.c:1439`—`1440`，`1444`—`1445`） |
| F22 | `PLAY` 时串口被 `[CTRL]` 刷屏，发布时序压在打印上 | 每帧一次的发布脉冲直接调 `ctrl_apply()`，30 fps 每秒推约 2 KB，而 115200 只有 11.5 KB/s 且 `xil_printf` 是轮询等 TX 的阻塞实现 | 板上实测 PLAY 10 s 收回 28549 B 全是 `[CTRL]` 行（来源：`src/ps/main.c:205`—`208`） | 已修：发布走 `ctrl_write()` 不打印（来源：`src/ps/main.c:208`—`209`） |
| F23 | "设了没反应"被误判成 PL 坏了 | `CFG_DATA0`(=RTL 的 `gpio_cfg1_o`) 与 `CFG_DATA1(+0x08)` 两个名字差一位，写错字寄存器 | 开机自测往 `CFG_DATA0` 写 `1ff`/`780000` 读回比对，不对打 `[CFG!]`；位流里没有 `axi_gpio_2` 时不会有编译错误（来源：`src/ps/main.c:221`—`222`，`1519` 段的 `[CFG!]` 那条） | 属规程 + 自测，非设计缺陷（来源同上） |
| F24 | `clk_pix` 与 `eth_rxc` 之间出现 WNS≈−6.7 的假违例 | `set_clock_groups` 少写 `-include_generated_clocks`，`clk_pix` 被当成独立时钟去做 setup 分析 | 见约束文件注释（来源：`src/constraints/clock_groups_impl.xdc:16`—`17`） | 已修；同一族还有对象名取不到会让整条命令不生效、只留一句 warning（来源：`src/constraints/rk_zynq7020.xdc:43`—`45`，`68`—`70`） |
| F25 | RTL821 断链后心跳一直在、`hb_gone` 永不触发 | PHY 断链时不停供 RXC 而是拉到约 1/48，只测"心跳有没有停"不够 | 关键方向是源时钟变慢 ⇒ 目的域量到的心跳间隔变长（不是变短），`FAST_ENOUGH` 用 `SLOW_MS=5` 把 1 ms 与约 50 ms 分居两侧（余量 5×/10×）（来源：`src/rtl/eth/snap_cross.v:6`—`7`，`33`—`35`） | 已修：心跳改间隔测量（来源同上） |
| F26 | 快照总线读到"半新一半旧" | 19 位各自打两拍 | `snap_cross` 契约：总线只在帧首变（准静态），发沿在捕获之后推迟 8 个像素周期（来源：`src/rtl/top/pl_video_top.v:649`，`src/rtl/eth/snap_cross.v:2`—`5`） | 已修：单独成模块 `zoom_snap.v`，`tb_v95` 逐周期验两条不变量（来源：`src/rtl/top/pl_video_top.v:649`） |

## 7. 量过并否决的优化

每条按 假设 → 刀法 → 读数 → 判负理由 → 凭据 五段写。凡读数只来自代码注释的，注明"注释转述"。

### D1 · 把入流缓冲加深来治丢字

- 假设：丢字是因为缓冲不够深，加深即可。
- 刀法：CDC 从 512 条扩到 8192 条（BRAM 实现）。
- 读数：上板毫无改善。
- 判负理由：瓶颈是平均排空速率不是深度——v6.2 之前每字走 `S_AW→S_W→S_B`、在途深度恒 1，HP0 写延迟约 40 拍直接成为吞吐上限 ≈20 MB/s，所以"每包固定从第 48 字节起丢字"与深度无关。ISSUES #32 明写"加深缓冲治不了它"。
- 凭据：`src/rtl/eth/axi_frame_saver64.v:5`—`7`；深度后来只用于吸收 V-blank 独占（`src/rtl/eth/eth_udp_video_top.v:296`—`297`）。

### D2 · `wr_full` 加 `max_fanout=12`（#105 第一刀）

- 假设：满判据扇出过大是关键路径来源，复制本地缓冲能买回余量。
- 刀法：给 `dc_fifo` 的 `wr_full` 加 `max_fanout=12`。
- 读数：WNS 从 r81 的 −0.062 掉到 −0.192，失败端点 28 → 34（2026-09-28 深夜，注释转述实测）。
- 判负理由：扇出不是瓶颈。同一条链上的第二刀（把满判据从"下一个写指针"改成"当前写指针"，削掉 14 位加法 + 二进制转格雷的比较锥体）才是买到了东西的那一刀，并把可用深度从 DEPTH−1 变 DEPTH。
- 凭据：`src/rtl/eth/dc_fifo.v:37`—`44`，注释点名 r83 那一轮的门禁件（盘上已无此件）与 `build/timing_summary.rpt`（在盘上）；C1 尺子 `sim/tb_cdc_capacity.v`（来源：`src/rtl/eth/dc_fifo.v:44`）。

### D3 · 在 PL 里把拍数除以 100 换成 µs（r49 / ISSUES #58）

- 假设：延迟直接以 µs 报出来更好读，PL 里做一次除法即可。
- 刀法：`frame_latency` 出口处 `拍数 / 100`。
- 读数：100 MHz 域直接 WNS −5.014 / 96 个失败端点（来源：`src/rtl/top/pl_video_top.v:621`—`623`）。
- 判负理由：除数不是 2 的幂 ⇒ 综合架出组合除法器。改法是"PL 里不做除法"：只报拍数，换算放在 `src/host/health_read.mjs` 的一个常量里（fclk0=100 MHz ⇒ 1 拍 = 10 ns）（来源：`src/rtl/top/pl_video_top.v:621`—`623`，`71`）。
- 凭据：`src/rtl/top/pl_video_top.v:619`—`623`，`src/rtl/video/frame_latency.v`（在 `ASYNC_REG` 名册内，来源：§5.2）。

### D4 · Pblock 把 `u_cdc` 圈回它自己那 9 块 BRAM 旁边（#146）

- 假设：CDC 的坏路径是布线跨度造成的，物理约束圈回去就能修。
- 刀法：给 `u_cdc` 下 Pblock，限定在它自己那 9 块 BRAM 邻域（#121 点名的"物理那一侧"）。
- 读数：跑完给了名册与 WNS 的对照，判词是"不采纳"，共三个理由（第一条：它瞄准的那一族本来就已经不在最差名单里，是 r88 的功劳）。
- 判负理由：刀砍在没有产出的族上；`OPTIMIZATION_LOG` 里那一行改为"已试、不采纳"，别再当"下一刀"推荐给下一个人。后续记录再次确认 Pblock 已在 r113 否掉。
- 凭据：`report/log/issues.md:6185`，`6208`，`6216`；再次引用见 `report/log/issues.md:12342`。

### D5 · 复制驱动来切公共锥（#288）

- 假设：把驱动复制多份能降低共享逻辑的时延，机制上应能动。
- 刀法：复制驱动，量目标族的改善与代价族。
- 读数：`MF-SUMMARY mech=2/2 gain=0.456 cost_red=1 lut_delta=31 verdict=DECLINE`，目标族 +0.456 ns，代价落在 `eth_rxc` 的 hold 上。
- 判负理由：它买到的 +0.456 ns 与被它拿走的东西在同一个域。判据不许反着写——这不是"WNS 没动所以不算收益"（rule 35 禁止的口径），是名册差分看见的代价否决的。采纳规则也同步收紧：名册差分若显示别的域被挤，这一版的采纳结论要跟着改。
- 凭据：`report/log/issues.md:12177`，`12191`，`12193`—`12198`，`12249`；本轮实验件在 `build/evidence/r114_mf`（目录已见盘上，来源：目录清单）。

### D6 · 四个域统一加严 hold 带（#302 r115 夜）

- 假设：只有 `eth_rxc` 带 0.800 的 hold 带（来源：`src/constraints/rk_zynq7020.xdc:50`）是不一致的，四个域统一加严更诚实。
- 刀法：把同一 hold 不确定度推广到其余派生钟域，纯测量。
- 读数：统一加严后 WHS −0.747 / 25,742 失败端点——这是"四域 WHS 不可比"这件事第一次被量出来。
- 判负理由：读数会变难看的一类动作必须有批准人点头，夜里没有批准人 ⇒ 只测不采纳，问题原样交给用户；约束本身没动，主树仍是原口径。
- 凭据：`report/log/issues.md:12490`，`12507`。

### D7 · 补齐派生钟覆盖面后再看 MMCM 够不够（路 (a)）

- 假设：假违例来自派生钟覆盖面没补齐；补齐之后 MMCM 的余量就够用了。
- 刀法：把生成钟的约束对象补齐（`-include_generated_clocks` 一族），再量一次。
- 读数：补齐后 hold −1.426 / setup −0.972，比主树更差。
- 判负理由：路 (a) 在此判负——补齐覆盖面没有换来余量，反而暴露出更差的界；口径回到 §5.1 那条"只写必要对象 + 一条带理由的 `set_max_delay`"。
- 凭据：`report/log/issues.md:12623`；界值出处 `build/timing_summary.rpt` 的 Clock Summary（转述于 `src/constraints/r114_io_async.xdc:55`）。

### D8 · 在富余处省资源（隔离滚动实验）

- 假设：省 LUT/FF 总是好的，资源薄处省一点就更安全。
- 刀法：在被判"富余"的结构上换存储/削余量的滚动产物。
- 读数：第二次滚动（`build/isolated_0929_2105/`）就是为验证这个去的。
- 判负理由：在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的 ⇒ 不采纳，回退到板上那一份。同时记了一句方法账：`utilization.rpt`/`timing_summary.rpt`/`crit_paths.txt` 都在盘上（隔离滚动产物；`.gitignore` 只挡位流，报告本身没入库），是"量过并且否决"的凭据。
- 凭据：`report/log/issues.md:6284`，`6363`，`6374`。

### D9 · 门禁判红就不采纳、不上板（r64 / r98 / r100）

- 假设：改动本身逻辑正确（真话），可以先采纳再补门禁。
- 刀法：r64 = r63c + #83，两项门禁判红且都是真话；r98 判定 20 项 2 红；r100 收摊。
- 读数：那两轮的门禁件没留在盘上（build 目录里现存最早的一份是 r65 那一轮，`build/r65_gates.txt` 头两行写着"报告目录：build"与它的新鲜度行，形状就是这类件的样子），判定文本记在 `report/log/issues.md:3139`：r64 那一句是"不采纳，保留上一版"，r98 判定 20 项、2 红 ⇒ 同一句尾巴；板子上跑的仍是 r63c（全绿那版），r64 的位流没刷。
- 判负理由：红项一律不采纳；盘上的 `build/frozen_` 目录共 4 个（`build/frozen_r13`、`build/frozen_r19_arb`、`build/frozen_r32_sdfix`、`build/frozen_r62_geom`），里面没有 r96 那一套 ⇒ 那次试冻结被自家硬门拒掉是留了形的。要区分的是"设计红"与"门禁红"——r98 的两条红都不是设计红，但仍足以挡住采纳。
- 凭据：`report/log/issues.md:3139`，`3158`，`8397`，`8832`，`8855`—`8861`，`7135`。

### D10 · 少一对同步器（r98）

- 假设：像素→sys 方向省一对同步器一定买时序。
- 读数：兑现了 −1，但方向反过来才成立——"少一对同步器"这句要按"方向反过来才成立"来念。
- 判负理由：r98 在归因清楚之前不采纳；提交包仍然出了，因为导出器的红名单只允许 `FAIL C5c` 这一条声明过的红。
- 凭据：`report/log/issues.md:8087`，`8094`，`8393`。

### D11 · 独热化 bank 使能（r110 刀 4①）

- 假设：把"新行"那根 316 扇出的网拆成每 bank 一根使能，能干净买到 hold/setup。
- 刀法：`wire [4:0] bank_one = new_row_w ? (5'b00001 << rbank) : 5'b00000`，每个 bank 各取一位（来源：`src/rtl/eth/frame_reasm.v:97`—`102`，`154`—`159`）。
- 读数：判据达成、台架与车道干净，但出现一个 −243 LUT 的待解释量（来源：`report/log/issues.md:11111`）。
- 判负理由：待解释的量不进主树——本轮处置不采纳、不刷板，并把被第一遍写进首页/`metrics.csv` 的数字退回（来源：`report/log/issues.md:11111`，`11126`）。
- 凭据：`report/log/issues.md:11111`，`11126`；`build/evidence/r110_notadopted`（盘上已见该目录），同组对照件 `build/evidence/r110_before.txt`、`build/evidence/r110_after.txt`、`build/evidence/r110_setup_paths_baseline.rpt`。

被采纳的对照组（写在同一批注释里，用来防止把上面几条当"通则"）：`frame_reasm` 把三操作数 32 bit 加法改成两个饱和计数 + 常量比较，因为那一个加法器独占本 125 MHz 分组全部十条最差路径，WNS +0.499（来源：`src/rtl/eth/frame_reasm.v:5`—`7`）；`axi_frame_saver64` 的打包 FIFO 显式 `ram_style="distributed"`，实测 task 写法 FF=32904/LUTRAM=0 vs 本写法 FF=85/LUTRAM=864（来源：`src/rtl/eth/axi_frame_saver64.v:104`—`107`）；`outst` 只减不回绕（来源：`src/rtl/eth/axi_frame_saver64.v:158`—`160`）。这三条的共同点是被否决的十条没有一条具备：收益落在最差名单上、且名册差分没有别的域被挤。

## 8. 未证与边界

本卷没能从仓库里读到证据、因此刻意没写进正文的东西，逐条列出。

一、SD 播放中拔卡永久冻帧（F18）。只读到根因那一行——"这一路片源还在不在"这件事没有任何计时器（来源：`report/known_issues.md:871`），以及与"边界条件下没人对账"同族的另一条记录（来源：`report/known_issues.md:295`）。该条的修复闭环、板级复验读数、以及 `src_life`/`src_mode` 与它的对应关系，本卷都没读到行号级凭据，因此 §6 的状态栏写"未证"，工程里确实存在 `src/rtl/util/src_life.v` 与 `src/rtl/util/src_mode.v` 两个文件（目录清单可见），但没核到它们就是 #94 的落地。

二、`ping -l 65000` 这一类合法大载荷与 `u_fifo` 深度之间的界。仓库自己就把它列为"当时没查的"（来源：`report/known_issues.md:630`），`report/60-failure-analysis.md:441`—`446` 只给了判别方法（台架侧喂超长合法帧、板侧 `ping -l 65000`）而没有给出结论读数，所以 §6/§7 都不写它的判定。

三、`ddr_bank_commit`、`link_monitor`、`frame_commit_lock`、`ps_publish`、`angle_ctrl`、`zoom/`、`src_arb`、`frame_latency` 这些模块的内部实现。本卷只在 §5.2 引用了约束注释对它们跨域机制的一句话概括（来源：`src/constraints/clock_groups_impl.xdc:20`—`23`），以及它们在实例化处的端口连接（来源：`src/rtl/eth/eth_udp_video_top.v:284`—`293`，`src/rtl/eth/eth_udp_video_top.v:330`—`341`，`src/rtl/top/pl_video_top.v:430`—`440`）。`lm_bus` 各位的含义、`stall_ms` 的具体阈值、`LIVE_MS` 之外还测了什么，都没读到。`frame_reasm` 注释里说短帧由 `stall_ms` 抓到（来源：`src/rtl/eth/frame_reasm.v:28`），抓这件事的实现本卷未读。

四、`tap_sched` 的槽位表正文。本卷只读到"每像素周期 5 个快槽、右窗 4 + 左窗 1、`vld` 落在下一周期 s1"这几句以及"槽位表见下面 `slot` 处"这句指向（来源：`src/rtl/process/bilin/tap_sched.v:4`—`5`，`11`—`13`），没有读 `slot` 的 case 本体，因此 §3.3 只给"1 像素周期 + 1 拍"而不给 s0..s4 的逐槽分配。

五、`proc_pipeline` 的 15 拍怎么分到六级。只读到 `LATENCY = 15` 这个声明与"级 0 的 gamma 不占拍、改成寄存读出就得同时改成 16"这条约束（来源：`src/rtl/process/proc_pipeline.v:20`—`22`），每级各占几拍没读。§3.4 因此只给总深度与 `OFF_LINES = 4` 行。

六、"注释点名的凭据路径"本卷逐条数过盘上，分两类。**在的**：`build/timing_summary.rpt`（被 `src/rtl/eth/dc_fifo.v:38`—`39` 点名）、`build/r98_201_before.txt`（被 `src/rtl/eth/frame_reasm.v:148`—`149` 点名）、`build/r103_board_ping.txt`（被 `report/known_issues.md:902` 点名）、`report/timing_global.md`（被 `src/constraints/r114_io_async.xdc:48` 点名）。**不在的**（那一轮的门禁件没留住；本轮不改 RTL 注释，只在这里登记）：r64、r83、r98 三轮的 gates 件（点名处 `report/log/issues.md:3139`，`8397`）、`src/rtl/eth/dc_fifo.v:26`—`27` 与 `src/rtl/eth/snap_cross.v:26`—`27` 点名的 r113 两份扫描件、以及 `report/log/issues.md:7135` 那句"29 个 frozen_ 目录"——现数 `build/frozen_` 只有 4 个目录（`build/frozen_r13`、`build/frozen_r19_arb`、`build/frozen_r32_sdfix`、`build/frozen_r62_geom`）。§7 凡引用这类没留住的读数，一律按"注释转述"记账，不当作盘上凭据。

七、`set_bus_skew` 至今没写。它需要点到同步器单元名，而 r114 的对象探针在 `get_false_paths` 上死了（该命令在本工具不存在），换成 `get_timing_exceptions` 之后能否数到对象，本卷没读到任何后续读数（来源：`src/constraints/r114_io_async.xdc:65`—`68`）。所以 §5.2 表里"兜它的约束"一栏对四条跨域路只到 `set_max_delay`，不含 bus skew。

八、`src/rtl/top/system_top.v`、`src/ps/sd_play.c`、`src/rtl/hdmi/rgb2dvi.v`、`src/rtl/video/frame_buffer_w64.v`、`src/rtl/eth/udp_rx_parser.v`、`src/rtl/eth/gmii_rx_mac.v` 本卷没打开。相关的两处后果写在正文里：FCS 自算与 `p_good` 变真值只引用了 `eth_udp_video_top` 的注释（来源：`src/rtl/eth/eth_udp_video_top.v:155`—`157`，`238`），没有从 `gmii_rx_mac.v`/`crc32_d8.v` 本体取证；HDMI 那一路只引了 `tmds_encoder.v` 与 `tmds_serializer.v` 的头部，没读 `rgb2dvi.v` 的三路并行与 `OSERDESE2` 级联完整端口表。`BOARD_IP` 在 `src/rtl/eth/arp.v:30` 这条也是 `report/known_issues.md:902` 的转述，本卷没直接打开 `arp.v`。

九、几处本卷推出来但仓库没成文的数：一帧 1344 × 625 个像点周期这一乘积、`MIX_D = 3 + 1 + 1 + 15 = 20` 与 `SB = 21` 的代入结果（表达式本身有凭据，来源：`src/rtl/top/pl_video_top.v:354`—`355`）、以及 §2.7 表里"整条链最窄处是 CDC 出口的 200 MB/s"这句比较（三个速率各自的出处分别是 `src/rtl/eth/axi_frame_saver64.v:3`、`src/rtl/eth/eth_udp_video_top.v:262`、`src/rtl/eth/eth_udp_video_top.v:258`—`261`）。仓库给出的相近数字是"25 blank lines = 33.5k pix cycles = 67k axi cycles"（来源：`src/rtl/top/pl_video_top.v:393`—`394`），本卷没有把它当作自己的读数来源之外的用途。

十、`report/log/issues.md` 体量在本卷的读取方式之外。§7 的每条否决都靠一次关键词定位（`否决|判负|回滚|DECLINE|不采纳|无效|放弃`）拿到行号后按行引用，同一条目上下文的完整推演过程没有逐行读完，因此 §7 的"判负理由"里凡本卷没能引到原文的，都写成了对记录句的转述而没有补细节。

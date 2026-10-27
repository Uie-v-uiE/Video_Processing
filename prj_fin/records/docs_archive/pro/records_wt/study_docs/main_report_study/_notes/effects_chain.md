# 图像处理 / 几何变换链 —— RTL 事实笔记

> 取证范围：`src/rtl/top/pl_video_top.v`（全文 522 行）、`src/rtl/process/*`、
> `src/rtl/video/line_cache.v`、`src/rtl/video/color_bar.v`、`src/rtl/video/split_display.v`、
> `src/rtl/video/frame_buffer_w64.v`、`src/rtl/video/video_timing*.v`、`src/rtl/util/key_debounce.v`、
> `src/rtl/clocks/clk_gen.v`、`src/rtl/top/system_top.v`、`src/ps/main.c`、`build/tcl/*`、
> `src/constraints/rk_zynq7020.xdc`、`build/build_r05_skid.log`、`report/ROTATION_AND_EFFECTS.md`。
> 所有行号均为读文件核对后的真实行号（相对仓库根）。标注「推断」者为推理，非文中明述。

## 0. 全局常量 / 时钟 / 几何

| 项 | 值 | 证据 |
|---|---|---|
| 板输入时钟 `sys_clk` | 50 MHz（`-period 20.000`，引脚 W17） | `src/constraints/rk_zynq7020.xdc:5`、`:6` |
| `clk_pix` | 50 MHz（VCO 1000 / 20） | `src/rtl/clocks/clk_gen.v:19`、`:21` |
| `clk_pix5x` | 250 MHz | `src/rtl/clocks/clk_gen.v:24` |
| `clk_200m` | 200 MHz（IDELAY 参考） | `src/rtl/clocks/clk_gen.v:27` |
| `axi_clk` = FCLK_CLK0 | 100 MHz | `build/tcl/build_system.tcl:28`、`:74` |
| 源图像 IMG_W×IMG_H | 512×300 | `src/rtl/top/pl_video_top.v:6`、`:7`；实例化 `src/rtl/top/system_top.v:161` |
| 显示时序 | 1024×600，H_TOTAL 1344，V_TOTAL 625 | `src/rtl/video/video_timing_1024x600.v:3`、`:18`-`:20` |
| 帧周期 | 1344×625 = 840 000 拍 @50 MHz = 16.8 ms ≈ 59.52 Hz（推断，由上行常数相除） | `src/rtl/video/video_timing_1024x600.v:18`-`:20` |
| 每半窗尺寸 | PANE_W=512 宽 × 600/2=300 行 → 与源 1:1 列、1:2 行 | `src/rtl/top/pl_video_top.v:8`、`:113` |
| 复位 | `rst_pix_n = sys_rst_n & locked`；而 `sys_rst_n` 在板级被绑 `1'b1` → 像素域复位只由 MMCM `locked` 提供 | `src/rtl/top/pl_video_top.v:65`、`src/rtl/top/system_top.v:162` |
| 时钟组约束 | `sys_clk` 及其全部生成时钟归为同一异步组，与 `clk_fpga_0`、`eth_rxc` 互相 false-path；组内（sys_clk↔clk_pix）仍按时序分析 | `src/constraints/rk_zynq7020.xdc:53`-`:56` |

## 1. pl_video_top 内部确切数据流

### 1.1 源像素从哪来（同一个 BRAM、同一个 16 bit 读端口，左右半窗分时复用）

- 显示帧缓存 `frame_buffer_w64 #(.W(512), .H(300)) u_fb`：64 bit 写口（AXI 回读/填充），
  16 bit 随机读口，`rd_clk = clk_pix`，`rd_addr = rd_addr_q`，`rd_data = fb_rd`
  —— `src/rtl/top/pl_video_top.v:369`-`:373`。读延迟 1 拍（`q_lo/q_hi` 输出寄存器 + lane mux）
  —— `src/rtl/video/frame_buffer_w64.v:64`-`:70`、`:3`（注释自述 "Read latency = 1 clock"）。
- 唯一的读地址端口被左右半窗**分时复用**：
  `fb_sel_right = ~left_d[2]` → `sx_fb/sy_fb/oob_fb` 三选二
  —— `src/rtl/top/pl_video_top.v:351`-`:354`。**没有第二个读口**。
- 地址换算：`rd_addr_q <= {sy_fb[8:0], 9'b0} + {7'b0, sx_fb}` ⇒ 行主序 `sy*512 + sx`
  —— `src/rtl/top/pl_video_top.v:363`。
- 越界地址由 `blank <= (rd_addr >= W*H)` 在读出口强行回黑
  —— `src/rtl/video/frame_buffer_w64.v:69`、`:82`。
- 另一路像素源：`color_bar` 程序化生成（不是读缓存）
  —— `src/rtl/top/pl_video_top.v:377`-`:384`。
- 二选一：`src_use = src_sel_pix`（3FF 同步 `src_sel`）
  —— `src/rtl/top/pl_video_top.v:273`-`:278`、`:289`；
  选择点在 `:398`、`:401`（`src_use ? bram_or_hold : bar_*`）。
- 拷贝期间的像素保持逻辑：`ac0/ac1` 同步 `allow_copy`，`!ac1` 时 `fb_pix_hold <= fb_rd`，
  `fb_out = (ac1 && !de_d[11]) ? fb_pix_hold : fb_rd` —— `src/rtl/top/pl_video_top.v:294`-`:305`；
  无 link 时 `bram_or_hold = 16'hF800`（纯红）—— `:307`。
- 写口同样二选一：`aw_wr_* = eth_mode ? row_wr_* : fill_wr_*` —— `:347`-`:349`；
  `eth_mode` 来自 `eth_link` 在 axi_clk 域的 3FF 同步 —— `:225`-`:230`。
- `eth_mode=1` 时由 `axi_frame_writer_gated u_row` 在 V-blank 内把 DDR 帧搬进 BRAM
  —— `:256`-`:271`；`eth_mode=0` 时由 `axi_frame_writer64 u_aw` 从 `BASE_ADDR` 自填
  —— `:323`-`:338`。V-blank 原子拷贝的窗口判据 `disp_quiet`、`VB_X_GUARD=1279`
  —— `:207`-`:211`；预算 `VBLANK_AXI_CYC = 67200` = 25 行 ×1344 拍 ×2 —— `:248`、`:199`-`:204`（注释自述）。

### 1.2 几何映射链（像素域）

- 光栅坐标 → 画布坐标：
  `left_pane = (x < PANE_W)`、`cx = left_pane ? x : x-PANE_W`、
  `cy = ((y>>1) < IMG_H) ? (y>>1) : IMG_H-1` —— `src/rtl/top/pl_video_top.v:111`-`:113`。
  即 **X 1:1、Y 2 倍行复制**；`cy` 的 clamp 在有效行内永不生效（y≤599 ⇒ y>>1≤299），
  只在消隐期 y=600..624 时起作用（推断，由 `:113` 与 `video_timing.v:63`-`:67` 的 x/y 为裸计数器得出）。
- **左半窗 = 纯旋转路径**：`rotate_mapper u_rmap`，`.enable(1'b1)`（硬接），
  `.x_in(cx), .y_in(cy)` → `sx_map/sy_map/oob_map` —— `:125`-`:130`。
  旋转关闭时改走 `cx_q3/cy_q3/oob_q3`（3 级延迟对齐 mapper 深度）—— `:132`-`:149`。
- **右半窗 = 缩放（可叠旋转）路径**：`zoom_mapper u_zmap`，
  `.inv_scale(inv_scale), .angle(angle), .rotate_en(rot_on), .x_in(cx), .y_in(cy)`
  → `sx_r/sy_r/oob_r` + `frac_x/frac_y → zfrac_x/zfrac_y` —— `:151`-`:160`。
- 两路按 `fb_sel_right`（`left_d[2]`，D=3）选择，与两条 mapper 的 3 拍延迟同域 —— `:351`-`:354`。
- 消隐/映射延迟对齐链 `SB = 16`：`de_d/hs_d/vs_d/left_d/x_d/y_d/cx_d/cy_d[0:15]` —— `:162`-`:181`。

### 1.3 效果链的接入点（关键事实：**只有右半窗进效果链**）

- `proc_pipeline #(.H_ACTIVE(IMG_W)) u_pipe` 的输入：
  `de_in = de_d[3] && !left_d[3]`（右半窗限定）、`x_in = cx_d[3]`、`y_in = cy_d[3]`、
  `din = pix_right`、`hs_in = hs_d[3]`、`vs_in = vs_d[3]` —— `src/rtl/top/pl_video_top.v:410`-`:419`。
- 左半窗像素不进效果链，只走 7 级 skid：`orig_skid[0] <= pix_left`，
  `orig_disp = orig_skid[LEFT_TAIL-1]`（LEFT_TAIL=7）—— `:406`、`:421`-`:441`；
  `oob_l_skid/oob_r_skid` 同深度 —— `:422`-`:423`、`:432`-`:437`、`:442`-`:443`。
- 结果去向：`pipe_dout` → `split_display.proc_pix`；`orig_disp` → `.orig_pix`；
  越界标志 → `.oob_l/.oob_r`；光栅基准 → `.x/.y/.de/.hs/.vs` 用 `x_d11/y_d11/de_d[11]/hs_d[11]/vs_d[11]`
  —— `:445`-`:458`。`split_display` 1 级寄存输出 RGB888 → `osd_overlay`（1 级寄存）
  → `rgb2dvi` —— `:450`-`:458`、`:491`-`:502`、`:504`-`:510`；
  `src/rtl/video/split_display.v:34`-`:50`；`src/rtl/video/osd_overlay.v:186`-`:200`。
- `pipe_de`（效果链自己的 de_out）被引出后**没有任何消费者** —— `:409`、`:418`。

### 1.4 逐信号"落后光栅多少拍"（记号 D：sig@T 对应光栅槽位 T−D；全部由上述行号推得）

| 信号 | D | 证据 |
|---|---|---|
| `de`/`cx`/`cy` | 0 | `:105`-`:113` |
| `sx_l`/`sx_r`/`oob_l`/`oob_r`（mapper 3 级） | 3 | `:147`-`:149`、`:125`-`:130`、`:154`-`:160` |
| `rd_addr_q` | 4 | `:363` |
| `fb_rd`/`bram_or_hold`（BRAM 1 拍） | 5 | `:372`、`frame_buffer_w64.v:64`-`:70` |
| `bar_l_d4`（1 级彩条 + 4 级） | 5 | `:379`-`:380`、`:386`-`:387` |
| `bar_r_d2`（彩条入口已 D=3，+1+2） | **6** | `:383`-`:384`、`:388` |
| `pix_left`/`oob_fb_d1`/`left_pix` | 5 | `:396`-`:403` |
| `de_d[3]`（效果链 de_in 参考） | **4** | `:415` |
| `pipe_dout`（效果链列延迟 9，见 §4.6） | **14**（视频源）/ **15**（彩条右路） | `:410`-`:419` |
| `x_d11`/`de_d11`（split_display 光栅基准） | 12 | `:445`-`:452` |
| `orig_disp`/`oob_lo`/`oob_ro` | 12（与光栅**精确一致**） | `:441`-`:443` |

⇒ 结论（推导）：左半窗对齐精确；右半窗 `pipe_dout` 比光栅基准晚 **2 列**（彩条源时晚 3 列）；
效果链自身的 `de_in`（D=4）与 `din`（D=5）之间有 **1 拍** 固定错位。

## 2. 效果使能与旁路

- 5 级级联，`bypass = ~effect_en[i]`，**没有旁路开关总线，全部是"每级一个反相位"**：
  `src/rtl/process/proc_pipeline.v:24`-`:28`。
- 位序：`effect_en[0]=gray, [1]=binary, [2]=blur, [3]=sobel, [4]=invert` —— `src/rtl/process/proc_pipeline.v:3`；
  串口串 "00111" ⇒ en[2]/[3]/[4] 开，**左起字符 = bit0** —— `proc_pipeline.v:4`；
  PS 侧 `en |= bit << n`（n 为字符下标）证实左起=bit0 —— `src/ps/main.c:74`；
  OSD `EN=` 字段第 1 个字符打印 `effect_en[0]` —— `src/rtl/video/osd_overlay.v:102`-`:106`。
- 旁路仍占 1 拍（dout 是寄存器）：`dout <= bypass ? din : <结果>`
  —— `proc_gray.v:30`、`proc_binary.v:29`、`proc_invert.v:23`、`proc_sobel.v:63`-`:66`。
  **例外**：blur 旁路时输出 `p11`（窗中心），不是 `din` —— `proc_box_blur.v:69`-`:72`。

## 3. 逐效果算术与位宽（含饱和/截断）

### 3.1 proc_gray —— 1 拍

- 565 拆分：`r5=din[15:11]`、`g6=din[10:5]`、`b5=din[4:0]` —— `src/rtl/process/proc_gray.v:12`-`:14`。
- 扩 8 bit = MSB 复制：`r8={r5,r5[4:2]}`、`g8={g6,g6[5:4]}`、`b8={b5,b5[4:2]}` —— `:16`-`:18`
  （`proc_binary.v:16`-`:18`、`proc_sobel.v:24`-`:26`、`src/rtl/video/split_display.v:45`-`:47` 四处完全相同）。
- BT.601 近似：`y16 = r8*77 + g8*150 + b8*29`，系数和恰为 256 ⇒ `y8 = y16[15:8]` 无溢出
  —— `proc_gray.v:19`-`:21`（注释 `:19` 自述 0.299/0.587/0.114 → 77/150/29 ÷256 = 0.3008/0.5859/0.1133）。
- 回包 565：`gray = {y8[7:3], y8[7:2], y8[7:3]}`（R=B=同一 5 bit，G 取高 6 bit，纯截断无舍入）
  —— `proc_gray.v:22`。
- 流水深度：1 级（`de_out`/`dout` 同拍寄存）—— `:24`-`:32`。

### 3.2 proc_binary —— 1 拍

- 重新解码输入并**再算一次 y8**：`y16 = r8*77+g8*150+b8*29`；`bin = (y16[15:8] >= threshold)`
  —— `src/rtl/process/proc_binary.v:19`-`:20`。
- 输出只有两值：`bw = bin ? 16'hFFFF : 16'h0000` —— `:21`。`>=` ⇒ 阈值本身判白。
- 若 gray 与 binary 同开，二值化作用在"已量化回 565 的灰度"上（`proc_pipeline.v:35`-`:43` 级联顺序），
  有效阈值相对原亮度略有偏移（推断）。
- TH 来源链：AXI GPIO bit[15:8] → `threshold` → `effect_ctrl` 3 级寄存 → `th_sync` → `proc_binary.threshold`
  —— `src/rtl/top/system_top.v:164`、`src/rtl/process/effect_ctrl.v:8`、`:13`、`:26`-`:29`、
  `src/rtl/top/pl_video_top.v:84`-`:89`、`:412`。
- `effect_ctrl` 复位默认 **80**（`th_meta/th_sync/threshold` 三处同值）—— `effect_ctrl.v:19`-`:22`；
  PS 侧默认同为 80 —— `src/ps/main.c:29`；UART `TH<dec>` 限幅 0..255 —— `main.c:102`-`:106`。

### 3.3 proc_box_blur —— 3 拍（列），并恒定上移 1 行

- 两片行缓存，深度 `H_ACTIVE`(=512)，宽度 16 bit（整像素，不是亮度）：
  `lb0`、`lb1`，均打 `(* ram_style = "block" *)` —— `src/rtl/process/proc_box_blur.v:18`-`:19`。
- 写：`lb0[x_in] <= lb1[x_in]; lb1[x_in] <= din;` 仅 `de_in` 时 —— `:25`-`:30`。
- 读：**组合（异步）读** `r0 = lb0[x_in]`、`r1 = lb1[x_in]` —— `:32`-`:33`。
- 9 点分量和：R/B 为 5 bit×9 → `rs`/`bs` 声明 10 bit（注释按 9 bit 估）；
  G 为 6 bit×9 → `gs` 声明 11 bit —— `:36`-`:44`、`:35`（注释）。
- 除以 9 用乘法：`*57 >> 9`，`57/512 = 0.111328 > 1/9` —— `:46`-`:49`；
  取位 `r_avg = rp[13:9]`、`g_avg = gp[14:9]`、`b_avg = bp[13:9]` —— `:50`-`:52`；
  常数场（R=31、G=63）验证结果精确等于原值 ⇒ 无饱和问题，仅存在 ≤1 LSB 的正偏（推断，由 `:46`-`:52` 位运算）。
- 输出 `avg = {r_avg, g_avg, b_avg}` —— `:53`。**按 R/G/B 三分量独立平均**，不是亮度域模糊。
- 窗口移位只在 `de_in` 时进行：`p00<=p01; p01<=p02; p02<=r0;` 等三行 —— `:60`-`:64`。
- 输出选择：`if (bypass || y_d1 == 12'd0) dout <= p11; else dout <= avg;` —— `:69`-`:72`；
  `y_d1 <= y_in` —— `:66`。
- `de` 链：`de_d1 <= de_in; de_d2 <= de_d1; de_out <= de_d2;` —— `:65`-`:68` ⇒ 3 拍。
- 寄存器数：9×16 + `de_d1/de_d2` + `y_d1`(12) + `dout`(16) + `de_out` = 175 触发器（`:21`-`:23`、`:15`-`:16`）。

### 3.4 proc_sobel —— 3 拍，+1 行位移（仅当使能）

- 行缓存 8 bit（存亮度）：`lb0/lb1 [0:H_ACTIVE-1]`，`ram_style="block"` —— `src/rtl/process/proc_sobel.v:17`-`:18`。
- 亮度在前级组合算出后写入：`lb1[x_in] <= y8` —— `:27`-`:34`。
- Gx（列差，中心列不参与）：`-p00 -2*p10 -p20 +p02 +2*p12 +p22` —— `:40`-`:41`；
  Gy（行差，中心行不参与）：`-p00 -2*p01 -p02 +p20 +2*p21 +p22` —— `:42`-`:43`。
  2 倍用 `{2'b0,p10,1'b0}` 移位实现；全部符号扩展到 11 bit signed（最大 |±1020| < 1024，不溢出）。
- 幅值 = `|Gx| + |Gy|`（曼哈顿近似，无开方）：`agx/agy = gx[10] ? -gx : gx`，`mag = agx+agy`（12 bit）
  —— `:44`-`:46`。
- 饱和：`m8 = (mag > 12'd255) ? 8'd255 : mag[7:0]` —— `:47`；
  回包 `sobel_out = {m8[7:3], m8[7:2], m8[7:3]}`（白边黑底）—— `:48`、`:2`（注释）。
- `de` 链与 blur 相同 3 拍 —— `:60`-`:62`；旁路为真直通 `dout <= din` —— `:63`-`:66`。
- **无行边界保护**：`y_in` 在本模块声明后完全未用（`:12` 为唯一出现处），
  因此不像 blur 那样对第 0 行做保护，首行用上帧末行的陈旧行缓存内容（推断，由 `:30`-`:35`、`:55`-`:59`）。
- 寄存器数：9×8 + 2 + 16 + 1 = 91 触发器。

### 3.5 proc_invert —— 1 拍

- 逐字段按位取反，**不是整 16 bit 取反**：
  `r5 = ~din[15:11]`、`g6 = ~din[10:5]`、`b5 = ~din[4:0]`，`inv = {r5,g6,b5}`
  —— `src/rtl/process/proc_invert.v:12`-`:15`。
  （等价于 565 各通道内取反，与 `~din` 结果相同，因为字段拼接恰好覆盖 16 bit —— 推断）

### 3.6 级联总深度 vs 文中声明

| 阶段 | 列延迟 | 垂直行偏移 | 证据 |
|---|---|---|---|
| gray | 1 | 0 | `proc_gray.v:29`-`:30` |
| binary | 1 | 0 | `proc_binary.v:28`-`:29` |
| box_blur | 3 | −1 行（旁路/使能都一样） | `proc_box_blur.v:65`-`:68`、`:69`-`:72` |
| sobel | 3 | −1 行（仅使能时） | `proc_sobel.v:55`-`:62` |
| invert | 1 | 0 | `proc_invert.v:22`-`:23` |
| **合计** | **9 拍（与使能位无关，恒定）** | **−1 行（全旁路）/ −2 行（sobel 使能）** | 上述行号 |

- **不匹配 1（核心）**：`localparam PROC_LAT = 7; localparam LEFT_TAIL = PROC_LAT;`
  —— `src/rtl/top/pl_video_top.v:405`-`:406`。实际每列 9 拍。
  由 §1.4：`orig_disp` 落在 D=12 与 `x_d11` 精确对齐（左半窗正确），
  而 `pipe_dout` 落在 D=14 ⇒ 右半窗的处理结果比其几何位置**晚 2 列**显示；
  同时右半窗的 OOB 遮罩 `oob_ro`（D=12）与像素（D=14）错 2 列 ⇒ 缩放/旋转边界处会出现 2 像素宽的错切黑边
  （推断，由 `:441`-`:454` 与延迟链常量）。
  若 PROC_LAT 改为 9，则 `orig_disp` 为 D=14，需把 `:445`-`:446` 的 11 改成 13（`SB=16` 已提供 0..15 的下标，推断这是 SB 取 16 而非 12 的余量）。
- **不匹配 2**：`de_in`（D=4）与 `din`（D=5）在效果链入口差 1 拍 —— `src/rtl/top/pl_video_top.v:415`、`:417`；
  后果：`proc_*_blur/sobel` 的行缓存"写索引"与"像素"整体错 1 列，且 `pipe_de`（D=13）与 `pipe_dout`（D=14）不自洽。
- **不匹配 3**：彩条右路 `bar_r_d2`（D=6）比彩条左路 `bar_l_d4`（D=5）多 1 拍
  —— `src/rtl/top/pl_video_top.v:383`-`:384`（入口已 D=3）、`:388`（2 级）、`:401`（用 d2）vs `:398`（用 d4）。
  ⇒ SRC0（彩条）与 SRC1（视频）下右半窗的水平配准相差 1 列。
- **不匹配 4**：`src/rtl/process/rotate/rotate_mapper.v:4` 注释自述 "Multiplies registered in 2 stages"
  且"at 75 MHz"；实际是 3 级（`xp/yp` → `xr_m/yr_m` → `x_out/y_out/oob`，`:24`-`:37`、`:45`-`:65`），
  且像素时钟是 50 MHz（`src/rtl/clocks/clk_gen.v:21`、`src/constraints/rk_zynq7020.xdc:6`）。
- **不匹配 5**：`src/rtl/process/proc_box_blur.v:2` 注释 "bypass => center pixel"。
  旁路输出的是 `p11`（3×3 窗中心 = 上一行的像素），不是当前输入像素 —— `:69`-`:72`。
  ⇒ 即使 blur 关闭，右半窗仍恒定下移 1 行（与左半窗不重合）。

## 4. 3×3 卷积的真实实现方式

- **不是** `line_cache.v`。`src/rtl/video/line_cache.v` 全文存在（双口、`wr_clk`/`rd_clk`、
  越界读回 `16'h0000`，`:14`-`:26`），但在 `src/` 内**没有任何例化点**（全仓搜索仅命中自身声明、
  工程文件清单 `vivado_system/zynq_video_sys.xpr:108` 与文档
  `report/ARCHITECTURE.md:93`、`report/MODULES.md:79`、`report/ISSUES.md:129`：「旧 line_cache（左扫右读）废弃」）。
- 真实实现：**每算子 2 片行缓存 + 3×3 移位寄存器阵列**（`p00..p22`），
  属于**逐像素流式滑窗**，不是"取窗口"式随机访问 —— `proc_box_blur.v:18`-`:33`、`:55`-`:64`；
  `proc_sobel.v:17`-`:35`、`:50`-`:59`。
- **行数**：2 行（`lb0` = row−2、`lb1` = row−1），第 3 行由 `din` 直接给 —— blur `:27`-`:28`、`:32`-`:33`、`:63`；
  sobel `:32`-`:33`、`:56`-`:58`。
- **窗口在目标域（显示/画布域）**建立：`x_in/y_in` 用的是 `cx_d[3]/cy_d[3]`（画布坐标），
  输入流是"逆映射之后的右窗光栅" —— `src/rtl/top/pl_video_top.v:415`-`:417`；
  设计意图见 `src/rtl/process/proc_pipeline.v:22`-`:23`（注释）与 `report/ROTATION_AND_EFFECTS.md:20`-`:25`。
- **2 倍行复制的必然后果（推断，由 `pl_video_top.v:113` + `proc_box_blur.v:26`-`:28`）**：
  行缓存的"上一行"= 上一条**显示行**，而 `cy = y>>1` 使相邻两条显示行对应同一源行，
  于是在偶数显示行窗口的上/下邻行是源 row−1/row+… 的错采样：3×3 在垂直方向的实际源跨度只有 1.5 行，
  逐行交替（奇数行的中心行与最新行同源同数据）。Sobel 的垂直梯度与 blur 的垂直平均因此呈"梳齿"状退化。
- **边界处理**：
  - 水平：`x_in=0` 时窗口的"左列"来自上一行末尾（`p*0` 在 `de_in` 间断流后保持不动，`:60`-`:64` 的移位仅在 `de_in` 执行），
    即**回卷污染**；`x_in=511` 时"右列"来自下一行首像素。无任何 clamp/复制边缘处理（推断，由 `:26`、`:60`）。
  - 垂直：blur 用 `y_d1 == 0` 把第 0 行改判为旁路（`:69`-`:70`），但旁路值本身是上一行的 `p11`，
    且该保护在行首有 1 拍错位（`y_d1@T = y_in@T-1` 而输出槽位对应 `y_in@T-2`）—— `:66`、`:69`。
    sobel 完全没有该保护（`y_in` 未用，`proc_sobel.v:12`）。
  - 跨帧：行缓存不清零，首帧/换帧后头两行仍含上一帧数据（推断，由 `:25`-`:30` 无刷新逻辑）。
- **实现层事实**：`ram_style="block"` 对 blur/sobel 的 `lb1` **不成立**，综合强制改分布式 RAM，
  并报 warning：`[Synth 8-6849] Infeasible attribute ram_style = "block" set for RAM
  "u_pl/u_pipe/u_blur/lb1_reg", trying to implement using LUTRAM`（sobel 同）——
  `build/build_r05_skid.log:999`-`:1002`；最终映射：
  `u_blur/lb0_reg = 512x16 BRAM(1×RAMB18)`、`u_sobel/lb0_reg = 512x8 BRAM(1×RAMB18)`
  —— `build/build_r05_skid.log:1124`-`:1125`（Block RAM: Final Mapping Report，表头 `:1116`）；
  `u_blur/lb1_reg = 512x16 LUTRAM(RAM256X1S x32)`、`u_sobel/lb1_reg = 512x8 LUTRAM(RAM256X1S x16)`
  —— `build/build_r05_skid.log:1138`-`:1139`（Distributed RAM: Final Mapping Report，表头 `:1129`；
  两行 Inference 列均写作 **"Implied"** 而非 "User Attribute"，说明用户的 `ram_style` 属性已被丢弃）。
  对照：显示帧缓存 `u_fb` = `lo_reg 32Kx64 → 64×RAMB36` + `hi_reg 8Kx64 → 16×RAMB36` —— `:1122`-`:1123`。
  根因是 `:32`-`:33`（sobel `:56`-`:57`）的组合读；只有 `lb0` 因为读被寄存器化（在 `:61`-`:62` 内 `p02<=r0`）而保住了 BRAM —— 推断自上述报告与源码。

## 5. 旋转

### 5.1 反映射公式（RTL 原文）

- s0（中心化 + Y 翻转，**无复位**）：`xp <= x_in - IMAGE_W/2; yp <= IMAGE_H/2 - y_in;`
  —— `src/rtl/process/rotate/rotate_mapper.v:24`-`:28`。
- s1（Q8 乘加）：
  `xr_m <= xp*cos_v + yp*sin_v;`
  `yr_m <= -(xp*sin_v) + yp*cos_v;`
  —— `:33`-`:36`（`xp` 由 13 bit 符号扩展到 24 bit：`$signed({{11{xp[12]}}, xp})`）。
  即旋转角为 **−angle**（注释 `:3`："rotate by -angle (matches reference matlab)"）。
- s2（移位 + 反中心 + 越界判定）：
  `xr = xr_m >>> 8; yr = yr_m >>> 8;`
  `xs = xr + IMAGE_W/2; ys = IMAGE_H/2 - yr;`
  —— `:40`-`:43`；输出寄存 `:45`-`:65`。
- 角度→象限的完整公式（推导自 `:33`-`:43`）：
  `sx = ((x−256)·cosθ + (150−y)·sinθ)/256 + 256`，
  `sy = 150 − ((−(x−256)·sinθ + (150−y)·cosθ)/256)`，整除用**算术右移（向 −∞ 取整）**，
  故负坐标额外 −1 偏置（推断，由 `>>>8`）。
- 位宽：`xp/yp` signed 13 bit，`sin_v/cos_v` signed 10 bit，乘积 `xr_m/yr_m` signed 24 bit；
  综合实际落在 DSP 上：`A2*B 13x10 → P23`、`(PCIN±A2*B)' → P24`（AREG=1，即 s1 被吸收进 DSP 输入寄存器）
  —— `build/build_r05_skid.log:1081`-`:1084`（DSP Preliminary Mapping Report 中 `rotate_mapper` 行）。

### 5.2 越界行为

- `if (xs<0 || xs>=IMAGE_W || ys<0 || ys>=IMAGE_H) x_out<=0; y_out<=0; oob<=1'b1;` —— `:55`-`:58`；
  否则 `x_out<=xs[11:0]; y_out<=ys[11:0]; oob<=1'b0;` —— `:59`-`:63`。
- 即**填黑**，不是 clamp/复制边缘：`oob` 一路传到
  `pix_left/pix_right = oob_fb_d1 ? 16'h0000 : ...`（`src/rtl/top/pl_video_top.v:398`-`:401`）
  与 `split_display` 的 `sel = oob ? 16'h0000 : ...`（`src/rtl/video/split_display.v:28`）。
  注意 `x_out/y_out` 仍被强制成 0，所以被遮罩的那一拍其实读的是源 (0,0) 像素（无害，但非"不读"）。

### 5.3 sin/cos ROM 的构造

- 两个文件均为**手写的 `always @(*) case` 组合查表**（不是 BRAM、无输出寄存器 ⇒ 0 拍延迟，组合项）：
  `src/rtl/process/rotate/sin_rom.v:7`-`:370`、`cos_rom.v:7`-`:370`。
- 注释自述生成式：`round(fn(angle_deg)*256), signed 10-bit` —— `sin_rom.v:2`、`cos_rom.v:2`。
- 地址 9 bit（0..359），**每个 ROM 恰好 360 条 case 项**（`grep -c "^            9'd"` = 360）+ `default`。
- `default` 值：`sin_rom.v:369` → `10'sd0`；`cos_rom.v:369` → `10'sd0`。
  ⇒ 若 `angle ≥ 360`（`angle_ctrl` 正常不会给出，`:17`-`:19` 在 0/359 处回绕），
  sin=cos=0 ⇒ 映射把所有点塌到源图中心 (256,150)。`cos` 的 default 用 0 而不是 256，
  与 0° 恒等不一致，属潜在隐患（推断，仅 `angle_ctrl` 越界或综合网表异常时可达）。
- 精度：Q8（÷256），可表示 ±256 ⇒ |sin|、|cos| 在 0°/90°/180°/270° 处为 **256 而非 255**，
  即 1.0 精确定标；10 bit signed（范围 −512..511）足够。

### 5.4 角度→(sin,cos) 实测对照表（逐条从文件读出）

| angle | sin_rom 值 : 行 | cos_rom 值 : 行 | 十学期望 ×256 |
|---|---|---|---|
| 0 | 0 : `sin_rom.v:9` | 256 : `cos_rom.v:9` | 0 / 256 |
| 45 | 181 : `sin_rom.v:54` | 181 : `cos_rom.v:54` | 181.02 |
| 90 | 256 : `sin_rom.v:99` | 0 : `cos_rom.v:99` | 256 / 0 |
| 135 | 181 : `sin_rom.v:144` | −181 : `cos_rom.v:144` | 181.02 / −181.02 |
| 180 | 0 : `sin_rom.v:189` | −256 : `cos_rom.v:189` | 0 / −256 |
| 225 | −181 : `sin_rom.v:234` | −181 : `cos_rom.v:234` | −181.02 |
| 269 | −256 : `sin_rom.v:278` | −4 : `cos_rom.v:278` | −255.95 / −3.54 |
| 270 | −256 : `sin_rom.v:279` | 0 : `cos_rom.v:279` | −256 / 0 |
| 271 | −256 : `sin_rom.v:280` | 4 : `cos_rom.v:280` | −255.95 / 3.54 |
| 315 | −181 : `sin_rom.v:324` | 181 : `cos_rom.v:324` | −181.02 |
| 359 | −4 : `sin_rom.v:368` | 256 : `cos_rom.v:368` | −4.45 / 255.96 |

- 45° 处 181/256 = 0.70703 vs 0.70711 ⇒ 相对误差 1.1e−4（推断，由 `sin_rom.v:54`）。
- **每份设计里 sin/cos ROM 各被例化两次**：`rotate_mapper.v:20`-`:21` 与 `zoom_mapper.v:22`-`:23`
  ⇒ 共 4 个查表实例。综合实证：**全部实现为 LUT，不占 BRAM**
  —— `build/build_r05_skid.log:1034`-`:1039`（ROM: Preliminary Mapping Report 列出
  `sin_rom/value`、`cos_rom/value`、`rotate_mapper u_sin|u_cos/value`、`zoom_mapper u_sin|u_cos/value`
  均 "512x10 → LUT"；表头 `:1030`）。注意条目按 512 深（9 bit 地址全展开）而非 360。

### 5.5 角度如何进来（按键 → angle_ctrl → deg）

- `key1_n/key2_n`（低有效）→ 两个独立 `key_debounce #(.CNT_MAX(1_000_000))`，
  `clk = sys_clk`，`key_stable()` 输出**悬空** —— `src/rtl/top/pl_video_top.v:68`-`:73`。
- 脉冲 `p1/p2` → `angle_ctrl`：`key_inc=p1`、`key_dec=p2`，
  `angle[8:0]`、`rotate_active = (angle != 0)` —— `:74`-`:80`、`src/rtl/process/rotate/angle_ctrl.v:11`-`:19`。
- `angle` 由 `sys_clk` 域的 9 个触发器产生，被 `clk_pix` 域的 `rotate_mapper`/`zoom_mapper`/
  `split_display`/`osd_overlay` 直接整总线使用（`:127`、`:156`、`:455`、`:494`）。
  两时钟同源同频（`clk_gen.v:17`、`:21`），且 XDC 把 `sys_clk` 与其生成时钟放进**同一** group，
  组内路径仍参与时序分析 ⇒ 不是未检查的异步 CDC（`src/constraints/rk_zynq7020.xdc:53`-`:56`）。
  但 `angle` 在 s0/s1 之间跳变时，`xp/yp`（旧）与 `sin/cos`（新）会不同拍 ⇒ 每按一次键有 1 帧内若干像素的过渡撕裂（推断）。
- `rotate_active` 在 `sys_clk` 域是 `angle != 0` 的组合译码（`angle_ctrl.v:11`），
  直接被 `clk_pix` 域用作 `sx_l`/`oob_l` 的选择信号（`pl_video_top.v:146`-`:149`）。
- 单位 = 1 度，0..359 回绕，**无小数度**（`angle_ctrl.v:17`-`:19`）。

## 6. 缩放

### 6.1 inv_scale 的 Q8 方案

- 语义：`INV_LO=256` 为 1.0×（最大），`INV_HI=512` 为 0.5×（最小，四周黑边），
  "inv 越大 → 采样越散 → 画面越小" —— `src/rtl/process/zoom/zoom_ctrl.v:2`-`:4`、`:6`-`:7`；
  顶层参数覆盖：`#(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd2))` —— `src/rtl/top/pl_video_top.v:117`。
- 11 bit 有符号扩展才能放得下 512：`wire signed [10:0] inv = $signed({1'b0, inv_scale});`
  —— `src/rtl/process/zoom/zoom_mapper.v:26`（注释 `:25`）。
- 无旋转分支：`raw_xs = xp_s1 * inv`（Q8）、`xs_pix = raw_xs >>> 8`、
  `sx_c = xs_pix + IMAGE_W/2`；`yp_disp = y_in − IMAGE_H/2`（**显示域，不做 Y 翻转**）
  ⇒ `sy_c = ys_pix + IMAGE_H/2` —— `zoom_mapper.v:32`-`:34`、`:60`-`:61`、`:65`-`:71`。
  与 `report/ROTATION_AND_EFFECTS.md:48`-`:51` 给出的 `sx = W/2 + ((x−W/2)*inv)>>8` 一致。
- 有旋转分支：先 Q8 旋转（`xr_m/yr_m`，用 `yp_math`），再乘 inv，最后 `>>>16`
  —— `:46`-`:51`、`:58`-`:64`、`:68`-`:70`。
  ⇒ RTL 的实际顺序是**先旋转后缩放**，而 `report/ROTATION_AND_EFFECTS.md:53` 的文字是"先缩放偏移再套旋转"
  （对"同一中心的等比缩放 + 旋转"二者可交换，故结果等价 —— 推断）。
- `rot_xs = xr_m * inv` 声明为 32 bit，而 24×11 乘积自定宽度为 35 bit ⇒ 高 3 bit 被丢；
  综合报告确认 DSP 用了 `A*B 24x11 → P 35`（且 AREG/BREG/CREG/DREG 全 0，纯组合）
  —— `build/build_r05_skid.log:1088`、`:1092`。
  按 IMG_W=512/IMG_H=300 与 inv≤512 估算最大 |值| ≈ (255+150)×256×512 ≈ 5.3e7 ≪ 2^31 ⇒ 该截断在本几何下无害（推断）。
- `inv=256` 时非旋转分支为严格恒等映射（`xp*256 >>> 8 == xp`，无舍入损失）—— 推导自 `:60`、`:65`。
- 0.5× 时的可见范围（推断自 `:65`-`:71`）：列 128..383（256 列显示 512 源列）、
  画布行 75..224（即显示行 150..449），四周各留 128 列 / 150 显示行黑边。

### 6.2 动画 / 呼吸循环

- 更新时机：只在 `frame_start` 单拍脉冲上（每帧一次）—— `zoom_ctrl.v:27`；
  `frame_start` 为 `(0,0)` 处 1 拍脉冲 —— `src/rtl/video/video_timing.v:68`、`:51`。
- 三角波：`dir=0` 时 `inv_scale + STEP >= INV_HI` → 顶到 512 并翻转 `dir`；
  `dir=1` 时 `inv_scale <= INV_LO + STEP` → 回 256 并翻转 —— `:28`-`:44`。
- 周期：256→512 用 128 帧，512→256 用 128 帧 ⇒ **256 帧一个完整呼吸**；
  16.8 ms/帧 ⇒ ≈ 4.30 s（推断，由 `:8` STEP=2 与 §0 帧周期）。每帧线性变化 2/256 = 0.78%。
- `zoom_active`：`frame_start` 分支里无条件 `<= 1'b1`（`:45`），否则 `<= (inv_scale != INV_LO)`（`:47`）
  ⇒ 它只是状态位，**并不参与 zoom_mapper 的使能**（`zoom_mapper` 无 enable 端口，
  `pl_video_top.v:154`-`:160`），缩放恒生效；`inv_scale=256` 时为数学恒等，等效"关"。
- `enable` 通路：`zoom_en` → 3FF `ze0/ze1/ze2`（ASYNC_REG），**复位值取 `ZOOM_DEFAULT_ON[0]`**，
  `zoom_run = ze2` —— `pl_video_top.v:91`-`:101`、`:10`、`:119`。
  `!enable` 时 `inv_scale/dir/zoom_active` 全部回到 1.0×（`zoom_ctrl.v:23`-`:26`）。
- **板级 `zoom_en` 被硬绑 `1'b1`** —— `src/rtl/top/system_top.v:165`；
  PS 侧也确认"当前 RTL 常开，bit17 仅预留" —— `src/ps/main.c:31`、`:155`；
  `build/tcl/set_src.tcl:1`-`:8` 的 GPIO 值 `0x00010000` 也只用到 bit16。

### 6.3 `frac_x / frac_y`：算了，但没人用（题设怀疑成立）

- 生成：`fx = rot_s1 ? 8'h00 : raw_xs[7:0]`、`fy = rot_s1 ? 8'h00 : raw_ys[7:0]`
  —— `zoom_mapper.v:73`-`:74`，即 Q8 定点的小数低 8 bit（非旋转分支）；
  寄存输出 `:81`-`:94`（越界时清 0）。
- 顶层连接：`wire [7:0] zfrac_x, zfrac_y;` → `.frac_x(zfrac_x), .frac_y(zfrac_y)`
  —— `src/rtl/top/pl_video_top.v:153`、`:159`。
- **全仓检索 `zfrac_x`/`zfrac_y` 只有这两处命中，无任何读方**；
  `frac_x/frac_y` 的其余命中全在 `zoom_mapper.v` 自身与 `sim/tb_zoom_mapper.v:31`。
  ⇒ 确认：小数坐标未被消费，缩放是**最近邻**采样，无 bilinear 插值（证据同上）。
- 附带：即使将来使用，一旦与旋转叠加（`rot_s1=1`）小数位被强制为 0（`:73`-`:74`），插值信息不可得。

## 7. 开窗（windowing）与左右半屏分隔

- **目标域开窗（效果）**：3×3 用画布坐标建窗 —— `pl_video_top.v:415`-`:417`（`de_d[3]/cx_d[3]/cy_d[3]`），
  设计说明 `proc_pipeline.v:22`-`:23`、`report/ROTATION_AND_EFFECTS.md:20`-`:25`。
- **源域开窗（几何）**：逆映射决定"从源图哪块矩形取样"：
  旋转中心 `(IMAGE_W/2, IMAGE_H/2) = (256, 150)` —— `rotate_mapper.v:26`-`:27`、`:42`-`:43`；
  缩放中心同上、比例 `inv/256` —— `zoom_mapper.v:32`-`:34`、`:68`-`:71`。
- **偏移/尺度常量清单**：
  `PANE_W = 512`（`:8`、`:111`-`:112`）；`IMG_W=512`、`IMG_H=300`（`:6`-`:7`）；
  `cy = y>>1`（2 倍垂直放大，`:113`）；`BASE_ADDR = 32'h1000_0000`（`:9`）；
  Q8 移位 `>>>8`（`rotate_mapper.v:40`-`:41`、`zoom_mapper.v:65`-`:66`）与 `>>>16`（`zoom_mapper.v:63`-`:64`）；
  `INV_LO/HI/STEP = 256/512/2`（`pl_video_top.v:117`）；`SB=16`、`PROC_LAT=LEFT_TAIL=7`（`:162`、`:405`-`:406`）；
  消隐守卫 `DISP_V_LINES=600 / DISP_V_LAST=624 / VB_X_GUARD=1279`（`:207`-`:209`）；
  `VBLANK_AXI_CYC=67200`（`:248`）。
- **左右分隔（4 处独立实现，各自延迟不同）**：
  1. `left_pane = (x < PANE_W)` 组合 —— `:111`。
  2. FB 读地址选择 `fb_sel_right = ~left_d[2]`（D=3）—— `:351`。
  3. 像素源选择 `left_pix = left_sel_d1`（D=5）—— `:358`、`:391`-`:396`。
  4. 进效果链的门控 `de_d[3] && !left_d[3]`（D=4）—— `:415`。
  5. 屏上最终分屏 `split_display` 用 `left = (x < PANE_W)` 再选一次，
     并在 `x == PANE_W-1 || x == PANE_W` 画 2 条 `(0x40,0x40,0xFF)` 分隔线 —— `src/rtl/video/split_display.v:26`-`:32`、`:42`-`:44`。

## 8. 悬空端口 / 常量绑定 / 死模块 / 死代码 清单

### 8.1 常量绑定的端口输入

| 位置 | 事实 |
|---|---|
| `pl_video_top.v:127` | `rotate_mapper .enable(1'b1)` 硬接 ⇒ `rotate_mapper.v:50`-`:53` 的 `!enable` 直通分支为**死代码** |
| `system_top.v:165` | `pl_video_top .zoom_en(1'b1)` 硬接 ⇒ GPIO bit17、`ZOOM_DEFAULT_ON`、`ze0/1/2` 同步链全部退化为常量 1（`pl_video_top.v:91`-`:101`） |
| `pl_video_top.v:290` | `assign copy_hold = 1'b0;` ⇒ 反向送给 ETH 发送侧 `u_eth.copy_hold`（`system_top.v:136`）的反压永久释放 |
| `pl_demo_top.v:29` | 演示顶层同样 `.zoom_en(1'b1)` |
| `pl_video_top.v:497` | `osd_overlay .bg_pix(16'h0)` 常量 |
| `pl_demo_top.v:43`-`:48` | AXI 从侧全为常量/悬空（`m_axi_arready(1'b0)`、`m_axi_rdata(64'd0)` 等），且 `eth_ddr_base`/`eth_commit`/`copy_hold` **完全未连** |

### 8.2 声明但无消费者的输出（悬空）

| 信号 | 证据 |
|---|---|
| `pipe_de` | 声明 `pl_video_top.v:409`，仅 `:418` 连接，全文件无读方 |
| `zfrac_x`, `zfrac_y` | `:153`、`:159`（详见 §6.3） |
| `key_stable` | 两个 key_debounce 实例均留空 `()` —— `:69`、`:72` |
| `clk_200m_unused` | `:60`、`:63`；真正用到的 200 MHz 来自 `system_top.v:108`-`:112` 的**第二个 MMCM** `u_idelay_clkgen` ⇒ 全设计消耗 2 个 MMCM |
| `axi_frame_writer64 .frame_busy()` | `pl_video_top.v:330` 悬空 |
| `u_aw .copy_cycles()` | `:337` 悬空（`row_*` 那份 `:270` 才接到 `row_copy_cycles`→`copy_overrun`→`led[0]`，`:247`-`:254`、`:517`） |
| `status` | 顶层 `:56`、`:520`-`:521` 拼出 32 bit（位序：`[31]=zoom_dir [30]=zoom_active [29:20]=inv_scale [19]=eth_ready [18]=locked [17]=rotate_active [16:8]=angle [7:3]=en_sync [2]=src_use [1:0]=0`），但 `system_top.v:44`、`:184` 之后**无任何读方** |
| `angle_ctrl` 无 reset 场景 | `system_top.v:162` 把 `sys_rst_n` 绑 1 ⇒ `key_debounce`/`angle_ctrl` 永不复位（`pl_video_top.v:68`-`:80` 的 `.rst_n(sys_rst_n)` 实为常量），只靠 FPGA 配置期触发器清零 |

### 8.3 端口在模块内未被读（dead inputs）

| 模块:行 | 端口 | 说明 |
|---|---|---|
| `proc_box_blur.v:9` | `hs_in` | 全文件仅声明处出现（顶层 `pl_video_top.v:414` 还在认真驱动它） |
| `proc_box_blur.v:10` | `vs_in` | 同上（`:47` 驱动） |
| `proc_sobel.v:9` | `vs_in` | 未用（`:54` 驱动） |
| `proc_sobel.v:12` | `y_in` | 未用 ⇒ Sobel 无行边界保护（`:55` 驱动） |
| `proc_pipeline.v:12` | `rotate_active` | 注释自述 "retained for status"，模块体内无引用（顶层 `:413` 仍驱动） |
| `split_display.v:9` | `y` | 未用 |
| `split_display.v:16` | `angle_idx` | 未用（顶层 `:455` 传 `angle[1:0]`） |
| `pl_video_top.v:45`-`:50` | `eth_wr_clk/eth_wr_en/eth_wr_addr/eth_wr_data/eth_frame` | 5 个输入在 522 行内只出现在端口声明（`system_top.v:174`-`:179` 仍在驱动）⇒ ETH 直写 BRAM 的旧通路已悬空 |
| `pl_video_top.v:104` | `frame_done`（video_timing） | `:108` 驱动，之后无读方；另有 `:330` 的 `fill_done` 同样无读方（`grep -nw fill_done` 仅命中 `:216`、`:330`） |
| `color_bar.v:5` | `V_ACTIVE` 参数 | 被 `pl_video_top.v:377`、`:381` 传值，但模块体内 0 次引用 |

### 8.3b 综合器对上表的独立确认（`WARNING: [Synth 8-7129] ... has no load`）

| 证据行（`build/build_r05_skid.log`） | 端口 |
|---|---|
| `:638`、`:639` | `proc_box_blur` 的 `hs_in`、`vs_in` 无负载 |
| `:640`-`:642` | `proc_box_blur` 的 `x_in[11:9]` 无负载（只需 9 bit 索引 512 深） |
| `:622` | `proc_sobel` 的 `vs_in` 无负载 |
| `:623`-`:625` | `proc_sobel` 的 `x_in[11:9]` 无负载 |
| `:626`-`:637` | `proc_sobel` 的 `y_in[11:0]` **整条总线**无负载 |
| `:643` | `proc_pipeline` 的 `rotate_active` 无负载 |
| `:608`-`:619` | `split_display` 的 `y[11:0]` 整条无负载 |
| `:620`-`:621` | `split_display` 的 `angle_idx[1:0]` 无负载 |
| `:653`、`:654`、`:655`-`:657`（及后续同类行） | `pl_video_top` 的 `eth_wr_clk`、`eth_wr_en`、`eth_wr_addr[*]` 无负载 |
| `:645`-`:650`、`:651`-`:652` | `pl_video_top` 的 `m_axi_rid[5:0]`、`m_axi_rresp[1:0]` 无负载 —— 端口声明在
  `pl_video_top.v:39`、`:40`，全文只在端口列表出现；两个 writer 只消费 `m_axi_rdata/rlast/rvalid`（`:268`、`:335`） |
| `:558`-`:591` | `osd_overlay` 的 `src_sel`、`eth_link`、`net_pkts[15:0]`、`net_bad[15:0]` 无负载 —— 与 RTL 一致：
  这 4 个端口在 `src/rtl/video/osd_overlay.v:25`-`:28` 声明后**正文零引用**，顶层 `pl_video_top.v:495`-`:496` 白驱动；
  OSD 只有 `N_LINES = 3` 行（`osd_overlay.v:15`），内容固定为 `FPS=`、`ANG=`、`EN=` 三行（`:87`-`:106`），
  因此**屏上并不显示 NET/链路统计**（推断，基于上述行号） |
| `:592`-`:597`+ | `osd_overlay` 的 `bg_pix[15:0]` 无负载（`osd_overlay.v:29` 声明后零引用；顶层 `pl_video_top.v:497` 传常量 `16'h0`） |

### 8.4 死模块 / 死文件（在工程清单里但从不被例化）

| 模块 | 状态证据 |
|---|---|
| `src/rtl/video/line_cache.v` | 全 `src/` 无例化（见 §4 首条）；文档也确认废弃 `report/MODULES.md:79` |
| `src/rtl/video/frame_buffer.v` | 无例化 |
| `src/rtl/video/frame_buffer_db.v` | 无例化；文档记为"7020 BRAM/LUT 爆资源，实现失败" —— `report/VERSION_LINEAGE.md:56` |
| `src/rtl/axi/axi_frame_writer.v` | 无例化，仅 TB 使用 —— `sim/run_sim.tcl:18` 注释自述 |
| `src/rtl/video/video_timing_720p.v` | 无例化 |
| `src/rtl/top/pl_demo_top.v` | **不在综合文件清单**：`build/tcl/build_system.tcl:17`-`:18` 只加入 `pl_video_top.v` |
| 备注 | 上述文件仍被 `add_files` 逐目录 glob 收进工程（`build_system.tcl:14`-`:17`），因此被分析但不被综合（推断）；`report/OVERNIGHT_LOG.md:118` 已把"树内 10 个未综合死模块"记为 P09 |

### 8.5 声明了但从不使用的中间量 / 参数

- `color_bar.v:17` `wire [12:0] x8 = {x, 3'b000};` 计算后**从未使用**（真正的分界用 `th1..th7` 比较，`:20`-`:26`、`:29`-`:38`）。
- `zoom_ctrl` 的 `zoom_active` 无消费者（仅进 `status`，`pl_video_top.v:520`）。
- `ZOOM_DEFAULT_ON` 从未被任何实例化覆盖（全仓仅 `pl_video_top.v:10`、`:94`-`:96`）。
- `rotate_mapper`/`zoom_mapper` 的 `IMAGE_W/IMAGE_H` 默认值（640/360、512/300）与实参不同处均已显式传 `IMG_W/IMG_H`（`pl_video_top.v:125`、`:154`）⇒ 默认值形同虚设。
- `pl_video_top.v:59`、`:60` 的 `clk_pix5x` 只喂 `rgb2dvi`（`:505`），`clk_200m` 悬空（§8.2）。

### 8.6 复位/多驱动审计

- **没有任何寄存器被两个不同 `always` 块写**（逐文件按语句首位置左值扫描，未命中真正的跨块多驱动）。
  形似"同寄存器多处赋值"的都属同一块内 reset 分支与逻辑分支，或"先清后置"：
  `key_debounce.v:27` `pulse <= 1'b0;` 后 `:39`-`:40` 命中按下沿再 `pulse <= 1'b1`（末次赋值生效，产生 1 拍脉冲）；
  `color_bar.v:41`-`:55` case 先赋值、随后对角线条带条件覆盖；
  `zoom_ctrl.v:28`-`:44`、`rotate_mapper.v:45`-`:65`、`zoom_mapper.v:76`-`:96` 为 if/else 多分支同寄存器（正常）。
- 无复位的 `always @(posedge clk)` 块（像素域，靠 FPGA 上电零值）：
  `pl_video_top.v:385`-`:389`（bar 延迟）、`:392`-`:395`（`oob_fb_d1/left_sel_d1`）、
  `:461`-`:463`（`vs_pix_d0/d1`）、`:469`（`vt0/1/2`，带 ASYNC_REG 但无 reset）、`:483`-`:487`（`pkts_s/bad_s/link_s`）；
  `proc_box_blur.v:25`-`:30`、`proc_sobel.v:30`-`:35`（行缓存写口，RAM 本就不需复位）；
  `rotate_mapper.v:25`-`:28`、`:32`-`:37`；`zoom_mapper.v:31`-`:36`、`:42`-`:55`。
- 顶层 5 处 `(* ASYNC_REG = "TRUE" *)`：`ze*`(`:91`)、`em*`(`:225`)、`ss*`(`:273`)、`ac0/ac1`(`:294`)、`fs*`(`:314`)、`vt*`(`:468`)。
- `pl_video_top.v:471` 的 `always @(posedge sys_clk or negedge rst_pix_n)` 用 **clk_pix 域的 `rst_pix_n`** 作为 sys_clk 域计数器的异步复位
  —— 跨域异步复位（释放端未同步），实际由 `locked` 驱动（`:65`）。

## 9. PS → PL：效果位如何到达

- 物理载体：**AXI GPIO（`axi_gpio_0`，`C_GPIO_WIDTH = 32`）**，地址 `0x41200000` ——
  `build/tcl/build_system_axigpio.tcl:47`-`:49`；
  `vivado_system/.../design_1_axi_gpio_0_0_stub.v`（`C_GPIO_WIDTH=32`，实测 grep 命中）；
  PS 侧 `#define AXI_GPIO_BASE 0x41200000u` / `GPIO_DATA = +0x00` —— `src/ps/main.c:24`-`:26`。
- 位分配（BD → `gpio_o` → `pl_video_top`）：
  `src/rtl/top/system_top.v:164` 明确 `.effect_en(gpio_o[4:0])`、`.threshold(gpio_o[15:8])`、`.src_sel(gpio_o[16])`。
  PS 打包：`v = (cur_en & 0x1F) | (cur_thr<<8) | (cur_src<<16) | (cur_zoom<<17)` —— `src/ps/main.c:33`-`:40`。
  ⇒ **bit[4:0] = 5 个效果位，宽 5 bit；threshold 8 bit；src_sel 1 bit；bit17 = zoom（RTL 未用）**。
- 位序（bit0 = 最左字符）：`[0]=gray [1]=binary [2]=blur [3]=sobel [4]=invert`
  —— `src/rtl/process/proc_pipeline.v:3`-`:4`、`:24`-`:28`；`src/rtl/video/osd_overlay.v:102`-`:106`；
  `build/tcl/set_src.tcl:3`、`src/ps/README.md:12`。
- 跨域同步：`effect_ctrl` 用 `en_meta → en_sync → effect_en` 三级（阈值同构）——
  `src/rtl/process/effect_ctrl.v:12`-`:30` ⇒ 使能/阈值变化在 `clk_pix` 域 3 拍后可见，复位值 `5'd0 / 8'd80`。
  注意该模块**没有做灰码/握手**，只是多一级的 2FF 型同步（对"准静态"总线可接受 —— 推断）。
- 文档不一致（事实）：`src/ps/README.md:11`-`:14` 称该映射为 "EMIO GPIO map" 且未列 bit17；
  而实际 BD 用 AXI GPIO，且 `report/ARCHITECTURE.md:155` 明写"勿用 EMIO：本板 bank2 读回恒 0"。
  `build/tcl/build_system.tcl:39` 是 EMIO 使能=1 的另一版脚本（`build_system_axigpio.tcl:39` 为 0）。

## 10. key_debounce 与旋转按键

- 结构：2 级同步 `key_sync0/1` + 计数器 `cnt[20:0]` + `key_prev` 边沿检测 —— `src/rtl/util/key_debounce.v:12`-`:41`。
- 时间常数：`CNT_MAX` 默认 1_000_000，顶层覆盖为同一值 —— `key_debounce.v:4`、`src/rtl/top/pl_video_top.v:68`、`:71`；
  在 50 MHz `sys_clk` 下 = **20 ms**（推断，由 `src/constraints/rk_zynq7020.xdc:6`）。
  `key_stable` 语义："1 = 释放，0 = 按下" —— `key_debounce.v:10`；
  比较用 `cnt >= CNT_MAX[20:0]` —— `:29` ⇒ `CNT_MAX > 2^21−1` 会静默截位（推断）。
- 计数规则：`key_sync1 != key_stable` 时累加、达标才更新 `key_stable` 并清 `cnt`；
  一旦两值相等立即把 `cnt` 清零 —— `:28`-`:35` ⇒ 需要**连续 20 ms 稳定电平**，抖动/短按不产生事件。
- 脉冲：`pulse` 每拍先清 0，仅在 `key_prev && !key_stable`（释放→按下的边沿）置 1，宽度 = 1 个 `sys_clk` —— `:27`、`:37`-`:40`。
  ⇒ **长按只出一次脉冲，无连发**：`angle_ctrl.v:2` 注释里的 "Optional hold-to-accel" 在 RTL 中**未实现**。
- 两键同时按下：`angle_ctrl.v:16`-`:19` 是 `if (key_inc) ... else if (key_dec) ...`
  ⇒ **key_inc（KEY1，+1°）优先**，两键同刻脉冲时只 `+1`，不是"抵消/不变化"；
  两个 debounce 实例彼此独立（`pl_video_top.v:68`-`:73`），不存在互锁。
- 分工：KEY1 → `p1` → `key_inc`；KEY2 → `p2` → `key_dec` —— `pl_video_top.v:76`-`:79`；
  359→0 与 0→359 双向回绕 —— `angle_ctrl.v:17`、`:19`。
- 指示：`led[0]` = 心跳（正常 `hb[24]`，发生过 V-blank 拷贝超时则 `hb[22]` 快闪），`led[1]` = `src_use`
  —— `pl_video_top.v:512`-`:518`、`:249`-`:254`；`hb` 为 25 bit 自由计数器（`:512`-`:515`）。

## 11. 彩条源（几何对照用）

- `color_bar #(.H_ACTIVE(512), .V_ACTIVE(300))` 两个实例：
  左路 `.x(cx), .y(cy), .de(de)`，右路 `.x(sx_r), .y(sy_r), .de(de_d[2])`
  —— `src/rtl/top/pl_video_top.v:377`-`:384` ⇒ **右半窗的彩条本身已按缩放/旋转后的坐标生成**（几何域彩条）。
- 8 条色带按 `th_k = k*H_ACTIVE/8` 的**精确阈值比较**划分（非除法/近似）
  —— `src/rtl/video/color_bar.v:20`-`:26`、`:29`-`:38`；H=512 时每带 64 列（推断）。
  颜色序：白/黄/青/绿/品红/红/蓝/深灰(0x10) —— `:42`-`:51`。
  对角暗条：`((x+y) & 13'h001F) < 2` → 置 `(0x30,0x30,0x30)` —— `:52`-`:54`。
- 输出 1 级寄存，`de` 无效时强制 `16'h0000` —— `:57`-`:64`。

## 12. 一句话结论索引（供文档引用）

1. 效果链**只作用于右半窗**，左半窗是"仅旋转"的原图对照 —— `pl_video_top.v:415`、`:398`-`:401`。
2. 左右半窗共用 BRAM 的**同一个** 16 bit 读口，靠 `left_d[2]` 分时 —— `pl_video_top.v:351`-`:373`。
3. `PROC_LAT=7` 与真实列延迟 9 不符，导致右半窗比光栅基准晚 2 列 —— `pl_video_top.v:405`、§3.6。
4. 3×3 在"Y 被 2 倍复制的显示域"里建窗 ⇒ 垂直邻行一半的采样落在同一源行 —— `pl_video_top.v:113` + §4。
5. blur 即使旁路也把图像整体上移 1 行（输出 `p11`）—— `proc_box_blur.v:69`-`:72`。
6. 缩放是最近邻：`frac_x/frac_y` 生成了却无人使用，且与旋转叠加时被强制清 0 —— `zoom_mapper.v:73`-`:74`、`pl_video_top.v:153`/`:159`。
7. `zoom_en` 板级硬绑 1、`rotate_mapper.enable` 硬绑 1、`copy_hold` 硬绑 0 —— `system_top.v:165`、`pl_video_top.v:127`、`:290`。
8. blur/sobel 的 `lb1` 因组合读而落到 LUTRAM（`ram_style=block` 被综合忽略并报 warning）—— `build/build_r05_skid.log:999`-`:1002`、`:1129`-`:1141`。
9. `line_cache`/`frame_buffer`/`frame_buffer_db`/`axi_frame_writer`/`video_timing_720p`/`pl_demo_top` 均为不例化的死文件 —— §8.4。
10. 按键：20 ms 消抖、仅按下沿出脉冲（无连发）、两键同按时 +1° 优先 —— `key_debounce.v:27`-`:40`、`angle_ctrl.v:16`-`:19`。

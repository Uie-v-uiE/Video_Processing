`timescale 1ns/1ps
// pl_video_top — ghosting-fix v5
// Display BRAM written ONLY by axi_frame_writer_gated during blanking (~de).
// commit base locked until copy completes.
module pl_video_top #(
    parameter IMG_W     = 512,
    parameter IMG_H     = 300,
    parameter PANE_W    = 512,
    parameter BASE_ADDR = 32'h1000_0000,
    // PS 片源（SD 回放 / FILL 诊断帧）专用 DDR bank。ETH 用 BASE_ADDR 起的乒乓双 bank
    // （0x1000_0000 / 0x1008_0000），以前 PS 也写 0x1000_0000 ⇒ 两路同时跑时 SD 的 DMA
    // 会刷掉 ETH 正在填/正在读的那块 DDR，屏幕上就是"两个片源打架、闪"。
    // 仲裁只管"谁用 DDR→帧缓存这台搬运机"，**管不到谁写 DDR**（SD 的 DMA 走 PS 的 HP0，
    // 根本不经过 PL），所以这个重叠只能靠地址分开来治。
    parameter PS_BASE_ADDR = 32'h1010_0000,
    parameter ZOOM_DEFAULT_ON = 1
)(
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        axi_clk,
    input  wire        axi_rst_n,

    input  wire [4:0]  effect_en,
    // V8 的九位算法选择字（新控制字 gpio_cfg[8:0]）。0 = "PS 没意见"，此时 effect_ctrl 用
    // effect_en 翻出来的等价形式 —— 老工具（set_src.tcl / health_read.mjs）因此一字不改还能用。
    input  wire [8:0]  stage_sel,
    input  wire [7:0]  threshold,
    // 第二个控制字的**通道 2**（axi_gpio_2 的 GPIO2，偏移 +0x08）：gamma 表的
    // {en[31], wr[30], data[29:22], idx[21:14]}。位序与理由写在 gamma_lut.v / spec §6b。
    input  wire [31:0] gamma_ctl,
    input  wire        src_sel,
    input  wire        zoom_en,
    // V8-2 补的那半件事（2026-09-25）：串口命令可以把片源模式**钉住**，不必只靠按键环。
    // 都是 axi 域准静态电平，跨域与"命令优先还是按键优先"全在 `src_mode` 里处理，
    // 这一层只负责把线接过去（不许在这里自己采）。
    input  wire [1:0]  mode_ovr,        // 00 自动 / 01 锁 ETH / 11 锁 SD / 10 锁 TEST（屏上就印这三个词）
    input  wire        mode_ovr_tog,    // 翻一次 = 上面那个码是新写的
    // V8-8 手动缩放：`zoom_sel_async[2:0]` = 档号、`zoom_manual_async` = 1 停在手动档。
    // 两者与 `stage_sel` 来自**同一个 32 位控制字**（gpio_cfg1 = PS 侧 CFG_DATA0 的
    // [28:26] 与 [29]），都是 axi 域异步电平 ⇒ 一律交给 effect_ctrl 那条 sel 链同步，
    // 这一层**不许自己采样**（#24/#49 那一课）。
    input  wire [2:0]  zoom_sel_async,
    input  wire        zoom_manual_async,
    // PS 侧"这一帧 DDR 写完了"的发布脉冲：每翻转一次 = 请求 PL 在下一个 frame_start
    // 把 DDR 搬进显示帧缓存一次。SD 回放靠它避免撕裂（见 src/ps/sd_play.c 头部协议说明）。
    input  wire        ps_publish,

    input  wire        key1_n,
    input  wire        key2_n,
    output wire [1:0]  led,
    // 仲裁状态的可观测口（axi_clk 域电平）：给 system_top 映到健康 GPIO 的 lane30。
    // 为什么要它：`owner_eth` 决定"此刻屏幕归谁"，但它以前**只能靠眼睛看屏幕**才知道是什么值
    // —— 于是"停流不交回"这类板级红，夜里既看不见也没法记账。有了这一口，JTAG 读一次就判红绿，
    // 而且**红的时候能直接读出是谁占着**（见下面位序里的 mode / 两个 busy）。
    // 位序（与 system_top 的 lane30 一致，全部是 axi 域本来就有的电平 ⇒ 零新增跨域）：
    //   bit0=eth_tb_ok bit1=eth_live bit2=owner_eth bit3=fill_busy(PS 搬运中)
    //   bit4=row_busy(ETH 搬运中) bit[6:5]=仲裁看到的模式(格雷码，同 src_arb 的 sel) bit7=0
    //   V8-7 起往上加：**bit[10:8]=why_ps** = 判决那一拍看到的 `{force_ps, ~eth_live, ~eth_tb_ok}`
    //   （只在 bit2=0 即"屏幕归 PS"时才有"为什么"的意思），bit[15:11]=0。
    //   往上加而不是改低 8 位：lane30 的老读者（`arb_handover_test.mjs`、`lane30_watch.mjs`）
    //   都按位 0..6 解析，扩高半段是**向后兼容**的；改低 8 位会让它们的判据静默失效。
    output wire [15:0] dbg_src,
    // V8-6 链路内时延的可观测口（axi 域电平，**单位是 axi 拍数不是时间**，见 frame_latency 文件头）：
    //   lane29=c1（等消隐）lane28=c2（搬运）lane27=tot（提交→上屏）lane26=max lane25={n_meas,clamped}
    // 换算成时间戳在 `src/host/health_read.mjs` 里做（一个常量：fclk0=100 MHz ⇒ 1 拍 = 10 ns）。
    // 与 dbg_src 同一套做法：全部是 axi 域本来就有的电平 ⇒ 零新增跨域。
    output wire [6*32-1:0] dbg_lat,
    // V8-8 最后一跳（lane23）：像素域**正在用**的缩放状态，已跨到 axi 域。
    //   bit31=像素时基活着（0 ⇒ 下面 19 位是上一次的值）bit[30:19]=0
    //   bit[18]=zman [17:15]=zsel [14:12]=zoom_code [11]=zoom_active [10]=zoom_dir [9:0]=inv_scale
    // ⚠ 与上面两口的区别：dbg_src/dbg_lat 全部取自 axi 域现成的电平 ⇒ 零新增跨域；
    //   这一口的 19 位**本来在像素域**，所以必须真跨一次（snap_cross + 帧首准静态总线，见文件尾）。
    //   代价实测过一次：r54 第一次构建里心跳借用了 `sof_tgl`，那一个发射触发器就同时扇出到
    //   两组目的域同步器 ⇒ `clkout0_1→clk_fpga_0` 整对被判 **CDC-11 Critical**（27 端点 / 2 unsafe），
    //   门禁第 6 项"配对集合不新增 Critical"当场红。现在心跳是独立的 `z_hb_tog` ⇒ 这一对只剩
    //   19 条 CDC-15 Warning（准静态总线被 bus_edge 使能采样，正是这个工具对这个-pattern 的说法）
    //   + 两条带 ASYNC_REG 的 Info，配对不再 Critical。账写在 build/gates_r54*.txt 与 OVERNIGHT §37。
    output wire [31:0] dbg_zoom,
    // 抄快照的触发：system_top 在"lane 选择指到 25"时给一拍（读这一组的第一个字天然就是它）。
    // 为什么需要它：五个字之间有恒等式 tot ≥ c1+c2，而 live 寄存器每轮都在换，
    // 上位机逐 lane 读会读到不同轮 ⇒ ISSUES #59（板级 11 组读数里 4 组破坏恒等式）。
    input  wire        lat_arm,

    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,

    output wire [31:0] m_axi_araddr,
    output wire [5:0]  m_axi_arid,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [63:0] m_axi_rdata,
    input  wire [5:0]  m_axi_rid,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    input  wire        eth_wr_clk,
    input  wire        eth_wr_en,
    input  wire [18:0] eth_wr_addr,
    input  wire [15:0] eth_wr_data,
    input  wire        eth_link,
    // "最近真的有帧"（axi_clk(fclk0) 域电平，取自健康快照 lane7.bit3 = stall_ms < 200）。
    // eth_tb_ok：量这位的**源时基**（eth_rxc）还准不准 —— 板级实测断链时 RTL8211 不停 RXC
    // 而是把它拉到 ≈2.5 MHz，于是 stall_ms 慢约 48 倍地爬，"活着"这一位会连着十几秒说谎。
    // 两位的相与放在 src_arb 里（那里才是判据的主人，也才台架验得到），不在本文件外面做。
    // 与 eth_link 的分工：eth_link 继续只喂 OSD/状态与"有没有见过片源"（R08~R10 三条板级结论
    // 依赖它的语义，不动）；而**谁拥有 AXI 读口 + 帧缓存写口**改由 src_arb 决定 ——
    // 老的 `eth_mode = 3FF(eth_link)` 里 eth_link 是"自配置以来收过任何一个包"（ARP 就触发、
    // 拔线不回 0），那是 PS 片源被永久锁死的根（ISSUES #47 修的是它在显示端的表现）。
    input  wire        eth_live,
    input  wire        eth_tb_ok,
    input  wire        eth_frame,
    input  wire [31:0] eth_ddr_base,
    input  wire        eth_commit,
    // （r55 起这里不再有 eth_pkts / eth_bad 两个入口：那两级触发器是**拿单 bit 的规矩跨 16 位总线**，
    //   而且同步完的值没有任何读者 —— 老六行 OSD 的 PKTS=/ERR= 在 V8-5 撤下屏之后就没人读了。
    //   这两个数今天由 link_monitor 经 snap_cross 正确跨到 axi 域，走 lane1（bad|err）/lane8（pkts）
    //   /lane9（bytes）给 health_read.mjs。整段账记在 ISSUES #64。）
    // v7.6 到这里为止的三个口（lm_bus / lm_bus_tog / lm_hb）在 V8-5 删了，
    // 原因与"数并没有丢"的去向写在文件下面那段注释里（搜"没有消费者"）。

    output wire [31:0] status,
    output wire        copy_hold
);
    wire clk_pix, clk_pix5x, locked;
    wire clk_200m_unused;
    clk_gen u_clk (
        .clk_in(sys_clk), .rst_n(sys_rst_n),
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .clk_200m(clk_200m_unused), .locked(locked)
    );
    wire rst_pix_n = sys_rst_n & locked;

    wire p1, p2, k1_up;
    wire k1_short, k1_hold, ltog;
    key_debounce #(.CNT_MAX(1_000_000)) u_k1 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key1_n), .pulse(p1), .key_stable(k1_up)
    );
    key_debounce #(.CNT_MAX(1_000_000)) u_k2 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key2_n), .pulse(p2), .key_stable()
    );
    wire owner_eth_pix;          // 前面声明、下面赋值：u_mode 要拿它挑 AUTO 的下一态

    // ---- 同一个按键的两种语义：短按 = 旋转 ±1°，长按 0.6 s = 切换片源模式。
    //      长按事件用**翻转位**跨域（脉冲跨域会被吃掉，与 `ps_publish` / ISSUES #36 是同一课）。
    //      短按改到**松手时**发（ISSUES #55）：以前它由 u_k1 在按下沿发，于是每次长按
    //      都必然先转 1° —— 用户报的原话就是"长按总会先触发一次短按"。
    //      p1 现在不再驱动旋转（留着只因为它就是 u_k1 的输出端口，删它要动 key_debounce 的接口）。
    key_long #(.HOLD_CYC(30_000_000), .ARM_CYC(10_000_000)) u_k1l (   // 50 MHz ⇒ 0.6 s / 0.2 s
        .clk(sys_clk), .rst_n(sys_rst_n), .pressed(~k1_up),
        .tog(ltog), .short_pulse(k1_short), .holding(k1_hold));

    localparam [1:0] M_AUTO = 2'd0, M_ETH = 2'd1, M_SD = 2'd3, M_TEST = 2'd2;
    // 模式寄存器搬到了 `src/rtl/util/src_mode.v`，原因是"这段逻辑有没有台架"：
    // 以前它就写在这里（一个 3 级链 + 一个四态寄存器），顶层没有任何台架碰得到它，
    // 于是链的复位值写成 3'b111（源头 `tog` 复位是 0）这件事一直没人查 —— 上电白送一次
    // "长按"，模式自己走到"锁 ETH"，`src_arb` 的 `force_eth` 就此长占，"停流交回"永不发生。
    // 这就是 #28 板级交接判据红的那条根（详见 src_mode.v 文件头与 ISSUES #49）。
    wire [1:0] mode;
    src_mode u_mode (
        .clk(clk_pix), .rst_n(rst_pix_n), .ltog(ltog),
        .eth_now(owner_eth_pix), .ov_code(mode_ovr), .ov_tog(mode_ovr_tog), .mode(mode)
    );
    wire mode_eth  = (mode == M_ETH);
    wire mode_ps   = (mode == M_SD);
    wire mode_card = (mode == M_TEST);

    (* ASYNC_REG = "TRUE" *) reg [1:0] ms0, ms1, ms2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin ms0 <= M_AUTO; ms1 <= M_AUTO; ms2 <= M_AUTO; end
        else begin ms0 <= mode; ms1 <= ms0; ms2 <= ms1; end
    end
    // 图卡模式不参与仲裁（保持 AUTO）：它只是"显示什么"，不是"谁在搬"
    wire [1:0] arb_sel = (ms2 == M_ETH) ? 2'd1 : (ms2 == M_SD) ? 2'd2 : 2'd0;
    wire [8:0] angle;
    wire rotate_active;
    angle_ctrl u_ang (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .key_inc(k1_short), .key_dec(p2),   // 短按改松手发（ISSUES #55）
        .angle(angle), .rotate_active(rotate_active)
    );

    wire [4:0] en_sync;
    wire [7:0] th_sync;
    wire [8:0] sel_sync;
    wire       gm_en, gm_wr;
    wire [7:0] gm_idx, gm_data;
    wire [5:0] gm_disp;          // V8-5：只给 OSD 的 gamma×10（同一对同步器带过来的 6 位）
    wire [2:0] zsel_pix;         // V8-8：手动档号（与 sel_sync 同源同深度）
    wire       zman_pix;         // V8-8：手动旗标
    wire [7:0] rot_code;         // V8-10：串口角度码（2 度步进），走 effect_ctrl 那条 gm 链进来
    wire       rot_ovr_en, osd_off;
    effect_ctrl u_eff (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .effect_en_async(effect_en),
        .stage_sel_async(stage_sel),
        .zoom_sel_async(zoom_sel_async),
        .zoom_manual_async(zoom_manual_async),
        .threshold_async(threshold),
        .gamma_async(gamma_ctl),
        .stage_sel(sel_sync),
        .zoom_sel(zsel_pix), .zoom_manual(zman_pix),
        .effect_en(en_sync), .threshold(th_sync),
        .gamma_en(gm_en), .gamma_wr(gm_wr), .gamma_idx(gm_idx), .gamma_data(gm_data),
        .gamma_disp(gm_disp),
        .rot_code(rot_code), .rot_ovr_en(rot_ovr_en), .osd_off(osd_off)
    );

    (* ASYNC_REG = "TRUE" *) reg ze0, ze1, ze2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            ze0 <= ZOOM_DEFAULT_ON[0];
            ze1 <= ZOOM_DEFAULT_ON[0];
            ze2 <= ZOOM_DEFAULT_ON[0];
        end else begin
            ze0 <= zoom_en; ze1 <= ze0; ze2 <= ze1;
        end
    end
    wire zoom_run = ze2;

    wire [11:0] x, y;
    wire hs, vs, de, frame_start, frame_done;
    video_timing_1024x600 u_t (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x), .y(y), .hs(hs), .vs(vs), .de(de),
        .frame_start(frame_start), .frame_done(frame_done)
    );

    wire [7:0]  pipe_off_rows;   // 效果链自己声明的"内容滞后几行"（u_pipe 的输出口）
    wire        left_pane = (x < PANE_W);
    wire [11:0] cx = left_pane ? x : (x - PANE_W);
    wire [11:0] cy = (y >> 1) < IMG_H ? (y >> 1) : (IMG_H - 1);
    // 右窗读坐标**提前 u_pipe.OFF_LINES 个显示行**（= 效果链的内容滞后，实测 −4 行且逐像素一致）。
    // 为什么这样补是免费的、也是唯一因果上成立的补法：
    //   * 行缓存式 3×3 滤波必然滞后一整行（收到第 y 行才算得出第 y−1 行的窗口），
    //     所以"把数据提前"不可能，只能"把地址提前" —— 而片源在帧缓存里，地址是随机的；
    //   * 两个窗共用一个读口、各用各的坐标（见下面 sx_fb/sy_fb 的 mux），
    //     所以只提前右窗这一路，左窗（未处理的原始画面）不动 ⇒ 缝两侧的内容从此同一行；
    //   * 提前量加在 **mapper 的显示行输入**上而不是加在 it 输出的源行上：
    //     链子的滞后发生在显示栅格上，缩放/旋转之后"源行差 4"并不等于"显示行差 4"。
    // 判据：tb_v89 的 T1（把激励按 OFF_LINES 提前，整链内部偏移必须变成 (0,0)）；
    //       缝连续性的最终凭据是眼睛（`board/README.md` 第 12 行）。
    wire [12:0] y_right_adv = {1'b0, y} + {5'b0, pipe_off_rows};
    wire [11:0] cy_r = ((y_right_adv >> 1) >= IMG_H) ? (IMG_H - 1) : y_right_adv[11:0] >> 1;

    wire [9:0] inv_scale;
    wire       zoom_active, zoom_dir;
    wire [2:0] zoom_code;        // V8-5：OSD 的"最近一档"（八档表在 zoom_ctrl 里，不除）
    zoom_ctrl #(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd2)) u_zctrl (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .enable(zoom_run), .frame_start(frame_start),
        .zsel(zsel_pix), .manual(zman_pix),        // V8-8：手动档（同一对同步器带来的两个位）
        .inv_scale(inv_scale), .zoom_active(zoom_active), .zoom_code(zoom_code),
        .dir(zoom_dir)
    );

    // V8-10（#70 追加）：串口可以覆盖按键角度。码是 2 度步进 ⇒ 最大 510，折回 0..359 只需一次减法，
    //   **没有除法**（#58 那条 100 MHz 组合除法器把 WNS 打到 −5.014 的账不许重犯）。
    //   覆盖是"整条角度一起换"，不是叠加：`rot_ovr_en=0` 时按键那一路完全照旧。
    wire [8:0] ang_ser = ({rot_code, 1'b0} >= 9'd360) ? ({rot_code, 1'b0} - 9'd360) : {rot_code, 1'b0};
    wire [8:0] angle_eff = rot_ovr_en ? ang_ser : angle;
    wire       rot_act_eff = (angle_eff != 9'd0);

    // 左半窗**不旋转**：旋转只属于右半窗（由 zoom_mapper 内部的 rotate_en 分支承担）。
    // 于是这里不再例化 rotate_mapper —— 保持左路用 cx_q3/cy_q3（= 今天 angle=0 时的同一条路径），
    // 流水深度不动，免得把已经验过的列配准重新搅一遍。
    reg [11:0] cx_q1, cx_q2, cx_q3, cy_q1, cy_q2, cy_q3;
    reg        oob_q1, oob_q2, oob_q3;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            {cx_q1,cx_q2,cx_q3} <= 36'd0;
            {cy_q1,cy_q2,cy_q3} <= 36'd0;
            {oob_q1,oob_q2,oob_q3} <= 3'd1;
        end else begin
            cx_q1 <= cx; cx_q2 <= cx_q1; cx_q3 <= cx_q2;
            cy_q1 <= cy; cy_q2 <= cy_q1; cy_q3 <= cy_q2;
            oob_q1 <= (cx >= IMG_W) || (cy >= IMG_H);
            oob_q2 <= oob_q1; oob_q3 <= oob_q2;
        end
    end
    wire        rot_on = rot_act_eff;     // 只驱动右窗（V8-10：按键或串口哪一路来的角度都从这里过）
    wire [11:0] sx_l = cx_q3;             // 左窗 = 未旋转原画面
    wire [11:0] sy_l = cy_q3;
    wire        oob_l = oob_q3;

    wire [11:0] sx_r, sy_r;
    wire        oob_r;
    wire [7:0]  zfrac_x, zfrac_y;
    zoom_mapper #(.IMAGE_W(IMG_W), .IMAGE_H(IMG_H)) u_zmap (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .inv_scale(inv_scale), .angle(angle_eff), .rotate_en(rot_on),
        .x_in(cx), .y_in(cy_r),     // ← 提前 OFF_LINES 个显示行，抵掉效果链的内容滞后（#54 (B)）
        .x_out(sx_r), .y_out(sy_r), .oob(oob_r),
        .frac_x(zfrac_x), .frac_y(zfrac_y)
    );

    // 混色级要的列坐标必须由**流水线深度**推出来，不许再抄字面量 11（ISSUES #68）。
    //   内容站在：3(`cx/cy` 打到 mapper 与左路的打拍) + 1(`rd_addr_q`) + 1(BRAM 读出) + PROC_LAT = 20 级。
    //   以前 `u_split` 拿的是 `x_d[11]` ⇒ 缝的判定比内容旧 9 列（台架 `tb_v98_top_seam` 的 C-tap 钉住）。
    localparam MIX_D = 3 + 1 + 1 + u_pipe.LATENCY;
    localparam SB = (MIX_D > 16) ? (MIX_D + 1) : 16;
    reg        de_d[0:SB-1], hs_d[0:SB-1], vs_d[0:SB-1], left_d[0:SB-1];
    reg [11:0] x_d[0:SB-1], y_d[0:SB-1], cx_d[0:SB-1], cy_d[0:SB-1];
    integer k;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            for (k = 0; k < SB; k = k + 1) begin
                de_d[k]<=0; hs_d[k]<=0; vs_d[k]<=0; left_d[k]<=1;
                x_d[k]<=0; y_d[k]<=0; cx_d[k]<=0; cy_d[k]<=0;
            end
        end else begin
            de_d[0]<=de; hs_d[0]<=hs; vs_d[0]<=vs; left_d[0]<=left_pane;
            x_d[0]<=x; y_d[0]<=y; cx_d[0]<=cx; cy_d[0]<=cy;
            for (k = 1; k < SB; k = k + 1) begin
                de_d[k]<=de_d[k-1]; hs_d[k]<=hs_d[k-1]; vs_d[k]<=vs_d[k-1];
                left_d[k]<=left_d[k-1]; x_d[k]<=x_d[k-1]; y_d[k]<=y_d[k-1];
                cx_d[k]<=cx_d[k-1]; cy_d[k]<=cy_d[k-1];
            end
        end
    end

    // --- v5.3 ETH path ---
    wire row_start, row_done, row_busy;
    wire [31:0] row_base;
    wire row_wr_en;
    wire [18:0] row_wr_addr;
    wire [63:0] row_wr_data;
    wire [31:0] row_araddr;
    wire [7:0]  row_arlen;
    wire [2:0]  row_arsize;
    wire [1:0]  row_arburst;
    wire        row_arvalid, row_rready;
    wire        allow_copy;
    wire        frame_ready;
    wire        copy_abort;
    wire        abort_tgl;          // copy_abort 的翻转位（axi 域产生，像素域同步后消费）

    // v6 ATOMIC SWAP: the whole frame is copied inside V-blank only.
    // V_TOTAL 625 lines, active 600 → 25 blank lines = 33.5k pix cycles =
    // 67k axi(100M) cycles, and the frame is 38.4k 64-bit words → the copy
    // finishes before the first active line is painted, so the display BRAM
    // holds ONE complete frame during every visible row: no new/old seam
    // (v5's fixed-position black line came from the copier overtaking the
    // beam mid-frame) and no read/write collision.
    // Closed 64 blank pixels early: allow_copy_axi lags this window by ~5 pix
    // cycles through the CDC in frame_commit_lock.
    localparam [11:0] DISP_V_LINES = 12'd600;   // active lines of 1024x600
    localparam [11:0] DISP_V_LAST  = 12'd624;   // V_TOTAL-1
    localparam [11:0] VB_X_GUARD   = 12'd1279;  // H_TOTAL(1344) - 65
    wire disp_quiet = (y >= DISP_V_LINES)
                      && ((y < DISP_V_LAST) || (x <= VB_X_GUARD));

    wire fill_wr_en;
    wire [18:0] fill_wr_addr;
    wire [63:0] fill_wr_data;
    wire fill_done;
    wire [31:0] fill_araddr;
    wire [7:0]  fill_arlen;
    wire [2:0]  fill_arsize;
    wire [1:0]  fill_arburst;
    wire        fill_arvalid, fill_rready;

    reg  eth_has_frame;

    // 仲裁见 src/rtl/util/src_arb.v。两个输入都是 system_top 在 **axi_clk(fclk0) 域**里
    // 取好的（健康快照的一位 + snap_cross 的两个时基标志），所以这里直接采样，不再跨域；
    // 需要跨到像素域的是**仲裁结果** owner_eth（下面的 op0/1/2），不再复制一份判据。
    // 换手只在"两个引擎都空闲"时发生，往 PS 方向再多等 T_OFF（帧间隔卡在阈值上时不会来回抢总线）。
    wire fill_busy;                       // u_aw 的 frame_busy 以前是悬空的，现在是互锁输入
    wire owner_eth;
    wire [2:0] why_ps;                    // V8-7：仲裁判决那一拍看到的三个输入（见 src_arb 端口注释）
    src_arb #(.T_OFF_CYC(2_000_000)) u_arb (   // AXI 域 100 MHz ⇒ 20 ms 静默才让给 PS
        .clk(axi_clk), .rst_n(axi_rst_n), .eth_live(eth_live), .eth_tb_ok(eth_tb_ok),
        .sel(arb_sel),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_eth),
        .why_ps(why_ps));
    // 名字留着：下面每一处 `eth_mode ? row_* : fill_*` 都是"这一拍搬运机归谁"的意思，
    // 只是判据从"收过包"换成了"仲裁过的 owner"。保持同一个名字 ⇒ 这次改动不需要动那 14 处 mux。
    wire eth_mode = owner_eth;

    frame_commit_lock #(.IMG_H(IMG_H), .DISP_H(600)) u_cmt (
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .commit_req(eth_commit), .commit_base(eth_ddr_base),
        .pix_clk(clk_pix), .pix_rst_n(rst_pix_n),
        .de(de), .vsync(vs), .blank_safe(disp_quiet),
        .copy_busy(row_busy), .copy_done(row_done),
        .start_copy(row_start), .copy_base(row_base),
        .frame_ready_pix(frame_ready),
        .allow_copy_axi(allow_copy),
        .copy_abort(copy_abort), .abort_tgl(abort_tgl)
    );

    // 板载诊断：拷贝是否超出一个 V-blank 窗口（25 行 × 1344 像素 × 2 axi 拍）。
    // 超出 ⇒ 换帧跨了两个消隐期 ⇒ 屏幕上同一帧的新旧两半并存 ⇒ 运动物体被
    // 一条水平缝「切开」+ 拖影。粘滞到重新加载 bit 为止，用 led[0] 看。
    wire [31:0] row_copy_cycles;
    localparam [31:0] VBLANK_AXI_CYC = 32'd67200;
    reg copy_overrun = 1'b0;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n)      copy_overrun <= 1'b0;
        else if (row_done && (row_copy_cycles > VBLANK_AXI_CYC))
                             copy_overrun <= 1'b1;
    end

    axi_frame_writer_gated #(.IMG_W(IMG_W), .IMG_H(IMG_H), .BASE_ADDR(BASE_ADDR)) u_row (
        .clk(axi_clk), .rst_n(axi_rst_n),
        .enable(eth_mode),
        .start(eth_mode ? row_start : 1'b0),
        .base_addr(row_base),
        .allow_wr(eth_mode ? allow_copy : 1'b0),
        .abort(eth_mode ? copy_abort : 1'b0),
        .busy(row_busy), .done(row_done),
        .fb_wr_en(row_wr_en), .fb_wr_addr(row_wr_addr), .fb_wr_data(row_wr_data),
        .m_axi_araddr(row_araddr), .m_axi_arlen(row_arlen),
        .m_axi_arsize(row_arsize), .m_axi_arburst(row_arburst),
        .m_axi_arvalid(row_arvalid), .m_axi_arready(eth_mode ? m_axi_arready : 1'b0),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(eth_mode ? m_axi_rvalid : 1'b0), .m_axi_rready(row_rready),
        .copy_cycles(row_copy_cycles)
    );

    (* ASYNC_REG = "TRUE" *) reg ss0, ss1, ss2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {ss2,ss1,ss0} <= 3'b0;
        else {ss2,ss1,ss0} <= {ss1, ss0, src_sel};
    end
    wire src_sel_pix = ss2;

    // U11（R22）：`eth_link` 是 eth_rxc 域的电平，原来在像素域被**裸采样** 4 处，
    // 而同一个文件里 `src_sel` 早就走了 3 级同步 —— 一处对一处错。
    // 证据是**行级**的：`cdc.rpt` 里 `eth_rxc→clkout0_1` 那一行的端点数 84→51、被标记 16→1
    // （这份报告不点名信号，所以它只能证明"这一类端点变少了"，不能当逐信号的凭据 ——
    // 逐信号的凭据要写台架，见 R23 的 tb_v79_abort_toggle）。现在统一成 3 级（多 60 ns，
    // 对"链路断"这种毫秒级事件不可见）。
    // 注意：`copy_abort` **不能**照这个模板同步 —— 它是 axi_clk 上只有 1 拍（10 ns）的脉冲，
    // 电平型 3 级同步会整拍漏掉它（比原来的裸采样更糟）。它要的是翻转式脉冲同步器：
    // R23 已在 `frame_commit_lock` 里补出 `abort_tgl`（与本文件 `blank_tog` 那一侧对称），
    // 下面这条链就是"3 级 + 异拍出沿"，判据在 sim/tb_v79_abort_toggle（含相位扫描）。
    (* ASYNC_REG = "TRUE" *) reg ab0, ab1, ab2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {ab2,ab1,ab0} <= 3'b0;
        else            {ab2,ab1,ab0} <= {ab1, ab0, abort_tgl};
    end
    wire copy_abort_pix = ab1 ^ ab2;   // 每次 abort 恰好一拍

    (* ASYNC_REG = "TRUE" *) reg el0, el1, el2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {el2,el1,el0} <= 3'b0;
        else {el2,el1,el0} <= {el1, el0, eth_link};
    end
    wire eth_link_pix = el2;

    // 像素域要的是**仲裁结果**而不是第二份判据。判据（eth_live AND 时基健康）留在 src_arb 里，
    // 这里只把它问一遍再拿答案用：
    //   · ETH 拥有搬运机时，PS 的发布不被消费（pend 留着，等轮到 PS 那一帧再消费），
    //     否则 pend 会在没人搬运的时候被清掉；
    //   · 反过来若这里再复制一份"活着"的判据，就会出现"ETH 那一位还在说谎、
    //     SD 帧却永远不被消费"的死锁 —— 今晚的板上现象正是它（STALL 钉在 9999）。
    // owner_eth 是 ms 级的慢变量，3 级同步的写法与上面 eth_link_pix 同构。
    (* ASYNC_REG = "TRUE" *) reg op0, op1, op2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {op2,op1,op0} <= 3'b0;
        else {op2,op1,op0} <= {op1,op0,owner_eth};
    end
    assign owner_eth_pix = op2;

    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) eth_has_frame <= 1'b0;
        else if (frame_ready && eth_link_pix) eth_has_frame <= 1'b1;
        else if (copy_abort_pix) eth_has_frame <= 1'b0;
    end

    // SRC0=colorbar, SRC1=video (v5 SRC bug was |eth_ready locking SRC0)
    wire [15:0] fb_rd;
    wire eth_ready   = eth_link_pix & eth_has_frame;
    wire src_use     = src_sel_pix;
    assign copy_hold = 1'b0;

    // Hold last pixel only while writer may touch BRAM in blanking.
    // Active video always shows live BRAM (complete frame after copy_done).
    (* ASYNC_REG = "TRUE" *) reg ac0, ac1;
    reg [15:0] fb_pix_hold;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            {ac1,ac0} <= 2'b0;
            fb_pix_hold <= 16'h0;
        end else begin
            {ac1,ac0} <= {ac0, allow_copy};
            if (!ac1) fb_pix_hold <= fb_rd;
        end
    end
    wire [15:0] fb_out = (ac1 && !de_d[11]) ? fb_pix_hold : fb_rd;
    // 这块红"没有片源"的判据往下挪三行 —— 它要用 ps_frame_start，而那是下面才声明的线。

    // 发布握手单独成模块（内含 3 级同步），这样它能被 sim/tb_ps_publish.v 逐相位验。
    // 顺带修掉一处真错：这里原来用 `src_sel`（axi_clk 域的**未同步**电平），
    // 而同文件里 src_sel_pix/src_use 早就存在 —— 帧起始那拍采它会采到亚稳态。
    wire pub_consume = frame_start && src_use && !owner_eth_pix;
    wire pub_pend;
    ps_publish u_pub (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .tog(ps_publish), .consume(pub_consume), .pend(pub_pend), .new_tog());

    reg fs_tog;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) fs_tog <= 1'b0;
        else if (pub_consume && pub_pend) fs_tog <= ~fs_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg fs0, fs1, fs2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fs2,fs1,fs0} <= 3'b0;
        else {fs2,fs1,fs0} <= {fs1,fs0,fs_tog};
    end
    wire ps_frame_start = fs1 ^ fs2;

    // 片源存在性判据（原来只有 eth_link_pix 一项，见上面那行注释被挪下来的原因）：
    //   ETH 侧：链路在 ⇒ 显示 fb（和以前**逐位一致**，不动已验过的行为）
    //   PS  侧：至少发布过一次搬运 ⇒ 也显示 fb
    // 少了后一项，网线一拔这块红就永久挡在 fb 前面 —— FILL / SD 回放在屏幕上不可达，
    // 而 pub_consume / ps_publish / axi_frame_writer64 明明都在，说明设计上要两条片源。
    // 用像素域的 pub_consume 置位，不引入新的跨域（ps_frame_start 是 axi_clk 域的脉冲）。
    reg ps_src_seen;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) ps_src_seen <= 1'b0;
        else if (pub_consume) ps_src_seen <= 1'b1;
    end
    // 片源存在性判据（#47 加的那一项）现在**只用来决定"看不看 fb"**，不再决定"涂不涂红"：
    // 没有片源时显示的是会动的图卡（见下面 pix_left/pix_right），屏幕从此不会是红的或黑的。
    // 这也是图卡存在的理由之一：#47 之前"看不见 PS 片源"和"没搬片源"在屏幕上长得一模一样。
    wire have_src = eth_link_pix | ps_src_seen;
    // 模式决定"看哪一路"：锁 ETH / 锁 SD 时强制看 fb；锁 TEST 时强制看图卡；AUTO 交回给
    // PS 的 SRC0/SRC1 命令（src_use），行为与 #23/#25 一致。
    wire fb_vis   = (mode_card ? 1'b0 : (mode_eth | mode_ps) ? 1'b1 : src_use) && have_src;

    // ---- 仲裁状态可观测口（dbg_src）----
    // 为什么值得加：`owner_eth` 决定"此刻屏幕归谁"，以前只有眼睛能知道。第一次上板跑
    // `src/host/arb_handover_test.mjs`（#28 那块 bit）就撞上"停流之后 owner 一直是 1"，
    // 但**只凭那一位回答不了"是谁占着"**：时基判错？判据算错？换手条件 `both_idle`
    // 从来没成立？还是长按把模式钉在了"锁 ETH"？所以这一口把仲裁**看得见的所有输入**
    // 都摆出来：判据三位 + 两个引擎的 busy + 它以为的模式。
    // 关键是这七位**全部本来就在 axi 域**（`ms2` 是模式打到 axi 侧的副本、`row_busy`/`fill_busy`
    // 是 axi 域引擎的握手位）⇒ 一个新增跨域都不引入。#26 那版我为此新加了一对"像素域 mode
    // 的同步器"，那是白交税（`cdc.rpt` 从 3 端点/0 unsafe 涨到 8/4）；要看模式，取现成的 ms2。
    // 位序：bit0=eth_tb_ok bit1=eth_live bit2=owner_eth bit3=fill_busy(PS 搬运中)
    //       bit4=row_busy(ETH 搬运中) bit[6:5]=仲裁看到的模式(格雷码，同 src_arb 的 sel) bit7=0
    assign dbg_src = {5'd0, why_ps, 1'd0, ms2, row_busy, fill_busy, owner_eth, eth_live, eth_tb_ok};

    // ---- V8-6：链路内时延（commit → 该帧开始被扫描），分三段量 ----
    // 显示帧起始在像素域 ⇒ 按仓库规矩先转成**翻转位**再进 axi 域（脉冲跨域会被吃掉，#36 那一课）。
    reg sof_tgl;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) sof_tgl <= 1'b0;
        else if (frame_start) sof_tgl <= ~sof_tgl;
    end

    wire [31:0] lat_c1, lat_c2, lat_tot, lat_max;
    wire [15:0] lat_n;
    // 快照那一组（读回口给出去的就是这六个，见下面的 dbg_lat）
    wire [31:0] lq_c1, lq_c2, lq_tot, lq_max, lq_stat, lq_ms;
    wire        lat_clamp;
    // V8-5：axi 域那一口的四个声明（必须在例化之前声明，否则端口先造出隐式 net，
    // 后面再显式声明就是重定义错误）
    wire [15:0] lat_ms_axi;
    wire        lat_ok_axi, lat_sticky_axi, lat_tog_axi;
    // **PL 里不做除法**：r49 在这里把拍数除以 100 换 µs，除数不是 2 的幂 ⇒ 综合架出组合除法器，
    // 100 MHz 域直接 WNS −5.014 / 96 个失败端点（被门禁拦下，见 ISSUES #58）。
    // 现在只报拍数，换算在 src/host/health_read.mjs 的一个常量里做（1 拍 = 10 ns）。
    frame_latency u_lat (
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .commit(eth_commit), .copy_start(row_start), .copy_done(row_done),
        .disp_sof_tgl(sof_tgl), .arm(lat_arm),
        .c1_cyc(lat_c1), .c2_cyc(lat_c2), .tot_cyc(lat_tot), .max_cyc(lat_max),
        .n_meas(lat_n), .clamped(lat_clamp),
        .q_c1(lq_c1), .q_c2(lq_c2), .q_tot(lq_tot), .q_max(lq_max), .q_stat(lq_stat),
        // V8-5：axi 域换算好的 ms（逐次除法，见 frame_latency 里那段注释）
        .lat_ms(lat_ms_axi), .lat_valid(lat_ok_axi),
        .lat_sticky(lat_sticky_axi), .lat_tog(lat_tog_axi),
        .q_ms(lq_ms)
    );
    // 五个字，lane 号 = 25 + 序号（system_top 的 mux 按这个式子取）：
    //   lane29 = c1（commit→start_copy，等消隐窗口）
    //   lane28 = c2（start_copy→copy_done，整帧搬运）
    //   lane27 = tot（commit→显示帧起始；c3 = tot − c1 − c2，不单独占一口）
    //   lane26 = max（历轮 tot 的最大值，演示念这个）
    //   lane25 = { n_meas[15:0], 15'd0, clamped }
    // ⚠ 这一行给出去的是 **q_*（快照）**，不是 live 的 lat_*：读回口要的是"一组自洽的数"，
    //    而 live 值每轮都在换（#59）。live 的 lat_* 仍然接在台架上（tb_v90 逐周期对账用它们），
    //    板级读回来的这五个字则是"指到 lane25 那一刻的同时抄走的那一轮"。
    // 六个字：lane29..25 = c1/c2/tot/max/stat（word0..4），lane24 = q_ms（word5）。
    // 为什么把 ms 塞进同一次武装的快照里：屏上 `Latency:` 那一格画的就是这个 ms，
    // 而 PLAN 步 5 要求"屏上数字与 health_read 回读必须同源"⇒ 只有**同一轮**的
    // (q_tot, q_ms) 能互相验；除法那 32 拍里武装的话 pair_ok 给 0，脚本就不下结论。
    assign dbg_lat = { lq_ms, lq_c1, lq_c2, lq_tot, lq_max, lq_stat };

    // ================= V8-8 最后一跳（lane23）：像素域真正在用的缩放状态 =================
    // 为什么寄存器回读不算数：GPIO 读回来的 zsel/zman 只能证明**PS 写了这一位**，
    // 证明不了"像素域收到了它"（sel 链有 13 级同步）更证明不了"用它算出的 inv_scale 是对的"。
    // 这一口把因果链的**末端**摆出来：收到的档号（zsel/zman）与据此算出的量（inv_scale/zoom_code），
    // 于是两条判据变成机器可判：
    //   ① PS 写 zsel=i ⇒ 像素域 inv_scale == TBL[i]（`zoom_mapper` 之外的整条链）；
    //   ② 屏上 `Zoom:` 那一格画的 zoom_code 与同一帧在用的 inv_scale 必须落在同一档
    //      （与 lane24 对照屏上 `Latency:` 是同一手法，PLAN 步 5 的"同源"要求）。
    // 跨法按仓库规矩：总线只在**帧首**变 ⇒ 准静态；沿在捕获之后再推迟 8 个像素周期
    // （≈318 ns @25.175 MHz）才发，目的域同步 + 采样至少再晚 2 个 axi 周期 ⇒ 采到的必是完整值。
    // 打包与发沿的规矩单独成模块 `zoom_snap.v`（台架 tb_v95 逐周期验它的两条不变量），
    // 不这么做的对照：19 位各自打两拍会读到"半新一半旧"的档位（#52/#59 两次都是它）。
    wire [18:0] z_bus;
    wire        z_bus_tog;
    zoom_snap u_zsnap (
        .pix_clk(clk_pix), .pix_rst_n(rst_pix_n), .frame_start(frame_start),
        .zman(zman_pix), .zsel(zsel_pix), .zoom_code(zoom_code),
        .zoom_active(zoom_active), .zoom_dir(zoom_dir), .inv_scale(inv_scale),
        .bus(z_bus), .bus_tog(z_bus_tog));
    wire [18:0] z_bus_axi;
    wire        z_pix_gone;
    // 心跳**单独一个触发器**，不共用现成的 sof_tgl —— 这不是洁癖：r54 第一次构建里就是共用了它，
    // 于是 `sof_tgl` 这个发射触发器同时扇出到两组目的域同步器（u_lat 与 u_zoom_axi），
    // cdc.rpt 立刻把整对 `clkout0_1 → clk_fpga_0` 从 Info 提成 **CDC-11 Critical**
    // （"Fan-out from launch flop to destination clock"），门禁第 6 项因此判红。
    // 一个 FF 换回"配对集合不新增 Critical 行"，并且语义一模一样（每个显示帧翻一次）。
    reg z_hb_tog;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) z_hb_tog <= 1'b0;
        else if (frame_start) z_hb_tog <= ~z_hb_tog;
    end
    // 心跳 = 每帧一次 ⇒ hb_gone 的含义是"200 ms 没等到帧起始"
    // = 像素时基停了，这时 bus_q 里的数还是上一个的，必须让脚本知道它旧。
    // SLOW_MS 这一档**不接出去**：模块里那个 5 ms 的门限是给 1 ms 心跳（eth_rxc）定的，
    // 帧心跳本来就是 16.7 ms，硬接只会常亮一位没意义的慢标志。
    snap_cross #(.W(19), .DST_HZ(100_000_000), .HB_TO_MS(200)) u_zoom_axi (
        .dst_clk(axi_clk), .dst_rst_n(axi_rst_n),
        .bus(z_bus), .bus_tog(z_bus_tog), .hb_tog(z_hb_tog),
        .bus_q(z_bus_axi), .hb_gone(z_pix_gone), .hb_slow()
    );
    // 位序（唯一出处，改这里要同步改 health_read.mjs 的 decodeZoom 与门禁反例）：
    //   bit31 = 像素时基活着（0 ⇒ 下面 19 位是旧的）  bit[30:19] = 0（留扩展）
    //   bit[18]=zman [17:15]=zsel [14:12]=zoom_code [11]=zoom_active [10]=zoom_dir [9:0]=inv_scale
    assign dbg_zoom = {~z_pix_gone, 12'd0, z_bus_axi};

    assign m_axi_arid = 6'd0;

    axi_frame_writer64 #(
        .IMG_W(IMG_W), .IMG_H(IMG_H), .BASE_ADDR(PS_BASE_ADDR)
    ) u_aw (
        .clk(axi_clk), .rst_n(axi_rst_n),
        .enable(eth_mode ? 1'b0 : src_sel),
        .frame_start(eth_mode ? 1'b0 : ps_frame_start),
        .base_addr(PS_BASE_ADDR),
        .frame_busy(fill_busy), .frame_done(fill_done),
        .fb_wr_en(fill_wr_en), .fb_wr_addr(fill_wr_addr), .fb_wr_data(fill_wr_data),
        .m_axi_araddr(fill_araddr), .m_axi_arlen(fill_arlen),
        .m_axi_arsize(fill_arsize), .m_axi_arburst(fill_arburst),
        .m_axi_arvalid(fill_arvalid), .m_axi_arready(eth_mode ? 1'b0 : m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(eth_mode ? 1'b0 : m_axi_rvalid), .m_axi_rready(fill_rready),
        .copy_cycles()
    );

    assign m_axi_araddr  = eth_mode ? row_araddr  : fill_araddr;
    assign m_axi_arlen   = eth_mode ? row_arlen   : fill_arlen;
    assign m_axi_arsize  = eth_mode ? row_arsize  : fill_arsize;
    assign m_axi_arburst = eth_mode ? row_arburst : fill_arburst;
    assign m_axi_arvalid = eth_mode ? row_arvalid : fill_arvalid;
    assign m_axi_rready  = eth_mode ? row_rready  : fill_rready;

    wire        aw_wr_en   = eth_mode ? row_wr_en   : fill_wr_en;
    wire [18:0] aw_wr_addr = eth_mode ? row_wr_addr : fill_wr_addr;
    wire [63:0] aw_wr_data = eth_mode ? row_wr_data : fill_wr_data;

    wire        fb_sel_right = ~left_d[2];
    wire [11:0] sx_fb = fb_sel_right ? sx_r : sx_l;
    wire [11:0] sy_fb = fb_sel_right ? sy_r : sy_l;
    wire        oob_fb = fb_sel_right ? oob_r : oob_l;

    reg [18:0] rd_addr_q;
    reg        oob_fb_d0;
    reg        left_sel_q;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            rd_addr_q <= 0; oob_fb_d0 <= 1; left_sel_q <= 1;
        end else begin
            rd_addr_q  <= {sy_fb[8:0], 9'b0} + {7'b0, sx_fb};
            oob_fb_d0  <= oob_fb;
            left_sel_q <= left_d[2];
        end
    end

    frame_buffer_w64 #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(axi_clk), .wr_en(aw_wr_en),
        .wr_addr(aw_wr_addr), .wr_data(aw_wr_data),
        .rd_clk(clk_pix), .rd_addr(rd_addr_q), .rd_data(fb_rd)
    );

    // SRC0 位置原来是静止彩条（`color_bar`）。换成**会动的测试图卡**：静止图案分不清
    // "通路在刷新"和"卡在最后一帧"，而这张卡自带移动块 + 帧号二值格（见 test_card.v 文件头）。
    // 端口与 color_bar 同形、输出同样只打一拍 ⇒ PROC_LAT 与 bar_l_d4/bar_r_d2 那些抽头不用动。
    wire [15:0] bar_l0, bar_r0;
    reg  [15:0] bar_l_d1, bar_l_d2, bar_l_d3, bar_l_d4, bar_r_d1, bar_r_d2;
    test_card #(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H)) u_bar_l (
        .clk(clk_pix), .rst_n(rst_pix_n), .vs(vs),
        .x(cx), .y(cy), .de(de), .rgb565(bar_l0)
    );
    test_card #(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H)) u_bar_r (
        .clk(clk_pix), .rst_n(rst_pix_n), .vs(vs),
        .x(sx_r), .y(sy_r), .de(de_d[2]), .rgb565(bar_r0)
    );
    always @(posedge clk_pix) begin
        bar_l_d1 <= bar_l0; bar_l_d2 <= bar_l_d1;
        bar_l_d3 <= bar_l_d2; bar_l_d4 <= bar_l_d3;
        bar_r_d1 <= bar_r0;  bar_r_d2 <= bar_r_d1;
    end

    reg oob_fb_d1, left_sel_d1;
    always @(posedge clk_pix) begin
        oob_fb_d1 <= oob_fb_d0;
        left_sel_d1 <= left_sel_q;
    end
    wire left_pix = left_sel_d1;

    wire [15:0] pix_left  = left_pix ? (oob_fb_d1 ? 16'h0000 : (fb_vis ? fb_out : bar_l_d4))
                                      : 16'h0000;
    wire [15:0] pix_right = left_pix ? 16'h0000
                                      : (oob_fb_d1 ? 16'h0000 : (fb_vis ? fb_out : bar_r_d2));
    wire oob_l_pix = left_pix & oob_fb_d1;
    wire oob_r_pix = (~left_pix) & oob_fb_d1;

    wire [15:0] pipe_dout;
    wire        pipe_de;
    proc_pipeline #(.H_ACTIVE(IMG_W)) u_pipe (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .stage_sel(sel_sync), .threshold(th_sync),
        .gamma_en(gm_en), .gamma_wr(gm_wr), .gamma_idx(gm_idx), .gamma_data(gm_data),
        .rotate_active(rot_on),
        .hs_in(hs_d[3]), .vs_in(vs_d[3]),
        .de_in(de_d[3] && !left_d[3]),
        .x_in(cx_d[3]), .y_in(cy_d[3]),
        .din(pix_right), .off_rows(pipe_off_rows),
        .de_out(pipe_de), .dout(pipe_dout)
    );

    // 处理链的延迟**只有一处定义**：proc_pipeline 自己的 LATENCY。
    // 以前这里是字面量 7，于是"链上加一级"必须同时记得改这里 —— 忘了不是编译错，
    // 而是左窗（原始画面）与右窗（处理后）错开 N 个像素。左窗的 skid 长度直接取 u_pipe 的值，
    // 而 tb_v86 的 T2 实测 de_in→de_out 与 LATENCY 对账 ⇒ 两处任一处漂移就有测试可红。
    localparam PROC_LAT = u_pipe.LATENCY;
    localparam LEFT_TAIL = PROC_LAT;

    reg [15:0] orig_skid [0:LEFT_TAIL-1];
    reg        oob_l_skid [0:LEFT_TAIL-1];
    reg        oob_r_skid [0:LEFT_TAIL-1];
    integer s;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            for (s = 0; s < LEFT_TAIL; s = s + 1) begin
                orig_skid[s] <= 0; oob_l_skid[s] <= 0; oob_r_skid[s] <= 0;
            end
        end else begin
            orig_skid[0] <= pix_left;
            oob_l_skid[0] <= oob_l_pix;
            oob_r_skid[0] <= oob_r_pix;
            for (s = 1; s < LEFT_TAIL; s = s + 1) begin
                orig_skid[s] <= orig_skid[s-1];
                oob_l_skid[s] <= oob_l_skid[s-1];
                oob_r_skid[s] <= oob_r_skid[s-1];
            end
        end
    end
    wire [15:0] orig_disp = orig_skid[LEFT_TAIL-1];
    wire        oob_lo = oob_l_skid[LEFT_TAIL-1];
    wire        oob_ro = oob_r_skid[LEFT_TAIL-1];

    wire de_d11 = de_d[11], hs_d11 = hs_d[11], vs_d11 = vs_d[11];
    wire [11:0] x_d11 = x_d[11], y_d11 = y_d[11];

    wire [7:0] r, g, b;
    wire de_o, hs_o, vs_o;
    // 标记线开关：今天仍是"画"（不改观感，也不动 `board/README.md` 第 12 行那条已验的口径），
    // V8-4 把缝做成真可动之后由 PS 决定关不关（#56-2 的 (a) 那一半就是这条线）。
    wire split_marker = 1'b1;
    split_display #(.PANE_W(PANE_W)) u_split (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x_d11), .y(y_d11), .de(de_d11), .hs(hs_d11), .vs(vs_d11),
        .x_sel(x_d[MIX_D]), .marker(split_marker),   // 与内容同级的那一路坐标（#68）；OSD 用的 x/y 不动
        .orig_pix(orig_disp), .proc_pix(pipe_dout),
        .oob_l(oob_lo), .oob_r(oob_ro),
        .angle_idx(angle_eff[1:0]),
        .r(r), .g(g), .b(b),
        .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    reg vs_pix_d0, vs_pix_d1;
    always @(posedge clk_pix) begin
        vs_pix_d0 <= vs_d11; vs_pix_d1 <= vs_pix_d0;
    end
    wire vs_tick = vs_pix_d0 & ~vs_pix_d1;
    reg [31:0] fps_acc;
    reg [25:0] sec_div;
    reg [7:0]  fps_q;
    (* ASYNC_REG = "TRUE" *) reg vt0, vt1, vt2;
    always @(posedge sys_clk) {vt2,vt1,vt0} <= {vt1,vt0,vs_tick};
    wire vs_sys = vt1 & ~vt2;
    always @(posedge sys_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            sec_div <= 0; fps_acc <= 0; fps_q <= 0;
        end else if (sec_div == 26'd49_999_999) begin
            sec_div <= 0; fps_q <= fps_acc[7:0]; fps_acc <= 0;
        end else begin
            sec_div <= sec_div + 1'b1;
            if (vs_sys) fps_acc <= fps_acc + 1'b1;
        end
    end

    // （r55）这里原来有一段 `{pkts_s1,pkts_s0} <= {pkts_s0, eth_pkts}` 之类的两级同步：
    // 两级触发器只能跨**单 bit**，跨 16 位计数值会读到"每一位各自新旧不一"的中间态；
    // 而它同步出来的东西在 V8-5 撤掉 PKTS=/ERR= 两行之后已经没有读者了 ⇒ 整段删除。
    // 数没有丢：pkts/bytes/bad 由 link_monitor 经 snap_cross 正确跨域，走 lane1/8/9。见 ISSUES #64。

    // v7.6: 健康快照跨到像素域。像素时钟是 50 MHz（clk_gen CLKOUT0_DIVIDE=20，
    // VCO 1000 MHz）；HB_TO_MS=200 ⇒ eth_rxc 停供 200 ms 后 OSD 的 STALL 直接钉 9999，
    // 这样"拔了线"和"还在只是慢"在屏上是两个长相。
    // V8-5：老 OSD 的 DROP / STALL 两格撤掉之后，这一路 320 bit 健康快照在像素域**没有消费者**了，
    // 于是原来那条 snap_cross（u_lm_x）连同 lm_bus / lm_bus_tog / lm_hb 三个输入口一起删掉：
    // 留着它就是一根"没人读的线"（本项目为这类线付过两次学费：#57 的位宽、#61 的多驱动）。
    // 数没有丢：lane0~lane9 在 axi 域由 `src/host/health_read.mjs` 机器可读（system_top 里那条
    // snap_cross 是给读回口用的，与本段无关，仍然存在）。
    // "链路断了"在屏上有三个长相：Src 那一格退回 CARD、FPS 掉到 0、Latency 变 `--`。
    // 老的 osd_drop / osd_stall 两格在 V8-5 撤掉了（屏上要让给 spec 的四个字段）。
    // **功能没有删**：drop 与 stall 仍然在 lane0/lane2 里由 `health_read.mjs` 机器可读，
    // 而"链路断了"这件事在屏上有三个长相：Src 那一格退回 CARD、FPS 掉到 0、Latency 变 `--`。

    // ---- V8-5：把 axi 域算好的 ms 跨到像素域（#36/#52 那一课：翻转位 + 3 级同步 + 整拍锁存）----
    // hb_tog 与 bus_tog 是**同一件事**：**没有新测量**就等于"心跳停了" ⇒ hb_gone 亮 ⇒ OSD 画 `--`。
    // 于是"ETH 停了、屏上还挂着最后一轮的 12 ms"这种过期读数不可能出现
    //（门限取 1000 ms：一轮测量正常是一帧 = 16~33 ms，留 30 倍以上余量，
    //  而 SLOW_MS 放到 200 ⇒ 只有时基真的废了才判 slow，不会把正常的帧间抖动当成断）。
    // 总线里带两位状态：lat_valid（这一轮算完了）与 ~lat_sticky（这一轮配对干净）。
    // 少了后一位，一次"倒挂/超长"的轮次就会把一个假 ms 画上屏 —— 那正是 #59 要防的那类谎。
    wire [17:0] lat_bus_q;
    wire        lat_gone;
    // 心跳**另起一个触发器**：语义仍然是"和发沿同一件事"（同域打一拍，10 ns，
    // 对 1000 ms 的门限什么都不意味着），但 `lat_tog_reg` 不再同时扇出到
    // bus_tog 与 hb_tog 两组目的域同步器 —— r55 的 cdc.rpt 里这一对
    // `clk_fpga_0 → clkout0_1` 有 3 个 unsafe 端点，其中 2 个就是这里（CDC-11
    // "Fan-out from launch flop to destination clock"），与 r54 构建 #34 判红那次
    // 同一个签名、同一个修法（见本文件 603 行 z_hb_tog 那段）。
    reg lat_hb_tog;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) lat_hb_tog <= 1'b0;
        else            lat_hb_tog <= lat_tog_axi;
    end
    snap_cross #(.W(18), .DST_HZ(50_000_000), .HB_TO_MS(1000), .SLOW_MS(200)) u_lat_x (
        .dst_clk(clk_pix), .dst_rst_n(rst_pix_n),
        .bus({lat_ok_axi, ~lat_sticky_axi, lat_ms_axi}),
        .bus_tog(lat_tog_axi), .hb_tog(lat_hb_tog),
        .bus_q(lat_bus_q), .hb_gone(lat_gone), .hb_slow()
    );
    wire        lat_ok_pix = lat_bus_q[17] & lat_bus_q[16] & ~lat_gone;
    wire [15:0] lat_ms_pix = lat_bus_q[15:0];

    // ---- Split 那一格现在来自几何参数（缝还没有执行者，见 ISSUES #62 / split_ctrl 的文件头）----
    // 除法是 elaboration 常数（PANE_W、DISP_W_H 都是参数），综合折成一个数，不留硬件。
    localparam [11:0] DISP_W_H      = 12'd1024;
    localparam [7:0]  SPLIT_PCT_FIX = ((PANE_W * 100) / DISP_W_H);

    wire [7:0] r_osd, g_osd, b_osd;
    wire de_osd, hs_osd, vs_osd;
    osd_overlay #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_osd (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x_d11), .y(y_d11), .de(de_o),
        .angle(angle_eff), .fps(fps_q),
        .stage_sel(sel_sync),                 // 五级链实际生效的九位
        .threshold(th_sync),
        .gamma_disp(gm_disp),
        .zoom_code(zoom_code), .zoom_auto(zoom_run && !zman_pix),   // V8-8：手动档不许再标 (Auto)
        .split_pct(SPLIT_PCT_FIX), .split_auto(1'b0),
        .lat_ms(lat_ms_pix), .lat_ok(lat_ok_pix),
        .src_eff({fb_vis, owner_eth_pix}),   // 屏幕上真的这一路：CARD / PS / ETH
        .mode(mode),
        .en(~osd_off),                     // V8-10：`osd 0` 关掉画字（节拍不变，见 osd_overlay 的 en 注释）
        .bg_pix(16'h0),
        .r_in(r), .g_in(g), .b_in(b),
        .hs_in(hs_o), .vs_in(vs_o),
        .r(r_osd), .g(g_osd), .b(b_osd),
        .de_out(de_osd), .hs_out(hs_osd), .vs_out(vs_osd)
    );

    rgb2dvi u_dvi (
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_pix_n),
        .r(r_osd), .g(g_osd), .b(b_osd),
        .hs(hs_osd), .vs(vs_osd), .de(de_osd),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );

    reg [24:0] hb;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) hb <= 0; else hb <= hb + 1'b1;
    end
    // led[0]: 正常 = 1.5Hz 心跳；一旦发生过「拷贝超出一个 V-blank 窗口」= 6Hz 快闪
    assign led[0] = copy_overrun ? hb[22] : hb[24];
    // led[1]：按下的过程里亮（0.2 s 后 = '我在计时'），松开后停在 ltog 上 —— 每成功一次长按它必翻转一次。
    // 原来这里挂的是 src_use，但屏幕 OSD 已经有片源行，LED 挂一个"看得见有没有生效"的东西更有用。
    assign led[1] = k1_hold ? 1'b1 : ltog;

    assign status = {zoom_dir, zoom_active, inv_scale, eth_ready, locked, rot_act_eff,   // V8-10：这一位报的是**真正在驱动几何的那一路**（按键或串口）
                     angle_eff, en_sync, src_use, 2'b00};
endmodule

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
    input  wire        src_sel,
    input  wire        zoom_en,
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
    output wire [7:0]  dbg_src,

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
    input  wire [15:0] eth_pkts,
    input  wire [15:0] eth_bad,

    // v7.6 (P0-A)：link_monitor 的快照总线 + 两个跳变信号（eth_rxc 域）。
    // 本模块只负责在像素域把它们安全取过来给 OSD。
    input  wire [319:0] lm_bus,
    input  wire         lm_bus_tog,
    input  wire         lm_hb,

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
    key_debounce #(.CNT_MAX(1_000_000)) u_k1 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key1_n), .pulse(p1), .key_stable(k1_up)
    );
    key_debounce #(.CNT_MAX(1_000_000)) u_k2 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key2_n), .pulse(p2), .key_stable()
    );

    // ---- 同一个按键的两种语义：短按 = 旋转 ±1°（R12/R13 板级验过，不动它），
    //      长按 ≈1.2 s = 切换片源模式。长按事件用**翻转位**跨域（脉冲跨域会被吃掉，
    //      与 `ps_publish` / ISSUES #36 是同一课）。
    //      已知代价：长按的那一拍也会先发一个短按脉冲 ⇒ 切模式时顺带 +1°。
    //      不去改旋转的触发时机，是为了保住已经验过的行为。
    wire ltog;
    key_long #(.HOLD_CYC(60_000_000)) u_k1l (     // sys_clk 50 MHz ⇒ 1.2 s
        .clk(sys_clk), .rst_n(sys_rst_n), .pressed(~k1_up), .tog(ltog));

    localparam [1:0] M_AUTO = 2'd0, M_ETH = 2'd1, M_PS = 2'd3, M_CARD = 2'd2;
    // 模式寄存器搬到了 `src/rtl/util/src_mode.v`，原因是"这段逻辑有没有台架"：
    // 以前它就写在这里（一个 3 级链 + 一个四态寄存器），顶层没有任何台架碰得到它，
    // 于是链的复位值写成 3'b111（源头 `tog` 复位是 0）这件事一直没人查 —— 上电白送一次
    // "长按"，模式自己走到"锁 ETH"，`src_arb` 的 `force_eth` 就此长占，"停流交回"永不发生。
    // 这就是 #28 板级交接判据红的那条根（详见 src_mode.v 文件头与 ISSUES #49）。
    wire [1:0] mode;
    src_mode u_mode (
        .clk(clk_pix), .rst_n(rst_pix_n), .ltog(ltog), .mode(mode)
    );
    wire mode_eth  = (mode == M_ETH);
    wire mode_ps   = (mode == M_PS);
    wire mode_card = (mode == M_CARD);

    (* ASYNC_REG = "TRUE" *) reg [1:0] ms0, ms1, ms2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin ms0 <= M_AUTO; ms1 <= M_AUTO; ms2 <= M_AUTO; end
        else begin ms0 <= mode; ms1 <= ms0; ms2 <= ms1; end
    end
    // 图卡模式不参与仲裁（保持 AUTO）：它只是"显示什么"，不是"谁在搬"
    wire [1:0] arb_sel = (ms2 == M_ETH) ? 2'd1 : (ms2 == M_PS) ? 2'd2 : 2'd0;
    wire [8:0] angle;
    wire rotate_active;
    angle_ctrl u_ang (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .key_inc(p1), .key_dec(p2),
        .angle(angle), .rotate_active(rotate_active)
    );

    wire [4:0] en_sync;
    wire [7:0] th_sync;
    wire [8:0] sel_sync;
    effect_ctrl u_eff (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .effect_en_async(effect_en),
        .stage_sel_async(stage_sel),
        .threshold_async(threshold),
        .stage_sel(sel_sync),
        .effect_en(en_sync), .threshold(th_sync)
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

    wire        left_pane = (x < PANE_W);
    wire [11:0] cx = left_pane ? x : (x - PANE_W);
    wire [11:0] cy = (y >> 1) < IMG_H ? (y >> 1) : (IMG_H - 1);

    wire [9:0] inv_scale;
    wire       zoom_active, zoom_dir;
    zoom_ctrl #(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd2)) u_zctrl (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .enable(zoom_run), .frame_start(frame_start),
        .inv_scale(inv_scale), .zoom_active(zoom_active), .dir(zoom_dir)
    );

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
    wire        rot_on = rotate_active;   // 只驱动右窗
    wire [11:0] sx_l = cx_q3;             // 左窗 = 未旋转原画面
    wire [11:0] sy_l = cy_q3;
    wire        oob_l = oob_q3;

    wire [11:0] sx_r, sy_r;
    wire        oob_r;
    wire [7:0]  zfrac_x, zfrac_y;
    zoom_mapper #(.IMAGE_W(IMG_W), .IMAGE_H(IMG_H)) u_zmap (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .inv_scale(inv_scale), .angle(angle), .rotate_en(rot_on),
        .x_in(cx), .y_in(cy),
        .x_out(sx_r), .y_out(sy_r), .oob(oob_r),
        .frac_x(zfrac_x), .frac_y(zfrac_y)
    );

    localparam SB = 16;
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
    src_arb #(.T_OFF_CYC(2_000_000)) u_arb (   // AXI 域 100 MHz ⇒ 20 ms 静默才让给 PS
        .clk(axi_clk), .rst_n(axi_rst_n), .eth_live(eth_live), .eth_tb_ok(eth_tb_ok),
        .sel(arb_sel),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_eth));
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
    wire owner_eth_pix = op2;

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
    // 模式决定"看哪一路"：锁 ETH / 锁 PS 时强制看 fb；锁图卡时强制看图卡；AUTO 交回给
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
    assign dbg_src = {1'd0, ms2, row_busy, fill_busy, owner_eth, eth_live, eth_tb_ok};

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
        .rotate_active(rot_on),
        .hs_in(hs_d[3]), .vs_in(vs_d[3]),
        .de_in(de_d[3] && !left_d[3]),
        .x_in(cx_d[3]), .y_in(cy_d[3]),
        .din(pix_right),
        .de_out(pipe_de), .dout(pipe_dout)
    );

    // 处理链的延迟**只有一处定义**：proc_pipeline 自己的 LATENCY。
    // 以前这里是字面量 7，于是"链上加一级"必须同时记得改这里 —— 忘了不是编译错，
    // 而是左窗（原始画面）与右窗（处理后）错开 N 个像素。左窗的 skid 长度直接取 u_pipe 的值，
    // 而 tb_v88 实测 de_in→de_out 与 LATENCY 对账 ⇒ 三处任一处漂移就有测试可红。
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
    split_display #(.PANE_W(PANE_W)) u_split (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x_d11), .y(y_d11), .de(de_d11), .hs(hs_d11), .vs(vs_d11),
        .orig_pix(orig_disp), .proc_pix(pipe_dout),
        .oob_l(oob_lo), .oob_r(oob_ro),
        .angle_idx(angle[1:0]),
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

    reg [15:0] pkts_s0, pkts_s1, bad_s0, bad_s1;
    always @(posedge clk_pix) begin
        {pkts_s1, pkts_s0} <= {pkts_s0, eth_pkts};
        {bad_s1, bad_s0}   <= {bad_s0, eth_bad};
    end

    // v7.6: 健康快照跨到像素域。像素时钟是 50 MHz（clk_gen CLKOUT0_DIVIDE=20，
    // VCO 1000 MHz）；HB_TO_MS=200 ⇒ eth_rxc 停供 200 ms 后 OSD 的 STALL 直接钉 9999，
    // 这样"拔了线"和"还在只是慢"在屏上是两个长相。
    wire [319:0] lm_pix;
    wire         lm_clk_gone, lm_clk_slow;
    snap_cross #(.W(320), .DST_HZ(50_000_000), .HB_TO_MS(200)) u_lm_x (
        .dst_clk(clk_pix), .dst_rst_n(rst_pix_n),
        .bus(lm_bus), .bus_tog(lm_bus_tog), .hb_tog(lm_hb),
        .bus_q(lm_pix), .hb_gone(lm_clk_gone), .hb_slow(lm_clk_slow)
    );
    wire [31:0] osd_drop  = lm_pix[0*32 +: 32];
    // gone = 源时钟没有；slow = 源时钟被 PHY 拉慢（板级实测拔线后 RXC≈2.5 MHz，
    // 只有 slow 会亮）—— 两种都意味着链路已断，STALL 就没有“毫秒”的含义了，
    // 于是钉成 9999，让屏上一眼看出“没流”，而不是一个爬得很慢的数字。
    wire [15:0] osd_stall = (lm_clk_gone | lm_clk_slow) ? 16'd9999 : lm_pix[2*32 +: 16];

    wire [7:0] r_osd, g_osd, b_osd;
    wire de_osd, hs_osd, vs_osd;
    osd_overlay u_osd (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x_d11), .y(y_d11), .de(de_o),
        .angle(angle), .effect_en(en_sync), .fps(fps_q),
        .src_sel(src_use), .eth_link(eth_link_pix),
        .net_pkts(pkts_s1), .net_bad(bad_s1),
        .net_drop(osd_drop), .net_stall(osd_stall),
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
    assign led[1] = src_use;

    assign status = {zoom_dir, zoom_active, inv_scale, eth_ready, locked, rotate_active,
                     angle, en_sync, src_use, 2'b00};
endmodule

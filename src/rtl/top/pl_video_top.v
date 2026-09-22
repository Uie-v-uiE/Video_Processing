`timescale 1ns/1ps
// pl_video_top — ghosting-fix v5
// Display BRAM written ONLY by axi_frame_writer_gated during blanking (~de).
// commit base locked until copy completes.
module pl_video_top #(
    parameter IMG_W     = 512,
    parameter IMG_H     = 300,
    parameter PANE_W    = 512,
    parameter BASE_ADDR = 32'h1000_0000,
    parameter ZOOM_DEFAULT_ON = 1
)(
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        axi_clk,
    input  wire        axi_rst_n,

    input  wire [4:0]  effect_en,
    input  wire [7:0]  threshold,
    input  wire        src_sel,
    input  wire        zoom_en,

    input  wire        key1_n,
    input  wire        key2_n,
    output wire [1:0]  led,

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

    wire p1, p2;
    key_debounce #(.CNT_MAX(1_000_000)) u_k1 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key1_n), .pulse(p1), .key_stable()
    );
    key_debounce #(.CNT_MAX(1_000_000)) u_k2 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key2_n), .pulse(p2), .key_stable()
    );
    wire [8:0] angle;
    wire rotate_active;
    angle_ctrl u_ang (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .key_inc(p1), .key_dec(p2),
        .angle(angle), .rotate_active(rotate_active)
    );

    wire [4:0] en_sync;
    wire [7:0] th_sync;
    effect_ctrl u_eff (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .effect_en_async(effect_en),
        .threshold_async(threshold),
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

    wire [11:0] sx_map, sy_map;
    wire        oob_map;
    rotate_mapper #(.IMAGE_W(IMG_W), .IMAGE_H(IMG_H)) u_rmap (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .angle(angle), .enable(1'b1),
        .x_in(cx), .y_in(cy),
        .x_out(sx_map), .y_out(sy_map), .oob(oob_map)
    );

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
    wire        rot_on = rotate_active;
    wire [11:0] sx_l = rot_on ? sx_map : cx_q3;
    wire [11:0] sy_l = rot_on ? sy_map : cy_q3;
    wire        oob_l = rot_on ? oob_map : oob_q3;

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

    (* ASYNC_REG = "TRUE" *) reg em0, em1, em2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {em2,em1,em0} <= 0;
        else {em2,em1,em0} <= {em1,em0,eth_link};
    end
    wire eth_mode = em2;

    frame_commit_lock #(.IMG_H(IMG_H), .DISP_H(600)) u_cmt (
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .commit_req(eth_commit), .commit_base(eth_ddr_base),
        .pix_clk(clk_pix), .pix_rst_n(rst_pix_n),
        .de(de), .vsync(vs), .blank_safe(disp_quiet),
        .copy_busy(row_busy), .copy_done(row_done),
        .start_copy(row_start), .copy_base(row_base),
        .frame_ready_pix(frame_ready),
        .allow_copy_axi(allow_copy),
        .copy_abort(copy_abort)
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

    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) eth_has_frame <= 1'b0;
        else if (frame_ready && eth_link) eth_has_frame <= 1'b1;
        else if (copy_abort) eth_has_frame <= 1'b0;
    end

    // SRC0=colorbar, SRC1=video (v5 SRC bug was |eth_ready locking SRC0)
    wire [15:0] fb_rd;
    wire eth_ready   = eth_link & eth_has_frame;
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
    // red only if no link; if link but not yet ready show BRAM (black/last)
    wire [15:0] bram_or_hold = eth_link ? fb_out : 16'hF800;

    reg fs_tog;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) fs_tog <= 1'b0;
        else if (frame_start && src_sel && !eth_link) fs_tog <= ~fs_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg fs0, fs1, fs2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fs2,fs1,fs0} <= 3'b0;
        else {fs2,fs1,fs0} <= {fs1,fs0,fs_tog};
    end
    wire ps_frame_start = fs1 ^ fs2;

    assign m_axi_arid = 6'd0;

    axi_frame_writer64 #(
        .IMG_W(IMG_W), .IMG_H(IMG_H), .BASE_ADDR(BASE_ADDR)
    ) u_aw (
        .clk(axi_clk), .rst_n(axi_rst_n),
        .enable(eth_mode ? 1'b0 : src_sel),
        .frame_start(eth_mode ? 1'b0 : ps_frame_start),
        .base_addr(BASE_ADDR),
        .frame_busy(), .frame_done(fill_done),
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

    wire [15:0] bar_l0, bar_r0;
    reg  [15:0] bar_l_d1, bar_l_d2, bar_l_d3, bar_l_d4, bar_r_d1, bar_r_d2;
    color_bar #(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H)) u_bar_l (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(cx), .y(cy), .de(de), .rgb565(bar_l0)
    );
    color_bar #(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H)) u_bar_r (
        .clk(clk_pix), .rst_n(rst_pix_n),
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

    wire [15:0] pix_left  = left_pix ? (oob_fb_d1 ? 16'h0000 : (src_use ? bram_or_hold : bar_l_d4))
                                      : 16'h0000;
    wire [15:0] pix_right = left_pix ? 16'h0000
                                      : (oob_fb_d1 ? 16'h0000 : (src_use ? bram_or_hold : bar_r_d2));
    wire oob_l_pix = left_pix & oob_fb_d1;
    wire oob_r_pix = (~left_pix) & oob_fb_d1;

    localparam PROC_LAT = 7;
    localparam LEFT_TAIL = PROC_LAT;

    wire [15:0] pipe_dout;
    wire        pipe_de;
    proc_pipeline #(.H_ACTIVE(IMG_W)) u_pipe (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .effect_en(en_sync), .threshold(th_sync),
        .rotate_active(rot_on),
        .hs_in(hs_d[3]), .vs_in(vs_d[3]),
        .de_in(de_d[3] && !left_d[3]),
        .x_in(cx_d[3]), .y_in(cy_d[3]),
        .din(pix_right),
        .de_out(pipe_de), .dout(pipe_dout)
    );

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

    reg [15:0] pkts_s0, pkts_s1, bad_s0, bad_s1, link_s0, link_s1;
    always @(posedge clk_pix) begin
        {pkts_s1, pkts_s0} <= {pkts_s0, eth_pkts};
        {bad_s1, bad_s0}   <= {bad_s0, eth_bad};
        {link_s1, link_s0} <= {link_s0, eth_link};
    end

    // v7.6: 健康快照跨到像素域。像素时钟是 50 MHz（clk_gen CLKOUT0_DIVIDE=20，
    // VCO 1000 MHz）；HB_TO_MS=200 ⇒ eth_rxc 停供 200 ms 后 OSD 的 STALL 直接钉 9999，
    // 这样"拔了线"和"还在只是慢"在屏上是两个长相。
    wire [319:0] lm_pix;
    wire         lm_clk_gone;
    snap_cross #(.W(320), .DST_HZ(50_000_000), .HB_TO_MS(200)) u_lm_x (
        .dst_clk(clk_pix), .dst_rst_n(rst_pix_n),
        .bus(lm_bus), .bus_tog(lm_bus_tog), .hb_tog(lm_hb),
        .bus_q(lm_pix), .hb_gone(lm_clk_gone)
    );
    wire [31:0] osd_drop  = lm_pix[0*32 +: 32];
    wire [15:0] osd_stall = lm_clk_gone ? 16'd9999 : lm_pix[2*32 +: 16];

    wire [7:0] r_osd, g_osd, b_osd;
    wire de_osd, hs_osd, vs_osd;
    osd_overlay u_osd (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x_d11), .y(y_d11), .de(de_o),
        .angle(angle), .effect_en(en_sync), .fps(fps_q),
        .src_sel(src_use), .eth_link(link_s1),
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

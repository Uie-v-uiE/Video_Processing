`timescale 1ns/1ps
// ETH UDP video top — ghosting-fix v5
// DDR ping-pong + burst saver; commit pulse with completed base.
module eth_udp_video_top #(
    parameter IMG_W      = 512,
    parameter IMG_H      = 300,
    parameter BASE_ADDR  = 32'h1000_0000,
    parameter [15:0] UDP_PORT = 16'd5001,
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = {8'd192,8'd168,8'd1,8'd10},
    parameter IDELAY_VALUE = 15
)(
    input  wire        rgmii_rxc,
    input  wire        rst_n,
    input  wire        axi_clk,
    input  wire        axi_rst_n,
    input  wire        idelay_clk,
    input  wire        copy_hold,

    input  wire        rgmii_rx_ctl,
    input  wire [3:0]  rgmii_rxd,
    output wire        rgmii_tx_clk,
    output wire        rgmii_tx_ctl,
    output wire [3:0]  rgmii_txd,

    output wire        fb_wr_en,
    output wire [18:0] fb_wr_addr,
    output wire [15:0] fb_wr_data,
    output wire        frame_done,
    output wire        link_active,
    output wire        eth_gmii_clk,

    output wire [31:0] ddr_commit_base,
    output wire        ddr_commit_pulse,

    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    output wire [31:0] stat_frames,
    output wire [31:0] stat_pkts,
    output wire [31:0] stat_bytes,
    output wire [31:0] stat_bad
);
    localparam [31:0] BANK0 = BASE_ADDR;
    localparam [31:0] BANK1 = BASE_ADDR + 32'h0008_0000;

    wire gmii_rx_clk, gmii_rx_dv, gmii_tx_clk, gmii_tx_en;
    wire [7:0] gmii_rxd, gmii_txd;

    gmii_to_rgmii #(.IDELAY_VALUE(IDELAY_VALUE)) u_rgmii (
        .idelay_clk(idelay_clk),
        .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
        .rgmii_rxc(rgmii_rxc), .rgmii_rx_ctl(rgmii_rx_ctl), .rgmii_rxd(rgmii_rxd),
        .rgmii_txc(rgmii_tx_clk), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd)
    );

    wire        arp_rx_done, arp_rx_type, arp_tx_en, arp_tx_done;
    wire [47:0] src_mac;
    wire [31:0] src_ip;
    wire        arp_gmii_tx_en;
    wire [7:0]  arp_gmii_txd;

    wire        icmp_rec_pkt_done, icmp_rec_en;
    wire [7:0]  icmp_rec_data;
    wire [15:0] icmp_rec_byte_num;
    wire        icmp_tx_done, icmp_tx_req;
    wire        icmp_gmii_tx_en;
    wire [7:0]  icmp_gmii_txd, icmp_tx_data;
    reg  [15:0] icmp_tx_byte_num;
    reg  [5:0]  icmp_dly;
    reg         icmp_tx_start_en;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) begin
            icmp_dly <= 0; icmp_tx_start_en <= 0; icmp_tx_byte_num <= 0;
        end else begin
            icmp_tx_start_en <= 0;
            if (icmp_rec_pkt_done) begin
                icmp_dly <= 6'd20;
                icmp_tx_byte_num <= icmp_rec_byte_num;
            end else if (icmp_dly != 0) begin
                icmp_dly <= icmp_dly - 1'b1;
                if (icmp_dly == 6'd1) icmp_tx_start_en <= 1'b1;
            end
        end
    end

    wire        udp_rec_pkt_done, udp_rec_en;
    wire [7:0]  udp_rec_data;
    wire [15:0] udp_rec_byte_num;
    wire        udp_gmii_tx_en, udp_tx_done, udp_tx_req;
    wire [7:0]  udp_gmii_txd, udp_tx_data;
    wire [7:0]  fifo_tx_data;
    wire        fifo_tx_req, fifo_rec_en;
    wire [7:0]  fifo_rec_data;

    wire [7:0] icmp_fifo_q;
    sync_fifo #(.DATA_W(8), .ADDR_W(11)) u_icmp_fifo (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .wr_en(icmp_rec_en), .wr_data(icmp_rec_data),
        .full(), .empty(), .level(),
        .rd_en(icmp_tx_req), .rd_data(icmp_fifo_q)
    );

    arp #(
        .BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP),
        .DES_MAC(48'hff_ff_ff_ff_ff_ff), .DES_IP({8'd192,8'd168,8'd1,8'd102})
    ) u_arp (
        .rst_n(rst_n),
        .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(arp_gmii_tx_en), .gmii_txd(arp_gmii_txd),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .src_mac(src_mac), .src_ip(src_ip),
        .arp_tx_en(arp_tx_en), .arp_tx_type(1'b1),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(arp_tx_done)
    );

    icmp #(
        .BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)
    ) u_icmp (
        .rst_n(rst_n),
        .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(icmp_gmii_tx_en), .gmii_txd(icmp_gmii_txd),
        .rec_pkt_done(icmp_rec_pkt_done), .rec_en(icmp_rec_en), .rec_data(icmp_rec_data),
        .rec_byte_num(icmp_rec_byte_num),
        .tx_start_en(icmp_tx_start_en), .tx_data(icmp_fifo_q),
        .tx_byte_num(icmp_tx_byte_num),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(icmp_tx_done), .tx_req(icmp_tx_req)
    );

    udp #(
        .BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)
    ) u_udp (
        .rst_n(rst_n),
        .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(udp_gmii_tx_en), .gmii_txd(udp_gmii_txd),
        .rec_pkt_done(udp_rec_pkt_done), .rec_en(udp_rec_en), .rec_data(udp_rec_data),
        .rec_byte_num(udp_rec_byte_num),
        .tx_start_en(1'b0), .tx_data(8'd0), .tx_byte_num(16'd0),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(udp_tx_done), .tx_req(udp_tx_req)
    );

    eth_ctrl u_ctrl (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .arp_tx_en(arp_tx_en), .arp_tx_type(), .arp_tx_done(arp_tx_done),
        .arp_gmii_tx_en(arp_gmii_tx_en), .arp_gmii_txd(arp_gmii_txd),
        .icmp_tx_start_en(icmp_tx_start_en), .icmp_tx_done(icmp_tx_done),
        .icmp_gmii_tx_en(icmp_gmii_tx_en), .icmp_gmii_txd(icmp_gmii_txd),
        .icmp_rec_en(icmp_rec_en), .icmp_rec_data(icmp_rec_data),
        .icmp_tx_req(icmp_tx_req), .icmp_tx_data(),
        .udp_tx_start_en(1'b0), .udp_tx_done(udp_tx_done),
        .udp_gmii_tx_en(udp_gmii_tx_en), .udp_gmii_txd(udp_gmii_txd),
        .udp_rec_data(udp_rec_data), .udp_rec_en(udp_rec_en),
        .udp_tx_req(udp_tx_req), .udp_tx_data(),
        .tx_data(fifo_tx_data), .tx_req(fifo_tx_req),
        .rec_en(fifo_rec_en), .rec_data(fifo_rec_data),
        .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd)
    );

    wire [31:0] s_frames, s_pkts, s_bytes, s_badc, s_oob;
    reg in_udp_pkt;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) in_udp_pkt <= 1'b0;
        else if (udp_rec_pkt_done) in_udp_pkt <= 1'b0;
        else if (udp_rec_en) in_udp_pkt <= 1'b1;
    end
    wire udp_sof = udp_rec_en && !in_udp_pkt;

    wire reasm_flush;
    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_reasm (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .p_data(udp_rec_data), .p_valid(udp_rec_en),
        .p_sof(udp_sof), .p_eof(udp_rec_pkt_done), .p_good(1'b1),
        .wr_en(fb_wr_en), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .flush(reasm_flush),
        .frame_done(frame_done), .frame_err(),
        .stat_frames(s_frames), .stat_pkts(s_pkts),
        .stat_bytes(s_bytes), .stat_bad(s_badc), .stat_oob_off(s_oob)
    );

    wire [35:0] fifo_dout;
    wire fifo_empty, fifo_full;
    reg  fifo_rd;
    reg  [35:0] cdc_d1;
    reg         cdc_d1_v;
    reg  sav_en, sav_flush;
    reg [18:0] sav_a;
    reg [15:0] sav_d;
    reg  flush_pend;
    wire sv_full;      // v6.2: 打包器 FIFO 满 ⇒ 反压 CDC 读（取出来丢掉等于白读）

    // v6.1: 一个 1392B 的包在 125MHz 下是**连续线速**进来的（上位机限速只能拉开
    // 包间隔），每包 698 个 16bit 写。原来读侧限成「每 3 个 axi 周期取 1 条」
    // = 66 MB/s < 125 MB/s，单包就能把 512 深的 CDC 灌满 → 稳定丢 ~46% 的字，
    // 表现为板上「每隔一个 16bit 空洞」的黑纹，且与上位机速率无关。
    // 现在 1 条/周期（200 MB/s），并且 flush 标记永远让路给真实数据写。
    wire cdc_wr = (fb_wr_en || reasm_flush || flush_pend) && !fifo_full;
    wire [35:0] cdc_data = fb_wr_en ? {1'b0, fb_wr_addr, fb_wr_data}
                                    : {1'b1, 19'd0, 16'd0};

    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) flush_pend <= 1'b0;
        else if (reasm_flush && fb_wr_en && !fifo_full) flush_pend <= 1'b1;
        else if (flush_pend && !fb_wr_en && !fifo_full) flush_pend <= 1'b0;
    end

    // v6.2: 缓冲主力——BRAM 实现的 CDC（dc_fifo 带 ram_style="block"）。
    // 8192 条 = 4096 个 64bit 字 = 16 KB，足以吸收「显示拷贝独占 HP0 一整个
    // V-blank」期间到达的入包数据（15 MBps × 672 µs ≈ 1260 字）。
    dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc (
        .wr_clk(gmii_rx_clk), .wr_rst_n(rst_n),
        .wr_en(cdc_wr),
        .wr_data(cdc_data),
        .wr_full(fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(fifo_rd), .rd_data(fifo_dout), .rd_empty(fifo_empty)
    );

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            fifo_rd<=0; cdc_d1<=0; cdc_d1_v<=0;
            sav_en<=0; sav_flush<=0; sav_a<=0; sav_d<=0;
        end else begin
            fifo_rd  <= !fifo_empty && !sv_full;
            cdc_d1   <= fifo_dout;
            cdc_d1_v <= fifo_rd;
            sav_en    <= cdc_d1_v && !cdc_d1[35];
            sav_flush <= cdc_d1_v &&  cdc_d1[35];
            if (cdc_d1_v) begin
                sav_a <= cdc_d1[34:16];
                sav_d <= cdc_d1[15:0];
            end
        end
    end

    reg frame_done_tog = 1'b0;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) frame_done_tog <= 1'b0;
        else if (frame_done) frame_done_tog <= ~frame_done_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fd2,fd1,fd0} <= 3'b0;
        else {fd2,fd1,fd0} <= {fd1,fd0,frame_done_tog};
    end
    wire fd_axi = fd1 ^ fd2;

    reg        bank = 1'b0;
    reg [31:0] completed_base = BANK0;
    reg        commit_pulse = 1'b0;
    reg        switch_req = 1'b0;
    reg        force_flush = 1'b0;
    wire       saver_idle;
    wire [31:0] sav_base = bank ? BANK1 : BANK0;

    // v5.6: same bank policy as the ghosting-free v5 —
    // switch only after saver idle (in-flight words finish on the old bank).
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            bank <= 1'b0;
            completed_base <= BANK0;
            commit_pulse <= 1'b0;
            switch_req <= 1'b0;
            force_flush <= 1'b0;
        end else begin
            commit_pulse <= 1'b0;
            if (fd_axi) begin
                switch_req  <= 1'b1;
                force_flush <= 1'b1;
            end
            if (switch_req && saver_idle) begin
                completed_base <= sav_base;
                bank           <= ~bank;
                commit_pulse   <= 1'b1;
                switch_req     <= 1'b0;
                force_flush    <= 1'b0;
            end
            if (saver_idle && !switch_req)
                force_flush <= 1'b0;
        end
    end
    assign ddr_commit_base  = completed_base;
    assign ddr_commit_pulse = commit_pulse;

    // v5.0: use saver64 so idle/commit/frame_ready can complete (burst hung → red).
    // v6.2: 打包器满时停止从 CDC 取数（反压），否则取出来就丢，等于白读。
    axi_frame_saver64 #(.BASE_ADDR(BANK0)) u_saver (
        .clk(axi_clk), .rst_n(axi_rst_n), .enable(1'b1),
        .base_addr(sav_base),
        .wr_en(sav_en), .wr_addr(sav_a), .wr_data(sav_d),
        .flush(sav_flush | force_flush),
        .fifo_full(sv_full), .idle(saver_idle), .busy(),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
    );

    assign stat_frames = s_frames;
    assign stat_pkts   = s_pkts;
    assign stat_bytes  = s_bytes;
    assign stat_bad    = s_badc;
    assign link_active = |s_pkts[15:0];
    assign eth_gmii_clk = gmii_rx_clk;
endmodule

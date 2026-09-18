`timescale 1ns/1ps
// Proven RK UDP stack (ARP/ICMP/UDP) + video reassembly sink
// Source adapted from 13_UDP_STACK (board-verified ping/ARP).
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
    // Delay TX start so all payload bytes are in FIFO
    reg  [5:0]  icmp_dly;
    reg         icmp_tx_start_en;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) begin
            icmp_dly <= 0;
            icmp_tx_start_en <= 0;
            icmp_tx_byte_num <= 0;
        end else begin
            icmp_tx_start_en <= 0;
            if (icmp_rec_pkt_done) begin
                icmp_dly <= 6'd20;
                icmp_tx_byte_num <= icmp_rec_byte_num;
            end else if (icmp_dly != 0) begin
                icmp_dly <= icmp_dly - 1'b1;
                if (icmp_dly == 6'd1)
                    icmp_tx_start_en <= 1'b1;
            end
        end
    end

    wire        udp_rec_pkt_done, udp_rec_en;
    wire [7:0]  udp_rec_data;
    wire [15:0] udp_rec_byte_num;
    wire        udp_gmii_tx_en, udp_tx_done, udp_tx_req;
    wire [7:0]  udp_gmii_txd, udp_tx_data;

    wire [7:0]  fifo_tx_data;
    wire        fifo_tx_req;
    wire        fifo_rec_en;
    wire [7:0]  fifo_rec_data;

    // ICMP payload FIFO — feed icmp_tx DIRECTLY (do not use eth_ctrl's shared FIFO path)
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
        .icmp_tx_req(icmp_tx_req), .icmp_tx_data(),  // payload comes from dedicated FIFO
        .udp_tx_start_en(1'b0), .udp_tx_done(udp_tx_done),
        .udp_gmii_tx_en(udp_gmii_tx_en), .udp_gmii_txd(udp_gmii_txd),
        .udp_rec_data(udp_rec_data), .udp_rec_en(udp_rec_en),
        .udp_tx_req(udp_tx_req), .udp_tx_data(),
        .tx_data(fifo_tx_data), .tx_req(fifo_tx_req),
        .rec_en(fifo_rec_en), .rec_data(fifo_rec_data),
        .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd)
    );

    // Video reassembly
    wire [31:0] s_frames, s_pkts, s_bytes, s_badc, s_oob;
    reg in_udp_pkt;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) in_udp_pkt <= 1'b0;
        else if (udp_rec_pkt_done) in_udp_pkt <= 1'b0;
        else if (udp_rec_en) in_udp_pkt <= 1'b1;
    end
    wire udp_sof = udp_rec_en && !in_udp_pkt;

    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_reasm (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .p_data(udp_rec_data), .p_valid(udp_rec_en),
        .p_sof(udp_sof), .p_eof(udp_rec_pkt_done), .p_good(1'b1),
        .wr_en(fb_wr_en), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .frame_done(frame_done), .frame_err(),
        .stat_frames(s_frames), .stat_pkts(s_pkts),
        .stat_bytes(s_bytes), .stat_bad(s_badc), .stat_oob_off(s_oob)
    );

    // CDC to AXI + DDR write
    wire [35:0] fifo_dout;
    wire fifo_empty, fifo_full;
    reg  fifo_rd, fifo_rd_d, sav_en;
    reg [18:0] sav_a;
    reg [15:0] sav_d;

    dc_fifo #(.DATA_W(36), .ADDR_W(6)) u_cdc (
        .wr_clk(gmii_rx_clk), .wr_rst_n(rst_n),
        .wr_en(fb_wr_en && !fifo_full), .wr_data({1'b0, fb_wr_addr, fb_wr_data}),
        .wr_full(fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(fifo_rd), .rd_data(fifo_dout), .rd_empty(fifo_empty)
    );

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            fifo_rd<=0; fifo_rd_d<=0; sav_en<=0; sav_a<=0; sav_d<=0;
        end else begin
            fifo_rd   <= !fifo_empty && !fifo_rd && !fifo_rd_d;
            fifo_rd_d <= fifo_rd;
            sav_en    <= fifo_rd_d;
            if (fifo_rd_d) begin
                sav_a <= fifo_dout[34:16];  // NOT [35:17]
                sav_d <= fifo_dout[15:0];
            end
        end
    end

    axi_frame_saver #(.BASE_ADDR(BASE_ADDR)) u_saver (
        .clk(axi_clk), .rst_n(axi_rst_n), .enable(1'b1),
        .wr_en(sav_en), .wr_addr(sav_a), .wr_data(sav_d),
        .busy(),
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

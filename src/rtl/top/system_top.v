`timescale 1ns/1ps

// system_top: PS BD + PL video + PL UDP ethernet RX (PHY2)
module system_top (
    inout  wire        DDR_cas_n,
    inout  wire        DDR_cke,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cs_n,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire [2:0]  DDR_ba,
    inout  wire [14:0] DDR_addr,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dm,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,
    input  wire        sys_clk,
    input  wire        key1_n,
    input  wire        key2_n,
    output wire [1:0]  led,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,

    // PL ETH PHY2 RGMII (RX used for video sink; TX for ARP/ICMP)
    input  wire        eth_rxc,
    input  wire        eth_rx_ctl,
    input  wire [3:0]  eth_rxd,
    output wire        eth_tx_clk,
    output wire        eth_tx_ctl,
    output wire [3:0]  eth_txd,
    output wire        eth_mdc,
    inout  wire        eth_mdio,
    output wire        eth_rst_n
);
    wire fclk0, fclk0_rst_n;
    wire [31:0] gpio_o, status;
    wire [31:0] m_araddr;
    wire [5:0]  m_arid;
    wire [3:0]  m_arlen_axi3;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire        m_arvalid, m_arready;
    wire [63:0] m_rdata;
    wire [5:0]  m_rid;
    wire [1:0]  m_rresp;
    wire        m_rlast, m_rvalid, m_rready;
    wire [7:0]  m_arlen8;

    // AXI write from PL UDP saver
    wire [31:0] m_awaddr;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire        m_awvalid;
    wire        m_awready;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    wire        m_wlast, m_wvalid, m_wready;
    wire        m_bvalid, m_bready;
    wire [3:0]  m_awlen_axi3 = m_awlen[3:0];

    design_1_wrapper u_bd (
        .DDR_cas_n(DDR_cas_n), .DDR_cke(DDR_cke), .DDR_ck_n(DDR_ck_n), .DDR_ck_p(DDR_ck_p),
        .DDR_cs_n(DDR_cs_n), .DDR_odt(DDR_odt), .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n), .DDR_ba(DDR_ba), .DDR_addr(DDR_addr), .DDR_dq(DDR_dq),
        .DDR_dm(DDR_dm), .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .FCLK_CLK0(fclk0), .FCLK_RESET0_N(fclk0_rst_n),
        .GPIO_0_tri_o(gpio_o),
        .M_AXI_HP0_araddr(m_araddr), .M_AXI_HP0_arburst(m_arburst),
        .M_AXI_HP0_arcache(4'b0011), .M_AXI_HP0_arid(m_arid),
        .M_AXI_HP0_arlen(m_arlen_axi3), .M_AXI_HP0_arlock(2'b00),
        .M_AXI_HP0_arprot(3'b000), .M_AXI_HP0_arqos(4'b0000),
        .M_AXI_HP0_arready(m_arready), .M_AXI_HP0_arsize(m_arsize),
        .M_AXI_HP0_arvalid(m_arvalid),
        .M_AXI_HP0_awaddr(m_awaddr), .M_AXI_HP0_awburst(m_awburst), .M_AXI_HP0_awcache(4'b0011),
        .M_AXI_HP0_awid(6'd0), .M_AXI_HP0_awlen(m_awlen_axi3), .M_AXI_HP0_awlock(2'b00),
        .M_AXI_HP0_awprot(3'b000), .M_AXI_HP0_awqos(4'b0000),
        .M_AXI_HP0_awready(m_awready),
        .M_AXI_HP0_awsize(m_awsize), .M_AXI_HP0_awvalid(m_awvalid),
        .M_AXI_HP0_bid(), .M_AXI_HP0_bready(m_bready), .M_AXI_HP0_bresp(), .M_AXI_HP0_bvalid(m_bvalid),
        .M_AXI_HP0_rdata(m_rdata), .M_AXI_HP0_rid(m_rid), .M_AXI_HP0_rlast(m_rlast),
        .M_AXI_HP0_rready(m_rready), .M_AXI_HP0_rresp(m_rresp), .M_AXI_HP0_rvalid(m_rvalid),
        .M_AXI_HP0_wdata(m_wdata), .M_AXI_HP0_wid(6'd0), .M_AXI_HP0_wlast(m_wlast),
        .M_AXI_HP0_wready(m_wready), .M_AXI_HP0_wstrb(m_wstrb), .M_AXI_HP0_wvalid(m_wvalid)
    );

    assign m_arlen_axi3 = m_arlen8[3:0];

    // PHY2 reset
    reg [23:0] phy_rst_cnt = 24'd0;
    always @(posedge sys_clk) begin
        if (!(&phy_rst_cnt)) phy_rst_cnt <= phy_rst_cnt + 1'b1;
    end
    assign eth_rst_n = phy_rst_cnt[23];
    assign eth_mdio  = 1'bz;
    assign eth_mdc   = 1'b0;

    // 200 MHz IDELAY ref
    wire clk_pix_unused, clk_pix5x_unused, mmcm_locked;
    wire clk_200m;
    clk_gen u_idelay_clkgen (
        .clk_in(sys_clk), .rst_n(1'b1),
        .clk_pix(clk_pix_unused), .clk_pix5x(clk_pix5x_unused),
        .clk_200m(clk_200m), .locked(mmcm_locked)
    );

    wire        eth_wr_en, eth_frame_done, eth_link;
    wire [18:0] eth_wr_addr;
    wire [15:0] eth_wr_data;
    wire [31:0] eth_frames, eth_pkts, eth_bytes, eth_bad;
    wire        eth_gmii_clk;

    // RAW eth_rxc into rgmii_rx (BUFIO needs pin clock)
    eth_udp_video_top #(
        .IMG_W(512), .IMG_H(300),
        .BASE_ADDR(32'h1000_0000),
        .UDP_PORT(16'd5001),
        .BOARD_MAC(48'h00_11_22_33_44_55),
        .BOARD_IP({8'd192,8'd168,8'd1,8'd10}),
        .IDELAY_VALUE(15)
    ) u_eth (
        .rgmii_rxc(eth_rxc),
        .rst_n(eth_rst_n & mmcm_locked),
        .axi_clk(fclk0),
        .axi_rst_n(fclk0_rst_n),
        .idelay_clk(clk_200m),
        .rgmii_rx_ctl(eth_rx_ctl),
        .rgmii_rxd(eth_rxd),
        .rgmii_tx_clk(eth_tx_clk),
        .rgmii_tx_ctl(eth_tx_ctl),
        .rgmii_txd(eth_txd),
        .fb_wr_en(eth_wr_en),
        .fb_wr_addr(eth_wr_addr),
        .fb_wr_data(eth_wr_data),
        .frame_done(eth_frame_done),
        .link_active(eth_link),
        .eth_gmii_clk(eth_gmii_clk),
        .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast), .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .stat_frames(eth_frames), .stat_pkts(eth_pkts),
        .stat_bytes(eth_bytes), .stat_bad(eth_bad)
    );

    pl_video_top #(.IMG_W(512), .IMG_H(300), .PANE_W(512), .BASE_ADDR(32'h1000_0000)) u_pl (
        .sys_clk(sys_clk), .sys_rst_n(1'b1),
        .axi_clk(fclk0), .axi_rst_n(fclk0_rst_n),
        .effect_en(gpio_o[4:0]), .threshold(gpio_o[15:8]), .src_sel(gpio_o[16]),
        // 右屏无极缩放：常开（用户需求）。若要串口控制可改为 gpio_o[17]，PS 默认写 1。
        .zoom_en(1'b1),
        .key1_n(key1_n), .key2_n(key2_n), .led(led),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .m_axi_araddr(m_araddr), .m_axi_arid(m_arid), .m_axi_arlen(m_arlen8),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata(m_rdata), .m_axi_rid(m_rid), .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
        .eth_wr_clk(eth_gmii_clk),
        .eth_wr_en(eth_wr_en),
        .eth_wr_addr(eth_wr_addr),
        .eth_wr_data(eth_wr_data),
        .eth_link(eth_link),
        .eth_frame(eth_frame_done),
        .eth_pkts(eth_pkts[15:0]),
        .eth_bad(eth_bad[15:0]),
        .status(status)
    );
endmodule

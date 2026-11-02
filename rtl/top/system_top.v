`timescale 1ns/1ps

// system_top â€? AXI GPIO (GP0) controls effects; HP0 reads DDR frames
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
    output wire [2:0]  tmds_data_n
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
        .M_AXI_HP0_awaddr(32'd0), .M_AXI_HP0_awburst(2'b01), .M_AXI_HP0_awcache(4'b0011),
        .M_AXI_HP0_awid(6'd0), .M_AXI_HP0_awlen(4'd0), .M_AXI_HP0_awlock(2'b00),
        .M_AXI_HP0_awprot(3'b000), .M_AXI_HP0_awqos(4'b0000), .M_AXI_HP0_awready(),
        .M_AXI_HP0_awsize(3'b011), .M_AXI_HP0_awvalid(1'b0),
        .M_AXI_HP0_bid(), .M_AXI_HP0_bready(1'b0), .M_AXI_HP0_bresp(), .M_AXI_HP0_bvalid(),
        .M_AXI_HP0_rdata(m_rdata), .M_AXI_HP0_rid(m_rid), .M_AXI_HP0_rlast(m_rlast),
        .M_AXI_HP0_rready(m_rready), .M_AXI_HP0_rresp(m_rresp), .M_AXI_HP0_rvalid(m_rvalid),
        .M_AXI_HP0_wdata(64'd0), .M_AXI_HP0_wid(6'd0), .M_AXI_HP0_wlast(1'b0),
        .M_AXI_HP0_wready(), .M_AXI_HP0_wstrb(8'd0), .M_AXI_HP0_wvalid(1'b0)
    );

    assign m_arlen_axi3 = m_arlen8[3:0];

    pl_video_top #(.IMG_W(512), .IMG_H(300), .PANE_W(512), .BASE_ADDR(32'h1000_0000)) u_pl (
        .sys_clk(sys_clk), .sys_rst_n(1'b1),
        .axi_clk(fclk0), .axi_rst_n(fclk0_rst_n),
        .effect_en(gpio_o[4:0]), .threshold(gpio_o[15:8]), .src_sel(gpio_o[16]),
        .key1_n(key1_n), .key2_n(key2_n), .led(led),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .m_axi_araddr(m_araddr), .m_axi_arid(m_arid), .m_axi_arlen(m_arlen8),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata(m_rdata), .m_axi_rid(m_rid), .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
        .status(status)
    );
endmodule


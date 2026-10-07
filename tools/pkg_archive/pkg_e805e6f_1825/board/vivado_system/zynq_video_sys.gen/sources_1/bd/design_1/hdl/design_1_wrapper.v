//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2.1 (win64) Build 6403652 Thu Mar 19 19:48:24 GMT 2026
//Date        : Mon Oct  5 14:44:18 2026
//Host        : Uie-laptop running 64-bit major release  (build 9200)
//Command     : generate_target design_1_wrapper.bd
//Design      : design_1_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module design_1_wrapper
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FCLK_CLK0,
    FCLK_RESET0_N,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    GPIO_0_tri_o,
    GPIO_1_tri_i,
    GPIO_2_tri_o,
    GPIO_3_tri_o,
    M_AXI_HP0_araddr,
    M_AXI_HP0_arburst,
    M_AXI_HP0_arcache,
    M_AXI_HP0_arid,
    M_AXI_HP0_arlen,
    M_AXI_HP0_arlock,
    M_AXI_HP0_arprot,
    M_AXI_HP0_arqos,
    M_AXI_HP0_arready,
    M_AXI_HP0_arsize,
    M_AXI_HP0_arvalid,
    M_AXI_HP0_awaddr,
    M_AXI_HP0_awburst,
    M_AXI_HP0_awcache,
    M_AXI_HP0_awid,
    M_AXI_HP0_awlen,
    M_AXI_HP0_awlock,
    M_AXI_HP0_awprot,
    M_AXI_HP0_awqos,
    M_AXI_HP0_awready,
    M_AXI_HP0_awsize,
    M_AXI_HP0_awvalid,
    M_AXI_HP0_bid,
    M_AXI_HP0_bready,
    M_AXI_HP0_bresp,
    M_AXI_HP0_bvalid,
    M_AXI_HP0_rdata,
    M_AXI_HP0_rid,
    M_AXI_HP0_rlast,
    M_AXI_HP0_rready,
    M_AXI_HP0_rresp,
    M_AXI_HP0_rvalid,
    M_AXI_HP0_wdata,
    M_AXI_HP0_wid,
    M_AXI_HP0_wlast,
    M_AXI_HP0_wready,
    M_AXI_HP0_wstrb,
    M_AXI_HP0_wvalid);
  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  output FCLK_CLK0;
  output FCLK_RESET0_N;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  output [31:0]GPIO_0_tri_o;
  input [31:0]GPIO_1_tri_i;
  output [31:0]GPIO_2_tri_o;
  output [31:0]GPIO_3_tri_o;
  input [31:0]M_AXI_HP0_araddr;
  input [1:0]M_AXI_HP0_arburst;
  input [3:0]M_AXI_HP0_arcache;
  input [5:0]M_AXI_HP0_arid;
  input [3:0]M_AXI_HP0_arlen;
  input [1:0]M_AXI_HP0_arlock;
  input [2:0]M_AXI_HP0_arprot;
  input [3:0]M_AXI_HP0_arqos;
  output M_AXI_HP0_arready;
  input [2:0]M_AXI_HP0_arsize;
  input M_AXI_HP0_arvalid;
  input [31:0]M_AXI_HP0_awaddr;
  input [1:0]M_AXI_HP0_awburst;
  input [3:0]M_AXI_HP0_awcache;
  input [5:0]M_AXI_HP0_awid;
  input [3:0]M_AXI_HP0_awlen;
  input [1:0]M_AXI_HP0_awlock;
  input [2:0]M_AXI_HP0_awprot;
  input [3:0]M_AXI_HP0_awqos;
  output M_AXI_HP0_awready;
  input [2:0]M_AXI_HP0_awsize;
  input M_AXI_HP0_awvalid;
  output [5:0]M_AXI_HP0_bid;
  input M_AXI_HP0_bready;
  output [1:0]M_AXI_HP0_bresp;
  output M_AXI_HP0_bvalid;
  output [63:0]M_AXI_HP0_rdata;
  output [5:0]M_AXI_HP0_rid;
  output M_AXI_HP0_rlast;
  input M_AXI_HP0_rready;
  output [1:0]M_AXI_HP0_rresp;
  output M_AXI_HP0_rvalid;
  input [63:0]M_AXI_HP0_wdata;
  input [5:0]M_AXI_HP0_wid;
  input M_AXI_HP0_wlast;
  output M_AXI_HP0_wready;
  input [7:0]M_AXI_HP0_wstrb;
  input M_AXI_HP0_wvalid;

  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FCLK_CLK0;
  wire FCLK_RESET0_N;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire [31:0]GPIO_0_tri_o;
  wire [31:0]GPIO_1_tri_i;
  wire [31:0]GPIO_2_tri_o;
  wire [31:0]GPIO_3_tri_o;
  wire [31:0]M_AXI_HP0_araddr;
  wire [1:0]M_AXI_HP0_arburst;
  wire [3:0]M_AXI_HP0_arcache;
  wire [5:0]M_AXI_HP0_arid;
  wire [3:0]M_AXI_HP0_arlen;
  wire [1:0]M_AXI_HP0_arlock;
  wire [2:0]M_AXI_HP0_arprot;
  wire [3:0]M_AXI_HP0_arqos;
  wire M_AXI_HP0_arready;
  wire [2:0]M_AXI_HP0_arsize;
  wire M_AXI_HP0_arvalid;
  wire [31:0]M_AXI_HP0_awaddr;
  wire [1:0]M_AXI_HP0_awburst;
  wire [3:0]M_AXI_HP0_awcache;
  wire [5:0]M_AXI_HP0_awid;
  wire [3:0]M_AXI_HP0_awlen;
  wire [1:0]M_AXI_HP0_awlock;
  wire [2:0]M_AXI_HP0_awprot;
  wire [3:0]M_AXI_HP0_awqos;
  wire M_AXI_HP0_awready;
  wire [2:0]M_AXI_HP0_awsize;
  wire M_AXI_HP0_awvalid;
  wire [5:0]M_AXI_HP0_bid;
  wire M_AXI_HP0_bready;
  wire [1:0]M_AXI_HP0_bresp;
  wire M_AXI_HP0_bvalid;
  wire [63:0]M_AXI_HP0_rdata;
  wire [5:0]M_AXI_HP0_rid;
  wire M_AXI_HP0_rlast;
  wire M_AXI_HP0_rready;
  wire [1:0]M_AXI_HP0_rresp;
  wire M_AXI_HP0_rvalid;
  wire [63:0]M_AXI_HP0_wdata;
  wire [5:0]M_AXI_HP0_wid;
  wire M_AXI_HP0_wlast;
  wire M_AXI_HP0_wready;
  wire [7:0]M_AXI_HP0_wstrb;
  wire M_AXI_HP0_wvalid;

  design_1 design_1_i
       (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FCLK_CLK0(FCLK_CLK0),
        .FCLK_RESET0_N(FCLK_RESET0_N),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .GPIO_0_tri_o(GPIO_0_tri_o),
        .GPIO_1_tri_i(GPIO_1_tri_i),
        .GPIO_2_tri_o(GPIO_2_tri_o),
        .GPIO_3_tri_o(GPIO_3_tri_o),
        .M_AXI_HP0_araddr(M_AXI_HP0_araddr),
        .M_AXI_HP0_arburst(M_AXI_HP0_arburst),
        .M_AXI_HP0_arcache(M_AXI_HP0_arcache),
        .M_AXI_HP0_arid(M_AXI_HP0_arid),
        .M_AXI_HP0_arlen(M_AXI_HP0_arlen),
        .M_AXI_HP0_arlock(M_AXI_HP0_arlock),
        .M_AXI_HP0_arprot(M_AXI_HP0_arprot),
        .M_AXI_HP0_arqos(M_AXI_HP0_arqos),
        .M_AXI_HP0_arready(M_AXI_HP0_arready),
        .M_AXI_HP0_arsize(M_AXI_HP0_arsize),
        .M_AXI_HP0_arvalid(M_AXI_HP0_arvalid),
        .M_AXI_HP0_awaddr(M_AXI_HP0_awaddr),
        .M_AXI_HP0_awburst(M_AXI_HP0_awburst),
        .M_AXI_HP0_awcache(M_AXI_HP0_awcache),
        .M_AXI_HP0_awid(M_AXI_HP0_awid),
        .M_AXI_HP0_awlen(M_AXI_HP0_awlen),
        .M_AXI_HP0_awlock(M_AXI_HP0_awlock),
        .M_AXI_HP0_awprot(M_AXI_HP0_awprot),
        .M_AXI_HP0_awqos(M_AXI_HP0_awqos),
        .M_AXI_HP0_awready(M_AXI_HP0_awready),
        .M_AXI_HP0_awsize(M_AXI_HP0_awsize),
        .M_AXI_HP0_awvalid(M_AXI_HP0_awvalid),
        .M_AXI_HP0_bid(M_AXI_HP0_bid),
        .M_AXI_HP0_bready(M_AXI_HP0_bready),
        .M_AXI_HP0_bresp(M_AXI_HP0_bresp),
        .M_AXI_HP0_bvalid(M_AXI_HP0_bvalid),
        .M_AXI_HP0_rdata(M_AXI_HP0_rdata),
        .M_AXI_HP0_rid(M_AXI_HP0_rid),
        .M_AXI_HP0_rlast(M_AXI_HP0_rlast),
        .M_AXI_HP0_rready(M_AXI_HP0_rready),
        .M_AXI_HP0_rresp(M_AXI_HP0_rresp),
        .M_AXI_HP0_rvalid(M_AXI_HP0_rvalid),
        .M_AXI_HP0_wdata(M_AXI_HP0_wdata),
        .M_AXI_HP0_wid(M_AXI_HP0_wid),
        .M_AXI_HP0_wlast(M_AXI_HP0_wlast),
        .M_AXI_HP0_wready(M_AXI_HP0_wready),
        .M_AXI_HP0_wstrb(M_AXI_HP0_wstrb),
        .M_AXI_HP0_wvalid(M_AXI_HP0_wvalid));
endmodule

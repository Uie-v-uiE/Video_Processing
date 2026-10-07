// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------
// This file contains confidential and proprietary information
// of AMD and is protected under U.S. and international copyright
// and other intellectual property laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
// DO NOT MODIFY THIS FILE.

// MODULE VLNV: amd.com:blockdesign:design_1:1.0

`timescale 1ps / 1ps

`include "vivado_interfaces.svh"

module design_1_sv (
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_HP0" *)
  (* X_INTERFACE_MODE = "slave M_AXI_HP0" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_HP0, DATA_WIDTH 64, PROTOCOL AXI3, FREQ_HZ 100000000, ID_WIDTH 6, ADDR_WIDTH 32, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_PROT 1, HAS_CACHE 1, HAS_QOS 1, HAS_REGION 0, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 8, NUM_WRITE_OUTSTANDING 8, MAX_BURST_LENGTH 16, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *)
  vivado_aximm_v1_0.slave M_AXI_HP0,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_cas_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_cke,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_ck_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_ck_p,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_cs_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_reset_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_odt,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_ras_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_we_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [2:0] DDR_ba,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [14:0] DDR_addr,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [3:0] DDR_dm,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [31:0] DDR_dq,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [3:0] DDR_dqs_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [3:0] DDR_dqs_p,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [53:0] FIXED_IO_mio,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_ddr_vrn,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_ddr_vrp,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_ps_srstb,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_ps_clk,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_ps_porb,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire FCLK_CLK0,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire FCLK_RESET0_N,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [31:0] GPIO_0_tri_o,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [31:0] GPIO_1_tri_i,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [31:0] GPIO_2_tri_o,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [31:0] GPIO_3_tri_o
);

  // interface wire assignments
  assign M_AXI_HP0.BUSER = 0;
  assign M_AXI_HP0.RUSER = 0;

  design_1 inst (
    .DDR_cas_n(DDR_cas_n),
    .DDR_cke(DDR_cke),
    .DDR_ck_n(DDR_ck_n),
    .DDR_ck_p(DDR_ck_p),
    .DDR_cs_n(DDR_cs_n),
    .DDR_reset_n(DDR_reset_n),
    .DDR_odt(DDR_odt),
    .DDR_ras_n(DDR_ras_n),
    .DDR_we_n(DDR_we_n),
    .DDR_ba(DDR_ba),
    .DDR_addr(DDR_addr),
    .DDR_dm(DDR_dm),
    .DDR_dq(DDR_dq),
    .DDR_dqs_n(DDR_dqs_n),
    .DDR_dqs_p(DDR_dqs_p),
    .FIXED_IO_mio(FIXED_IO_mio),
    .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
    .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
    .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
    .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
    .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
    .M_AXI_HP0_awaddr(M_AXI_HP0.AWADDR),
    .M_AXI_HP0_awlen(M_AXI_HP0.AWLEN),
    .M_AXI_HP0_awsize(M_AXI_HP0.AWSIZE),
    .M_AXI_HP0_awburst(M_AXI_HP0.AWBURST),
    .M_AXI_HP0_awlock(M_AXI_HP0.AWLOCK),
    .M_AXI_HP0_awcache(M_AXI_HP0.AWCACHE),
    .M_AXI_HP0_awprot(M_AXI_HP0.AWPROT),
    .M_AXI_HP0_awqos(M_AXI_HP0.AWQOS),
    .M_AXI_HP0_awvalid(M_AXI_HP0.AWVALID),
    .M_AXI_HP0_awready(M_AXI_HP0.AWREADY),
    .M_AXI_HP0_wdata(M_AXI_HP0.WDATA),
    .M_AXI_HP0_wstrb(M_AXI_HP0.WSTRB),
    .M_AXI_HP0_wlast(M_AXI_HP0.WLAST),
    .M_AXI_HP0_wvalid(M_AXI_HP0.WVALID),
    .M_AXI_HP0_wready(M_AXI_HP0.WREADY),
    .M_AXI_HP0_bresp(M_AXI_HP0.BRESP),
    .M_AXI_HP0_bvalid(M_AXI_HP0.BVALID),
    .M_AXI_HP0_bready(M_AXI_HP0.BREADY),
    .M_AXI_HP0_araddr(M_AXI_HP0.ARADDR),
    .M_AXI_HP0_arlen(M_AXI_HP0.ARLEN),
    .M_AXI_HP0_arsize(M_AXI_HP0.ARSIZE),
    .M_AXI_HP0_arburst(M_AXI_HP0.ARBURST),
    .M_AXI_HP0_arlock(M_AXI_HP0.ARLOCK),
    .M_AXI_HP0_arcache(M_AXI_HP0.ARCACHE),
    .M_AXI_HP0_arprot(M_AXI_HP0.ARPROT),
    .M_AXI_HP0_arqos(M_AXI_HP0.ARQOS),
    .M_AXI_HP0_arvalid(M_AXI_HP0.ARVALID),
    .M_AXI_HP0_arready(M_AXI_HP0.ARREADY),
    .M_AXI_HP0_rdata(M_AXI_HP0.RDATA),
    .M_AXI_HP0_rresp(M_AXI_HP0.RRESP),
    .M_AXI_HP0_rlast(M_AXI_HP0.RLAST),
    .M_AXI_HP0_rvalid(M_AXI_HP0.RVALID),
    .M_AXI_HP0_rready(M_AXI_HP0.RREADY),
    .FCLK_CLK0(FCLK_CLK0),
    .FCLK_RESET0_N(FCLK_RESET0_N),
    .GPIO_0_tri_o(GPIO_0_tri_o),
    .GPIO_1_tri_i(GPIO_1_tri_i),
    .GPIO_2_tri_o(GPIO_2_tri_o),
    .GPIO_3_tri_o(GPIO_3_tri_o),
    .M_AXI_HP0_arid(M_AXI_HP0.ARID),
    .M_AXI_HP0_awid(M_AXI_HP0.AWID),
    .M_AXI_HP0_bid(M_AXI_HP0.BID),
    .M_AXI_HP0_rid(M_AXI_HP0.RID),
    .M_AXI_HP0_wid(M_AXI_HP0.WID)
  );

endmodule

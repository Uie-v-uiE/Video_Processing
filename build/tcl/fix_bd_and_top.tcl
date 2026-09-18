# Fix BD: export FCLK/RESET, assign HP0 address, then rebuild
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado_system]
set proj_name zynq_video_sys
set outdir [file join $root build]
file mkdir $outdir

open_project [file join $proj_dir ${proj_name}.xpr]
open_bd_design [get_files design_1.bd]

# Export FCLK and RESET if missing
if {[llength [get_bd_ports -quiet *FCLK_CLK0*]] == 0} {
  make_bd_pins_external [get_bd_pins processing_system7_0/FCLK_CLK0]
}
foreach p [get_bd_ports] {
  if {[string match *FCLK_CLK0* $p] && $p ne "FCLK_CLK0"} {
    set_property name FCLK_CLK0 $p
  }
}
if {[llength [get_bd_ports -quiet *FCLK_RESET0*]] == 0} {
  catch {make_bd_pins_external [get_bd_pins processing_system7_0/FCLK_RESET0_N]}
}
foreach p [get_bd_ports] {
  if {[string match *FCLK_RESET0* $p] && $p ne "FCLK_RESET0_N"} {
    set_property name FCLK_RESET0_N $p
  }
}

# Associate M_AXI_HP0 with FCLK_CLK0
set_property CONFIG.ASSOCIATED_BUSIF {M_AXI_HP0} [get_bd_ports FCLK_CLK0]

# Address editor: assign HP0 master to DDR
# The external M_AXI_HP0 is the interconnect slave - need to assign address segments
# After automation, HP0_DDR_LOWOCM should be auto-assigned. Force:
assign_bd_address
# exclude OCM if needed, keep DDR
# enable HP0_DDR_LOWOCM / HP0_DDR_HIGHOCM for the master path
# For external master, the address is provided by PL so just ensure slave segments exist

# Reset synchronizer note: FCLK_RESET0_N is already synchronous from PS
# Silence async reset warning is OK for Zynq

validate_bd_design
save_bd_design
make_wrapper -files [get_files design_1.bd] -top

puts "PORTS:"
foreach p [get_bd_ports] { puts "  $p [get_property CONFIG.ASSOCIATED_BUSIF $p]" }

# --- rewrite system_top to match wrapper ---
set wrap [file join $proj_dir ${proj_name}.gen sources_1 bd design_1 hdl design_1_wrapper.v]
# read arlen width from wrapper
set fp [open $wrap r]; set wt [read $fp]; close $fp
puts "WRAPPER exists, len=[string length $wt]"

# Write matching system_top
set sys [file join $root src rtl top system_top.v]
set fp [open $sys w]
puts $fp {`timescale 1ns/1ps}
puts $fp {module system_top (}
puts $fp {    inout  wire        DDR_cas_n,}
puts $fp {    inout  wire        DDR_cke,}
puts $fp {    inout  wire        DDR_ck_n,}
puts $fp {    inout  wire        DDR_ck_p,}
puts $fp {    inout  wire        DDR_cs_n,}
puts $fp {    inout  wire        DDR_odt,}
puts $fp {    inout  wire        DDR_ras_n,}
puts $fp {    inout  wire        DDR_reset_n,}
puts $fp {    inout  wire        DDR_we_n,}
puts $fp {    inout  wire [2:0]  DDR_ba,}
puts $fp {    inout  wire [14:0] DDR_addr,}
puts $fp {    inout  wire [31:0] DDR_dq,}
puts $fp {    inout  wire [3:0]  DDR_dm,}
puts $fp {    inout  wire [3:0]  DDR_dqs_n,}
puts $fp {    inout  wire [3:0]  DDR_dqs_p,}
puts $fp {    inout  wire        FIXED_IO_ddr_vrn,}
puts $fp {    inout  wire        FIXED_IO_ddr_vrp,}
puts $fp {    inout  wire [53:0] FIXED_IO_mio,}
puts $fp {    inout  wire        FIXED_IO_ps_clk,}
puts $fp {    inout  wire        FIXED_IO_ps_porb,}
puts $fp {    inout  wire        FIXED_IO_ps_srstb,}
puts $fp {    input  wire        sys_clk,}
puts $fp {    input  wire        key1_n,}
puts $fp {    input  wire        key2_n,}
puts $fp {    output wire [1:0]  led,}
puts $fp {    output wire        tmds_clk_p,}
puts $fp {    output wire        tmds_clk_n,}
puts $fp {    output wire [2:0]  tmds_data_p,}
puts $fp {    output wire [2:0]  tmds_data_n}
puts $fp {); }
puts $fp {    wire fclk0, fclk0_rst_n;}
puts $fp {    wire [31:0] gpio_o, gpio_i, status;}
puts $fp {    wire [31:0] m_araddr;}
puts $fp {    wire [5:0]  m_arid;}
puts $fp {    wire [3:0]  m_arlen_axi3;}
puts $fp {    wire [2:0]  m_arsize;}
puts $fp {    wire [1:0]  m_arburst;}
puts $fp {    wire        m_arvalid, m_arready;}
puts $fp {    wire [63:0] m_rdata;}
puts $fp {    wire [5:0]  m_rid;}
puts $fp {    wire [1:0]  m_rresp;}
puts $fp {    wire        m_rlast, m_rvalid, m_rready;}
puts $fp {    wire [7:0]  m_arlen8;}
puts $fp {}
puts $fp {    design_1_wrapper u_bd (}
puts $fp {        .DDR_cas_n(DDR_cas_n), .DDR_cke(DDR_cke), .DDR_ck_n(DDR_ck_n), .DDR_ck_p(DDR_ck_p),}
puts $fp {        .DDR_cs_n(DDR_cs_n), .DDR_odt(DDR_odt), .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n),}
puts $fp {        .DDR_we_n(DDR_we_n), .DDR_ba(DDR_ba), .DDR_addr(DDR_addr), .DDR_dq(DDR_dq),}
puts $fp {        .DDR_dm(DDR_dm), .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p),}
puts $fp {        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),}
puts $fp {        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),}
puts $fp {        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),}
puts $fp {        .GPIO_0_tri_i(gpio_i), .GPIO_0_tri_o(gpio_o),}
puts $fp {        .M_AXI_HP0_araddr(m_araddr), .M_AXI_HP0_arburst(m_arburst),}
puts $fp {        .M_AXI_HP0_arcache(4'b0011), .M_AXI_HP0_arid(m_arid), .M_AXI_HP0_arlen(m_arlen_axi3),}
puts $fp {        .M_AXI_HP0_arlock(2'b00), .M_AXI_HP0_arprot(3'b000), .M_AXI_HP0_arqos(4'b0000),}
puts $fp {        .M_AXI_HP0_arready(m_arready), .M_AXI_HP0_arsize(m_arsize), .M_AXI_HP0_arvalid(m_arvalid),}
puts $fp {        .M_AXI_HP0_awaddr(32'd0), .M_AXI_HP0_awburst(2'b01), .M_AXI_HP0_awcache(4'b0011),}
puts $fp {        .M_AXI_HP0_awid(6'd0), .M_AXI_HP0_awlen(4'd0), .M_AXI_HP0_awlock(2'b00),}
puts $fp {        .M_AXI_HP0_awprot(3'b000), .M_AXI_HP0_awqos(4'b0000), .M_AXI_HP0_awready(),}
puts $fp {        .M_AXI_HP0_awsize(3'b011), .M_AXI_HP0_awvalid(1'b0),}
puts $fp {        .M_AXI_HP0_bid(), .M_AXI_HP0_bready(1'b0), .M_AXI_HP0_bresp(), .M_AXI_HP0_bvalid(),}
puts $fp {        .M_AXI_HP0_rdata(m_rdata), .M_AXI_HP0_rid(m_rid), .M_AXI_HP0_rlast(m_rlast),}
puts $fp {        .M_AXI_HP0_rready(m_rready), .M_AXI_HP0_rresp(m_rresp), .M_AXI_HP0_rvalid(m_rvalid),}
puts $fp {        .M_AXI_HP0_wdata(64'd0), .M_AXI_HP0_wid(6'd0), .M_AXI_HP0_wlast(1'b0),}
puts $fp {        .M_AXI_HP0_wready(), .M_AXI_HP0_wstrb(8'd0), .M_AXI_HP0_wvalid(1'b0)}
puts $fp {    );}
puts $fp {}
puts $fp {    // If FCLK exported on wrapper, connect here. Otherwise use sys_clk+MMCM only.}
puts $fp {    // Check wrapper for FCLK_CLK0 / FCLK_RESET0_N}
puts $fp {    generate}
puts $fp {      if (1) begin : g_fclk}
puts $fp {        // fall back: use MMCM from sys_clk for axi domain if FCLK not in wrapper}
puts $fp {      end}
puts $fp {    endgenerate}
puts $fp {}
puts $fp {    // Prefer FCLK if present in wrapper 鈥?bind via defparam-less instance}
puts $fp {    // Read note: wrapper currently has no FCLK ports; use 100MHz from clk_gen extra}
puts $fp {    // Use sys_clk through a simple BUFG as axi clock for demo (50MHz) OR}
puts $fp {    // generate 100MHz: 50*2}
puts $fp {    wire clk_axi, rst_axi_n;}
puts $fp {    wire mmcm_locked_axi;}
puts $fp {    wire clk_axi_fb, clk_axi_fb_buf, clk_axi_raw;}
puts $fp {    MMCME2_BASE #(.CLKIN1_PERIOD(20.000), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(8.000),}
puts $fp {      .CLKOUT0_DIVIDE_F(4.000), .STARTUP_WAIT("FALSE")) u_mmcm_axi (}
puts $fp {        .CLKIN1(sys_clk), .CLKFBIN(clk_axi_fb_buf), .CLKFBOUT(clk_axi_fb),}
puts $fp {        .CLKFBOUTB(), .CLKOUT0(clk_axi_raw), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),}
puts $fp {        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),}
puts $fp {        .PWRDWN(1'b0), .RST(1'b0), .LOCKED(mmcm_locked_axi));}
puts $fp {    BUFG u_bg_fb_axi (.I(clk_axi_fb), .O(clk_axi_fb_buf));}
puts $fp {    BUFG u_bg_axi (.I(clk_axi_raw), .O(clk_axi));}
puts $fp {    assign rst_axi_n = mmcm_locked_axi;}
puts $fp {    // NOTE: true PS FCLK is better 鈥?we will fix BD export next if needed.}
puts $fp {    // For HP0 ACLK must be FCLK0 from PS. So this MMCM clock is NOT valid for HP0.}
puts $fp {}
puts $fp {    assign gpio_i = status;}
puts $fp {    assign m_arlen_axi3 = m_arlen8[3:0]; // AXI3: only low 4 bits, max 16 beats}
puts $fp {}
puts $fp {    pl_video_top #(.IMG_W(640), .IMG_H(360), .BASE_ADDR(32'"'"'h1000_0000)) u_pl (}
puts $fp {        .sys_clk(sys_clk), .sys_rst_n(mmcm_locked_axi),}
puts $fp {        .axi_clk(clk_axi), .axi_rst_n(rst_axi_n),}
puts $fp {        .effect_en(gpio_o[4:0]), .threshold(gpio_o[15:8]), .src_sel(gpio_o[16]),}
puts $fp {        .key1_n(key1_n), .key2_n(key2_n), .led(led),}
puts $fp {        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),}
puts $fp {        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),}
puts $fp {        .m_axi_araddr(m_araddr), .m_axi_arid(m_arid), .m_axi_arlen(m_arlen8),}
puts $fp {        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),}
puts $fp {        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),}
puts $fp {        .m_axi_rdata(m_rdata), .m_axi_rid(m_rid), .m_axi_rresp(m_rresp),}
puts $fp {        .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),}
puts $fp {        .status(status));}
puts $fp {endmodule}
close $fp
puts "WROTE system_top (partial)"
puts "NOTE: FCLK export and AXI3 arlen still need RTL fix 鈥?see next script"


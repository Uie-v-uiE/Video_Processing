# System with AXI GPIO on GP0 for PL effect control (EMIO bank2 not writable on this board)
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado_system]
set proj_name zynq_video_sys
set part xc7z020clg484-2
set outdir [file join $root output]
file mkdir $outdir

create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]

set rtl_files {}
foreach d {util clocks video process process/rotate axi hdmi} {
  foreach f [glob -nocomplain [file join $root rtl $d *.v]] { lappend rtl_files $f }
}
lappend rtl_files [file join $root rtl top pl_video_top.v]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $root constraints rk_zynq7020.xdc]

create_bd_design design_1
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set ps [get_bd_cells processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable" apply_board_preset "0"} $ps

set_property -dict [list \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
  CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_RST0_PORT {1} \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
  CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
  CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
  CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} CONFIG.PCW_UART0_UART0_IO {MIO 10 .. 11} \
  CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
  CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
  CONFIG.PCW_SD0_GRP_CD_ENABLE {1} CONFIG.PCW_SD0_GRP_CD_IO {MIO 9} \
  CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {0} \
  CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
  CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
  CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
  CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
  CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
] $ps

# --- AXI GPIO ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {32} \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells axi_gpio_0]

# --- GP0 IC ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_gp0_ic
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_gp0_ic]

# --- HP0 IC ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_mem_intercon]

# clocks/resets
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
  [get_bd_pins axi_gp0_ic/ACLK] \
  [get_bd_pins axi_gp0_ic/S00_ACLK] \
  [get_bd_pins axi_gp0_ic/M00_ACLK] \
  [get_bd_pins axi_gpio_0/s_axi_aclk] \
  [get_bd_pins axi_mem_intercon/ACLK] \
  [get_bd_pins axi_mem_intercon/S00_ACLK] \
  [get_bd_pins axi_mem_intercon/M00_ACLK] \
  [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
  [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
  [get_bd_pins axi_gp0_ic/ARESETN] \
  [get_bd_pins axi_gp0_ic/S00_ARESETN] \
  [get_bd_pins axi_gp0_ic/M00_ARESETN] \
  [get_bd_pins axi_gpio_0/s_axi_aresetn] \
  [get_bd_pins axi_mem_intercon/ARESETN] \
  [get_bd_pins axi_mem_intercon/S00_ARESETN] \
  [get_bd_pins axi_mem_intercon/M00_ARESETN]

# data paths
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
  [get_bd_intf_pins axi_gp0_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_ic/M00_AXI] \
  [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_mem_intercon/M00_AXI] \
  [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

make_bd_intf_pins_external [get_bd_intf_pins axi_mem_intercon/S00_AXI]
foreach p [get_bd_intf_ports] {
  if {[string match *S00* $p]} { catch {set_property name M_AXI_HP0 $p} }
}

create_bd_port -dir O -type clk -freq_hz 100000000 FCLK_CLK0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_ports FCLK_CLK0]
create_bd_port -dir O -type rst FCLK_RESET0_N
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports FCLK_RESET0_N]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_ports FCLK_RESET0_N]

make_bd_pins_external [get_bd_pins axi_gpio_0/gpio_io_o]
foreach p [get_bd_ports] {
  if {[string match *gpio_io_o* $p] || [string match *GPIO* $p]} {
    catch {set_property name GPIO_0_tri_o $p}
  }
}

catch {set_property CONFIG.ASSOCIATED_BUSIF {M_AXI_HP0} [get_bd_ports FCLK_CLK0]}
assign_bd_address

puts "CLOCK CHECK:"
foreach p [get_bd_pins -hier *ACLK*] { puts "  $p" }
validate_bd_design
save_bd_design
make_wrapper -files [get_files design_1.bd] -top
set wrap [file join $proj_dir ${proj_name}.gen sources_1 bd design_1 hdl design_1_wrapper.v]
if {![file exists $wrap]} {
  set wrap [lindex [glob -nocomplain [file join $proj_dir ${proj_name}.srcs sources_1 bd design_1 hdl design_1_wrapper.v]] 0]
}
add_files -norecurse $wrap
puts "WRAPPER: $wrap"

# system_top with AXI GPIO (no EMIO)
set sys [file join $root rtl top system_top.v]
set fp [open $sys w]
puts $fp "`timescale 1ns/1ps"
puts $fp {
// system_top — AXI GPIO (GP0) controls effects; HP0 reads DDR frames
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
}
close $fp
add_files -norecurse $sys
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "SYNTH FAILED [get_property STATUS [get_runs synth_1]]"
  exit 1
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bit [file join $proj_dir ${proj_name}.runs impl_1 system_top.bit]
if {![file exists $bit]} {
  set bit [lindex [glob -nocomplain [file join $proj_dir ${proj_name}.runs impl_1 *.bit]] 0]
}
file copy -force $bit [file join $outdir system.bit]
open_run impl_1
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]
puts "BIT: [file join $outdir system.bit]"
puts "XSA: [file join $outdir system.xsa]"
puts "SYSTEM AXI-GPIO BUILD DONE"
puts "ADDR: AXI GPIO typically 0x41200000 — check xparameters.h after platform build"

# System with AXI GPIO on GP0 + PL ETH video sink
set root [file normalize [file join [file dirname [info script]] .. ..]]
set proj_dir [file join $root vivado_system]
set proj_name zynq_video_sys
set part xc7z020clg484-2
set outdir [file join $root build]
file mkdir $outdir

create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]

set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi eth} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] { lappend rtl_files $f }
}
lappend rtl_files [file join $root src rtl top pl_video_top.v]
lappend rtl_files [file join $root src rtl top system_top.v]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]

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

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {32} \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells axi_gpio_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_gp0_ic
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_gp0_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_mem_intercon]

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
validate_bd_design
save_bd_design
make_wrapper -files [get_files design_1.bd] -top
set wrap [file join $proj_dir ${proj_name}.gen sources_1 bd design_1 hdl design_1_wrapper.v]
if {![file exists $wrap]} {
  set wrap [lindex [glob -nocomplain [file join $proj_dir ${proj_name}.srcs sources_1 bd design_1 hdl design_1_wrapper.v]] 0]
}
add_files -norecurse $wrap
puts "WRAPPER: $wrap"
puts "TOP: system_top.v (maintained, includes PL ETH)"

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
report_timing_summary -file [file join $outdir timing_summary.rpt]
report_utilization -file [file join $outdir utilization.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]
puts "BIT: [file join $outdir system.bit]"
puts "XSA: [file join $outdir system.xsa]"
puts "SYSTEM BUILD DONE"


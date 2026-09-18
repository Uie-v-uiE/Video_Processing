# Create Vivado project for Zynq7020 video pipeline (Vivado 2025.2.x)
# Usage:
#   vivado -mode batch -source tcl/create_project.tcl -tclargs pl
#   vivado -mode batch -source tcl/create_project.tcl -tclargs system

set mode "pl"
if {[llength $argv] > 0} { set mode [lindex $argv 0] }

set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado]
set proj_name zynq_video_pipeline
set part xc7z020clg484-2

create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

# ---- RTL ----
set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi top} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] {
    lappend rtl_files $f
  }
}
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]

if {$mode eq "pl"} {
  set_property top pl_demo_top [current_fileset]
  update_compile_order -fileset sources_1
  puts "INFO: PL-only project. Top=pl_demo_top"
  puts "PROJECT: [file join $proj_dir ${proj_name}.xpr]"
} else {
# ---- System: PS7 + interconnect + external HP0 + EMIO GPIO ----
create_bd_design design_1

# Zynq PS (preset not used 鈥?configure explicitly for this board)
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set ps [get_bd_cells processing_system7_0]

# Apply board automation for DDR/FIXED_IO only
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable" apply_board_preset "0"} \
  $ps

# Custom PS config (RK-ZYNQ7020-F)
set_property -dict [list \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
  CONFIG.PCW_EN_CLK0_PORT {1} \
  CONFIG.PCW_EN_RST0_PORT {1} \
  CONFIG.PCW_USE_M_AXI_GP0 {0} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
  CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
  CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
  CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
  CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART0_UART0_IO {MIO 10 .. 11} \
  CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
  CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
  CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
  CONFIG.PCW_SD0_GRP_CD_IO {MIO 9} \
  CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
  CONFIG.PCW_GPIO_EMIO_GPIO_IO {32} \
  CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
  CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
  CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
  CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
  CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
  CONFIG.PCW_UIPARAM_DDR_USE_STATIC_DELAY {0} \
] $ps

# AXI Interconnect: PL master -> HP0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1} CONFIG.STRATEGY {1}] \
  [get_bd_cells axi_mem_intercon]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
  [get_bd_pins axi_mem_intercon/ACLK] \
  [get_bd_pins axi_mem_intercon/S00_ACLK] \
  [get_bd_pins axi_mem_intercon/M00_ACLK] \
  [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
  [get_bd_pins axi_mem_intercon/ARESETN] \
  [get_bd_pins axi_mem_intercon/S00_ARESETN] \
  [get_bd_pins axi_mem_intercon/M00_ARESETN]

connect_bd_intf_net [get_bd_intf_pins axi_mem_intercon/M00_AXI] \
  [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# Externalize interconnect slave as M_AXI_HP0 (PL is master)
make_bd_intf_pins_external [get_bd_intf_pins axi_mem_intercon/S00_AXI]
# Name may be S00_AXI_0 鈥?normalize
set intf_ports [get_bd_intf_ports]
foreach p $intf_ports {
  if {[string match *S00* $p] || [string match *S00_AXI* $p]} {
    set_property name M_AXI_HP0 $p
  }
}

# Externalize FCLK and reset
make_bd_pins_external [get_bd_pins processing_system7_0/FCLK_CLK0]
set_property name FCLK_CLK0 [get_bd_ports *FCLK_CLK0*]
catch {
  make_bd_pins_external [get_bd_pins processing_system7_0/FCLK_RESET0_N]
  set_property name FCLK_RESET0_N [get_bd_ports *FCLK_RESET0_N*]
}

# GPIO EMIO as tri_o / tri_i
# processing_system7 GPIO_O / GPIO_I
catch {make_bd_pins_external [get_bd_pins processing_system7_0/GPIO_O]}
catch {set_property name GPIO_0_tri_o [get_bd_ports *GPIO_O*]}
catch {make_bd_pins_external [get_bd_pins processing_system7_0/GPIO_I]}
catch {set_property name GPIO_0_tri_i [get_bd_ports *GPIO_I*]}

# Loopback unused GPIO_I if not exported cleanly
if {[llength [get_bd_ports -quiet *GPIO*]] == 0} {
  # fallback: connect GPIO_I to GPIO_O internally and export only O
  catch {delete_bd_objs [get_bd_pins processing_system7_0/GPIO_I]}
}

regenerate_bd_layout
validate_bd_design
save_bd_design

make_wrapper -files [get_files design_1.bd] -top
set wrap [glob -nocomplain [file join $proj_dir ${proj_name}.srcs sources_1 bd design_1 hdl design_1_wrapper.v]]
if {[llength $wrap] == 0} {
  set wrap [glob -nocomplain [file join $proj_dir ${proj_name}.gen sources_1 bd design_1 hdl design_1_wrapper.v]]
}
add_files -norecurse $wrap

set_property top system_top [current_fileset]
update_compile_order -fileset sources_1
puts "INFO: System project. Top=system_top"
puts "PROJECT: [file join $proj_dir ${proj_name}.xpr]"
puts "NOTE: If system_top port names fail, open BD and rename externals to match rtl/top/system_top.v"
}



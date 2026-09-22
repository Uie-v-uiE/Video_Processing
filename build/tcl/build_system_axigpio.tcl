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
foreach d {util clocks video process process/rotate process/zoom process/bilin axi hdmi eth} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] { lappend rtl_files $f }
}
lappend rtl_files [file join $root src rtl top pl_video_top.v]
lappend rtl_files [file join $root src rtl top system_top.v]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]
# 异步时钟组单独一个文件，并且**只在实现阶段生效**：clk_fpga_0 由 PS7 IP 的 XDC
# 创建，综合阶段还不存在，而 XDC 里不能用 if/catch（[Designutils 20-1307]）。
# 不拆的话每个 run 都吃 2 条 CRITICAL WARNING [Vivado 12-4739]，且整条
# set_clock_groups 不生效（综合阶段本来就不生效 ⇒ 拆分不改时序数字，只是去掉噪声）。
set cgxdc [add_files -fileset constrs_1 -norecurse [file join $root src constraints clock_groups_impl.xdc]]
set_property used_in_synthesis false $cgxdc
set_property used_in_implementation true $cgxdc

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

# v7.6 (P0-A)：第二条 GPIO，**只读 32bit**，给 PS 读 PL 侧的链路健康快照。
# 不新增 AXI 从地址之外的任何东西：lane 号走已有的 GPIO_0（gpio_o[31:27]），
# 数据走这条 —— BD 里只多一个 ip、多一条 M01_AXI。
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {32} \
  CONFIG.C_ALL_INPUTS {1} \
  CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells axi_gpio_1]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_gp0_ic
set_property -dict [list CONFIG.NUM_MI {2} CONFIG.NUM_SI {1}] [get_bd_cells axi_gp0_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_mem_intercon]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
  [get_bd_pins axi_gp0_ic/ACLK] \
  [get_bd_pins axi_gp0_ic/S00_ACLK] \
  [get_bd_pins axi_gp0_ic/M00_ACLK] \
  [get_bd_pins axi_gpio_0/s_axi_aclk] \
  [get_bd_pins axi_gpio_1/s_axi_aclk] \
  [get_bd_pins axi_gp0_ic/M01_ACLK] \
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
  [get_bd_pins axi_gpio_1/s_axi_aresetn] \
  [get_bd_pins axi_gp0_ic/M01_ARESETN] \
  [get_bd_pins axi_mem_intercon/ARESETN] \
  [get_bd_pins axi_mem_intercon/S00_ARESETN] \
  [get_bd_pins axi_mem_intercon/M00_ARESETN]

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
  [get_bd_intf_pins axi_gp0_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_ic/M00_AXI] \
  [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_ic/M01_AXI] \
  [get_bd_intf_pins axi_gpio_1/S_AXI]
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
make_bd_pins_external [get_bd_pins axi_gpio_1/gpio_io_i]
# 按实际生成的名字改，避免依赖 make_bd_pins_external 的命名细节。
# 注意：Tcl 没有独立的 elseif 命令（写成分行形式会 invalid command name "elseif"），
# 而且 gpio_1 的外部端口实际叫 gpio_io_i_0_1，不含 axi_gpio_1 前缀。
foreach p [get_bd_ports] {
  if {[string match "*gpio_io_o*" $p]} { catch {set_property name GPIO_0_tri_o $p} }
  if {[string match "*gpio_io_i*" $p]} { catch {set_property name GPIO_1_tri_i $p} }
}
puts "BD PORTS: [get_bd_ports]"

catch {set_property CONFIG.ASSOCIATED_BUSIF {M_AXI_HP0} [get_bd_ports FCLK_CLK0]}
assign_bd_address
# 地址要在 assign_bd_address 之后才有效：上位机脚本要用它做 mwr/mrd。
catch {puts "ADDR GPIO0 = [get_property OFFSET [get_bd_addr_segs axi_gpio_0/S_AXI/Reg]]"}
catch {puts "ADDR GPIO1 = [get_property OFFSET [get_bd_addr_segs axi_gpio_1/S_AXI/Reg]]"}
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

# ---- build#16：只换一个旋钮，测"实现策略"能不能收掉 250 MHz 域最后那 0.485 ns ----
# 证据：build#15 唯一剩下的违例是 u_rd/u_sched 的 5 选 1 地址 mux → RAMB36 地址脚，
#       数据延迟 3.844 ns 里**布线 3.255 ns（84.7%）**、逻辑只有 2 级 LUT 0.589 ns
#       ⇒ 是布局距离/高扇出（一根地址线要打到 80 个 tile），不是逻辑深度。
# 已排除的选项：R07 实测 `Performance_Explore` 与默认策略**逐位相同** ⇒ 换它没有意义。
# RTL 与约束都不动（尤其不用 set_multicycle_path：那会连带豁免 rgb2dvi 里真实的跨域检查）。
# 失败就照 §9.5 的口径回落到冻结的 build#13 bit，不拿红色版本上板。
if {[catch {set_property STRATEGY {Performance_ExtraTimingOpt} [get_runs impl_1]} e1]} {
  puts "STRATEGY ExtraTimingOpt FAILED: $e1"
  catch {set_property STRATEGY {Performance_Explore} [get_runs impl_1]}
}
puts "IMPL STRATEGY = [get_property STRATEGY [get_runs impl_1]]"

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
# V7：一并产出 CDC / 方法学报告，让仓库脚本的输出与库里提交的文件一致
catch {report_cdc -file [file join $outdir cdc.rpt]}
catch {report_methodology -file [file join $outdir methodology.rpt]}
# 门禁还要求功耗与布线状态，缺了就只能靠人工补跑 —— 一并产出
catch {report_power -file [file join $outdir power.rpt]}
catch {report_route_status -file [file join $outdir route_status.rpt]}
catch {report_clock_utilization -file [file join $outdir clock_util.rpt]}
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]
catch {close_project}
puts "BIT: [file join $outdir system.bit]"
puts "XSA: [file join $outdir system.xsa]"
puts "SYSTEM BUILD DONE"


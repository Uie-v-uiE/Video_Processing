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

# V8-2：开 MIO GPIO，为了读板上那两个 PS 按键（原理图网络名 PS_MIO0_KEY1 / PS_MIO12_KEY2）。
# 老配置只有 EMIO GPIO=0、MIO GPIO 根本没开 ⇒ 那两个脚电气上存在但固件读不到（见 report/PLAN_V8_SPEC.md §6a）。
# MIO 0 与 12 都没被占用：QSPI=MIO 1..6、UART0=MIO 10..11、ENET0=MIO 16..27(+MDIO 52..53)、SD0=MIO 40..45(+CD MIO 9)。
# 每脚四行（PULLUP/IOTYPE/DIRECTION/SLEW）是 GPIO 认领这两行 MIO 所必需的，缺了 validate_bd_design 会报 IOTYPE 未设。
# 注意这个 dict 里**不能夹注释行**：整块是一个 `set_property -dict [list ... ]`，
# 行续 `\` 之间出现的裸文本会变成 list 的元素（我第一次就这么把脚本写坏了）。
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
  CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} \
  CONFIG.PCW_MIO_0_PULLUP {enabled} CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V} \
  CONFIG.PCW_MIO_0_DIRECTION {inout} CONFIG.PCW_MIO_0_SLEW {slow} \
  CONFIG.PCW_MIO_12_PULLUP {enabled} CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} \
  CONFIG.PCW_MIO_12_DIRECTION {inout} CONFIG.PCW_MIO_12_SLEW {slow} \
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

# V8-2：第三条 GPIO —— **双通道 ×32bit 纯输出**，装 V7 那条 32bit 控制字放不下的东西。
# 为什么要多这一条：gpio_0 里 [4:0] 效果、[15:8] 阈值、[16] 片源、[17] 缩放、[18] 发布、
# [19] 双线性、[26] gapclr、[31:27] lane 读回 都用掉了，只剩 9 位空；而 V8 的算法选择字就要
# 9 位，后面 Gamma 的索引+数据窗口与分割线的位置/range/速度还要 30 多位。
# 把这 64 位**一次开出来**（通道 2 现在故意不接），V8-3/V8-4 就不必再动 BD ——
# 动一次 BD = 地址、约束、全套门禁重来。老工具（set_src.tcl / health_read.mjs /
# arb_handover_test.mjs）读写的 gpio_0 位序一个都没动。
# 地址在下面钉死 0x41220000：固件里的 AXI_GPIO_CFG_BASE 必须等于它（BSP 不会重新生成
# xparameters.h，基址是硬编码的，错了不是编译失败而是"写了没反应"）。
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_2
set_property -dict [list \
  CONFIG.C_IS_DUAL {1} \
  CONFIG.C_GPIO_WIDTH {32} \
  CONFIG.C_GPIO2_WIDTH {32} \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_ALL_OUTPUTS_2 {1} \
  CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells axi_gpio_2]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_gp0_ic
set_property -dict [list CONFIG.NUM_MI {3} CONFIG.NUM_SI {1}] [get_bd_cells axi_gp0_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_mem_intercon]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
  [get_bd_pins axi_gp0_ic/ACLK] \
  [get_bd_pins axi_gp0_ic/S00_ACLK] \
  [get_bd_pins axi_gp0_ic/M00_ACLK] \
  [get_bd_pins axi_gpio_0/s_axi_aclk] \
  [get_bd_pins axi_gpio_1/s_axi_aclk] \
  [get_bd_pins axi_gpio_2/s_axi_aclk] \
  [get_bd_pins axi_gp0_ic/M01_ACLK] \
  [get_bd_pins axi_gp0_ic/M02_ACLK] \
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
  [get_bd_pins axi_gpio_2/s_axi_aresetn] \
  [get_bd_pins axi_gp0_ic/M01_ARESETN] \
  [get_bd_pins axi_gp0_ic/M02_ARESETN] \
  [get_bd_pins axi_mem_intercon/ARESETN] \
  [get_bd_pins axi_mem_intercon/S00_ARESETN] \
  [get_bd_pins axi_mem_intercon/M00_ARESETN]

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
  [get_bd_intf_pins axi_gp0_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_ic/M00_AXI] \
  [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_ic/M01_AXI] \
  [get_bd_intf_pins axi_gpio_1/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_ic/M02_AXI] \
  [get_bd_intf_pins axi_gpio_2/S_AXI]
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

# 外部端口改名：**不能依赖 make_bd_pins_external 的返回值**（r45 第二次试跑实测它在这里返回空，
# 于是 `get_bd_ports {}` 报 "No ports matched"，脚本按判据自己停了）。
# 也不能按子串匹配：双通道 GPIO 的两个端口都叫 gpio_io_o*，子串循环会把第二个也命名成
# GPIO_0_tri_o，冲突被 catch 吞掉之后端口留着自动名 —— 顶层例化时报的错看起来像"凭空少一个端口"。
# 所以：调用前后各取一次端口名集合，diff 出来的那一个就是刚建出来的，再改名。
proc bd_port_names {} {
  set r {}
  foreach p [get_bd_ports] { lappend r [get_property NAME $p] }
  return $r
}
foreach {pin newname} {
  axi_gpio_0/gpio_io_o   GPIO_0_tri_o
  axi_gpio_1/gpio_io_i   GPIO_1_tri_i
  axi_gpio_2/gpio_io_o   GPIO_2_tri_o
  axi_gpio_2/gpio2_io_o  GPIO_3_tri_o
} {
  set before [bd_port_names]
  make_bd_pins_external [get_bd_pins $pin]
  set fresh {}
  foreach n [bd_port_names] { if {[lsearch -exact $before $n] < 0} { lappend fresh $n } }
  if {[llength $fresh] != 1} { puts "PORT_LOOKUP_FAILED $pin fresh={$fresh}"; exit 1 }
  set_property name $newname [get_bd_ports $fresh]
  puts "PORT $pin -> $newname"
}
puts "BD PORTS: [get_bd_ports]"

catch {set_property CONFIG.ASSOCIATED_BUSIF {M_AXI_HP0} [get_bd_ports FCLK_CLK0]}
assign_bd_address
# 三个基址钉死（0x41210000 是固件与 health_read.mjs 一直在用的 GPIO_1，0x41220000 是新的控制字）。
# 为什么不能"让它自动排"：BSP 不会重新生成 xparameters.h，固件里基址是硬编码的；
# 地址一挪，现象不是编译失败而是"写了没反应"——最难查的那一类。
foreach {seg want} {
  axi_gpio_0/S_AXI/Reg 0x41200000
  axi_gpio_1/S_AXI/Reg 0x41210000
  axi_gpio_2/S_AXI/Reg 0x41220000
} {
  assign_bd_address -offset $want -range 64K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs $seg] -force
}
set aspace [get_bd_addr_spaces processing_system7_0/Data]
# 先整张地址图打出来：上一次这里查不到偏移时只能看到 got=（空串），看不出"是查询写错了还是地址真没钉上"。
foreach s [get_bd_addr_segs -quiet -of_objects $aspace] {
  puts "ADDRMAP [get_property NAME $s] = [get_property OFFSET $s]"
}
set bad_addr 0
foreach {cell want} { axi_gpio_0 0x41200000  axi_gpio_1 0x41210000  axi_gpio_2 0x41220000 } {
  # 段对象要从**地址空间里**取（`get_bd_addr_segs axi_gpio_0/S_AXI/Reg` 取到的是接口定义，
  # 它的 OFFSET 是空的 —— 上一次这里判红就是这个原因，不是地址没钉上）
  set s [get_bd_addr_segs -quiet -of_objects $aspace -filter "NAME =~ *SEG_${cell}_Reg*"]
  if {$s eq ""} { puts "ADDR_LOG $cell want=$want got=NOT_FOUND"; incr bad_addr; continue }
  set got [get_property OFFSET $s]
  # 比较必须在**数值**上做：把 OFFSET 塞进 expr 或直接当字符串比都会误判 ——
  # 这个属性经数字一走就显示成十进制（0x41200000 → 1092616192），字符串比对必然红。
  set gv 0
  set wv 0
  scan [string tolower $got] "%x" gv
  scan [string tolower $want] "%x" wv
  puts "ADDR_LOG $cell want=$want got=$got num_ok=[expr {$gv == $wv}]"
  if {$gv != $wv} { incr bad_addr }
}
validate_bd_design
if {$bad_addr} { puts "ADDRESS PINNING FAILED"; exit 1 }
save_bd_design
# BD 配置写错（IP 的参数名、引脚名、MIO 认领）本来 3 分钟就能验出来，不必等 20 分钟的综合+实现。
# 所以留一个只建 BD 就退出的口子：`vivado -mode batch -source 本脚本 -tclargs bd_only`。
if {[lindex $argv 0] eq "bd_only"} { puts "BD_ONLY_DONE"; exit 0 }
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

# ---- build#16 试过的实现策略旋钮：已撤掉，恢复默认 impl_1 ----
# 记录：`Performance_ExtraTimingOpt` 把 clk_pix→clk_pix5x 那组从 −0.485 抬到 **+0.788**（转好），
# 并把 intra-5x 从 −0.485 收到 −0.327（phys_opt 复制了高扇出的地址 mux 驱动，日志里
# 有 `Processed net u_pl/u_rd/u_sched/... Replicated`），但**仍然红** ⇒ V7.8 的顶层没有进主线，
# 主线回到 build#13 的结构。留这个旋钮在这里没有意义（默认结构不需要它），
# 想接着做 V7.8 的时序收口时，连同 tag `v7.8-bilinear-wip` 一起再打开。
# 历史结论 R07：`Performance_Explore` 与默认策略产出逐位相同的 bit ⇒ 那不是个可选项。

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


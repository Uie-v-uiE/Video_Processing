## RK-ZYNQ7020-F constraints — 时序/跨钟优化版
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports key1_n]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports key2_n]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD TMDS_33} [get_ports tmds_clk_p]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD TMDS_33} [get_ports tmds_clk_n]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[0]}]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[0]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[1]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[1]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[2]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[2]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports eth_rxc]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports eth_rx_ctl]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[0]}]
set_property -dict {PACKAGE_PIN W21 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[1]}]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[2]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[3]}]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS33} [get_ports eth_tx_clk]
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports eth_tx_ctl]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports {eth_txd[0]}]
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports {eth_txd[1]}]
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS33} [get_ports {eth_txd[2]}]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS33} [get_ports {eth_txd[3]}]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports eth_mdc]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS33} [get_ports eth_mdio]
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS33} [get_ports eth_rst_n]

create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]
# eth_rst_n 是**输出**（system_top.v:41 `output wire eth_rst_n`，由上电复位计数器驱动），
# 所以它只能作为 -to 的终点；原先那行 `set_false_path -from [get_ports eth_rst_n]`
# 每次综合都报 `CRITICAL WARNING [Constraints 18-513] ... -from ... contains no valid
# startpoints`，是一条**空约束**（不约束任何东西，只制造噪声），已删除。
set_false_path -to   [get_ports eth_rst_n]
set_false_path -to   [get_ports eth_tx_clk]
set_false_path -to   [get_ports eth_tx_ctl]
set_false_path -to   [get_ports {eth_txd[*]}]
set_false_path -from [get_ports key1_n]
set_false_path -from [get_ports key2_n]

## ============================================================
## 异步时钟组：本文件**不再**声明，见 src/constraints/clock_groups_impl.xdc
##
## 原因（2025.2.1 实测）：clk_fpga_0 是 PS7 IP 自己的 XDC 里 create_clock 的
## （FCLKCLK[0]），综合阶段它还不存在。`-quiet` 只能压住 get_clocks 的报错、
## 压不住命令本身 ⇒ 每个 run 都吃一条
##   CRITICAL WARNING [Vivado 12-4739] set_clock_groups:
##     No valid object(s) found for '-group [get_clocks -quiet clk_fpga_0]'
## 而且**整条命令不生效**（eth_rxc / sys_clk 那两组一起废掉）。
## XDC 里又不允许写控制流（`if` 会报 [Designutils 20-1307] Command 'if'
## is not supported in the xdc constraint file），所以唯一的正规解法是
## 「按时机分文件」：把这条约束放进只在 implementation 生效的 XDC。
## 综合阶段本来就拿不到这条约束（命令是失败的），所以拆分**不改变任何时序数字**。
## ============================================================

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

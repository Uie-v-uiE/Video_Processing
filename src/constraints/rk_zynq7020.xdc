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
set_false_path -from [get_ports eth_rst_n]
set_false_path -to   [get_ports eth_rst_n]
set_false_path -to   [get_ports eth_tx_clk]
set_false_path -to   [get_ports eth_tx_ctl]
set_false_path -to   [get_ports {eth_txd[*]}]
set_false_path -from [get_ports key1_n]
set_false_path -from [get_ports key2_n]

## ============================================================
## 异步时钟组（关键：用 -include_generated_clocks 抓住 MMCM 输出）
## sys_clk → MMCM → clkout0_1(50M pix)/clkout1_1(250M)/clkout2(200M)
## 跨域数据：2FF 同步器 + gray dc_fifo，不做 setup 分析
## ============================================================
set_clock_groups -asynchronous \
  -group [get_clocks eth_rxc] \
  -group [get_clocks -quiet clk_fpga_0] \
  -group [get_clocks -include_generated_clocks sys_clk]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

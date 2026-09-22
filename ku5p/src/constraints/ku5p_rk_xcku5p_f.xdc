# ku5p/src/constraints/ku5p_rk_xcku5p_f.xdc
# RK-XCKU5P-F V1.2 / xcku5p-ffvb676-2-i
#
# 引脚来源（两套独立证据一致，才敢写进来）：
#   ① 原理图 RK-XCKU5P-F+V1.2原理图.pdf p4（bank66 HP，VCCO_66 = VCC_ADJ1，默认 1.8 V）
#      与 p5（bank86 = +3.3 V 固定）；
#   ② 厂商例程 KU5P_DEMO/07_UDP_STACK/Constraint/PHY_Pin.xdc（同一块板、同一个工程用途）。
# 之前从"用户手册文字"里读出来的 AK6/AV23/AY10 一套与这两套都不符，已废弃 —— 记在
# ku5p/README.md 的"踩坑"里，免得下次又被手册的叙述带偏。

## 复位按键（KEY1，bank86 3.3 V，板上有 4.7k 上拉 + 100nF 硬件滤波，按下为低）
set_property PACKAGE_PIN K9 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

## RGMII：全部在 bank66，1.8 V
set_property PACKAGE_PIN K22 [get_ports eth_rxc]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxc]
set_property PACKAGE_PIN K23 [get_ports eth_rx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rx_ctl]
set_property PACKAGE_PIN L24 [get_ports {eth_rxd[0]}]
set_property PACKAGE_PIN L25 [get_ports {eth_rxd[1]}]
set_property PACKAGE_PIN K25 [get_ports {eth_rxd[2]}]
set_property PACKAGE_PIN K26 [get_ports {eth_rxd[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {eth_rxd[*]}]

set_property PACKAGE_PIN M25 [get_ports eth_txc]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txc]
set_property PACKAGE_PIN M26 [get_ports eth_tx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports eth_tx_ctl]
set_property PACKAGE_PIN L23 [get_ports {eth_txd[0]}]
set_property PACKAGE_PIN L22 [get_ports {eth_txd[1]}]
set_property PACKAGE_PIN L20 [get_ports {eth_txd[2]}]
set_property PACKAGE_PIN K20 [get_ports {eth_txd[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {eth_txd[*]}]

## LED1..4（bank86，3.3 V，高电平点亮）
set_property PACKAGE_PIN H9  [get_ports {led[0]}]
set_property PACKAGE_PIN J9  [get_ports {led[1]}]
set_property PACKAGE_PIN G11 [get_ports {led[2]}]
set_property PACKAGE_PIN H11 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## 时钟：整个入口只有 PHY 恢复出来的这一根 125 MHz（厂商例程同样只约束它）
# 没有 MMCM、没有板载系统时钟参与 —— 这正是"没有显示消费者 ⇒ 单时钟域"的结果。
create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]
set_clock_uncertainty 0.500 [get_clocks eth_rxc]

# 复位按键是异步的，por 拉伸之后才被使用
set_false_path -from [get_ports sys_rst_n]

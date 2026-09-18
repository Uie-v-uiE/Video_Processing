# RK-ZYNQ7020-F 关键管脚

器件：XC7Z020-CLG484-2

## PL 时钟 / 按键 / LED
| 信号 | 封装脚 | 说明 |
|------|--------|------|
| sys_clk | W17 | 50 MHz |
| pl_key1 | W18 | 旋转角度 + |
| pl_key2 | V14 | 旋转角度 - |
| pl_led1 | V15 | 心跳 / 帧有效 |
| pl_led2 | V13 | 效果使能指示 |

## PL ETH PHY2 RGMII（原理图页 5 BANK33）
| 信号 | 封装脚 |
|------|--------|
| eth_rxc | Y19 |
| eth_rx_ctl | V19 |
| eth_rxd[0] | W20 |
| eth_rxd[1] | W21 |
| eth_rxd[2] | U20 |
| eth_rxd[3] | V20 |
| eth_tx_clk | AB22 |
| eth_tx_ctl | AB21 |
| eth_txd[0] | T21 |
| eth_txd[1] | U21 |
| eth_txd[2] | AA22 |
| eth_txd[3] | AA21 |
| eth_mdc | AB20 |
| eth_mdio | AB19 |
| eth_rst_n | Y21 |

## HDMI OUT (TMDS)
| 信号 | 封装脚 |
|------|--------|
| hdmi_clk_p | W16 |
| hdmi_clk_n | Y16 |
| hdmi_data_p[0] | AA17 |
| hdmi_data_n[0] | AB17 |
| hdmi_data_p[1] | U17 |
| hdmi_data_n[1] | V17 |
| hdmi_data_p[2] | U15 |
| hdmi_data_n[2] | U16 |
| hdmi_hpd | Y18 |
| hdmi_scl | AA16 |
| hdmi_sda | AB16 |

## PS（MIO，由 PS7 IP 配置）
| 功能 | MIO |
|------|-----|
| UART0 TX/RX | 11 / 10 |
| ENET0 RGMII | 16-27, MDIO 52-53 |
| QSPI | 1-6 |
| SD0 | 40-45 |

## DDR
PS 侧 32-bit DDR3，由 PS7 预设处理，本工程不额外约束 PL 侧 DDR 管脚。

# RK-ZYNQ7020-F 关键管脚（第三版）

器件：XC7Z020-CLG484-2  
约束文件：`src/constraints/rk_zynq7020.xdc`

---

## PL 时钟 / 按键 / LED

| 信号 | 封装脚 | 说明 |
|------|--------|------|
| sys_clk | W17 | 50 MHz |
| key1_n | W18 | 旋转 +1° |
| key2_n | V14 | 旋转 −1° |
| led[0] | V15 | 心跳 |
| led[1] | V13 | eth_link / zoom_active / 效果 |

---

## PL ETH PHY2 RGMII（BANK33）

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

时序：`create_clock -period 8.000 -name eth_rxc`（125 MHz）。

---

## HDMI OUT (TMDS)

| 信号 | 封装脚 |
|------|--------|
| tmds_clk_p/n | W16 / Y16 |
| tmds_data_p/n[0] | AA17 / AB17 |
| tmds_data_p/n[1] | U17 / V17 |
| tmds_data_p/n[2] | U15 / U16 |

IOSTANDARD：TMDS_33。

---

## PS（MIO，由 PS7 配置）

| 功能 | MIO |
|------|-----|
| UART0 TX/RX | 11 / 10 |
| ENET0 RGMII | 16–27，MDIO 52–53（本工程数据面不用） |
| QSPI / SD0 | 按 BD 预设 |

控制：AXI GPIO @ `0x41200000`（GP0）。

---

## DDR

PS 侧 32-bit DDR3，由 PS7 预设；PL 不额外约束 DDR 管脚。  
HP0 用于可选的 PL↔DDR 访问。

---

## 复位 / 时钟相关

| 信号 | 说明 |
|------|------|
| eth_rst_n | sys_clk 计数约 168 ms 后释放 |
| IDELAYCTRL | clk_200m |
| FCLK_RESET0_N | PS 域复位 |

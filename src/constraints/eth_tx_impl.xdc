## eth_tx_impl.xdc — RGMII 发侧时序约束（只在 implementation 阶段生效）
##
## 状态：候选件（`VP_TX_CONSTRAIN=1` 才进实现）。目标是 TX_STYLE="ODDR0"：
## TXC 与 TXD 都由 clk_eth 过 ODDR，0° 同沿，直接对应 RTL8211F 规格书 Table 60 的
## `TskewT`（Data to Clock Output Skew Time at transmitter, without delay integrated）
## = -0.5 / 0 / +0.5 ns。这是发射端（FPGA）的义务，不是 PHY 的接收 setup/hold。
##
## 历史：
##   · r136 的 90° ODDR（clk90）静态 0.169/0.134 全过，但板上 ARP 完全不通 —— Table 60
##     的 TskewT ±0.5 ns 正好解释：2 ns 相移超出 4 倍，PHY 不认。
##   · r137b 的 FWD0（TXC 直接由 BUFG 送 OBUF，0°）板上 ping 20/20，但时钟路径与数据
##     ODDR 不匹配，output delay 写 ±1.0 时 r138 判 5 条 hold 失败（WHS -2.036）。
##   · ODDR0 把时钟也放进 ODDR，时钟/数据路径匹配，保持 0° 相位；这份 ±0.5 才是
##     Table 60 那一行，不是"为了绿放大窗口"。
##
## ⚠ 如果 ODDR0 的实现报负 slack，先看报告里的 DCD/SCD 与 ODDR 布局，不要改回 ±1.0
##    或 false_path；TskewT 是数据手册给的窗口，改它就成了另一把尺子。
## 时钟源是 clk_eth（0°）：ODDR0 的时钟和数据都过 ODDR、同用 clk_eth。
## r140 试过用 CLKOUT5 的 -45°（-1 ns）补偿"时钟比数据晚 ~1.345 ns"的输出路径 skew：
## 静态 hold 从 -0.845 改善到 -0.366，但板上 ping 1/6（比 r139 的 20/20 差）⇒ PHY 不接受
## 这个补偿后的相位。CLKOUT5 与那条补偿线已撤掉，回到 r139 的 0° 结构。
create_generated_clock -name eth_txc -source [get_pins u_idelay_clkgen/u_bufg_eth/O] \
    -divide_by 1 [get_ports eth_tx_clk]
set_output_delay -clock eth_txc -max  0.5 [get_ports {eth_txd[*] eth_tx_ctl}]
set_output_delay -clock eth_txc -min -0.5 [get_ports {eth_txd[*] eth_tx_ctl}]

## r116_rgmii_input_window.xdc —— RGMII 收口 5 个输入的**有出处输入窗**（本轮进构建；只加严，不放宽）
##
## 这一笔还的是 H5 的债：出货流程里 `eth_rx_ctl` / `eth_rxd[3:0]` 从来没有 `set_input_delay`，
## `check_timing` 把它们点名成缺口（件 `build/check_timing_verbose.rpt`、`report/timing/debt_ledger.md` §2）。
## 未覆盖 = 不是"满足"，是"没检查"。
##
## 数从哪儿来（三条，全部本地可核，抄件 build/evidence/r115_rtl8211f_delay_source.txt）：
##   1) 原理图 `<board-docs>/ZYNQ7020/Board_Resource/ZYNQ7020-F+V1.1原理图.pdf` 第 8 页：
##      R57 4.7K 把 PHY1_RXD0 上拉到 PHY1_IODVDD，R59 4.7K 把 PHY1_RXD1 上拉到 PHY1_IODVDD
##      （PHY2 那一半是 R72/R73，同一接法）。图件 build/evidence/r115_sch_p8/rxd_area.png、phy2_straps.png。
##   2) 规格书 RTL8211F-CG（JATR-8275-15 Rev 1.4）Table 10（PDF p23）：RXD0=RXDLY、RXD1=TXDLY；
##      Table 11（同页）与 Table 6（PDF p16）："1: Add 2ns delay to RXC for RXD latching
##      (via 4.7k-ohm to DVDD_RG)" ⇒ 板上 **RXDLY 是开的**，2 ns 延时加在 **RXC** 上，不是加在数据上。
##   3) 规格书 Table 60（PDF p67）里管这一路的行是**发射端**那两行（"transmitter" = PHY 输出 = 我们的收口）：
##        TsetupT  Data→Clock Output Setup at transmitter（delay integrated）  min 1.2  typ 2  –  ns
##        TholdT   Clock→Data  Output Hold  at transmitter（delay integrated）  min 1.2  typ 2  –  ns
##      两者相加 = 半周期 4 ns ⇒ 数据沿相对它自己的捕获沿落在 **[1.2, 2.8] ns 之前**。
##      ⚠ `TskewR 1/1.8/2.6` 与 `TsetupR/TholdR` 是**PHY 的接收端**= 我们 TXD/TXC 那一侧，
##        不能拿来当收口的窗；±0.500（r114 用的）更是 `TskewT`（"without delay integrated"）那一行。
##        这两次"用错行"分别记在 ISSUES #304 与 #309。
##
## 为什么写成正的 1.2/2.8（不是 −2.8/−1.2，也不是 5.2/6.8）：
##   工具对 IDDR 的 D 脚做的是"上升沿发射 → **下一个（下降）沿**捕获"的 setup 检查
##   （报告原文 `Requirement: 4.000ns (eth_rxc fall@4.000ns - eth_rxc rise@0.000ns)`），
##   hold 则对**同一个上升沿**（`Requirement: 0.000`）。所以 offset 要从**发射沿**量起，
##   数据落在发射沿之后 [1.2, 2.8] ns —— 件 `build/evidence/r115_window/probe2_console.txt`
##   的 W1..W4 四组读数把另外两种拼法各差一个整周期的镜像关系量出来了（±4.0 的对称红绿）。
##
## 为什么两沿都要写：IDDR 上下各采一半字节，`-clock_fall` 那一对是第二沿的发射参考。
## （本机 `set_input_delay` 没有 `-setup/-hold`，也没有 `-clock_edges`；`-min` 与 `-max` 还必须
##   **各写一条命令**——合在一条里会被解析成"太多 positional"，ISSUES #308。）
set_input_delay -clock eth_rxc -min  1.200 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -max  2.800 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -clock_fall -min  1.200 -add_delay [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -clock_fall -max  2.800 -add_delay [get_ports {eth_rxd[*] eth_rx_ctl}]

## 输出侧那 6 个端口（`tmds_clk_p`、`tmds_data_p[0..2]`、`led[0..1]`）**这里仍然故意不写**：
## `set_output_delay` 的数要来自接收端（面板/HDMI 接收器）或 DVI/HDMI 规范的窗口条款，
## 本机板级资料（用户手册 + 原理图 + 芯片手册目录）里没有这一项，2026-10-03/04 两次在线取原文也没拿到可引用的一页。
## ⇒ **没有来源就不写数**，这笔继续挂在 `report/timing/debt_ledger.md` §2，本轮收口的是 11 个未约束端口里的 5 个。

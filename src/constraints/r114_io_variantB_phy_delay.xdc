## r114_io_variantB_phy_delay.xdc —— 变体 B：RGMII RX 内部延迟打开时的到达窗（沿后 1.5–2.5 ns） —— "其他地方的时序"里能一次性补上的两类约束（ISSUES #259/#266/#262 的约束侧）
##
## 为什么单独一个文件、并且只在 implementation 阶段生效：
##   这里要点名 clk_fpga_0 / clkout0_1，它们是 PS7 IP 与 MMCM 在**实现阶段**才存在的钟
##   （同一件事在 src/constraints/clock_groups_impl.xdc:1-13 已经踩过一次：综合阶段这些名字取不到，
##   而 XDC 里不能用 if/catch，一条取不到对象的命令会让**整条命令空转**、现场只留一句 warning，
##   见 rk_zynq7020.xdc:52-55 那条 CRITICAL WARNING [Constraints 18-513] 的旧账）。
##   ⇒ 绑定方式与 clock_groups_impl.xdc 相同：add_files + set_property used_in_synthesis false。
##
## 这一把的凭据（先量后写，不猜对象名）：
##   ① `check_timing -verbose` 的**权威名单**（件 build/check_timing_verbose.rpt，2026-10-03 15:32 实测）：
##        no_input_delay (HIGH)   = 5 个端口：eth_rx_ctl、eth_rxd[0..3]
##        no_output_delay (HIGH)  = 6 个端口：led[0]、led[1]、tmds_clk_p、tmds_data_p[0..2]
##        MEDIUM（已有 false path）= 输入 key1_n/key2_n，输出 eth_rst_n/eth_tx_ctl/eth_txd[0..3]
##      本文件先动**输入侧**与**跨域界**两组；TMDS/LED 那 6 个端口的对外窗要的是**面板/接收芯片的手册数**，
##      本机此刻取不到规范原文（试过 TI/DVI 页都不能解析），所以按 §二.2 的纪律**留到下一笔**并写明缺出处，
##      不许把 UI 的 0.26/0.28 当成"已按规范"写进来。
##   ② 时钟对象实测清单（件 build/evidence/r114_objects_probe_console.txt 的 CLOCKS_LIST）：
##        clk_fpga_0, sys_clk, eth_rxc, clkfbout, clkfbout_1, clkout0_1, clkout1_1, clkout2
##      ⇒ 下面用的每个钟名都来自这一行，不是记忆。
##   ③ 命令形状用 help 量过（件 build/evidence/r114_help_probe_console.txt）：
##      `set_input_delay [-clock][-reference_pin][-clock_fall][-rise][-fall][-max][-min][-add_delay] ...`
##      `set_max_delay [-from][-to][-through][-datapath_only] ...`
##      **两把都没有 -setup/-hold，也没有 -clock_edges** ⇒ DDR 的第二沿只能靠再写一条 -clock_fall，
##      UG949 里 -setup/-hold 那套 boundary 写法在这个版本取不到，所以不照抄文章。

## ============================================================
## 一、RGMII 收口（125 MHz DDR，4 位数据 + 控制）：给 eth_rxc 一个真的到达窗
## ============================================================
## 出处：RGMII 规范里 RXD/RX_CTL 与 RXC **对齐**，允许的对齐误差是 ±500 ps（"data alignment is
##   restricted to within ±500 ps"，见 report/TIMING_GLOBAL.md 参考那一条链接的 RGMII 汇总页；
##   TI 的 RGMII timing budget 文档 SNLA243 是同一口径的原文，本机 PDF 解析不出来，所以这里引的是
##   数值本身而不是"我读过 PDF"）。板级共走的偏差由规范给的接收端容忍量 1.0–2.6 ns 覆盖，
##   而这一段在 FPGA 内部是靠 IDELAY 把采样点挪进眼心（r92 实测 IDELAY_VALUE=26  taps），
##   ⇒ 这里只声明**片外**那一段：数据在 RXC 沿 ±0.5 ns 内变化。
## ⚠ 这一组约束以前**完全不存在**（`set_input_delay` 在整棵 src/constraints 里 0 次，#57 立案时量到的），
##    所以此前 eth_rxc 域的 hold 余数一直是"把理想到达当现实"的结果；加上之后 WNS/WHS 都会动，
##    动多少由快车道（同一份 opt.dcp 重跑 place+route）先量，不在这里预言。
## 变体 B（模型 b）：RTL8211F 的 RGMII **RX 内部延迟打开** 时，RXD/RX_CTL 不是"与 RXC 同沿对齐"，
##   而是被 PHY 推后约 2 ns、眼心落在 RXC 沿**之后** ~2 ns 处（规范给的窗宽还是 ±0.5 ns）。
##   ⇒ 到达窗写成"沿后 1.5–2.5 ns"：-max 2.500 / -min 1.500。
##   为什么值得单开一滚：扫档已经把模型 (a) 判死了（tap 0/13/26/31 的 WHS = -4.522/-3.703/-2.885/-2.570，
##   斜率约 63 ps/tap，到最大 31 档还差 -2.57 ns ⇒ 不可能是"少给几拍延迟"能解的），
##   而这块板子在 ETH 片源下是**真的能收流**的（r113 的 29.8–30.0 fps 读回）⇒ 一定有一个模型的窗写错了方向。
set_input_delay -clock eth_rxc -max  2.500 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -min  1.500 [get_ports {eth_rxd[*] eth_rx_ctl}]

## ============================================================
## 二、异步组间四条跨域路：从"完全不管"改成"给一条带理由的上界"（#266）
## ============================================================
## 现状（r113 量的）：`set_clock_groups -asynchronous` 把三组钟两两排除 ⇒ 这四条跨域路在任何尺子里**都不出现**
##   （report/TIMING_GLOBAL.md §4c），也就是说"格雷码/翻转同步器最多跨几个周期"这件事今天没有任何约束兜着，
##   全靠布线碰运气。UG949 的口径是：同步器这类路不该完全 false path，应该给 **set_max_delay -datapath_only**
##   （把数据路径本身限制在目的钟一个周期内，不参与时钟偏斜/不确定度的加倍计算），必要时再配 set_bus_skew。
## 界值 = **目的钟周期**（这是 UG949 给同步器的一周期界；不是收益声明，也不指望它改 WNS——
##   组排除下的路本来就不进 WNS，所以"WNS 没动"是预期而不是证据，看的是名册里别的域没被挤、
##   以及这四条界在 report_exceptions 里数得出条数）。
##   周期来自 build/timing_summary.rpt 的 Clock Summary（eth_rxc 8.000 / clk_fpga_0 10.000 / clkout0_1 20.000）。
## eth_rxc -> clk_fpga_0：dc_fifo 的读侧格雷指针 + ddr_bank_commit 的帧事件翻转
set_max_delay -datapath_only -from [get_clocks eth_rxc] -to [get_clocks clk_fpga_0] 10.000
## clk_fpga_0 -> eth_rxc：dc_fifo 写侧格雷指针（同一根 FIFO 的反方向）
set_max_delay -datapath_only -from [get_clocks clk_fpga_0] -to [get_clocks eth_rxc] 8.000
## clk_fpga_0 -> clkout0_1（像素 50 MHz）：effect_ctrl 的控制字/使能跨域
set_max_delay -datapath_only -from [get_clocks clk_fpga_0] -to [get_clocks clkout0_1] 20.000
## clkout0_1 -> clk_fpga_0：frame_commit_lock 的消隐窗事件
set_max_delay -datapath_only -from [get_clocks clkout0_1] -to [get_clocks clk_fpga_0] 10.000
## 还没写的一条（如实交代，不留假话）：`set_bus_skew` 需要点到**同步器单元名**，
## 而 r114 的对象探针在 `get_false_paths` 上死了（该命令在本工具不存在），异常清单还没数出来；
## 探针换成 `get_timing_exceptions` 之后若数不到对应对象，这一条就继续挂着，不写成"已做"。

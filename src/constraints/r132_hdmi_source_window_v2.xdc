## src/constraints/r132_hdmi_source_window_v2.xdc —— HDMI 源端（TP1）对外窗的第二版候选件（默认不加载）
##
## 与 r119 那一版只差一件事：**参考时钟绑在哪个对象上**。
##   r119 版绑内部串行钟 `clkout1_1`（周期 4.000 ns）；
##   本版按 `report/io/hdmi_cts_source_window.md` 规定的形状，把参考钟定义在**输出端口** `tmds_clk_p` 上，
##   周期 = Tcharacter = 20.000 ns（50 MHz 像素档，出处 `data/metrics.csv` 的显示像素时钟那一行）。
##
## 为什么 r119 那个绑法是错的（不是口味问题，是 2026-10-20 一次带窗构建量出来的，
## 件 `build/evidence/r132_tmdswindow_timing_summary.rpt` 第一条违例路径）：
##   Requirement: 4.000ns  (clkout1_1 rise@4.000ns - clkout1_1 rise@0.000ns)
##     ⇒ 工具拿"一个位周期"当成规范里"钟到数据"的窗口；
##   Slack (VIOLATED) -5.408ns，其中 Clock Path Skew 占 -3.300ns
##     （源侧 SCD 4.991ns 走 MMCM 到 OSERDESE2，端口侧 DCD 只有 1.596ns），
##     比的是不同位槽的沿；数据路径本身只有 1 级 OBUFDS、2.034 ns。
##   规范给的 0.20 Tcharacter 是**连接器上**钟与数据的互对偏斜（HDMI 1.4 §4.2.4 Table 4-24），
##   参考对象只能是面板上看到的那条 20 ns 钟，不是芯片内部 250 MHz 的串行钟。
##   r119 文件里"参考时钟对象由 pin 反查得到（clkout1_1）"那段推理，把"哪条钟驱动触发器"
##   当成了"对外窗以哪条钟为参考"——这两件事在 serdes 输出上不是一回事。
##
## 窗宽不变：±4.000 ns = 0.20 × 20.000 ns，出处与推导同 r119（不是新抄的第三个数）。
## 射程不变：只约束三条数据的 p/n 六口；`tmds_clk_p`/`_n` 是参考对象本身。
## 本文件必须是纯 SDC/XDC 子集：不写 `if`/`puts`/`error`/`expr`——Vivado 解析 .xdc 时会整块跳过并只报
##   Designutils 20-1307，守卫会变成"防呆失效且不报错"（实测件 build/evidence/r119_xdc_loads_probe2.txt）。
## 默认不进构建：新增约束要先量它对逐时钟名册的影响（别域不许变差），量过之前带进发布物就是用声明代替测量。
## 开法：VP_R132_TMDS_V2=1（开关在 build/tcl/build_system_axigpio.tcl 的 6c 块）。
create_clock -period 20.000 -name tmds_clk_ref [get_ports tmds_clk_p]
set_output_delay -clock tmds_clk_ref -max  4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]
set_output_delay -clock tmds_clk_ref -min -4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]

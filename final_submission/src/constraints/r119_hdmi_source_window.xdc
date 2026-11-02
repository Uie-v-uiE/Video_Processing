## src/constraints/r119_hdmi_source_window.xdc —— HDMI **源端（TP1）** 对外窗（候选件，默认不加载）
##
## 本文件必须是纯 SDC/XDC 子集：不写 `if` / `puts` / `error` / `expr`。
##   理由（2026-10-04 实测，件 build/evidence/r119_xdc_loads_probe2.txt 第 42–56 行原文）：
##   Vivado 2025.2.1 解析 .xdc 时对这三行报
##     CRITICAL WARNING: [Designutils 20-1307] Command 'if' is not supported in the xdc constraint file.
##     CRITICAL WARNING: [Designutils 20-1307] Command 'puts' is not supported in the xdc constraint file.
##   ——上一版本文件在这里写了 Tcl 守卫（读不到时钟就 REFUSE），守卫被解析器整块跳过，
##   于是"防呆"变成"防呆失效且不报错"，这比没有守卫更危险。检查与 REFUSE 挪到
##   build/tcl/build_system_axigpio.tcl 的 VP_R119_TMDS_WINDOW 块（那里是 Tcl 脚本，`if`/`error` 合法）。
##   同形状的写法参照 src/constraints/r116_rgmii_input_window.xdc（纯 SDC，已被一轮带窗构建量过）。
##
## 为什么是"源端"而不是"接收窗"：`tmds_clk_p/_n`、`tmds_data_p[0..2]/_n` 是本工程（Source）的**输出**，
## 所以对应的是 HDMI 源端合规里 TP1 的那一组量，不是 Sink 侧 TP2 的接收窗。
## 这个方向是 2026-10-04 用户指出来才纠正的（此前记成"要面板/接收端的窗口数"，还试过 UG471——
## UG471 只有 TMDS_33 的电气属性，没有窗时间；见 report/timing/debt_ledger.md §2 的那段追加）。
##
## 窗宽的数字（逐条可指回出处，全部见 report/io/hdmi_cts_source_window.md 第一节结论表）：
##   * 钟↔数据（互对偏斜，Source at TP1，max）= **0.20 Tcharacter**
##     出处：《HDMI Specification 1.4》§4.2.4 Table 4-24 "Source AC Characteristics at TP1" 行
##     `Inter-Pair Skew at Source Connector, max | 0.20 Tcharacter`（同表在 1.3 Table 4-16 / 1.1 Table 4-13
##     逐字一致；Tektronix 的 CTS 应用笔记复述为 "20% of the pixel-time (TPIXEL)"）。
##   * 本工程当前档的 Tcharacter = 像素周期 = 1/50 MHz = **20.000 ns**
##     出处：`data/metrics.csv` 第 3 行"显示像素时钟,核心,50,MHz"（同一行的 H_TOTAL 1344、V_TOTAL 625 ⇒ 场频 59.5 Hz）；
##     10 bit/character 且 TMDS 钟 = 像素钟的关系出自 HDMI 1.4 §4.2.1（同一份取证文档的表行）。
##   ⇒ 半窗 = 0.20 × 20.000 = **4.000 ns**（这是从上面两个数算出来的，不是抄来的第三个数）。
##     这两个数与下面的 4.000 是否一致，由只读尺子 build/r119_window_check.mjs 判（不靠人眼）。
##
## 参考时钟对象的身份（不是猜的）：四条 TMDS 串行器的 CLK 脚在实现网表里同属一条时钟
##   `u_pl/u_dvi/u_ser_clk|u_ser0|u_ser1|u_ser2/u_master/CLK → clock=clkout1_1 period=4.000`
##   实测件：`build/evidence/r119_ser_clock_probe.txt`（只读探针 `build/tcl/probe_ser_clock.tcl` 打在
##   `vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp` 上）。
##   对照：`report_clock_networks` 只列 3 条主钟（`build/evidence/r119_clock_networks.rpt`），
##   所以"用哪条钟做参考"必须由 pin 反查，不能按主钟表挑。
##
## 为什么不进默认构建（与 RGMII 输入窗同一形状）：这是一次**新增约束**，会改变实现看出去的边界，
## 必须先用一轮构建量它对逐时钟名册的影响（尤其 `clk_fpga_0`/`eth_rxc` 两域不许变差），
## 量完之前把它塞进默认构建就等于"用声明代替测量"。开关：`VP_R119_TMDS_WINDOW=1`。
##
## 仍然如实保留的三条：
##   1) TP1 真正的判据是**眼图掩模 + 抖动/占空比/上升下降**，那几条不在 SDC 的语义里
##      （`set_output_delay` 只约束沿的到达时刻），只能靠仿真与示波器；
##      本文件不代表"过 CTS"，只代表"把规范里唯一能用 SDC 表达的那一个量写进来了"。
##      CTS 表本体属 HDMI Adopter NDA 材料，所以 0.20 Tcharacter 之外的分档值只能作第三方代理 ⇒ 见取证文档第四节。
##   2) `led[0]`/`led[1]` 是 `LVCMOS33` 直驱 LED（`src/constraints/rk_zynq7020.xdc:10-11` 实测），
##      HDMI 连接器引脚表里没有这类信号 ⇒ **没有可引用的对外窗**；
##      要给它们"不查"的定性属于一次放宽，必须先进放宽账本（当前账本仍 0 条），本文件不替它们写任何窗。
##   3) 本窗只挂在 `tmds_data_*`（相对钟道的对齐），钟道自身不挂输出窗：源端的钟就是参考，
##      对它要求的是占空比/抖动/沿/对内偏斜（见取证文档表行 #2/#4/#5），那些都不是 SDC 量。

set_output_delay -clock clkout1_1 -max  4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]
set_output_delay -clock clkout1_1 -min -4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]

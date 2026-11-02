## src/constraints/r119b_hdmi_tp1_pinclk.xdc —— 候选 2（只给只读探针用，**不进任何构建**）
##
## 为什么要这第二版（2026-10-04 实测，件 build/evidence/r119_xdc_loads_probe3.txt）：
##   把 0.20 Tcharacter 的 ±4.000 ns 直接挂在启动串行的那条钟 `clkout1_1`（周期 4.000 ns）上，
##   load 之前 4 个端口的 `Path Group` 全是 (none)，load 之后 3 条数据道变成
##   `Path Group: clkout1_1`、`Requirement: 4.000ns`、`Slack (VIOLATED): -3.482 / -3.458 / -3.474 ns`。
##   ⇒ 约束确实生效了（这证明窗挂上了），但**参考量纲错了**：
##   规范里的 0.20 Tcharacter 是相对 **TMDS 钟（=像素钟，本档周期 20.000 ns）** 的互对偏斜，
##   而 `clkout1_1` 是片内 250 MHz 串行器时钟，两者不同一个周期，
##   拿 4 ns 的钟当 20 ns 周期的参考，等于把窗口压缩成 1/5。
##
## 本文件唯一变量 = **把参考钟定在 TMDS 钟脚上**（`create_clock` 打在 `tmds_clk_p`，周期按 50 MHz 档 = 20.000 ns），
## 窗宽仍用规范原文 0.20 × 20.000 = 4.000 ns（出处见 report/io/hdmi_cts_source_window.md 表行 #1）。
## 数据道相对这条"脚上的钟"再挂 ±4.000。
##
## 这只是**探针输入**：默认不加载、没进 build/tcl/build_system_axigpio.tcl 的任何开关块，
## 量出来的 slack 只能说明"这一族约束在 SDC 里怎么表达"，不能当"过了 CTS"（TP1 的真判据是眼图/抖动/占空比/沿，
## 那些不在 SDC 语义里）。最终采用哪一版必须走一轮完整构建量逐时钟名册（还欠着）。
##
## 如实记下的不确定性：`create_clock` 打在**输出脚**上得到的是"外部参考钟"，
## 它与片内启动钟 `clkout1_1` 之间没有声明的时序关系；工具会不会把这两者当成无关时钟组、
## 会不会因此根本不产生到数据道的路径，**由探针实测回答**，这里不预判结论。

create_clock -name r119b_tmclk -period 20.000 [get_ports {tmds_clk_p}]
set_output_delay -clock r119b_tmclk -max  4.000 [get_ports {tmds_data_p[*]}]
set_output_delay -clock r119b_tmclk -min -4.000 [get_ports {tmds_data_p[*]}]

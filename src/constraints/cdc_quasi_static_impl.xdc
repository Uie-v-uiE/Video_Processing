## cdc_quasi_static_impl.xdc — 准静态总线跨域例外（只在 implementation 阶段生效）
##
## 为什么单独一个文件：这三条只改实现阶段的时序判据，不改综合网表；绑法与
## clock_groups_impl.xdc 相同（used_in_synthesis=false）。XDC 里不能写 if/catch，
## 所以“只在实现阶段存在”必须由构建脚本的 fileset 属性表达，而不是文件内守卫。
##
## 这三条路径为什么不再按 4 ns 的 setup 要求去收：
##   clk_pix（u_pl/u_clk 的 CLKOUT0，50 MHz）与 clk_eth（u_idelay_clkgen 的 CLKOUT3，
##   125 MHz）来自**两颗不同的 MMCM**。Vivado 把同一主钟下面的生成钟当“相关钟”，
##   于是 50→125 的最紧沿差被算成 4.000 ns；但这两颗 MMCM 的 VCO 各自独立，
##   相位关系没有可签字的界。设计上本来就不靠这个 4 ns：
##     · snap_cross 的宽总线在源域整拍更新，和 bus_tog 同拍翻转，目的域用 3 级
##       同步器抓到跳变沿之后才采总线；总线至少保持一帧（16 ms），
##       远大于 10 ns 的位间 skew 预算。
##     · link_active_r 是寄存后的电平，进像素域 3 级 ASYNC_REG 链后才使用。
##   所以这里用 set_max_delay -datapath_only 把“位间 skew ≤ 10 ns”写成显式契约：
##   既不假装 4 ns 可签，也不把路径当不存在（still checked，slack 可读）。
##   -datapath_only 去掉时钟路径的 skew/pessimism，只约束数据路径本身，这正是
##   准静态总线要量的东西；该选项同时不做 hold 检查（数据保持 16 ms，结构上不需要）。
##
## 判据（本文件生效后应看到）：
##   report_timing 里 u_pl/pv_lat_reg[*] → u_eth/u_pane_eth/bus_q_reg[*] 的
##   Requirement 从 4.000 变成 10.000，且不再占据最差 setup 的前几名；
##   这 19 条 50→125 路径仍然出现在报告里（不是 set_false_path 抹掉）。

# 处理窗完整性：{pane_valid, pane_bad[15:0]} 与同一拍翻转的 pane_tog
set_max_delay -datapath_only 10.000 \
  -from [get_cells {u_pl/pv_lat_reg[*] u_pl/pv_valid_reg}] \
  -to   [get_cells u_eth/u_pane_eth/bus_q_reg[*]]

# 跳变沿本身进 3 级同步器（ts/hs 是同一个源翻转的两条链）
set_max_delay -datapath_only 10.000 \
  -from [get_cells u_pl/pv_tog_reg] \
  -to   [get_cells {u_eth/u_pane_eth/ts_reg[*] u_eth/u_pane_eth/hs_reg[*]}]

# 链路电平：u_eth 寄存一拍后的 link_active_r → 像素域 3 级链的第一级 el0
set_max_delay -datapath_only 10.000 \
  -from [get_cells u_eth/link_active_r_reg] \
  -to   [get_cells u_pl/el0_reg]

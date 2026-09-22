## clock_groups_impl.xdc — 异步时钟组（只在 implementation 阶段生效）
##
## 为什么单独一个文件：clk_fpga_0 由 PS7 IP 自己的 XDC 创建（FCLKCLK[0]），
## 综合阶段还不存在；而 XDC 文件里不能用 if/catch（[Designutils 20-1307]）。
## 于是把它拆出来，用 add_files + set_property used_in_synthesis false 绑定到
## 只在实现阶段生效（见 build/tcl/build_system_axigpio.tcl 的 constrs_1 部分）。
##
## 时序数字不受影响：综合阶段这条约束在拆分前**也是失败的**（等于不存在）。
##
## 三组互相异步：
##   eth_rxc        125 MHz，PHY 恢复出来的收包时钟（RGMII 域，整个协议栈 + frame_reasm）
##   clk_fpga_0     100 MHz，PS FCLK0（全部 AXI 事务）
##   sys_clk 及其全部生成钟 50/250/200 MHz，
##                  用 -include_generated_clocks 才能把 MMCM 的
##                  clkout0_1(像素 50M)/clkout1_1(TMDS 250M)/clkout2(IDELAY 参考 200M)
##                  一起抓进本组 —— 少了这个后缀，clk_pix 会被当成独立时钟去和
##                  eth_rxc 做 setup 分析，历史上是 WNS≈-6.7 的假违例（ISSUES.md #18）。
##
## 跨域数据由结构保证，不靠时序分析：
##   eth_rxc → clk_fpga_0 视频流  = dc_fifo（格雷码 + 2FF，BRAM）
##   eth_rxc → clk_fpga_0 帧事件  = 翻转 + 3FF 边沿检测（ddr_bank_commit）
##   clk_pix → clk_fpga_0 消隐窗  = 3 级像素 + 3FF（frame_commit_lock）
##   clk_fpga_0 → clk_pix 控制字  = 3FF（pl_video_top / effect_ctrl）
##
## 注意：clk_pix 与 clk_pix5x **有意留在同一组内**（同 MMCM、5:1、0° 相位），
## 让 TMDS 并串转换按同步路径做 setup 分析；声明成异步反而会漏检。

set_clock_groups -asynchronous \
  -group [get_clocks eth_rxc] \
  -group [get_clocks -quiet clk_fpga_0] \
  -group [get_clocks -include_generated_clocks sys_clk]

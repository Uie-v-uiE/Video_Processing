#!/bin/bash
# 20 秒的"顶层端口对得上吗"预检（改完 ku5p 顶层先跑这个，再去跑十分钟的构建）。
#
# 为什么需要它：`sim/run_one.sh` 不能编译 ku5p/src/rtl/*.v —— 那边的 gmii_*/rgmii_* 与
# src/rtl/eth 下的同名文件会撞（Vivado 工程里也是靠"只加需要的文件"来分开的）。
# 于是 ku5p_eth_top 的端口改动没有任何台架碰得到，只能等构建 —— 2026-09-23 主线那边
# 因为同样的空档差点把"判据写在没人例化的地方"当成交付。
#
# 三个不显然的开关（少一个就 elaboration 失败，而失败信息看起来像 RTL 错了）：
#   -L unisims_ver -L unimacro_ver -L secureip   认 IDDRE1/ODDR/BUFG 这些原语
#   glbl                                        作为第二个 top unit 传进去（不是 -L），
#                                               否则 unisim 里的 `glbl` 引用报 "not declared"
#   -timescale 1ns/1ps                          厂商那份 gmii_to_rgmii.v 没有 `timescale
V=/d/Software/Vivado/2025.2.1/Vivado/bin
ROOT=/d/Xilinx/Prj/pro/Video_Processing
R=/tmp/kx/ku5p_top
rm -rf $R && mkdir -p $R && cd $R || exit 1
ETH="arp.v arp_rx.v arp_tx.v icmp.v icmp_rx.v icmp_tx.v udp_tx.v udp_rx_parser.v
     frame_reasm.v sync_fifo.v dc_fifo.v crc32_d8.v link_monitor.v snap_cross.v gmii_rx_mac.v"
$V/xvlog $(find $ROOT/ku5p/src/rtl -name '*.v') \
         $ROOT/src/rtl/video/frame_buffer_w64.v $ROOT/src/rtl/video/fb_pack.v \
         $(for f in $ETH; do echo $ROOT/src/rtl/eth/$f; done) \
         "$V/../data/verilog/src/glbl.v" > xv.log 2>&1
if grep -q "^ERROR" xv.log; then echo "XVLOG FAILED"; grep "^ERROR" xv.log | head -8; exit 1; fi
$V/xelab ku5p_eth_top glbl -s topchk -timescale 1ns/1ps \
      -L unisims_ver -L unimacro_ver -L secureip > el.log 2>&1
if grep -q "^ERROR" el.log; then echo "XELAB FAILED"; grep -A2 "^ERROR" el.log | head -20; exit 1; fi
echo "PASS ku5p_eth_top elaborates（端口全对得上）"
grep -a "^WARNING" el.log | head -5

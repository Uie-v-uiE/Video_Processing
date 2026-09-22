#!/bin/bash
# 快速单台架回归（绕开全量 run_sim.tcl 的两分钟编译），用法：run_one.sh <tb_name>
V=/d/Software/Vivado/2025.2.1/Vivado/bin
TB=$1
R=/tmp/kx/$TB.run
mkdir -p $R && cd $R || exit 1
rm -rf xsim.dir
SRC="/d/Xilinx/Prj/pro/Video_Processing/ku5p/src/rtl/ku5p_telem.v
/d/Xilinx/Prj/pro/Video_Processing/ku5p/src/rtl/ku5p_tx_arb.v
/d/Xilinx/Prj/pro/Video_Processing/src/rtl/eth/udp.v
/d/Xilinx/Prj/pro/Video_Processing/src/rtl/eth/udp_rx.v
/d/Xilinx/Prj/pro/Video_Processing/src/rtl/eth/udp_tx.v
/d/Xilinx/Prj/pro/Video_Processing/src/rtl/eth/crc32_d8.v
/d/Xilinx/Prj/pro/Video_Processing/src/rtl/eth/eth_ctrl.v
/d/Xilinx/Prj/pro/Video_Processing/src/rtl/video/frame_commit_lock.v
/d/Xilinx/Prj/pro/Video_Processing/sim/tb_ku5p_telem.v
/d/Xilinx/Prj/pro/Video_Processing/sim/tb_ku5p_tx_arb.v
/d/Xilinx/Prj/pro/Video_Processing/sim/tb_v79_abort_toggle.v"
$V/xvlog $SRC > xv.log 2>&1
if grep -q "^ERROR" xv.log; then echo "XVLOG FAILED"; grep "^ERROR" xv.log | head -8; exit 1; fi
$V/xelab $TB -s snap > el.log 2>&1
if grep -q "^ERROR" el.log; then echo "XELAB FAILED"; grep -A3 "^ERROR" el.log | head -20; exit 1; fi
$V/xsim snap -R > run.log 2>&1
grep -aE "FAIL|PASS|INFO|error|Error" run.log | head -40
tail -2 run.log

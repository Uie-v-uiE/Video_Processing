#!/bin/bash
# 快速单台架回归（绕开全量 run_sim.tcl 的两分钟编译），用法：run_one.sh <tb_name>
#
# 编译清单与 run_sim.tcl 同口径：src/rtl 整棵树 + KU5P 自研那两个模块（**不整目录 glob**，
# 那边的 gmii_*/rgmii_* 与 src/rtl/eth 下同名会撞）+ sim/tb_*.v。
# 以前这里是手写的一小串文件，结果是"改了 pl_video_top 想快点看一眼"时 xelab 直接报
# Cannot find design unit —— 顶层唯一的台架 tb_v6_vblank_copy 根本不在清单里（2026-09-23 撞到）。
V=/d/Software/Vivado/2025.2.1/Vivado/bin
TB=$1
ROOT=/d/Xilinx/Prj/pro/Video_Processing
R=/tmp/kx/$TB.run
mkdir -p $R && cd $R || exit 1
rm -rf xsim.dir
SRC="$(find $ROOT/src/rtl -name '*.v' | tr '\n' ' ') \
$ROOT/ku5p/src/rtl/ku5p_telem.v $ROOT/ku5p/src/rtl/ku5p_tx_arb.v $ROOT/ku5p/src/rtl/ku5p_cmd.v \
$(find $ROOT/sim -maxdepth 1 -name 'tb_*.v' | tr '\n' ' ')"
$V/xvlog $SRC > xv.log 2>&1
if grep -q "^ERROR" xv.log; then echo "XVLOG FAILED"; grep "^ERROR" xv.log | head -8; exit 1; fi
$V/xelab $TB -s snap > el.log 2>&1
if grep -q "^ERROR" el.log; then echo "XELAB FAILED"; grep -A3 "^ERROR" el.log | head -20; exit 1; fi
$V/xsim snap -R > run.log 2>&1
grep -aE "FAIL|PASS|INFO|error|Error" run.log | head -40
tail -2 run.log

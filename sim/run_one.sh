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
$(find $ROOT/sim -maxdepth 1 -name 'tb_*.v' | tr '\n' ' ') \
$(find $ROOT/sim/prim -name '*.v' 2>/dev/null | tr '\n' ' ')"
# ⚠ 清单**必须走 -f 文件**，不能拼在命令行上：台架加多之后 xvlog 会被 Windows 命令行长度上限
#   截成一句"参数太多"，而 xv.log 里连 ERROR 都没有 ⇒ 本脚本只看 "^ERROR" 就往下走，
#   最后报成一句看不懂的 "Cannot find design unit"（2026-09-25 加 tb_v94 时撞到）。
# ⚠ 文件里写的必须是 **Windows 正斜杠路径**（`cygpath -m`）：命令行参数会被 MSYS 自动换算，
#   但 -f 文件的内容不会 —— 直接写 /d/... 会让 xvlog 报 "Can not find file"（同一天撞到第二次）。
printf '%s\n' $SRC | cygpath -m -f - > files.f
$V/xvlog -f files.f > xv.log 2>&1
if grep -q "^ERROR" xv.log; then echo "XVLOG FAILED"; grep "^ERROR" xv.log | head -8; exit 1; fi
if [ ! -d xsim.dir/work ]; then echo "XVLOG 没建出 work 库，xv.log 尾部："; tail -3 xv.log; exit 1; fi
$V/xelab $TB -s snap > el.log 2>&1
if grep -q "^ERROR" el.log; then echo "XELAB FAILED"; grep -A3 "^ERROR" el.log | head -20; exit 1; fi
$V/xsim snap -R > run.log 2>&1
# ⚠ 过滤词表必须包含台架**专门为了回答"缺口在哪"而打的那些行**（PROBE/DIAG/NOTE/OBS）：
#   2026-09-25 台架 tb_v98 数出"帧缓存到底被写了多少字"的那条 PROBE 就是被这个过滤器挡在
#   run.log 里的，我因此多绕了一趟临时目录才看到它 —— 而那份 console 才是要留在报告里的凭据。
grep -aE "FAIL|PASS|INFO|PROBE|DIAG|NOTE|OBS |error|Error" run.log | head -60
tail -2 run.log

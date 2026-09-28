#!/bin/bash
# 快速单台架回归（绕开全量 run_sim.tcl 的两分钟编译），用法：run_one.sh <tb_name>
#
# 编译清单与 run_sim.tcl 同口径：src/rtl 整棵树 + sim/prim 占位件 + sim/tb_*.v。
# 以前这里是手写的一小串文件，结果是"改了 pl_video_top 想快点看一眼"时 xelab 直接报
# Cannot find design unit —— 顶层唯一的台架 tb_v6_vblank_copy 根本不在清单里（2026-09-23 撞到）。
V=/d/Software/Vivado/2025.2.1/Vivado/bin
TB=$1
ROOT=/d/Xilinx/Prj/pro/Video_Processing
R=/tmp/kx/$TB.run
# ⚠ 2026-09-27 12:48 撞到的一件事：**同一时刻只能有一个 xsim 在写这个目录**。
#   第二次 `run_one.sh` 并不会让第一次停下 —— 前一个 xsim/xsimk 还活着，继续往同一个
#   `run.log` 里写它那一跑的行。两次跑的行混在一份文件里，`tb98_report.sh` 就会把
#   "上一跑的 C5c" 与 "这一跑的 C5c" 拼成一份报告（今天 12:45 那份就是这么废掉的，
#   而它的头部 md5 全对 —— 认 md5 也救不了"正文来自两个进程"这件事）。
#   所以：门口先看有没有活的 xsim/xsimk，有就**拒绝启动**并说清该杀谁（不自动杀：
#   正在跑的那一跑可能是别人要的凭据）。
if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    echo "REFUSE: 已经有 xsim 在跑（它会把行写进同一份 run.log）。先看是谁的：tasklist //FI \"IMAGENAME eq xsim.exe\""
    echo "        确认可以中断再：taskkill //F //IM xsim.exe //T && taskkill //F //IM xsimk.exe //T"
    exit 3
fi
mkdir -p $R && cd $R || exit 1
rm -rf xsim.dir
SRC="$(find $ROOT/src/rtl -name '*.v' | tr '\n' ' ') \
$(find $ROOT/sim -maxdepth 1 -name 'tb_*.v' | tr '\n' ' ') \
$(find $ROOT/sim/prim -name '*.v' 2>/dev/null | tr '\n' ' ')"
# ⚠ 清单**必须走 -f 文件**，不能拼在命令行上：台架加多之后 xvlog 会被 Windows 命令行长度上限
#   截成一句"参数太多"，而 xv.log 里连 ERROR 都没有 ⇒ 本脚本只看 "^ERROR" 就往下走，
#   最后报成一句看不懂的 "Cannot find design unit"（2026-09-25 加 tb_v94 时撞到）。
# ⚠ 文件里写的必须是 **Windows 正斜杠路径**（`cygpath -m`）：命令行参数会被 MSYS 自动换算，
#   但 -f 文件的内容不会 —— 直接写 /d/... 会让 xvlog 报 "Can not find file"（同一天撞到第二次）。
printf '%s\n' $SRC | cygpath -m -f - > files.f
# 出处（provenance）：**编译之前**记下这次跑的树里两份关键源的 md5。
# 为什么在这里记而不是事后：门禁第 15 项要的恰恰是"这份报告是不是**当前这份顶层**跑出来的"，
# 而事后补 md5 等于把今天的指纹盖在昨天的日志上（#88 那几天"gates 全绿 + 顶层台架红着"的根源
# 就是没有任何东西把报告与被测的树绑在一起）。
# ⚠ 只有 `top_md5` 是**不够的**（2026-09-26 r72 那天撞见）：那一轮改的是四个窗口级
#   （`proc_box_blur/sharpen/sobel/morph`），`pl_video_top.v` 一个字节没动 ⇒ 顶层 md5 仍然"对得上"，
#   而 r71 那份旧报告可以原样冒充"当前这一版台架"。所以再加一枚 `rtl_md5`：整个 `src/rtl` 的合指纹。
RTLALL=$(cd "$ROOT" && find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
{ echo "top_md5=$(md5sum $ROOT/src/rtl/top/pl_video_top.v | cut -c1-12)"
  echo "tb_md5=$(md5sum $ROOT/sim/$TB.v 2>/dev/null | cut -c1-12)"
  echo "rtl_md5=$RTLALL"
  echo "date=$(date -Iseconds)"; } > prov.txt
$V/xvlog -f files.f > xv.log 2>&1
if grep -q "^ERROR" xv.log; then echo "XVLOG FAILED"; grep "^ERROR" xv.log | head -8; exit 1; fi
if [ ! -d xsim.dir/work ]; then echo "XVLOG 没建出 work 库，xv.log 尾部："; tail -3 xv.log; exit 1; fi
$V/xelab $TB -s snap > el.log 2>&1
if grep -q "^ERROR" el.log; then echo "XELAB FAILED"; grep -A3 "^ERROR" el.log | head -20; exit 1; fi
$V/xsim snap -R > run.log 2>&1
# ⚠ 过滤词表必须包含台架**专门为了回答"缺口在哪"而打的那些行**（PROBE/DIAG/NOTE/OBS）：
#   2026-09-25 台架 tb_v98 数出"帧缓存到底被写了多少字"的那条 PROBE 就是被这个过滤器挡在
#   run.log 里的，我因此多绕了一趟临时目录才看到它 —— 而那份 console 才是要留在报告里的凭据。
grep -aE "FAIL|PASS|INFO|PROBE|DIAG|NOTE|OBS |GOLDEN|^D[123] |error|Error" run.log | head -80
tail -2 run.log

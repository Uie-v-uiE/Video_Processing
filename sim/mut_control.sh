#!/bin/bash
# 判据的"必须能红"控制（#91）。
#
# 为什么要有这个脚本：C10f（行缓存写地址越界）在修好之后是绿的，而"绿"有两种可能 ——
# 根因真的没了，或者这条判据压根没被执行过（#103 第一版就栽在后一种：消隐期喂 x=0，
# 越界那一拍永远不会出现 ⇒ 判据恒绿却什么都没管）。唯一的分辨办法是把**修复前的写法**
# 复原一次、看它红不红。
#
# 为什么不直接改 src/rtl：门禁在跑、构建在跑的时候改源 = 静默重新综合（历史上烧掉过一整轮），
# 而"改回来"这一步全靠人记住。这里改成把整棵 rtl 拷到 /tmp 再机械地 sed 回旧写法，
# 真源一个字节都不动；拷贝与原件的 diff 必须恰好是那五行，多一行少一行都拒绝继续
# （否则控制跑测的可能是"我以为的旧代码"以外的东西）。
#
# 用法：sim/mut_control.sh <tb 名> <判据前缀>   例：sim/mut_control.sh tb_v103_pipe_bypass C10f
# 判定：控制跑里这条判据必须报红 ⇒ 它测得到 #103；仍然 PASS ⇒ MUTATION FAILED（判据没有力）。
# 当前只会用一条 mutation（proc_pipeline 的坐标延迟线差一拍 = #103 的根因）；
# 换判据要换 mutation，别再套这个脚本。
# 仓库根自适应：本文件在 <repo>/sim/ 下，所以 .. 就是根（原来两行都是这台机器的绝对路径）
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 工具路径只有一个说法：VP_VIVADO_BIN 指到 <Vivado>/bin（见 docs/BUILD.md「换一台机器」那一节）。
# 默认值留着是为了本机少敲一步，**不是**"这台机器就是标准"：找不到 xvlog 就明说并退出，
# 别让人对着一句 "No such file or directory" 去怀疑 RTL。
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
[ -x "$V/xvlog" ] || { echo "REFUSE: 找不到 xvlog（当前 $V）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（docs/BUILD.md）"; exit 2; }
TB=${1:?用法: mut_control.sh <tb_name> <criterion>}
CRIT=${2:?用法: mut_control.sh <tb_name> <criterion>}
R=/tmp/kx/mut_${TB}_${CRIT}.run

if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    echo "REFUSE: 已经有 xsim 在跑，它会往同一份 run.log 里写行（详见 run_one.sh 头部）。"
    exit 3
fi

rm -rf "$R" && mkdir -p "$R" && cd "$R" || exit 1

# ---- 1) 拷贝整棵 rtl，机械复原 proc_pipeline 修复前的延迟线 ----
cp -r "$ROOT/src/rtl" rtl_mut || exit 1
P=rtl_mut/process/proc_pipeline.v
sed -i \
  -e 's/reg \[11:0\] xd \[1:12\];/reg [11:0] xd [0:12];/' \
  -e 's/reg \[11:0\] yd \[1:12\];/reg [11:0] yd [0:12];/' \
  -e 's/for (cp = 1; cp <= 12; cp = cp + 1) begin xd\[cp\]/for (cp = 0; cp <= 12; cp = cp + 1) begin xd[cp]/' \
  -e 's/xd\[1\] <= x_in; yd\[1\] <= y_in;/xd[0] <= x_in; yd[0] <= y_in;/' \
  -e 's/for (cp = 2; cp <= 12; cp = cp + 1) begin/for (cp = 1; cp <= 12; cp = cp + 1) begin/' \
  "$P" || exit 1
diff <(sed -e 's/[[:space:]]*$//' "$ROOT/src/rtl/process/proc_pipeline.v") \
     <(sed -e 's/[[:space:]]*$//' "$P") > mut.diff
NCH=$(grep -c '^[<>]' mut.diff)
echo "== mutation diff（必须恰好 5 对 = 10 行）=="
cat mut.diff
[ "$NCH" -eq 10 ] || { echo "REFUSE: 改动行数 $NCH != 10，复原的不是我预期的那五行。"; exit 4; }

# ---- 2) 只编译 mutant + 目标台架（真源一个字节没动）----
find "$R/rtl_mut" -name '*.v' > list.txt
echo "$ROOT/sim/$TB.v" >> list.txt
find "$ROOT/sim/prim" -name '*.v' 2>/dev/null >> list.txt
cygpath -m -f list.txt > files.f
printf 'mut_src=%s\nmut_diff_lines=%s\ntb_md5=%s\nrtl_md5_real=%s\ndate=%s\n' \
  "$(md5sum "$P" | cut -c1-12)" "$NCH" "$(md5sum "$ROOT/sim/$TB.v" | cut -c1-12)" \
  "$(cd "$ROOT" && find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)" \
  "$(date -Iseconds)" | tee prov.txt

$V/xvlog -f files.f > xv.log 2>&1
if grep -q "^ERROR" xv.log; then echo "XVLOG FAILED"; grep "^ERROR" xv.log | head -8; exit 1; fi
$V/xelab "$TB" -s snap > el.log 2>&1
if grep -q "^ERROR" el.log; then echo "XELAB FAILED"; grep -A3 "^ERROR" el.log | head -20; exit 1; fi
$V/xsim snap -R > run.log 2>&1

# ---- 3) 判定：这条判据在旧写法上必须红 ----
echo "== 控制跑里的 $CRIT =="
grep -a "$CRIT" run.log | head -6
grep -a RESULT run.log | tail -2
if grep -aqE "FAIL[[:space:]]+$CRIT" run.log; then
    echo "MUTATION OK: $CRIT 在修复前的延迟线上报红 ⇒ 这条判据有力。"
    exit 0
else
    echo "MUTATION FAILED: $CRIT 在修复前的写法上仍然不红 ⇒ 判据测不到 #103，别把它当凭据。"
    exit 5
fi

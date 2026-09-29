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
# 用法：sim/mut_control.sh <tb 名> <判据前缀> [mutation]
#   例：sim/mut_control.sh tb_v103_pipe_bypass C10f              （默认 pipeline）
#       sim/mut_control.sh tb_osd_lines T18 osd_inchar           （拆掉 in_char 的 in_box 项）
# 判定：控制跑里这条判据必须报红 ⇒ 它测得到那一族；仍然 PASS ⇒ MUTATION FAILED（判据没有力）。
# 每条 mutation 都要单独写 case 分支并给出"改动行数"上界（对不上就拒绝继续）——
# 别再往 pipeline 那条 sed 里塞别的模块的旧写法，那会让一次控制跑同时测两件事。
# 仓库根自适应：本文件在 <repo>/sim/ 下，所以 .. 就是根（原来两行都是这台机器的绝对路径）
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 工具路径只有一个说法：VP_VIVADO_BIN 指到 <Vivado>/bin（见 docs/BUILD.md「换一台机器」那一节）。
# 默认值留着是为了本机少敲一步，**不是**"这台机器就是标准"：找不到 xvlog 就明说并退出，
# 别让人对着一句 "No such file or directory" 去怀疑 RTL。
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
[ -x "$V/xvlog" ] || { echo "REFUSE: 找不到 xvlog（当前 $V）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（docs/BUILD.md）"; exit 2; }
TB=${1:?用法: mut_control.sh <tb_name> <criterion>}
CRIT=${2:?用法: mut_control.sh <tb_name> <criterion>}
R=/tmp/kx/mut_${TB}_${CRIT}_${3:-pipeline}.run

if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    echo "REFUSE: 已经有 xsim 在跑，它会往同一份 run.log 里写行（详见 run_one.sh 头部）。"
    exit 3
fi

rm -rf "$R" && mkdir -p "$R" && cd "$R" || exit 1

# ---- 1) 拷贝整棵 rtl，按选中的 mutation 机械复原"修复前/门被拆掉"的写法 ----
# mutation 选择器：`pipeline`（默认）= #103 的坐标延迟线差一拍；`osd_inchar` = 拆掉 `in_char` 里的
# `in_box` 那一项（它正是把 `chars` 越界读"门住"的那道门，`tb_osd_lines` 的 T18 就靠它才有力）。
MUT=${3:-pipeline}
cp -r "$ROOT/src/rtl" rtl_mut || exit 1
case "$MUT" in
pipeline)
    P=rtl_mut/process/proc_pipeline.v
    EXPDIFF=10          # 五行：一增一删算 2
    sed -i \
      -e 's/reg \[11:0\] xd \[1:12\];/reg [11:0] xd [0:12];/' \
      -e 's/reg \[11:0\] yd \[1:12\];/reg [11:0] yd [0:12];/' \
      -e 's/for (cp = 1; cp <= 12; cp = cp + 1) begin xd\[cp\]/for (cp = 0; cp <= 12; cp = cp + 1) begin xd[cp]/' \
      -e 's/xd\[1\] <= x_in; yd\[1\] <= y_in;/xd[0] <= x_in; yd[0] <= y_in;/' \
      -e 's/for (cp = 2; cp <= 12; cp = cp + 1) begin/for (cp = 1; cp <= 12; cp = cp + 1) begin/' \
      "$P" || exit 1
    ;;
osd_inchar)
    P=rtl_mut/video/osd_overlay.v
    EXPDIFF=2           # 只动 in_char 那一行
    sed -i 's/wire        in_char = in_box \&\& (pix_y/wire        in_char =          (pix_y/' "$P" || exit 1
    ;;
osd_addr)
    # ⚠ 这条**不是** T18 的反例，而是 T18 的一条限度测量：把 DUT 读地址整体推到数组外
    # （+6*MAX_CHARS=+192 > 上界 159）之后，T18 仍然 0 ⇒ 因为判据自己按 `s_line*MC+s_cidx` 重算索引，
    # 看不见 RTL 里那条表达式被改。今天 RTL 的表达式与重算式逐字相同（`osd_overlay.v:487`）所以不失真，
    # 但"改了地址算术就抓不到"是这条判据的真实边界 ⇒ 要修得先在 RTL 里给读地址起一根线（动 src/rtl ⇒ 排到有构建轮次时）。
    P=rtl_mut/video/osd_overlay.v
    EXPDIFF=2
    sed -i 's/chars\[s_line \* MAX_CHARS + s_cidx\]/chars[s_line * MAX_CHARS + s_cidx + 6*MAX_CHARS]/' "$P" || exit 1
    ;;
osd_inchar_all)
    # T18 的真正反例：把 `in_char` 里**两道门一起拆掉**（`in_box` 与 `line < N_LINES`），
    # 于是"画像素"与"索引越界"第一次能同拍成立 ⇒ T18 必须数到非零的 harm 拍。
    # 只拆一道门是不够的（`osd_inchar` 那次实测机会计数 190464 一字不变）：这两项是**冗余的双重门**，
    # 这一条就是 #127 第 2 条的收口结论 —— 越界读被门住，而且门有两道。
    P=rtl_mut/video/osd_overlay.v
    EXPDIFF=2
    sed -i 's/wire        in_char = in_box \&\& (pix_y < CHAR_H) \&\& (line < N_LINES);/wire        in_char = (pix_y < CHAR_H);/' "$P" || exit 1
    ;;
bilin_ky_fold)
    # `tb_v101_fb_bilin` 的 L10 需要的正例：拆掉纵向抽头的折回钉子（`ky_use` 里的 `sy >= IMG_H-1` 那一项），
    # 于是末行那次 `w_b` 越界读**不再被折回**、直接喂进插值 ⇒ L10 必须数到非零。
    # 为什么这条算正例而"改判据的 mask"不算：那个只证明计数器会动，这个证明它管的是 DUT 的那道门。
    # ⚠ 预期会有连带红（参考模型仍按折回算 ⇒ 末行的像素比对也会红）⇒ 判定看"L10 在不在红名单里"，
    #   连带项写进凭据而不是删掉。
    P=rtl_mut/process/bilin/fb_bilin.v
    EXPDIFF=2
    sed -i 's/ ky_use = !bilin_en || sy >= IMG_H-1;/ ky_use = !bilin_en;/' "$P" || exit 1
    ;;
*)  echo "REFUSE: 不认识 mutation '$MUT'（现有：pipeline | osd_inchar | osd_addr | osd_inchar_all | bilin_ky_fold）。别猜，往下读 case 分支。"; exit 2 ;;
esac
# 原件那一侧必须写**绝对**路径：这个脚本前面已经 `cd "$R"` 了，用相对路径会让 diff 找不到原件，
# 于是把整个 mutant 文件当成"新增"报出 509 行 —— 守卫照样拒绝，但拒绝的原因是路径而不是改动本身（2026-09-29 08:19 实踩）。
ORIG="$ROOT/src/rtl/${P#rtl_mut/}"
diff <(sed -e 's/[[:space:]]*$//' "$ORIG") \
     <(sed -e 's/[[:space:]]*$//' "$P") > mut.diff
NCH=$(grep -c '^[<>]' mut.diff)
echo "== mutation diff（必须恰好 $((EXPDIFF/2)) 对 = $EXPDIFF 行）=="
cat mut.diff
[ "$NCH" -eq "$EXPDIFF" ] || { echo "REFUSE: 改动行数 $NCH != $EXPDIFF，复原的不是我预期的那几行。"; exit 4; }

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
    echo "MUTATION OK: $CRIT 在 mutation '$MUT' 下报红 ⇒ 这条判据有力。"
    exit 0
else
    echo "MUTATION FAILED: $CRIT 在修复前的写法上仍然不红 ⇒ 判据测不到 #103，别把它当凭据。"
    exit 5
fi

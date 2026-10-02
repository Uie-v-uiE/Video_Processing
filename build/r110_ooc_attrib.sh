#!/bin/bash
# r110 的 -243 LUT 归因：把 frame_reasm.v 单独 OOC 综合两遍（base 未打刀 / cut 打了刀 4①），
# 两遍用同一套默认参数（顶层实参 VIDEO_W=512 VIDEO_H=300 ⇒ FRAME_BYTES=307200，正是模块默认值）。
# 两腿都是**拷贝树**，src/ 一个字节都不动（规矩：不许在构建/台架链中途改 RTL）。
# 为什么单独量这一刀：r110 的采纳裁决卡在「WNS 抓手成立，但 -243 LUT 从平铺的 utilization.rpt 归不出来」
#（ISSUES #246）。OOC 只回答「刀 4① 自己值多少 LUT」，刀 1（link_monitor 的 gapclr）不在这一份里。
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
V=${VP_VIVADO_BIN:-}
[ -f "$V/vivado.bat" ] || [ -x "$V/vivado" ] || { echo "ATTR-REFUSE: 先设 VP_VIVADO_BIN=<Vivado>/bin（当前 '$V'）"; exit 2; }
PATCH="$ROOT/build/evidence/r110_notadopted/r110_cuts.patch"
RTL=src/rtl/eth/frame_reasm.v
W=/tmp/kx/r110_attrib          # bash 用这个
WM=$(cygpath -m "$W")           # 原生件（node / vivado）只认 Windows 形
[ -n "$WM" ] || { echo "ATTR-REFUSE: cygpath 没给出 $W 的 Windows 形"; exit 2; }
rm -rf "$W"; mkdir -p "$W" || { echo "ATTR-REFUSE: 建不起 $W"; exit 2; }

for leg in base cut; do
    mkdir -p "$W/$leg/src/rtl/eth"
    cp "$RTL" "$W/$leg/src/rtl/eth/"
done

# 只取补丁里 frame_reasm 那一段：刀 1 那半在拷贝树里没有它的前提，留着会让整份补丁失败
node -e '
const fs=require("fs");
const t=fs.readFileSync(process.argv[2],"utf8").replace(/\r\n/g,"\n");
const keep=t.split(/^(?=diff --git )/m).filter(p=>p.startsWith("diff --git a/src/rtl/eth/frame_reasm.v"));
if(keep.length!==1){ console.log("SPLIT expected exactly 1 frame_reasm section, got "+keep.length); process.exit(2); }
fs.writeFileSync(process.argv[3], keep[0]);
console.log("SPLIT ok bytes="+keep[0].length);
' x "$PATCH" "$W/cut_reasm.patch" || { echo "ATTR-REFUSE: 补丁里切不出 frame_reasm 那一段"; exit 2; }

( cd "$W/cut" && git apply -p1 --ignore-whitespace "$W/cut_reasm.patch" ) \
    || { echo "ATTR-REFUSE: cut 腿打刀失败（git apply 非 0）"; exit 2; }

# 断言：cut 腿必须真的和 base 不一样（忘打刀 = 白跑两遍综合）。
# ⚠ `git apply` 会顺手把整份文件的行尾换掉 ⇒ 直接 diff 会得到"1,218c1,222"这种全文件差异，
#   那等于尺子说谎；所以比对时吃掉 CR，并**数差异行数**设上限（只许行覆盖那一段动）。
diff --strip-trailing-cr "$W/base/src/rtl/eth/frame_reasm.v" "$W/cut/src/rtl/eth/frame_reasm.v" > "$W/diff.txt"
[ -s "$W/diff.txt" ] || { echo "ATTR-REFUSE: 两腿一模一样，打刀没生效"; exit 2; }
NCH=$(grep -cE '^[<>]' "$W/diff.txt")
[ "$NCH" -le 40 ] || { echo "ATTR-REFUSE: 差异 $NCH 行 > 40 —— 打刀打到了别处，停手"; exit 2; }
[ "$(grep -c 'new_row_w' "$W/cut/src/rtl/eth/frame_reasm.v")" -ge 3 ] \
    && [ "$(grep -c 'new_row_w' "$W/base/src/rtl/eth/frame_reasm.v")" -eq 0 ] \
    || { echo "ATTR-REFUSE: 独热化那几行没进 cut 腿（或还在 base 腿里）"; exit 2; }
echo "ATTR-DIFFOK 差异行=$NCH（上限 40）cut 有 new_row_w、base 没有"

run_leg () {   # $1=腿名
    local leg=$1 dir rpt lut ff
    dir="$W/$leg/run"; mkdir -p "$dir"
    ( cd "$dir" && "$V/vivado" -mode batch -nojournal -log viv.log \
        -source "$ROOT/build/tcl/ooc_util_probe.tcl" \
        -tclargs "$WM/$leg/src/rtl/eth" frame_reasm "$WM/$leg/run/util.rpt" > console.txt 2>&1 )
    rpt="$dir/util.rpt"
    [ -s "$rpt" ] || { echo "ATTR $leg NO-REPORT 读 $dir/viv.log"; return 1; }
    grep -aE "Slice LUTs|Slice Registers|Block RAM Tile|LUT as Memory" "$rpt" | sed "s/^/  $leg /"
    # 行形状（实测 util.rpt:34-37）：`| Slice LUTs*             |  737 |     0 | ... |`
    # ⇒ 取第一列数字用 awk 按竖线切，不用 sed 的贪心匹配（`.*\|` 会一路吞到最后一个竖线）
    lut=$(awk -F'|' '/Slice LUTs/ {gsub(/[^0-9]/,"",$3); if ($3!="") {print $3; exit}}' "$rpt")
    ff=$(awk -F'|' '/Slice Registers/ {gsub(/[^0-9]/,"",$3); if ($3!="") {print $3; exit}}' "$rpt")
    [ -n "$lut" ] && [ -n "$ff" ] || { echo "ATTR $leg PARSE-FAIL lut='$lut' ff='$ff'（读 $rpt 的形状再改式子，不许蒙）"; return 1; }
    # ⚠ 只能 eval：`ATTR_$1_LUT=$lut` 里 bash 在展开前判定它不是赋值 ⇒ 整行当命令跑（#244 同一族）
    eval "ATTR_${leg}_LUT=$lut"; eval "ATTR_${leg}_FF=$ff"
    echo "ATTR $leg LUT=$lut FF=$ff"
    return 0
}

run_leg base || exit 1
run_leg cut  || exit 1
DL=$((ATTR_cut_LUT - ATTR_base_LUT)); DF=$((ATTR_cut_FF - ATTR_base_FF))
echo "ATTR-DELTA 刀4①：LUT=$DL FF=$DF（base=$ATTR_base_LUT cut=$ATTR_cut_LUT）"
echo 'ATTR 口径：设计里 r110 相对 r109 是 -243 LUT，凭据 build/evidence/r110_notadopted/utilization.rpt；'
echo '           这一条只量刀 4① 自己。|ATTR-DELTA| 远小于 243 ⇒ 那笔账不在这把刀上，r110 维持不采纳。'

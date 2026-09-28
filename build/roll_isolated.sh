#!/bin/bash
# 滚一轮构建，但**不碰 build/ 里那套被门禁与文档引用的产物**（r84 那轮的教训）。
#
# 为什么要它：夜里想做"第二轮遍历代码"的时序/资源对账，可 `build/system.bit` 一旦变旧，
# ① 板子上那块与树里那份就对不上号，② `board_verify.sh` 开头打印的三件套 md5 会与屏上跑的
# 不是同一块，③ 早上验收的人无从判断"板上是哪一版"。所以把产物写到旁边一个目录去。
#
# 做法只有一件事：**不复制那 300 行构建脚本**（两份同样的脚本必然漂），而是原地用 sed 把
# `set outdir [file join $root build]` 换成隔离目录，临时脚本仍放在 build/tcl/ 里 ——
# 因为脚本里的 `root` 是按自己所在位置往回两级算的，换个目录就会指向别处。
# 跑法与正式构建一致：
#   bash build/roll_isolated.sh            # 产物落在 build/isolated_<时间戳>/
#   OUT=mydir bash build/roll_isolated.sh
# 2026-09-29 02:49 的 r85 那一轮就是这么跑的（当时 sed 是手敲的，脚本化的是同一条）。
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
SRC=build/tcl/build_system_axigpio.tcl
OUT=${OUT:-build/isolated_$(date +%m%d_%H%M)}
TMP=build/tcl/_tmp_isolated_roll.tcl

[ -f "$SRC" ] || { echo "REFUSE: 找不到 $SRC"; exit 1; }
# 工具路径只有一个说法：VP_VIVADO_BIN 指到 <Vivado>/bin（见 docs/BUILD.md「换一台机器」那一节）。
# 默认值留着是为了本机少敲一步，**不是**"这台机器就是标准"：找不到 xvlog 就明说并退出，
# 别让人对着一句 "No such file or directory" 去怀疑 RTL。
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
[ -x "$V/xvlog" ] || { echo "REFUSE: 找不到 xvlog（当前 $V）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（docs/BUILD.md）"; exit 2; }
sed 's#^set outdir \[file join \$root build\]$#set outdir [file join $root '"$OUT"']#' "$SRC" > "$TMP"
# 改不动就停：正式脚本哪天换了写法，这条 sed 会**静默不匹配**，于是一轮构建就把 build/ 覆盖了。
grep -q "file join \$root $OUT" "$TMP" || { echo "REFUSE: outdir 那一行没被改写（正式脚本的写法变了，先去看一眼）"; rm -f "$TMP"; exit 1; }

mkdir -p "$OUT"
echo "产物目录：$OUT（build/ 里那套不动）"
"$V/vivado.bat" -mode batch -nojournal -source "$TMP" 2>&1 | tee "${OUT%/}/build_console.txt" | tail -6
rm -f "$TMP"
grep -qa "SYSTEM BUILD DONE" "${OUT%/}/build_console.txt" \
  && echo "ROLL DONE -> $OUT（$OUT/system.bit md5=$(md5sum "$OUT/system.bit" 2>/dev/null | cut -c1-12)）" \
  || echo "ROLL NOT PROVEN：控制台里没有 SYSTEM BUILD DONE，别看数字，先看日志"

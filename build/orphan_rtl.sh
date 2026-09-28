#!/bin/bash
# build/orphan_rtl.sh —— 一次算出"声明了但没进这一版位流"的 RTL，并给出可删性分类
#
# 为什么用**综合日志**当 oracle 而不是 grep 例化名（这条是本脚本存在的全部理由）：
# 我先用 grep 找"`模块名` 后面跟 (`或 `#(`"的行，结果是**错的**：
#   · 行首的直接例化（`frame_buffer u_fb (`）要求前面有一个非单词字符 ⇒ 整行漏掉；
#   · 反过来注释里提到一个名字又会**假命中**。
# 两边都错过之后，`icmp_tx` 被判成"没人例化"，而它其实就在 `icmp.v` 里 —— 差一点就把
# 一个在用的模块写进"可删"清单。综合器不会撒这个谎：
#   `INFO: [Synth 8-6157] synthesizing module 'X'` 只对**从顶层可达**的模块出，
#   没被例化的文件即使被 `add_files` 收了、被 xvlog 分析了，也**不会**出这一行。
#
# 用法：
#   bash build/orphan_rtl.sh [build/evidence_rNN/rNN_build_console.txt]
#   bash build/orphan_rtl.sh --selftest
# 口径：报告的是"**这一版构建**里没有"，不是"永远没用"—— 别的顶层、
# 以及台架的被测对象都会落在"没进位流"里，所以下面按**去向**分类，不许直接读成"删掉它"。
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
SRC_RTL=${ORPH_RTL_SRC:-src/rtl}
TB=${ORPH_RTL_TB:-sim}

selftest() {
    local T=${TMPDIR:-/tmp}/orphan_self.$$ nbad=0 out
    mkdir -p "$T/src/rtl/a" "$T/src/rtl/b" "$T/sim" "$T/build"
    printf 'module used_a;\nendmodule\n'   > "$T/src/rtl/a/used_a.v"
    printf 'module dead_b;\nendmodule\n'   > "$T/src/rtl/b/dead_b.v"
    printf 'module tb_only;\nendmodule\n'  > "$T/src/rtl/b/tb_only.v"
    printf 'used_a u1();\ntb_only u2();\n' > "$T/sim/tb_only.v"     # 台架里例化 tb_only/used_a
    { echo "INFO: [Synth 8-6157] synthesizing module 'used_a' [<file>:1]"; } > "$T/console.txt"
    # ⚠ 三个路径必须是**绝对**的：本脚本一进来就 `cd $ROOT`（真仓库），传相对名的话子进程扫的是
    #   真树，fixture 形同不存在 ⇒ "selftest 绿"就成了假绿。
    out=$(ORPH_RTL_SRC="$T/src/rtl" ORPH_RTL_TB="$T/sim" \
          bash "$0" --no-gate "$T/console.txt" 2>&1)
    chk() { echo "$out" | grep -q "$1" || { echo "SELFTEST FAIL $2: 没有这一行 [$1]"; nbad=1; }; }
    has() { echo "$out" | grep -q "$1" && { echo "SELFTEST FAIL $2: 出现了不该出现的 [$1]"; nbad=1; }; }
    chk "dead_b" 1                       # 谁也没提它 ⇒ 该报
    has "used_a" 2                        # 进了位流 ⇒ 不该报
    chk "tb_only.*台架" 3                  # 没进位流，但被台架例化 ⇒ 归"别处"
    # 反例：空/不含 oracle 行的日志必须**拒绝出表**（拿空集合当"全都没用"是最坏的一种绿）
    : > "$T/empty.txt"
    ORPH_RTL_SRC=src/rtl bash "$0" "$T/empty.txt" >/dev/null 2>&1
    [ $? -ne 0 ] || { echo "SELFTEST FAIL 4: 空日志被当成'这些模块全没用'（地板判据没生效）"; nbad=1; }
    rm -rf "$T"
    [ "$nbad" = 0 ] && echo "SELFTEST PASS 4/4：报出真孤儿、不报在用的、台架归去向、空日志拒绝出表"
    exit $nbad
}

GATE=1
LOG=build/evidence_r75/r75_build_console.txt
for a in "$@"; do
    [ "$a" = "--selftest" ] && selftest
    [ "$a" = "--no-gate" ] && GATE=0
done
for a in "$@"; do case "$a" in --*) ;; *) [ -f "$a" ] && LOG="$a";; esac; done

# ⚠ 不能写 `N=$(grep -c … || echo 0)`：`grep -c` 在"没有匹配"时**既打印 0 又返回非零**，
#   那两个 0 会拼成 "0\n0" ⇒ `[ "$N" -lt 50 ]` 报"不是整数"并把地板判据整个跳过
#   （selftest 第 5 条抓住的就是它 —— 空日志于是被当成"这些模块全没用"）。
N=$(grep -c "synthesizing module '" "$LOG" 2>/dev/null); N=${N:-0}
if [ "$GATE" = 1 ] && [ "$N" -lt 50 ]; then
    echo "FATAL：$LOG 里只有 $N 行 \"synthesizing module\"（地板 50）——"
    echo "       没有可达性 oracle 就不能出这张表：拿空集合去比，**每一个**模块都会被判成'没用'。"
    echo "       （这一条就是本脚本存在的理由：错的 oracle 比没有 oracle 更危险。）"
    exit 1
fi
echo "# 出处：$LOG（$N 行 synthesis 记录）"

grep -oP "synthesizing module '\K\w+" "$LOG" | LC_ALL=C sort -u > /tmp/_orph_s.txt
grep -rhoP '^\s*module\s+\K\w+' "$SRC_RTL" --include=*.v | LC_ALL=C sort -u > /tmp/_orph_d.txt
echo "# 声明 $(wc -l < /tmp/_orph_d.txt) 个模块，其中 **$N 行**综合记录覆盖 $(wc -l < /tmp/_orph_s.txt) 个名字"
echo "# 没进这一版位流的："
while read -r m; do
    [ -z "$m" ] && continue
    f=$(grep -rl "^[[:space:]]*module[[:space:]]\+$m\b" "$SRC_RTL" --include=*.v | head -1)
    ln=$(wc -l < "$f" 2>/dev/null || echo '?')
    tb=$(grep -rlw "$m" "$TB" --include=*.v 2>/dev/null | wc -l)
    tc=$(grep -rlw "$m" build/tcl --include=*.tcl 2>/dev/null | wc -l)
    why="**没人引用（唯一可考虑删的一档）**"
    [ "$tb" -gt 0 ] && why="$why；台架引用 tb=$tb"
    [ "$tc" -gt 0 ] && why="另一个顶层/构建脚本点名（tcl=$tc）⇒ 不删"
    printf '  %-24s %5s 行  %s\n' "$m" "$ln" "$why"
done < <(comm -23 /tmp/_orph_d.txt /tmp/_orph_s.txt)

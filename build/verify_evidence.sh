#!/bin/bash
# build/verify_evidence.sh <NN|目录> [--self] —— 校验一个冻结目录的凭据章，并把"章量的是什么"说清。
#
# 为什么要它（台账 #202 的尾巴 #148）：`MANIFEST.md5` 一直是按**磁盘字节**盖章的（`md5sum`），
# 而 `.gitattributes` 故意没钉 `*.txt`/`*.log` 的换行 ⇒ 一次 `git checkout` 就可能把已盖章件
# 的字节改成 CRLF，内容一字未动、章却全漂（2026-09-30 夜门禁第 15/15 项就红在这个形状上）。
# 260/400 份跟踪的 `.txt` 现在就是"只差 CR"的状态。
#
# 所以这里同时认两枚章：
#   MANIFEST.md5         v1 = 磁盘字节（历史冻结件只有这枚，也永远能验）
#   MANIFEST.content.md5 v2 = 先 `tr -d '\r'` 再取 md5（换行不敏感；新冻结件才有）
# 用法：
#   bash build/verify_evidence.sh 75          # 验 build/evidence_r75/
#   bash build/verify_evidence.sh --self      # 判据自己的反例（不碰真凭据）
# 退出码：0 = 该目录至少有一枚章逐份对上且无一件不符；1 = 有不符/缺件；2 = 用不了（目录或章缺失、计数为 0）。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT" || exit 2

seal_lines() { grep -E '^[0-9a-f]{32} [ *]' "$1" 2>/dev/null | sed -E 's/^[0-9a-f]{32} [. *]?//'; }
check_one() { # $1 = 目录  $2 = 章文件  $3 = mode bytes|content
    local d=$1 m=$2 mode=$3 n=0 bad=0 f h a
    [ -f "$d/$m" ] || { echo "  （没有 $m，跳过）"; return 3; }
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$d/$f" ] || { echo "  MISSING $f"; bad=$((bad+1)); n=$((n+1)); continue; }
        h=$(awk -v F="$f" '$0 ~ ("[* ]" F "$") {print $1; exit}' "$d/$m")
        if [ "$mode" = bytes ]; then a=$(md5sum "$d/$f" | cut -c1-32); else a=$(tr -d '\r' < "$d/$f" | md5sum | cut -c1-32); fi
        n=$((n+1))
        [ "$a" = "$h" ] || { echo "  MISMATCH($mode) $f"; bad=$((bad+1)); }
    done < <(seal_lines "$d/$m")
    echo "  $m[$mode] 逐份比了 $n 件，不符 $bad 件"
    [ "$n" -gt 0 ] || { echo "  FATAL $m 里一件都没比到 —— 章是空的不能算过"; return 2; }
    [ "$bad" -eq 0 ] || return 1
    return 0
}

# 覆盖度（advisory，不参与判定）：章比了几件、目录里有几件，两个数必须一起念出来。
#   只看「不符 0 件」会空过——r75 的字节章只点名 11 件，目录里却有 20 件（#192 之前 freeze 用另一份名单盖章），
#   那 9 件被改动也看不出来。新的冻结件由 freeze_evidence.sh 的 NLANDED/NSEALED 不相等即 REFUSE 兜住，
#   这里只负责把数说出来：历史件非 0 是已知形状，不是红。
coverage() { # $1 = 目录  $2 = 章文件（可缺）
    local d=$1 m=${2:-MANIFEST.md5} ndir nsealed nun
    ndir=$( { cd "$d" && find . -type f ! -name 'MANIFEST.md5' ! -name 'MANIFEST.content.md5' | grep -c '' || true; } ); ndir=${ndir:-0}
    if [ -f "$d/$m" ]; then nsealed=$(seal_lines "$d/$m" | grep -c '' || true); else nsealed=0; fi
    nsealed=${nsealed:-0}
    nun=$((ndir - nsealed)); [ "$nun" -lt 0 ] && nun=0
    echo "  覆盖：目录 $ndir 件 / $m 点名 $nsealed 件 ⇒ 不在章内 $nun 件（advisory，不判红）"
    [ "$nun" -eq 0 ] && return 0
    return 1
}

self_test() {
    local t rc fails=0
    t=$(mktemp -d); mkdir -p "$t/frozen_x"; cd "$t/frozen_x" || exit 2
    printf 'alpha\r\nbeta\r\n' > a.txt; printf 'GATE PASS\r\n' > b.txt; printf '\x01\x02binary' > c.bit
    ( cd "$t/frozen_x" && md5sum a.txt b.txt c.bit > MANIFEST.md5
      cd "$t/frozen_x" && for f in a.txt b.txt c.bit; do printf '%s  %s\n' "$(tr -d '\r' < "$f" | md5sum | cut -c1-32)" "$f"; done > MANIFEST.content.md5 )
    echo "S1 原样两枚章都该过"; check_one "$t/frozen_x" MANIFEST.md5 bytes && check_one "$t/frozen_x" MANIFEST.content.md5 content || fails=$((fails+1))
    echo "S2 把 .txt 换成 LF（内容不变、字节变）：v1 必须红、v2 必须绿（这就是 #148 的那把尺子有牙）"
    printf 'alpha\nbeta\n' > a.txt
    check_one "$t/frozen_x" MANIFEST.md5 bytes >/dev/null 2>&1; rc=$?
    [ "$rc" = 1 ] && echo "  v1 如期望判红" || { echo "  FAIL v1 没判红（rc=$rc）"; fails=$((fails+1)); }
    check_one "$t/frozen_x" MANIFEST.content.md5 content || { echo "  FAIL v2 该过而没过"; fails=$((fails+1)); }
    echo "S3 改一个字节：v2 也必须红"; printf 'alphX\r\nbeta\r\n' > a.txt
    check_one "$t/frozen_x" MANIFEST.content.md5 content >/dev/null 2>&1; rc=$?
    [ "$rc" = 1 ] && echo "  如期望判红" || { echo "  FAIL 改字符没被判出（rc=$rc）"; fails=$((fails+1)); }
    echo "S4 少一件（章里点名、盘上没有）必须红"; printf 'alpha\r\nbeta\r\n' > a.txt; rm -f b.txt
    check_one "$t/frozen_x" MANIFEST.md5 bytes >/dev/null 2>&1; rc=$?
    [ "$rc" = 1 ] && echo "  如期望判红" || { echo "  FAIL 缺件没被判出（rc=$rc）"; fails=$((fails+1)); }
    echo "S5 空章（只有一行说明、没有一枚章）必须拒绝，不许空过"
    printf '# 只有说明文字\n' > "$t/frozen_x/MANIFEST.md5"; touch "$t/frozen_x/MANIFEST.content.md5"
    check_one "$t/frozen_x" MANIFEST.md5 bytes >/dev/null 2>&1; rc=$?
    [ "$rc" = 2 ] && echo "  如期望拒绝（rc=2）" || { echo "  FAIL 空章没被拒（rc=$rc）"; fails=$((fails+1)); }
    echo "S6 覆盖度：目录多一件没盖章的件，那行数必须从 0 变成 1（r75 就是这个形状）"
    printf 'GATE PASS\r\n' > b.txt
    printf 'alpha\r\nbeta\r\n' > a.txt
    md5sum a.txt b.txt c.bit > MANIFEST.md5
    for f in a.txt b.txt c.bit; do printf '%s  %s\n' "$(tr -d '\r' < "$f" | md5sum | cut -c1-32)" "$f"; done > MANIFEST.content.md5
    coverage "$t/frozen_x" MANIFEST.md5 >/dev/null; rc=$?
    [ "$rc" = 0 ] && echo "  齐全时候为 0" || { echo "  FAIL 齐全的目录被判成有漏（rc=$rc）"; fails=$((fails+1)); }
    printf 'extra\r\n' > d.txt
    coverage "$t/frozen_x" MANIFEST.md5 | sed 's/^/    /'; rc=${PIPESTATUS[0]}
    [ "$rc" = 1 ] && echo "  如期望：多一件未盖章 ⇒ 非 0" || { echo "  FAIL 漏盖章没被念出来（rc=$rc）"; fails=$((fails+1)); }
    md5sum a.txt b.txt c.bit d.txt > MANIFEST.md5
    coverage "$t/frozen_x" MANIFEST.md5 >/dev/null; rc=$?
    [ "$rc" = 0 ] && echo "  如期望：补进章里就回 0（这把尺子能动）" || { echo "  FAIL 补章后仍非 0（rc=$rc）"; fails=$((fails+1)); }
    cd /; rm -rf "$t"
    [ "$fails" -eq 0 ] && { echo "SELF PASS verify_evidence（六条对照都按期望动）"; return 0; }
    echo "SELF FAIL verify_evidence（$fails 条不如期望）"; return 1
}

if [ "${1:-}" = "--self" ]; then self_test; exit $?; fi
[ -n "${1:-}" ] || { echo "用法：bash build/verify_evidence.sh <NN|目录> | --self"; exit 2; }
D=$1; case "$D" in */*) [ -d "$D" ] || D="build/evidence_r$1";; *) D="build/evidence_r$1";; esac
[ -d "$D" ] || { echo "找不到冻结目录 $D"; exit 2; }
echo "校验 $D："
r1=3; r2=3
check_one "$D" MANIFEST.md5 bytes; r1=$?
if [ -f "$D/MANIFEST.content.md5" ]; then check_one "$D" MANIFEST.content.md5 content; r2=$?; else echo "  （无 v2 内容章：这一版是 ${D} 上只有字节章的老形状）"; fi
if [ -f "$D/MANIFEST.md5" ]; then COVSEAL=MANIFEST.md5; else COVSEAL=MANIFEST.content.md5; fi
coverage "$D" "$COVSEAL"
echo "  （覆盖度是提示项：新冻结件该为 0，由 freeze_evidence.sh 的 REFUSE 保证；r75 这类历史件非 0 是已知形状）"
if [ "$r1" = 0 ] || [ "$r2" = 0 ]; then echo "VERIFY PASS $D（至少一枚章逐份对上）"; exit 0; fi
if [ "$r1" = 3 ] && [ "$r2" = 3 ]; then echo "VERIFY 无从判断：$D 里没有可认的章"; exit 2; fi
echo "VERIFY RED $D：两枚章都对不上（先问是不是 checkout 翻了换行，再问内容是否真的变了）"; exit 1

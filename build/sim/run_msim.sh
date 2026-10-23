#!/bin/bash
# ModelSim 快速回归：run_msim.sh <tb1> [tb2 ...]
# 只编译 src/rtl/eth + sim/prim + 指定台架（frame_reasm / UDP 链这一族用）。
# 输出落在 build/msim/：compile.log、<tb>.log；判定行照旧 PAS/FAIL 由台架自己打。
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MS=${MSIM_BIN:-}
[ -n "$MS" ] || { echo "REFUSE: 设 MSIM_BIN 指到 ModelSim 的 win64（或 Linux）目录"; exit 2; }
for e in vlib vlog vsim; do
    [ -x "$MS/$e.exe" ] || [ -x "$MS/$e" ] || { echo "REFUSE: $MS/$e(.exe) 不存在（设 MSIM_BIN）"; exit 2; }
done
[ $# -ge 1 ] || { echo "usage: run_msim.sh <tb> [...]"; exit 2; }

OUT="$ROOT/build/msim"
mkdir -p "$OUT"
cd "$OUT" || exit 2
rm -rf work
"$MS/vlib" work > /dev/null 2>&1 || { echo "VLIB FAILED"; exit 2; }

SRC=()
for d in eth video util axi clocks process process/rotate process/zoom process/bilin hdmi top; do
    while IFS= read -r f; do SRC+=("$f"); done < <(find "$ROOT/src/rtl/$d" -maxdepth 1 -name '*.v' | sort)
done
while IFS= read -r f; do SRC+=("$f"); done < <(find "$ROOT/sim/prim" -maxdepth 1 -name '*.v' | sort)
for tb in "$@"; do SRC+=("$ROOT/sim/tb_$tb.v"); done

"$MS/vlog" -sv -work work "${SRC[@]}" > compile.log 2>&1
if [ $? -ne 0 ]; then
    echo "VLOG FAILED — 见 $OUT/compile.log"
    grep -aE "Error|error" "$OUT/compile.log" | head -20
    exit 2
fi

nfail=0
for tb in "$@"; do
    echo "==== $tb ===="
    "$MS/vsim" -c -work work "work.tb_$tb" ${MSIM_PLUSARGS:-} -do "run -all; quit -f" -l "$tb.log" > /dev/null 2>&1
    grep -aE "^#? *(PASS|FAIL)|^#? ?RESULT|^#? ?TB RESULT" "$tb.log" | tail -8
    if grep -aqE "^#? *FAIL|^#? ?RESULT .*FAIL|^#? ?TB RESULT FAIL" "$tb.log"; then
        echo "RESULT $tb FAIL"
        nfail=$((nfail + 1))
    elif grep -aqE "^#? *PASS|^#? ?RESULT .*PASS|^#? ?TB RESULT PASS" "$tb.log"; then
        echo "RESULT $tb PASS"
    else
        echo "RESULT $tb NO_ASSERT（判失败）"
        nfail=$((nfail + 1))
    fi
done
echo "MSIM DONE fail=$nfail"
exit $((nfail == 0 ? 0 : 1))

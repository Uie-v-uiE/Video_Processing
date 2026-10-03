#!/usr/bin/env bash
# build/check_powup_init.sh —— 判据：位流上电值必须等于代码想要的复位值（#256 那条根因的落地尺子）
#
# 为什么单独一把尺子：#256 的因果链是"`system_top.v` 把 sys_rst_n 恒接 1'b1 ⇒ `if (!rst_n)` 是死支
#   ⇒ 综合把复位摘掉 ⇒ FF 的上电值只剩位流 INIT ⇒ 代码写 1、网表给 0"。
#   台架（tb_v113_key_powup）判的是**RTL 语义**，它看不见网表里那位 INIT；
#   只有 open_checkpoint 问 `get_property INIT` 才算摸到硅片那一侧。两把尺子各管一半，缺一个都不成立。
# 判据都是"一行一条、末列是判定"（规矩 40），并且每条都带计数地板（规矩 38：空转的尺子会全绿）。
# 用法：
#   ROUND=r113 bash build/check_powup_init.sh            # 问盘上那两份 dcp
#   bash build/check_powup_init.sh --self                # 变异对照：INIT=0 的假日志必须判红
set -u
cd "$(dirname "$0")/.."
mkdir -p /tmp/kx
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
ROUND=${ROUND:-r113}
FLOOR=${FLOOR:-20}
OUT="build/evidence/${ROUND}_ff_init_probe.txt"
VERD="build/evidence/${ROUND}_powup_init_check.txt"
say() { printf '%s\n' "$*"; }

if [ "${1:-}" = "--self" ]; then
    # 自我检查：一份"修好了"的日志要绿，一份"没修"的日志必须红 —— 尺子不能只会念 PASS。
    good() {
        printf '%s\n' \
            "===== STAGE synth  DCP /tmp/fake.dcp =====" \
            "FF u_pl/u_k1/key_stable_reg TYPE=FDRE INIT=1'b1 RST_USED=0" \
            "FF u_pl/u_k1/key_sync0_reg TYPE=FDRE INIT=1'b1 RST_USED=0" \
            "FF u_pl/u_k1/key_sync1_reg TYPE=FDRE INIT=1'b1 RST_USED=0" \
            "FF u_pl/u_k1/key_prev_reg TYPE=FDRE INIT=1'b1 RST_USED=0" \
            "FF u_pl/u_ang/angle_reg[0] TYPE=FDRE INIT=1'b0 RST_USED=0" \
            "FF u_pl/u_k1/cnt_reg[0] TYPE=FDRE INIT=1'b0 RST_USED=0" \
            "FF u_pl/u_k1/acnt_reg[0] TYPE=FDRE INIT=1'b0 RST_USED=0" \
            "FF u_pl/u_k1/armed_reg TYPE=FDRE INIT=1'b0 RST_USED=0" \
            "FF u_pl/u_k1l/fired_reg TYPE=FDRE INIT=1'b0 RST_USED=0" \
            "FF u_pl/u_k1l/cnt_reg[0] TYPE=FDRE INIT=1'b0 RST_USED=0" \
            "FF u_pl/u_k2/key_stable_reg TYPE=FDRE INIT=1'b1 RST_USED=0" \
            "FF u_pl/u_ang/fs_s_reg[0] TYPE=FDRE INIT=1'b0 RST_USED=0" \
            "COMPARED=12"
    }
    bad() { good | sed "s/u_k1\/key_stable_reg TYPE=FDRE INIT=1'b1/u_k1\/key_stable_reg TYPE=FDRE INIT=1'b0/"; }
    chk_self() { # $1=日志 $2=期望 $3=标签 $4=期望读到的 FF 行数（管道没送进去时这条必须红，见 #256 工具账）
        local f=/tmp/kx/powup_fixture.txt out got nfl
        printf '%s\n' "$1" > "$f"
        out=$(bash build/check_powup_init.sh --parse < "$f" 2>/dev/null)
        got=$(printf '%s\n' "$out" | grep -a '^POWUP-SUMMARY' | tail -1 | sed 's/.*result=//' | tr -d '\r')
        nfl=$(printf '%s\n' "$out" | grep -a '^POWUP round=' | head -1 | sed -E 's/.*ff_lines=([0-9]+).*/\1/')
        printf '%s\n' "$out" | grep -a '^POWUP ' | sed 's/^/    SELFDETAIL /'
        if [ "$got" = "$2" ] && [ "$nfl" = "$4" ]; then say "SELF $3 expected=$2 got=$got ff_lines=$nfl/$4 PASS"
        else say "SELF $3 expected=$2 got=$got ff_lines=$nfl/$4 FAIL"; return 1; fi
    }
    n_good_cells=$(good | grep -c '^FF ')
    # 计数地板用真值：fixture 里 FF 行不足 12 就说明这份对照自己空转了
    [ "$n_good_cells" -ge 12 ] || { say "SELF fixture_floor cells=$n_good_cells FAIL"; exit 1; }
    say "SELF fixture_floor cells=$n_good_cells PASS"
    export FLOOR=$n_good_cells   # 子进程（--parse）用同一把地板，否则 fixture 会被真地板判红
    r=0
    chk_self "$(good)" "GREEN" "positive_control_fixed" "$n_good_cells" || r=1
    chk_self "$(bad)" "RED" "mutation_k1_unfixed"       "$n_good_cells" || r=1
    chk_self "$(good | sed "s/u_k2\/key_stable_reg TYPE=FDRE INIT=1'b1/u_k2\/key_stable_reg TYPE=FDRE INIT=1'b0/")" \
             "RED" "mutation_k2_unfixed" "$n_good_cells" || r=1
    # 反向对照：angle 那颗复位值本来就是 0 ⇒ 谁把它读成 1 就是尺子在编数
    chk_self "$(good | sed "s/u_ang\/angle_reg\[0\] TYPE=FDRE INIT=1'b0/u_ang\/angle_reg[0] TYPE=FDRE INIT=1'b1/")" \
             "RED" "mutation_angle_control" "$n_good_cells" || r=1
    chk_self "$(good | sed 's/STAGE synth/STAGE impl/')" "RED" "wrong_stage_only" "0" || r=1
    [ $r -eq 0 ] && say "SELF powup_init_check 对照 5/5 全过 PASS" || say "SELF powup_init_check FAIL"
    exit $r
fi

if [ "${1:-}" = "--parse" ]; then
    # 只解析 stdin 给的探针文本，不落任何文件（--self 走这条路，避免覆盖真凭据）
    cat > /tmp/kx/powup_stdin.txt
    SRC=/tmp/kx/powup_stdin.txt
    PARSE_ONLY=1
else
    [ -d /tmp/kx ] || mkdir -p /tmp/kx
    [ -f "$V/vivado.bat" ] || { say "REFUSE no Vivado VP_VIVADO_BIN=$V"; exit 2; }
    say "PROBE run probe_ff_init.tcl -> $OUT"
    "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_ff_init.tcl > "$OUT" 2>&1
    P=$?
    [ $P -eq 0 ] || say "PROBE rc=$P （非 0 也继续解析：探针里的 REFUSE 行本身就是信息）"
    SRC="$OUT"
    PARSE_ONLY=0
fi

# 归档，绝不让这一把尺子的固定输出名覆盖上一轮唯一快照（规矩 17）
if [ $PARSE_ONLY -eq 0 ] && [ -f "$OUT" ]; then
    prev=$(ls -t build/evidence/*_ff_init_probe.txt 2>/dev/null | sed -n '2p' || true)
    [ -n "${prev:-}" ] || prev=$(ls -t build/evidence/*_ff_init.txt 2>/dev/null | sed -n '2p' || true)
    if [ -n "${prev:-}" ] && [ "$prev" != "$OUT" ]; then
        say "ARCHIVE 上一份探针文本 = $prev（md5 $(md5sum < "$prev" | cut -c1-12)）"
    fi
fi

STAGE="synth"   # 只看综合后那一段：INIT 属性从综合一路带到位流，布线后不该变
awk -v stage="$STAGE" '
    /^===== STAGE /{ cur=$3 }
    cur==stage && /^FF /{ print }
' "$SRC" > /tmp/kx/powup_ff.txt 2>/dev/null

NFF=$(grep -c '^FF ' /tmp/kx/powup_ff.txt)
CMP=$(grep -a '^COMPARED=' "$SRC" | head -1 | tr -d '\r' | sed 's/COMPARED=//' | tr -dc '0-9')
[ -n "$CMP" ] || CMP=0

prop() { grep -aF "FF $1 " /tmp/kx/powup_ff.txt | head -1 | sed -E 's/.*INIT=([^ ]*).*/\1/' | tr -d '\r'; }
has() { grep -qaF "FF $1 " /tmp/kx/powup_ff.txt; }

R=0
mkdir -p /tmp/kx
: > /tmp/kx/powup_lines.txt
say "POWUP round=$ROUND stage=$STAGE ff_lines=$NFF probed=${SRC}"
line() { printf 'POWUP %-26s %-14s %s %s\n' "$1" "$2" "$3" "$4" | tee -a /tmp/kx/powup_lines.txt; [ "$4" = RED ] && R=1; return 0; }

# 1) 修好的那颗：key_stable 上电必须是 1（=松着）。这是 #256 的直接判据。
V1=$(prop "u_pl/u_k1/key_stable_reg")
if has "u_pl/u_k1/key_stable_reg"; then
    [ "$V1" = "1'b1" ] && line W1_key_stable "$V1" "expect=1'b1" GREEN || line W1_key_stable "$V1" "expect=1'b1" RED
else
    line W1_key_stable "NO_CELL" "cell_missing" RED
fi

# 2) 同模块里另外三颗"代码想要 1"的寄存器（同步器 + key_prev），方向必须一致
N1=0; N1T=0
for c in key_sync0_reg key_sync1_reg key_prev_reg; do
    has "u_pl/u_k1/$c" || continue
    N1T=$((N1T+1))
    [ "$(prop "u_pl/u_k1/$c")" = "1'b1" ] && N1=$((N1+1))
done
[ "$N1T" -ge 3 ] && [ "$N1" -eq "$N1T" ] \
    && line W2_sync_prev "$N1/$N1T" "all=1'b1" GREEN || line W2_sync_prev "$N1/$N1T" "want_3_of_3" RED

# 3) k2 那一颗同族（两个键都要对，不能只修被看着的那一个）
V3=$(prop "u_pl/u_k2/key_stable_reg")
if has "u_pl/u_k2/key_stable_reg"; then
    [ "$V3" = "1'b1" ] && line W3_k2_stable "$V3" "expect=1'b1" GREEN || line W3_k2_stable "$V3" "expect=1'b1" RED
else
    line W3_k2_stable "NO_CELL" "cell_missing" RED
fi

# 4) 反向对照（positive control 必须能动）：angle 的复位值是 0 ⇒ INIT 必须真的是 0。
#    这条如果绿不了，说明这一把尺子在把所有 INIT 都读成 1，前三条的绿就是假的。
V4=$(prop "u_pl/u_ang/angle_reg[0]")
[ "$V4" = "1'b0" ] && line W4_angle_control "$V4" "expect=1'b0" GREEN || line W4_angle_control "$V4" "expect=1'b0" RED

# 5) 计数地板：探针若一条 FF 都没问到（名字全变、dcp 没开），上面几条会 NO_CELL 判红，
#    但 COMPARED 也要念出来 —— 空转的尺子不能只有"缺行"这一种死法。
[ "$CMP" -ge "$FLOOR" ] && [ "$NFF" -ge "$FLOOR" ] \
    && line W5_scope_floor "FF=$NFF CMP=$CMP" "floor>=$FLOOR" GREEN || line W5_scope_floor "FF=$NFF CMP=$CMP" "floor>=$FLOOR" RED

say "POWUP-SUMMARY round=$ROUND judged=5 result=$([ $R -eq 0 ] && echo GREEN || echo RED)"
if [ $PARSE_ONLY -eq 0 ]; then
    {
        say "# ${ROUND} 上电值对账（尺子：build/check_powup_init.sh；探针原文：$OUT）"
        say "identity bit=$(md5sum < build/system.bit 2>/dev/null | cut -c1-12) synth_dcp_ff_lines=$NFF probed=$CMP"
        cat /tmp/kx/powup_lines.txt
        say "POWUP-SUMMARY round=$ROUND judged=5 result=$([ $R -eq 0 ] && echo GREEN || echo RED)"
        say ""
    } > "$VERD"
    say "WRITE $VERD"
fi
[ $R -eq 0 ] && exit 0 || exit 1

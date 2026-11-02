#!/bin/bash
# build/ports_floor_ce.sh —— 门禁第 14 项"扫描面地板"自己的对照（#194 的后半）。
# 跑的就是 gates 调的那份 build/ports_floor.sh：四条各喂一行合成汇总，期望的绿红必须一一兑现。
set -u
cd "$(dirname "$0")/.." || exit 2
FAIL=0
want() { # want <名字> <期望退出码> <汇总行>
    local out; out=$(bash build/ports_floor.sh "$3"); local rc=$?
    if [ "$rc" = "$2" ]; then echo "PASS CE $1（rc=$rc）$out"
    else echo "FAIL CE $1（期望 rc=$2，实得 $rc）$out"; FAIL=$((FAIL+1)); fi
}
want "P 真机汇总行必须放行"        0 "CHECK PORTS: instances=208 modules=80 skipped=0 width_compared=564 violations=0 PASS"
want "A 什么都没查（两个计数为 0）" 1 "CHECK PORTS: instances=0 modules=80 skipped=80 width_compared=0 violations=0 PASS"
want "B 汇总行缺字段（取不到数）"    1 "CHECK PORTS: 汇总行被改坏了"
want "C 只塌一半（位宽没比）"        1 "CHECK PORTS: instances=208 modules=80 skipped=0 width_compared=12 violations=0 PASS"
# 反例自己的反例：地板不许高到把真机挡红 —— P 那条就是它的正对照，两条必须一起绿/红才叫有牙
[ "$FAIL" = 0 ] || { echo "CE: 有红（$FAIL 条不对）"; exit 1; }
echo "CE: 全绿（4 条）"

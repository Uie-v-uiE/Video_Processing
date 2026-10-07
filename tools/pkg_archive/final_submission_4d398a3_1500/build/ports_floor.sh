#!/bin/bash
# build/ports_floor.sh —— 门禁第 14 项的**扫描面地板**（#194 的后半：那一项原来只看退出码）。
#
#   bash build/ports_floor.sh "<CHECK PORTS 汇总行>"        # 退出码 0=扫描面够，1=塌了（并说原因）
#
# 为什么单独一个脚本而不是把判断写在 gates.sh 里：判据写在门禁里就没法离线喂合成日志验它
# （`build/ports_floor_ce.sh` 必须跑**同一份**代码，否则"反例过了"只证明我另抄的那份没问题）。
# 同一族的前半（`check_ports.py` 里第一句 return 之后那段永不执行的副本）已经删掉——
# 写在那段里的判据等于没加。
set -u
L=${1:-}
PCI=$(sed -n 's/.*instances=\([0-9]*\).*/\1/p' <<<"$L")
PCW=$(sed -n 's/.*width_compared=\([0-9]*\).*/\1/p' <<<"$L")
FLOOR_I=${FLOOR_I:-100}      # 当前实测 208；地板取一半以下，正常增删模块碰不到
FLOOR_W=${FLOOR_W:-280}      # 当前实测 564
if [ -z "$PCI" ] || [ -z "$PCW" ]; then
    echo "FLOOR BAD 汇总行里取不到 instances/width_compared（这一项什么都没查）：[$L]"
    exit 1
fi
if [ "$PCI" -lt "$FLOOR_I" ] || [ "$PCW" -lt "$FLOOR_W" ]; then
    echo "FLOOR BAD instances=$PCI width_compared=$PCW 低于地板 $FLOOR_I/$FLOOR_W ⇒ violations=0 可能是没看而不是没违规"
    exit 1
fi
echo "FLOOR OK instances=$PCI width_compared=$PCW（地板 $FLOOR_I/$FLOOR_W）"
exit 0

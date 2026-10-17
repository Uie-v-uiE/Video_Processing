#!/bin/bash
# build/checks/round_bit_pairing.sh —— 拦「轮次标签 x 位流号」的错配。
#   来历：2026-10-17 一次全仓库 token 换之后，留下五处「板上 r118（bit cb907d3e4898）」这类新假话，
#   是复查 git diff 才抓到的（台账 report/log/issues.md #479）。这一支把那次复查固化成可重跑的检。
# 用法：bash build/checks/round_bit_pairing.sh      退出码 0=无错配 / 3=有错配（逐条点名）/ 2=REFUSE
# 口径：当前号 = `md5sum build/system.bit` 前 12 位；旧号 = 文档里历史上那几颗前 12 位（现列 cd04907e1369）。
set -u
cd "$(dirname "$0")/../.." || exit 2
NOW=$(md5sum build/system.bit 2>/dev/null | cut -c1-12)
[ -n "$NOW" ] || { echo "REFUSE 读不到 build/system.bit"; exit 2; }
FAIL=0
# 方向 1：带「当前号」的行里不许再挂旧轮次标签
while IFS= read -r line; do
  file=$(printf '%s' "$line" | cut -d: -f1); ln=$(printf '%s' "$line" | cut -d: -f2)
  body=$(printf '%s' "$line" | cut -d: -f3-)
  case "$body" in *r132*|*版本戳*|*不是当前*|*当前签署*) continue ;; esac
  if printf '%s' "$body" | grep -qaE 'r1[0-9][0-9]'; then
    echo "MISMATCH 当前号配旧轮次  $file:$ln  $(printf '%.120s' "$body")"; FAIL=1
  fi
done < <(grep -rn "$NOW" --include="*.md" --include="*.csv" report board data README.md README_EN.md 2>/dev/null | grep -avE 'report/log/issues.md|report/log/overnight_log.md')
# 方向 2：带「旧号」的行里不许说板上现在 / 当前 / 现役 / 这一版
while IFS= read -r line; do
  file=$(printf '%s' "$line" | cut -d: -f1); ln=$(printf '%s' "$line" | cut -d: -f2)
  body=$(printf '%s' "$line" | cut -d: -f3-)
  case "$body" in *版本戳*|*历史*|*当时*|*不是当前*|*待重签*) continue ;; esac
  # 同一行里还挂着别的轮次标签（r1NN）时，这句话是"某年那一判"的历史陈述，不是现读声明 ⇒ 不报
  if printf '%s' "$body" | grep -qaE 'r1[0-9][0-9]'; then continue; fi
  if printf '%s' "$body" | grep -qaE '板上现在|当前板上|板上这一版|现在跑的是|现役'; then
    echo "MISMATCH 旧号配现读词  $file:$ln  $(printf '%.120s' "$body")"; FAIL=1
  fi
done < <(grep -rn 'cd04907e1369' --include="*.md" report board 2>/dev/null | grep -avE 'report/log/|report/study/|project-brief|raw-vs-golden|hdmi_tp1')
if [ "$FAIL" = 0 ]; then echo "ROUND_BIT_PAIRING GREEN（当前号 $NOW，两个方向都无错配）"; else echo "ROUND_BIT_PAIRING RED"; fi
exit $((FAIL ? 3 : 0))

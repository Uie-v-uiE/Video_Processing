#!/usr/bin/env bash
# 用途：r112 那把"校验和累加器 32→20"的抓手判读（只读，不改任何东西）
# 输入：命令行参数
# 输出：stdout
# 退出码：2=REFUSE 3=REFUSE
# build/r112_verdict.sh —— r112 那把"校验和累加器 32→20"的抓手判读（只读，不改任何东西）。
# 口径：**同一条族自己动没动**，不是全局 WNS 的绝对差（规矩 35）；归属若换族要整句重写（规矩 46）。
#
# 第一版在这里栽过一次并**被自检抓到**：awk 里 `match($0,/CARRY4=[0-9]+")` 多带一个引号 ⇒
# "unterminated regexp"，整支解析交白卷，而脚本照旧往下念结论。所以今天这版自带地板：
# 解析出来的路径块数 < 1、或 slack 取不到数 ⇒ VERDICT-REFUSE，不产结论（#194 那一族：每把尺子都要数得出比较次数）。
# 用法：bash build/r112_verdict.sh [改前.rpt] [改后.rpt]   两份都点名自己的件
cd "$(dirname "$0")/.."
A=${1:-build/evidence/r110_setup_paths_baseline.rpt}
B=${2:-build/setup_paths.rpt}
[ -f "$A" ] && [ -f "$B" ] || { echo "VERDICT-REFUSE: 读不到 $A 或 $B"; exit 2; }
for f in "$A" "$B"; do [ -s "$f" ] || { echo "VERDICT-REFUSE: $f 是空的"; exit 2; }; done
echo "# r112 判读  改前=$A  改后=$B"

# 每块路径抽成一行：slack | src=.. | dst=.. | levels=.. | CARRY4=..
parse() {
  awk '
    function flush() { if (slack != "") printf "%s | src=%s | dst=%s | levels=%s | CARRY4=%s\n", slack, src, dst, levs, carry; slack=""; src=""; dst=""; levs=""; carry="-" }
    BEGIN { carry = "-" }
    /^Slack \((MET|VIOLATED)/ { flush(); slack = $4 }
    /^  Source:/ { src = $2 }
    /^  Destination:/ { dst = $2 }
    /^  Logic Levels:/ { levs = $3; if (match($0, /CARRY4=[0-9]+/)) carry = substr($0, RSTART + 7, RLENGTH - 7) }
    END { flush() }
  ' "$1"
}
check_floor() {   # $1=文件 $2=标签
  local n s
  n=$(parse "$1" | grep -ac "|")
  s=$(parse "$1" | head -1 | cut -d'|' -f1 | tr -d ' ')
  [ "$n" -ge 1 ] || { echo "VERDICT-REFUSE: $2 解析出 0 块路径（报告形状变了，别看结论）"; exit 3; }
  case "$s" in *.*) : ;; *) echo "VERDICT-REFUSE: $2 第一条的 slack 取不到数（读到 '$s'）"; exit 3 ;; esac
  echo "  $2 解析块数=$n 第一条 slack=$s"
}
echo "## 地板（解析器自己要被数一次）"
check_floor "$A" 改前
check_floor "$B" 改后

echo "## 改前：IP 校验和那一条族（终点是 check_buffer_reg[*]）"
parse "$A" | grep -a "check_buffer_reg" | head -4
echo "## 改后：同一条族"
parse "$B" | grep -a "check_buffer_reg" | head -4
echo "## 全设计最差那一格（两份各自的第一条）"
echo "  改前：$(parse "$A" | head -1)"
echo "  改后：$(parse "$B" | head -1)"
CA=$(parse "$A" | grep -ac "check_buffer_reg"); CB=$(parse "$B" | grep -ac "check_buffer_reg")
S1=$(parse "$A" | head -1 | cut -d'|' -f1 | tr -d ' '); S2=$(parse "$B" | head -1 | cut -d'|' -f1 | tr -d ' ')
echo "## 三条结论（每条都点名它读的是哪份件）"
echo "  1) 全局最差 slack：改前 ${S1} → 改后 ${S2}（件：$(basename "$A") / $(basename "$B") 的第一块）。"
echo "     ⚠ 规矩 35：这一行的绝对差本身不叫收益，收益要看第 2 条的同族对照。"
if [ "$CB" -gt 0 ]; then
  echo "  2) 这一族仍出现在最差报告里（改前 $CA 块 → 改后 $CB 块），读它自己：$(parse "$B" | grep -a check_buffer_reg | head -1)"
else
  echo "  2) 这一族已从最差路径报告里消失（改前 $CA 块 → 改后 0 块）⇒ 抓手成立"
fi
W2=$(parse "$B" | head -1)
case "$W2" in
  *u_icmp_tx*) echo "  3) 归属没换族（最差仍是 u_icmp_tx 那一条）⇒ 首页归属句只改数字，不改主语。";;
  *) echo "  3) ⚠ 归属**换族**了：改后最差是 $(echo "$W2" | sed 's/.*src=\([^ ]*\).*/\1/') → $(echo "$W2" | sed 's/.*dst=\([^ ]*\).*/\1/')；首页归属句要整句重写（规矩 46）。";;
esac

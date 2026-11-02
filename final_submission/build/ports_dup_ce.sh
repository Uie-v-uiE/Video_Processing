#!/usr/bin/env bash
# 用途：门禁第 14 项那条 `--dup` 的**正对照**（判据自己的测试）
# 输入：命令行参数
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行）
# build/ports_dup_ce.sh —— 门禁第 14 项那条 `--dup` 的**正对照**（判据自己的测试）。
#
# 为什么必须有它：`--dup` 从今天起是硬项（#127-1：`pl_demo_top` 里两条 `.stage_sel(...)`
# 让"gray only"的演示默认被静默覆盖成六级全旁路）。但"我把树改干净了所以它绿了"这句话
# 什么都不证明 —— 也许它根本就不会红。所以要造一份**故意接错**的拷贝，让它在同一把尺子下红，
# 再让修好的那份绿：一红一绿成对出现，才算这条判据有牙。
#
# 全程只在 /tmp 里造树，仓库一个字节不动（`check_ports.py` 的 ROOT 是按自己所在位置往上两级算的，
# 所以把脚本本身拷进那棵临时树里就行 —— 这也正是它当年能被复用的原因）。
#
# 跑法：bash build/ports_dup_ce.sh        ；凭据落 build/reports/ports_dup_ce.txt
set -u
cd "$(dirname "$0")/.." || exit 1
OUT=build/reports/ports_dup_ce.txt
T=$(mktemp -d /tmp/ports_dup_ce.XXXXXX)
mkdir -p "$T/build" "$T/src/rtl" "$T/sim"
cp build/check_ports.py "$T/build/check_ports.py"

cat > "$T/src/rtl/mod.v" <<'V'
module m_a (input wire clk, input wire [8:0] stage_sel, output wire o);
  assign o = clk & (stage_sel != 9'd0);
endmodule
V
cat > "$T/src/rtl/top_ok.v" <<'V'
module top_ok (input wire clk, output wire o);
  wire [8:0] stage_sel = 9'd1;
  m_a u_a (.clk(clk), .stage_sel(stage_sel), .o(o));   // 一份关联，正常
endmodule
V
cat > "$T/src/rtl/top_dup.v" <<'V'
module top_dup (input wire clk, output wire o);
  wire [8:0] stage_sel = 9'd1;
  m_a u_a (.clk(clk), .stage_sel(stage_sel), .o(o),
           .stage_sel(9'd0));                          // 故意重复关联 = #127-1 的形状
endmodule
V

run() { (cd "$T" && python build/check_ports.py --dup 2>&1); }
last() { printf '%s\n' "$1" | tail -1; }

# ① 只放"好"的那份 ⇒ 必须 0 违规（否则这条判据在绿的时候也骗人）
mkdir -p "$T/keep" && mv "$T/src/rtl/top_dup.v" "$T/keep/"
GOOD=$(run); GRC=$?
# ② 把坏的那份放回去 ⇒ 必须恰好报出重复关联，且退出码非 0
#    ⚠ 这里第一次写的时候只截了 `tail -1`（汇总那一行），于是"抓到 DUP 那一行"永远是 0，
#    CE 就红着报"判据没牙"——那是我的尺子写错，不是 check_ports 不灵。明细行在汇总之前，必须看全文。
mv "$T/keep/top_dup.v" "$T/src/rtl/top_dup.v"
BAD=$(run)
grep -q "被连了 2 次" <<< "$BAD" && DETECT=1 || DETECT=0
grep -q "violations=0 PASS" <<< "$(last "$GOOD")" && GOODOK=1 || GOODOK=0
grep -qE "violations=[1-9]" <<< "$(last "$BAD")" && BADOK=1 || BADOK=0

{
  echo "# ports_dup_ce —— \`--dup\` 的正对照：同一把尺子，好树必须 0、坏树必须抓到那条重复关联"
  echo "# $(date '+%F %T')  临时树=$T"
  echo "好树（只有 top_ok）      : $(last "$GOOD")"
  echo "坏树（再放进 top_dup）   : $(last "$BAD")"
  echo "抓到 DUP 那一行=$DETECT  好树判 0=$GOODOK  坏树判红=$BADOK"
  if [ "$GOODOK" = 1 ] && [ "$DETECT" = 1 ] && [ "$BADOK" = 1 ]; then
      echo "RESULT PASS ports_dup_ce —— 这条判据能红也能绿"
  else
      echo "RESULT FAIL ports_dup_ce —— 判据自己不成立，第 14 项的 --dup 不能算有牙"
  fi
} | tee "$OUT"
rm -rf "$T"
grep -q "RESULT PASS" "$OUT"

#!/usr/bin/env bash
# build/r115_noise_cal.sh —— 提示词 §3 B4：把本工具的**噪声底**量出来（只做一次，不是每轮）
#
# 做法：同一份 `impl_1/system_top_opt.dcp`（r114 的，树指纹 rtl=3969247aaf7f）连跑两遍
#   **完全相同**的流程 `place_design → phys_opt_design → route_design`（mode=none，不加任何变量），
#   然后比同名读数。两遍之间没有任何输入变化 ⇒ 差值就是噪声底 noise_ns。
# 为什么便宜：快车道 7–9 分钟一滚（今天实测 A 滚 place 2m + route 4m、B 滚 place 1m + route 4m），
#   比一次正式构建（≈18 分钟构建 + 70–128 分钟顶层台架）低两个数量级，这正是提示词要的"廉价反事实"。
# ⚠ 已知事实（写在这里免得被当成"重复三轮=噪声为 0"的巧合）：本机布局布线是**确定性**的，
#   r113 曾三滚逐位复现 0.445（件 build/evidence/r113_roll_ABC_verdict.txt）。
#   所以 noise_ns 很可能 = 0.000。但那是**量出来的 0**，不是假设的 0：
#   只有当两滚的每个头条读数逐位相同，才允许写 noise_ns=0；任何一位不同就取最大差。
# 判定（每条一行，末列是判定；判定项必须"做过比较"而不是"通过"才计数，G9）：
#   N1 两滚都跑完（ROLLDONE 各 1）
#   N2 两滚的输入指纹一致（同一份 dcp 的 md5 + 同一棵树 fp，两个来源都要等）
#   N3 setup/hold 头条四个数逐位相等 ⇒ noise_ns 取最大差
#   N4 最差路径**身份**（起点/终点单元名）相等（数字相同但路径换了也不许当噪声为 0）
#   N5 与归档的正式构建读数对表（r114：WNS 0.739 / WHS 0.052）——只念差值，不判（跨构建不可比，H3）
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:?VP_VIVADO_BIN 必须给（见 report/BUILD.md）}
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp
W=/tmp/kx/r115_noise
R=0
say() { printf '[noise %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
line() { printf 'NOISE %-22s %-34s %s %s\n' "$1" "$2" "$3" "$4"; [ "$4" = RED ] && R=1; return 0; }
[ -f "$DCP" ] || { say "REFUSE 没有 $DCP（基线那一轮的 opt.dcp）"; exit 2; }
if tasklist 2>/dev/null | grep -qiE '^vivado\.exe'; then say "REFUSE 已有 Vivado 在飞"; exit 2; fi
mkdir -p $W "$W/n1" "$W/n2"
MD=$(md5sum < "$DCP" | cut -c1-12)
FP=$(bash build/rtl_fingerprint.sh | tr '\n' ' ')
say "dcp md5=$MD  tree fp=$FP"
for n in n1 n2; do
    say "空白滚 $n 起跑"
    MF_MODE=none MF_OUT=$W/$n MF_MINFO=200 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/mf114_roll.tcl \
        > "$W/$n/roll_console.txt" 2>&1
    say "空白滚 $n rc=$?"
done
hdr() { # $1=目录 → "wns whs nfp_setup nfp_hold"
    awk '/^\s+[0-9-]+\.[0-9]+\s+[0-9-]+\.[0-9]+/ {print $1, $5, $3, $7; exit}' "$1/timing_summary.rpt" 2>/dev/null
}
worst() { grep -a -m1 -A3 "Max Delay Paths" "$1/setup_paths.rpt" 2>/dev/null | grep -aoE "Source:[[:space:]]*\S+|Destination:[[:space:]]*\S+" | tr '\n' ' '; }
a=$(hdr $W/n1); b=$(hdr $W/n2)
sa=$(worst $W/n1); sb=$(worst $W/n2)
n1=$(grep -ac ROLLDONE $W/n1/roll_console.txt); n2=$(grep -ac ROLLDONE $W/n2/roll_console.txt)
line N1_both_rolls "n1=$n1 n2=$n2" "want 1/1" $([ "$n1" = 1 ] && [ "$n2" = 1 ] && echo GREEN || echo RED)
m1=$(grep -a "^ROLL mode=" $W/n1/roll_console.txt | head -1); m2=$(grep -a "^ROLL mode=" $W/n2/roll_console.txt | head -1)
same_fp=$( [ -n "$m1" ] && [ "$m1" = "$m2" ] && echo yes || echo no )
line N2_same_inputs "dcp_md5=$MD fp_equal=$same_fp" "两滚同一份 dcp 同一棵树" $([ "$same_fp" = yes ] && echo GREEN || echo RED)
noise=$(awk -v a="$a" -v b="$b" 'BEGIN{split(a,x," ");split(b,y," ");
   d1=x[1]-y[1]; if(d1<0)d1=-d1; d2=x[2]-y[2]; if(d2<0)d2=-d2;
   m=d1; if(d2>m)m=d2; printf "%.3f", m}')
cmp_ab=$( [ "$a" = "$b" ] && echo equal || echo differ )
line N3_headline_equal "A=[$a] B=[$b]" "逐位相等则 noise_ns=0" $([ "$cmp_ab" = equal ] && echo GREEN || echo RED)
line N4_worst_identity "A=[$sa] B=[$sb]" "最差路径身份也要相等" $([ -n "$sa" ] && [ "$sa" = "$sb" ] && echo GREEN || echo RED)
off=$(hdr build)
line N5_vs_official "roll=[$a] official_r114=[$off]" "只念不判（H3 跨构建不可比）" INFO
{
  printf 'NOISE-SUMMARY noise_ns=%s cmp=%s identity=%s dcp_md5=%s fp=%s\n' "$noise" "$cmp_ab" \
     "$([ "$sa" = "$sb" ] && echo equal || echo differ)" "$MD" "$FP"
  printf '# 口径：noise_ns 之后所有"收益"必须严格大于它才许叫收益（提示词 §3 B4/§4 D）。这个标定每个项目只做一次。\n'
} | tee "$W/noise.txt"
say "噪声底 noise_ns=$noise（件 $W/noise.txt）"
exit $R

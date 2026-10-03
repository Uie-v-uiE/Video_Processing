#!/usr/bin/env bash
# build/r117c_chain.sh —— r117 的第三次起飞：只重跑实现段（synth_1 复用），其余判读与门禁照旧。
#
# 前两次的账都留在盘上：
#   r117_chain.sh  = 03:44 我主动杀掉（发现带窗版会被自家发布门判红，决定撤窗采纳）
#   r117b_chain.sh = 04:00 被**我自己的钩子记账 bug** 打死（ISSUES #327：catch 的返回码当哨兵用）
#   —— 那一次钩子是在切割**已经成功**之后才把 run 杀掉的（239 -> 1 引脚、10 颗 replica）。
# 判据一字未改，仍然预登记在 r117b_chain.sh 头部（A1 机制 / A2 收益对 r114 / A3 不加严不放宽 /
# A4 资源与放置 / A5 发布门红数必须回到 1）。唯一修的是"读 A1 的出水口"：钩子的 puts 落在
# impl_1/runme.log，不在顶层控制台，所以这里两份都读（件 build/r117_a1_read.sh，#327）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录（机器相关，不写死）}
export VP_VIVADO_BIN="${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}"
export VP_XSDB=${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}
export VP_XPR="$(ls -1 vivado_system/*.xpr 2>/dev/null | head -1)"
NN=117
say(){ printf '[r117c %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a build/r117c_console.txt; }
say "项目=$VP_XPR 钩子=$(grep -a '^set hook_net' build/tcl/r117_post_place_hook.tcl)"
[ -n "$VP_XPR" ] || { say "找不到 .xpr —— 不猜路径"; exit 2; }

bash build/rtl_fingerprint.sh > build/evidence/r117c_tree_fp.txt 2>&1
say "指纹 rc=$? $(grep -a '^rtl=\|^top=' build/evidence/r117c_tree_fp.txt | tr '\n' ' ')"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/r117_resume_impl.tcl \
    > build/r117c_impl_console.txt 2>&1; B=$?
say "实现段 rc=$B $(grep -a '^RESUME impl_status\|^RESUME-DONE\|^RESUME-FAIL\|^RESUME-REFUSE' build/r117c_impl_console.txt | tr '\n' ' ')"
BIT=vivado_system/zynq_video_sys.runs/impl_1/system_top.bit
[ -s "$BIT" ] || { say "还是没有位流 —— 链停在这里（不伪造判读）"; exit 2; }
md5sum "$BIT" | cut -c1-12 > build/evidence/r117_bit_md5.txt
say "bit md5 = $(cat build/evidence/r117_bit_md5.txt)"
say "A1 机制（两处出水口都读）："; bash build/r117_a1_read.sh | tee -a build/r117c_console.txt

VP_LABEL=r${NN}_after VP_N=4 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl \
    > build/r${NN}_roster_console.txt 2>&1; say "roster rc=$?"
grep -a "^ROSTER|" build/r${NN}_roster_console.txt > build/evidence/r${NN}_after_roster.txt
say "名册行数=$(grep -c '^ROSTER|' build/evidence/r${NN}_after_roster.txt)"
# 链子里这一跑照原样保留（它会 REFUSE，那是 #326 的凭据），正式判定用同生成器配对的 pair_fix。
bash build/timing_roster_diff.sh build/evidence/r114_after_roster.txt build/evidence/r${NN}_after_roster.txt \
    > build/evidence/r${NN}_roster_diff.txt 2>&1; say "名册差分(旧 A 侧，预期 REFUSE) rc=$?"
bash build/r117_pair_fix.sh > build/evidence/r${NN}_roster_diff_vs_r114.txt 2>&1
say "同生成器差分 rc=$? $(grep -a 'ROSTERDIFF-SUMMARY' build/evidence/r${NN}_roster_diff_vs_r114.txt | tail -1)"
bash build/pre_readings.sh r${NN}_after > build/r${NN}_post_readings_console.txt 2>&1
say "改后读数 rc=$? —— build/evidence/r${NN}_after.txt"
bash build/timing_lane.sh > build/r${NN}_lane_after.txt 2>&1
say "快车道 rc=$? $(grep -a 'LANE-SUMMARY' build/r${NN}_lane_after.txt | tail -1)"

{
    echo "R117 date=$(date '+%F %T')  chain=r117c（实现段重启，synth_1 复用；r117b 被 #327 的钩子记账 bug 打死）"
    echo "R117 bit=$(cat build/evidence/r${NN}_bit_md5.txt)  （r116=bb2fb707aebc，r114=7142a1fbf082）"
    echo "R117 config io_window=off hook=on tau=31"
    echo "R117 A1_mechanism_below"
    bash build/r117_a1_read.sh
    echo "R117 A2_rows $(grep -a '^ROSTER|' build/evidence/r${NN}_after_roster.txt | tr '\n' ' ')"
    echo "R117 A2_diff_vs_r114 $(grep -a '^ROSTERDIFF-ROW\|^ROSTERDIFF D\|^ROSTERDIFF-SUMMARY' build/evidence/r${NN}_roster_diff_vs_r114.txt | tr '\n' ' ')"
    echo "R117 A3_debt no_input_delay 应=5（撤窗）、no_output_delay 应=6：由 r117_post.sh 的 io probe 现问"
    echo "R117 A4_util $(grep -a '| Slice Registers\|| Slice LUTs\|| Block RAM Tile' build/utilization.rpt | tr '\n' ' ')"
    echo "R117 A4_place30439=$(grep -a -c 'Place 30-439' build/r117c_impl_console.txt)"
    echo "R117 lane=$(grep -a 'LANE-SUMMARY' build/r${NN}_lane_after.txt | tail -1)"
} > build/r${NN}_verdict.txt 2>&1
say "判读写在 build/r${NN}_verdict.txt"

mkdir -p /tmp/kx
bash build/gates.sh > "/tmp/kx/g_r${NN}c.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}c.txt" "build/r${NN}_gates.txt"
bash build/gates.sh > "/tmp/kx/g_r${NN}c-2.txt" 2>&1
cmp -s "/tmp/kx/g_r${NN}c.txt" "/tmp/kx/g_r${NN}c-2.txt" \
    && say "门禁两跑逐字节一致 rc=$G" || say "门禁两跑不一致（文档或产物在动，先停下查）"
cp -f "/tmp/kx/g_r${NN}c-2.txt" "build/r${NN}_gates.txt"
say "门禁 绿=$(grep -c ' PASS$' build/r${NN}_gates.txt) 红=$(grep -c ' FAIL$' build/r${NN}_gates.txt)"
say "链结束（刷板由 build/r117_board.sh 接手，post 自动化由 build/r117_post.sh 接手）"

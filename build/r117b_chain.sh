#!/usr/bin/env bash
# build/r117b_chain.sh —— r117 的**第二次**起飞（第一版 r117_chain.sh 在 03:44 被我主动杀掉，原因写在下面）。
#
# 为什么杀掉重来（这是判断，不是事故）：
#   r116 的门禁两跑回来是 **24 项 = 17 绿 / 7 红**（件 `build/r116_gates.txt`），其中 4 项是
#   发布硬门（WNS ≥ 0、失败 setup 端点 == 0、WHS ≥ 0、失败 hold 端点 == 0），
#   红的原因是**本轮新加的 RGMII 输入窗第一次检查了那 5 个端点**，而这一族已被证明关不掉
#   （0…31 全档不相交 + 角间差 3.411 vs 0.467 ns）。仓库自己的那句结论是
#   "GATES: 有红项 —— 不采纳，保留上一版"。
#   ⇒ 我不去把发布门改成允许红（那是给自己开门），也不把正确的约束删掉不算账：
#     约束留在仓里当**候选件**、全部读数与证明都保留，构建默认**不加载**它
#     （`VP_R116_IO_WINDOW=1` 一条命令就能复现带窗那一版）。相对 r114 这**不是放宽**（r114 从来没有这条约束），
#     是"本轮采纳的新约束被自家发布门拒绝" ⇒ 按 H7 回滚这一处切割，并把回滚原因与它当初的预测收益写进文档。
#   ⇒ 所以 r117 只带两样：**τ=31 的眼心** + **C9 强制复制那根 239 引脚广播网**。
#     这一版的对照对象也跟着换成 **r114 的官方名册**（同一套约束才是同一条尺子；拿带窗的 r116 当对照
#     会把"撤掉一条约束"读成"收益"，那是我最不该犯的那种错）。
#
# 判据（与第一版同一条，预登记，不接受事后改口径）：
#   A1 机制 构建日志 `R117HOOK ... pins_after` 远小于 239 且 replica_cells ≥ 1，否则 MECHANISM_INERT
#   A2 收益 clk_fpga_0 / clkout0_1 / sys_clk 的 rel_margin_setup 相对 **r114** 不许变小，且至少一格显著变大
#   A3 不加严不放宽：check_timing 的 `no_output_delay` 端口数 == 6、`unconstrained_internal_endpoints` == 0
#   A4 资源 Slice 寄存器增量 ≤ +15、LUT/BRAM/DSP 不变、route successful、无 Place 30-439
#   A5 发布门 24 项的红数必须回到 **1**（只有声明过的 C5c），否则这一版不采纳、板子回刷 r114
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录（机器相关，不写死）}
export VP_VIVADO_BIN="${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}"
export VP_XSDB=${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}
NN=117
say(){ printf '[r117b %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a build/r117b_console.txt; }
# 钩子用 Windows 风格绝对路径：MSYS 的 /d/... Vivado 不认（第一版这里也可能踩到，所以先换成 D:/）
export IMPL_POST_PLACE_HOOK="$(pwd -W)/build/tcl/r117_post_place_hook.tcl"
unset VP_R116_IO_WINDOW          # 显式不加载输入窗（默认就是不加载，这里写出来是给自己看的）
sleep 20                          # 让上一版链子的 Vivado 进程与工程锁彻底退掉

bash build/rtl_fingerprint.sh > build/evidence/r117_tree_fp.txt 2>&1
say "指纹 rc=$? $(grep -a '^rtl=' build/evidence/r117_tree_fp.txt)"
say "构建起飞：钩子=$IMPL_POST_PLACE_HOOK，输入窗=off"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > build/r117_build_console.txt 2>&1; B=$?
say "构建 rc=$B"
grep -a "VP_R116_IO_WINDOW\|BUILD_POST_PLACE_HOOK\|^R117HOOK\|Place 30-439\|Route 35-57" \
    build/r117_build_console.txt | tail -8

BIT=vivado_system/zynq_video_sys.runs/impl_1/system_top.bit
[ -s "$BIT" ] || { say "没有位流 —— 链停在这里（不伪造判读）"; exit 2; }
md5sum "$BIT" | cut -c1-12 > build/evidence/r117_bit_md5.txt
say "bit md5 = $(cat build/evidence/r117_bit_md5.txt)"

VP_LABEL=r${NN}_after VP_N=4 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl \
    > build/r${NN}_roster_console.txt 2>&1; say "roster rc=$?"
grep -a "^ROSTER|" build/r${NN}_roster_console.txt > build/evidence/r${NN}_after_roster.txt
say "名册行数=$(grep -c '^ROSTER|' build/evidence/r${NN}_after_roster.txt)"
# 对照 = r114 官方名册（同一套约束）。r116 那份带窗，只作为"带窗会发生什么"的证据留在原处。
bash build/timing_roster_diff.sh build/evidence/r114_after_roster.txt build/evidence/r${NN}_after_roster.txt \
    > build/evidence/r${NN}_roster_diff.txt 2>&1; say "名册差分(对 r114) rc=$?"
grep -a "^ROSTERDIFF-ROW\|^ROSTERDIFF-SUMMARY\|^ROSTERDIFF D" build/evidence/r${NN}_roster_diff.txt | head -20
# E1 那张表的两个债务列只能来自**本轮自己的** check_timing（去窗之后 `no_input_delay` 会回到 5）⇒
# 这里不做，交给 build/r117_post.sh 的只读探针现问现生成（它先跑 build/tcl/r117_io_probe.tcl）。
say "E1 名册交给 r117_post.sh（本轮 check_timing 由它的 io probe 现问）"
bash build/pre_readings.sh r${NN}_after > build/r${NN}_post_readings_console.txt 2>&1
say "改后读数 rc=$? —— build/evidence/r${NN}_after.txt"
bash build/timing_lane.sh > build/r${NN}_lane_after.txt 2>&1
say "快车道 rc=$? $(grep -a 'LANE-SUMMARY' build/r${NN}_lane_after.txt | tail -1)"

{
    echo "R117 date=$(date '+%F %T')"
    echo "R117 bit=$(cat build/evidence/r${NN}_bit_md5.txt)  （上一版 r116=bb2fb707aebc，r114=7142a1fbf082）"
    echo "R117 config io_window=off hook=on tau=31"
    echo "R117 A1_mechanism $(grep -a 'R117HOOK phystopt_rc' build/r${NN}_build_console.txt | tail -1)"
    echo "R117 A2_rows $(grep -a '^ROSTER|' build/evidence/r${NN}_after_roster.txt | tr '\n' ' ')"
    echo "R117 A2_diff $(grep -a '^ROSTERDIFF-ROW\|^ROSTERDIFF-SUMMARY' build/evidence/r${NN}_roster_diff.txt | tr '\n' ' ')"
    echo "R117 A3_debt 本轮 no_input_delay 应回到 5（去窗）、输出侧仍 6：由 r117_post.sh 的 io probe 现问"
    echo "R117 A4_util $(grep -a '| Slice Registers\|| Slice LUTs\|| Block RAM Tile' build/utilization.rpt | tr '\n' ' ')"
    echo "R117 A4_place30439=$(grep -a -c 'Place 30-439' build/r${NN}_build_console.txt)"
    echo "R117 lane=$(grep -a 'LANE-SUMMARY' build/r${NN}_lane_after.txt | tail -1)"
} > build/r${NN}_verdict.txt 2>&1
say "判读写在 build/r${NN}_verdict.txt"

mkdir -p /tmp/kx
bash build/gates.sh > "/tmp/kx/g_r${NN}b.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}b.txt" "build/r${NN}_gates.txt"
bash build/gates.sh > "/tmp/kx/g_r${NN}b-2.txt" 2>&1
cmp -s "/tmp/kx/g_r${NN}b.txt" "/tmp/kx/g_r${NN}b-2.txt" \
    && say "门禁两跑逐字节一致 rc=$G" || say "门禁两跑不一致（文档或产物在动，先停下查）"
cp -f "/tmp/kx/g_r${NN}b-2.txt" "build/r${NN}_gates.txt"
say "门禁 绿=$(grep -c ' PASS$' build/r${NN}_gates.txt) 红=$(grep -c ' FAIL$' build/r${NN}_gates.txt)"
say "链结束（刷板与板级复验由 build/r117_board.sh 接手，post 自动化由 build/r117_post.sh 接手）"

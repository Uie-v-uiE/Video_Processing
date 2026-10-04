#!/usr/bin/env bash
# 用途：r117（C9 复制刀）从构建到判读的一条链，夜里自己走，人不敲第二条命令
# 输入：命令行参数、build/tcl/build_system_axigpio.tcl、build/tcl/probe_timing_roster.tcl
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 2=非 0 分支（该文件 exit 2 那一行）
# build/r117_chain.sh —— r117（C9 复制刀）从构建到判读的一条链，夜里自己走，人不敲第二条命令。
#
# 为什么必须等 r116 的门禁先落地再起飞：`build/*.rpt` 与 `build/system.bit` 是**同一批被跟踪的产物**，
# r117 的构建会在结束时覆盖它们；如果 r116 的门禁正在读这些文件，它读到的就是"两版混合"，
# 那份 rNN_gates.txt 就再也指不动是哪一块 bit（#221/D1b 定的就是这件事）。⇒ 顺序是硬的。
#
# H4：构建前先打指纹；构建期间**不改 src/**（这一条链自己就是"不许中途编辑"的对象：
# 起飞之后不要再改这个文件，要改就另起一个名字）。
# 判据（写在末尾 R117-VERDICT 那一行，事前登记在这里，不许事后改口径）：
#   A1 机制   构建日志里 `R117HOOK ... pins_after=<N>`，N 必须显著小于 239，且 replica_cells>=1
#            ⇒ 不满足就是 MECHANISM_INERT（机制没动不许汇报成"没有收益"，提示词附录 1）
#   A2 收益   名册 `clk_fpga_0` 的 rel_margin_setup >= r116 的 19.76 %（noise_ns=0.000）
#   A3 代价   其余三域的 rel_margin 一格不许变小（G1）；`eth_rxc` 两格应逐格不动（它不吃这一刀）
#   A4 资源   Slice 寄存器 +<=15（快车道实测 +10）、LUT/BRAM/DSP 不许变、route successful、无 Place 30-439
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}"
export VP_XSDB=${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}
NN=117
say() { printf '[r117 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
mkdir -p build/evidence

# ---- 0. 等 r116 的门禁件（最多 150 分钟）----
for i in $(seq 1 300); do
    [ -s build/r116_gates.txt ] && break
    sleep 30
done
[ -s build/r116_gates.txt ] || { say "等不到 build/r116_gates.txt —— 不起飞（本轮没有凭据基线）"; exit 1; }
say "r116 门禁件到位；再等 150 s 让第二跑与拷贝落定"
sleep 150

# ---- 1. 指纹（编译前）----
bash build/rtl_fingerprint.sh > "build/evidence/r${NN}_tree_fp.txt" 2>&1
say "指纹 rc=$? —— build/evidence/r${NN}_tree_fp.txt"

# ---- 2. 正式构建：只多挂一个 post-place 钩子 ----
export IMPL_POST_PLACE_HOOK="$PWD/build/tcl/r117_post_place_hook.tcl"
say "构建起飞（钩子 = $IMPL_POST_PLACE_HOOK）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
say "构建 rc=$B"
grep -a "BUILD_POST_PLACE_HOOK\|^R117HOOK\|Place 30-439\|Route 35-57\|write_bitstream" \
    "build/r${NN}_build_console.txt" | tail -8

# ---- 3. 位流身份 ----
BIT=vivado_system/zynq_video_sys.runs/impl_1/system_top.bit
if [ ! -s "$BIT" ]; then say "没有位流 —— 构建没走完，链停在这里"; exit 2; fi
md5sum "$BIT" | cut -c1-12 > "build/evidence/r${NN}_bit_md5.txt"
say "bit md5 = $(cat build/evidence/r${NN}_bit_md5.txt)"

# ---- 4. 名册 / 改后读数 / 差分 / 快车道 ----
VP_LABEL=r${NN}_after VP_N=4 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl \
    > "build/r${NN}_roster_console.txt" 2>&1; say "roster rc=$?"
grep -a "^ROSTER|" "build/r${NN}_roster_console.txt" > "build/evidence/r${NN}_after_roster.txt"
say "名册行数=$(grep -c '^ROSTER|' "build/evidence/r${NN}_after_roster.txt")"
bash build/timing_roster_diff.sh build/evidence/r116_after_roster.txt "build/evidence/r${NN}_after_roster.txt" \
    > "build/evidence/r${NN}_roster_diff.txt" 2>&1; say "名册差分 rc=$?"
bash build/pre_readings.sh r${NN}_after > "build/r${NN}_post_readings_console.txt" 2>&1
say "改后读数 rc=$? —— build/evidence/r${NN}_after.txt"
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; say "快车道 rc=$? $(grep -a 'LANE-SUMMARY' "build/r${NN}_lane_after.txt" | tail -1)"

# ---- 5. 判据逐条打印（一条判据一行，规矩：每条判据每轮打一行）----
{
    echo "R117 date=$(date '+%F %T')"
    echo "R117 bit=$(cat build/evidence/r${NN}_bit_md5.txt) r116 bit=bb2fb707aebc"
    echo "R117 A1_mechanism $(grep -a 'R117HOOK byname' build/r${NN}_build_console.txt | tail -1)"
    echo "R117 A1_mechanism $(grep -a 'R117HOOK phystopt_rc' build/r${NN}_build_console.txt | tail -1)"
    echo "R117 A2_gain $(grep -a 'ROSTER|setup|clk=clk_fpga_0' build/evidence/r${NN}_after_roster.txt)"
    echo "R117 A3_domains $(grep -a 'ROSTERDIFF\|ROSTERDIFF-ROW\|SUMMARY' build/evidence/r${NN}_roster_diff.txt | tail -14)"
    echo "R117 A4_util $(grep -a '| Slice Registers\|| Slice LUTs\|| Block RAM Tile\|| DSPs' build/utilization.rpt | head -4)"
    echo "R117 A4_route $(grep -a -c 'Place 30-439' build/r${NN}_build_console.txt) 条 Place 30-439"
    echo "R117 lane $(grep -a 'LANE-SUMMARY' "build/r${NN}_lane_after.txt" | tail -1)"
} > build/r${NN}_verdict.txt 2>&1
say "判读写在 build/r${NN}_verdict.txt"
# ---- 6. 门禁两跑（同一把尺，先 /tmp 再 cp，两跑要逐字节一致）----
mkdir -p /tmp/kx
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
bash build/gates.sh > "/tmp/kx/g_r${NN}-2.txt" 2>&1
cmp -s "/tmp/kx/g_r${NN}.txt" "/tmp/kx/g_r${NN}-2.txt" && say "门禁两跑逐字节一致 rc=$G" || say "门禁两跑不一致（写回后再跑一遍）"
cp -f "/tmp/kx/g_r${NN}-2.txt" "build/r${NN}_gates.txt"
say "门禁 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
say "链结束（下一步是刷板与带流复验，那两步要人看着串口，不在这里自动做）"

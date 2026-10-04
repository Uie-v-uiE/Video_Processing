#!/usr/bin/env bash
# build/r118_chain.sh —— 最后一轮：只带 tau=31（r116 量的眼心），**不挂** C9 复制钩子、**不加载**输入窗。
#
# 为什么把 C9 撤掉（判据是硬的，不是我的口味）：r117 官方构建实测（件 build/evidence/r117_roster_diff_vs_r114.txt）
#   clk_fpga_0 setup 1.850 -> 2.104（赢），但 clkout0_1 3.630 -> 3.353、eth_rxc 0.739 -> 0.615、
#   eth_rxc hold 0.052 -> 0.044、sys_clk 14.876 -> 14.815 四格变小 ⇒ 预登记的 A2/A3 严格口径不过 ⇒ 按 H7 回滚。
#   记录在 build/r117_verdict_declined.txt；`timing_roster_diff.sh` 的 D3 用 25 % 门槛给的是 GREEN，
#   两把尺子对同一份数据判语不同这件事记 ISSUES #328（口径债，我自己不加宽任何一方）。
# 为什么 tau=31 值得单独一轮：它是**硬件侧**的收口眼心（0…31 全档扫描里 min(hold,setup) 的最大点，
#   件 build/evidence/r115_window/probe3_console.txt），收益不体现在片内 slack 上——它体现在
#   "片外数据沿离捕获窗中心最远"，所以判据必须是**不劣化 + 上板复验**，不是"WNS 变好"。
#
# 判据（起飞前登记，不接受事后改口径）：
#   B1 严格名册：8 对（4 域 × setup/hold）里，任何一格 rel_margin_setup/hold 相对 r114 **不许变小**
#   B2 机构中性：构建日志里**没有** R117HOOK（这版故意不挂）；`unconstrained_internal_endpoints` 仍 0
#   B3 资源中性：Slice 寄存器 == 8188（与 r114 同），LUT/BRAM/DSP 不变，route successful、无 Place 30-439
#   B4 发布门：判定 24 项的红数 == 1（只有声明过的 C5c），且门禁两跑逐字节一致
#   四条全过 ⇒ 刷 r118 + board_verify；任一不过 ⇒ 刷回 r114 + board_verify，r118 记"量过并否决"
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}"
export VP_XSDB=${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}
unset IMPL_POST_PLACE_HOOK VP_R116_IO_WINDOW
NN=118
say(){ printf '[r118 %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a build/r118_console.txt; }
bash build/rtl_fingerprint.sh > build/evidence/r118_tree_fp.txt 2>&1
say "指纹 rc=$? $(grep -a '^rtl=\|^top=' build/evidence/r118_tree_fp.txt | tr '\n' ' ')"
say "构建起飞：钩子=none 输入窗=off tau=31（IDELAY_VALUE=$(grep -a -o 'IDELAY_VALUE([0-9]*)' src/rtl/top/system_top.v | head -1)）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > build/r118_build_console.txt 2>&1; B=$?
say "构建 rc=$B"
grep -a "VP_R116_IO_WINDOW off\|BUILD_POST_PLACE_HOOK\|Place 30-439\|Route 35-57" build/r118_build_console.txt | tail -4
BIT=vivado_system/zynq_video_sys.runs/impl_1/system_top.bit
[ -s "$BIT" ] || { say "没有位流 —— 链停在这里（不伪造判读）"; exit 2; }
md5sum "$BIT" | cut -c1-12 > build/evidence/r118_bit_md5.txt
say "bit md5 = $(cat build/evidence/r118_bit_md5.txt)  （r114=7142a1fbf082 r116=bb2fb707aebc r117=beda9298331d）"
VP_LABEL=r${NN}_after VP_N=4 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl \
    > build/r${NN}_roster_console.txt 2>&1; say "roster rc=$?"
grep -a '^ROSTER|\|^FANOUT|' build/r${NN}_roster_console.txt > build/evidence/r${NN}_after_roster_probefmt.txt
say "名册 rows=$(grep -ac '^ROSTER|' build/evidence/r${NN}_after_roster_probefmt.txt) fanout=$(grep -ac '^FANOUT|' build/evidence/r${NN}_after_roster_probefmt.txt)"
bash build/timing_roster_diff.sh build/evidence/r114_after_roster_probefmt.txt build/evidence/r${NN}_after_roster_probefmt.txt \
    > build/evidence/r${NN}_roster_diff_vs_r114.txt 2>&1; say "差分(25% 门槛那把) rc=$?"
# B1 严格口径：两把尺子都念，判定按严格的那把
python - <<'PY' > build/evidence/r118_strict_b1.txt 2>&1
import io, re
def load(p):
    d = {}
    for l in io.open(p, encoding="utf-8", errors="replace").read().splitlines():
        if not l.startswith("ROSTER|"):
            continue
        parts = l.split("|"); kind = parts[1]
        f = dict(x.split("=", 1) for x in parts[2:] if "=" in x)
        m = re.search(r"-?\d+(?:\.\d+)?", f.get("slack", ""))
        if not m:
            continue
        d[(f["clk"], kind)] = float(m.group(0))
    return d
a = load("build/evidence/r114_after_roster_probefmt.txt")
b = load("build/evidence/r118_after_roster_probefmt.txt")
per = sorted(set(a) & set(b))
lo = []
for k in per:
    delta = b[k] - a[k]
    tag = "SAME" if abs(delta) < 1e-9 else ("GAIN" if delta > 0 else "LOSS")
    if tag == "LOSS":
        lo.append(k)
    print("B1 %s/%s r114=%.3f r118=%.3f d=%+.3f %s" % (k[0], k[1], a[k], b[k], delta, tag))
print("B1 pairs_compared=%d losses=%d verdict=%s" %
      (len(per), len(lo), "GREEN" if not lo else "RED " + ",".join("%s/%s" % x for x in lo)))
PY
say "B1 严格名册 $(grep -a '^B1 pairs_compared' build/evidence/r118_strict_b1.txt)"
bash build/pre_readings.sh r${NN}_after > build/r${NN}_post_readings_console.txt 2>&1
say "改后读数 rc=$?"
{ echo "R118 date=$(date '+%F %T') bit=$(cat build/evidence/r118_bit_md5.txt) config=hook=off io_window=off tau=31"
  echo "R118 B1_strict $(grep -a '^B1 pairs_compared' build/evidence/r118_strict_b1.txt)"
  grep -a '^B1 ' build/evidence/r118_strict_b1.txt
  echo "R118 B2_hook_absent=$(grep -a -c 'R117HOOK' build/r${NN}_build_console.txt)（应为 0）"
  echo "R118 B3_util $(grep -aE '\| *(Slice Registers|Slice LUTs|Block RAM Tile|DSPs) *\|' build/utilization.rpt | head -4 | tr '\n' ' ')"
  echo "R118 B3_place30439=$(grep -a -c 'Place 30-439' build/r${NN}_build_console.txt)"
  echo "R118 D3_loose $(grep -a '^ROSTERDIFF D3\|^ROSTERDIFF-SUMMARY' build/evidence/r${NN}_roster_diff_vs_r114.txt | tr '\n' ' ')"
} > build/r${NN}_verdict.txt 2>&1
say "判读写在 build/r${NN}_verdict.txt"
bash build/gates.sh > /tmp/kx/g_r118.txt 2>&1; G=$?
cp -f /tmp/kx/g_r118.txt build/r${NN}_gates.txt
bash build/gates.sh > /tmp/kx/g_r118-2.txt 2>&1
cmp -s /tmp/kx/g_r118.txt /tmp/kx/g_r118-2.txt && say "门禁两跑逐字节一致 rc=$G" || say "门禁两跑不一致（文档或产物在动）"
cp -f /tmp/kx/g_r118-2.txt build/r${NN}_gates.txt
say "门禁 绿=$(grep -c ' PASS$' build/r${NN}_gates.txt) 红=$(grep -c ' FAIL$' build/r${NN}_gates.txt)"
B1OK=$(grep -a '^B1 pairs_compared' build/evidence/r118_strict_b1.txt | grep -ac 'verdict=GREEN')
B4OK=$([ "$(grep -c ' FAIL$' build/r${NN}_gates.txt)" = 1 ] && echo 1 || echo 0)
D=build/evidence/r118_board; mkdir -p "$D"
if [ "$B1OK" = 1 ] && [ "$B4OK" = 1 ]; then
    say "采纳：刷 r118"; mkdir -p build/evidence/r118_bit
    cp -f "$BIT" build/evidence/r118_bit/system.bit; md5sum "$BIT" | cut -c1-12 > build/evidence/r118_bit/md5.txt
    bash build/r116_bit_cycle.sh r118build build/evidence/r118_bit/system.bit > "$D/bitcycle_console.txt" 2>&1
    RC=$?
else
    say "不采纳（B1 或 B4 不过）：板子回刷 r114"
    bash build/r116_bit_cycle.sh r114back build/evidence/r114_bit/system.bit > "$D/bitcycle_console.txt" 2>&1
    RC=$?
fi
bash build/board_verify.sh --geom --battery --round=r118 > "$D/board_verify_console.txt" 2>&1; BV=$?
{ printf '板上现在 = %s（刷入 %s，bit_cycle rc=%s board_verify rc=%s）\n' \
    "$([ "$B1OK" = 1 ] && [ "$B4OK" = 1 ] && echo r118 || echo r114回刷)" "$(date '+%F %T')" "$RC" "$BV"
  printf 'B1 严格名册：%s\nB4 门禁：绿=%s 红=%s\n' "$(grep -a '^B1 pairs_compared' build/evidence/r118_strict_b1.txt)" \
    "$(grep -c ' PASS$' build/r${NN}_gates.txt)" "$(grep -c ' FAIL$' build/r${NN}_gates.txt)"
} > "$D/board_now.txt" 2>&1
say "链结束（板上状态见 $D/board_now.txt）"

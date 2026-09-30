#!/bin/bash
# build/freeze_selftest.sh —— 冻结脚本（#192/#193）自己的对照，跑在 /tmp 沙箱里，不碰仓库里任何真凭据。
#
# 为什么要有它：`build/freeze_evidence.sh` 的"拷贝名单"与"盖章名单"原来是两份分开维护的，
# 结果拷进冻结目录 19+6 份而 MANIFEST 只盖 11 份（#192）。这种缺陷只在"少盖章"的方向上发作，
# 光读代码看不出来，必须**造一份被改动的、不在盖章集合里的冻结件**，再看 `md5sum -c` 响不响。
#
# 沙箱成立的前提：freeze_evidence.sh 用 `dirname $0/..` 自适应仓库根（#111 那一刀），
# 所以整份脚本可以拷进 /tmp 下一个假 `build/ + src/rtl/` 骨架里跑。
#
# 用法：bash build/freeze_selftest.sh        （退出码 0 = 三条判定全部符合预期）
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$(mktemp -d "${TMPDIR:-/tmp}/fzsb.XXXXXX")"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/build" "$S/src/rtl/top" "$S/src/rtl/process"
cp "$ROOT/build/freeze_evidence.sh" "$S/build/freeze_evidence.sh" || { echo "FAIL 拷不进冻结脚本"; exit 1; }
cp "$ROOT/build/rtl_fingerprint.sh" "$S/build/rtl_fingerprint.sh" || { echo "FAIL 拷不进指纹脚本"; exit 1; }
# 对照的**标本**必须钉在一个固定提交上，不能用 HEAD：#192 修完之后 HEAD 那版已经不写死名单了，
# 于是 A/C 两段量的就变成"新版 vs 新版"，四条对照当场集体失真（2026-09-30 夜里第二次撞见同一族：
# 尺子的参照物自己会移动）。88cf452^ 就是那份"拷 19+6、只盖 11"的旧脚本。
FREEZE_OLD_REF=${FREEZE_OLD_REF:-88cf452^}
git -C "$ROOT" show "$FREEZE_OLD_REF:build/freeze_evidence.sh" > "$S/build/freeze_old.sh" 2>/dev/null \
    || { echo "FAIL 取不到 $FREEZE_OLD_REF 版对照"; exit 1; }

printf 'module top; endmodule\n' > "$S/src/rtl/top/pl_video_top.v"
printf 'module win; endmodule\n' > "$S/src/rtl/process/win.v"
# 脚本自己算的两枚指纹，按**它自己的算法**复算一遍写进假报告，两道硬门才走得通。
# 新旧两版的算法不同：旧版是 `find … | xargs md5sum | md5sum`（MSYS 的 md5sum 会在文件名前加
# `*` 这个二进制标记），新版只认 `build/rtl_fingerprint.sh` 的 norm1（去 CR、行格式写死）。
# 所以 A/C 段用旧方言的报告、D 段以后换成新方言的报告 —— 两段各拿自己那一版的凭据。
TOP=$(md5sum "$S/src/rtl/top/pl_video_top.v" | cut -c1-12)
RTL_OLD=$(cd "$S" && find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
RTL_NEW=$(FP_ROOT="$S" bash "$S/build/rtl_fingerprint.sh" | sed -n 's/^rtl=//p')
fake_report() { printf 'PROVENANCE top_md5=%s rtl_md5=%s tb_md5=deadbeefdead\nRESULT tb_v98_top_seam PASS\n' "$1" "$2" \
                > "$S/build/tb_v98_report.txt"; }
# 沙箱不许看见真机的台架运行目录：#193 那一族说"空集上的绿"，而**反过来**也成立——
# 沙箱里读到 /tmp/kx 那份正在写的 run.log，就会凭空造出逐列读数件，F1/F2 两条对照当场失真。
mkdir -p "$S/empty_kx"
export KX_RUN_DIR="$S/empty_kx"
fake_report "$TOP" "$RTL_OLD"
for nn in 5 6; do echo "GATES: ALL PASS" > "$S/build/r${nn}_gates.txt"; done
echo "PASS c1" > "$S/build/r5_benches.txt"; echo "PASS c1" > "$S/build/r6_benches.txt"
echo "RESULT tb_edge_rim PASS" > "$S/build/tb_edge_rim_r5.txt"
echo "RESULT tb_edge_rim PASS" > "$S/build/tb_edge_rim_r6.txt"
echo "baseline FAIL C5c" > "$S/build/tb_v98_c5_baseline.txt"
for r in timing_summary utilization power route_status methodology cdc clock_util; do echo "rpt $r" > "$S/build/$r.rpt"; done
for t in multi_driven width_warnings ports_check; do echo "ok $t" > "$S/build/$t.txt"; done
echo "product bit" > "$S/build/system.bit"
echo "product xsa" > "$S/build/system.xsa"
echo "product elf" > "$S/build/ps_app.elf"
# 故意缺两份可选件：缺项必须被念出来而不是被 2>/dev/null 吞掉
rm -f "$S/build/rim_gate_ce_r5.txt" "$S/build/rim_gate_ce_r6.txt"

PASS=0; FAIL=0
want() { # want <判据名> <期望> <实际>
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS $1（$3）";
    else FAIL=$((FAIL+1)); echo "FAIL $1（期望 $2，实际 $3）"; fi
}

echo "=== A) 盖章覆盖：新版必须等于落地数，旧版应当小于（这就是 #192） ==="
bash "$S/build/freeze_old.sh" 6 > /dev/null 2>&1; RCOLD=$?
OLDLANDED=$(cd "$S/build/evidence_r6" && find . -type f ! -name MANIFEST.md5 | wc -l)
OLDSEAL=$(grep -c '^[0-9a-f]\{32\}' "$S/build/evidence_r6/MANIFEST.md5")
want "A1 旧版跑通" 0 "$RCOLD"
want "A2 旧版盖章=11（那份写死的名单）" 11 "$OLDSEAL"
if [ "$OLDLANDED" -le "$OLDSEAL" ]; then echo "FAIL A3 旧版落地 $OLDLANDED 不比盖章 $OLDSEAL 多，标本不成立"; FAIL=$((FAIL+1));
else PASS=$((PASS+1)); echo "PASS A3 旧版落地 $OLDLANDED > 盖章 $OLDSEAL（有 $((OLDLANDED-OLDSEAL)) 份没指纹）"; fi

echo "=== B) 对照的标本必须先证明它不在被测集合里（我自己错过一次的那条） ==="
SPEC=clock_util.rpt
want "B1 标本不在旧清单里" 0 "$(grep -c "$SPEC" "$S/build/evidence_r6/MANIFEST.md5")"

echo "=== C) 旧清单下篡改标本：md5sum -c 不许有任何反应（这就是漏） ==="
printf ' tampered\n' >> "$S/build/evidence_r6/$SPEC"
OLDHITS=$( ( cd "$S/build/evidence_r6" && md5sum -c --quiet MANIFEST.md5 2>&1 || true ) | grep -c 'FAILED' )
want "C1 旧版看不见这次篡改" 0 "$OLDHITS"

echo "=== D) 新清单：盖章数=落地数，且同一份篡改必须被发现 ==="
# D0 换算法不等于放行：桥接表里没有的旧方言 raw 必须还是 REFUSE（否则 norm1 就成了"谁都能过"）
fake_report "$TOP" "$RTL_OLD"
bash "$S/build/freeze_evidence.sh" 7 > "$S/d0.out" 2>&1; RCX=$?
want "D0 旧方言不在桥接表里 ⇒ 新脚本 REFUSE" 1 "$RCX"
want "D0b REFUSE 没留下冻结目录" 0 "$(ls -1 "$S/build" 2>/dev/null | grep -c evidence_r7)"
fake_report "$TOP" "$RTL_NEW"          # 新算法读自己的方言
bash "$S/build/freeze_evidence.sh" 5 > /dev/null 2>&1; RCNEW=$?
NEWLANDED=$(cd "$S/build/evidence_r5" && find . -type f ! -name MANIFEST.md5 | wc -l)
NEWSEAL=$(grep -c '^[0-9a-f]\{32\}' "$S/build/evidence_r5/MANIFEST.md5")
want "D1 新版跑通" 0 "$RCNEW"
want "D2 新版盖章=落地" "$NEWLANDED" "$NEWSEAL"
printf ' tampered\n' >> "$S/build/evidence_r5/$SPEC"
NEWHITS=$( ( cd "$S/build/evidence_r5" && md5sum -c --quiet MANIFEST.md5 2>&1 || true ) | grep -c 'FAILED' )
want "D3 新版看得见这次篡改" 1 "$NEWHITS"

echo "=== E) 缺件不许沉默（#193 那一族的抱怨要写进凭据） ==="
MISSLINE=$(grep -c '没拷成的件' "$S/build/evidence_r5/MANIFEST.md5")
want "E1 缺件清单被念出来" 1 "$MISSLINE"
grep '没拷成的件' "$S/build/evidence_r5/MANIFEST.md5" | cut -c1-150

echo "=== F) 空文件不许冒充逐列读数（#193 本体） ==="
want "F1 没有 c2_shape 这个空壳" 0 "$(ls -1 "$S/build/evidence_r5" | grep -c 'c2_shape')"
want "F2 清单改口说没有逐列读数" 1 "$(grep -c '没有逐列读数' "$S/build/evidence_r5/MANIFEST.md5")"

echo "=== G) 反配对：三件成品缺任一件必须 REFUSE ==="
mv "$S/build/system.xsa" "$S/system.xsa.bak"
bash "$S/build/freeze_evidence.sh" 5 > /dev/null 2>&1; want "G1 缺 xsa 时退出码 1" 1 "$?"
want "G2 说的是 xsa" 1 "$(bash "$S/build/freeze_evidence.sh" 5 2>&1 | grep -c 'REFUSE：三件成品缺 system.xsa')"
mv "$S/system.xsa.bak" "$S/build/system.xsa"

echo "=== H) 硬门本身还能拦住假门禁（回归 r77 那条规矩） ==="
echo "GATES: 有红项" > "$S/build/r5_gates.txt"
bash "$S/build/freeze_evidence.sh" 5 > /dev/null 2>&1; want "H1 非 ALL PASS 不冻结" 1 "$?"

echo "SELFTEST: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] || exit 1

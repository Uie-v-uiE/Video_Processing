#!/bin/bash
# build/freeze_evidence.sh <NN> —— 把第 NN 次构建的成套凭据收进 build/evidence_rNN/，并生成 MANIFEST.md5。
#
# 为什么要有 MANIFEST.md5：现场只认 md5 不认文件名（`build/evidence_r*` 里同名的位流有好几份），
# 而"板上跑的到底是哪一版"是眼睛判据能不能算数的前提（`report/DEMO_SCRIPT.md` 第 0 步那条）。
#
# 两道硬门（"红 = 没做完"，把红的东西冻结下来等于给下一轮留一个"看起来有凭据"的坑）：
#   1) `build/rNN_gates.txt` 里必须是 `GATES: ALL PASS`；
#   2) `build/tb_v98_report.txt` 的 **两枚**指纹（`top_md5` 与 `rtl_md5`）都必须还等于当前树：
#      只比顶层是不够的——r72 改的是四个窗口级，`pl_video_top.v` 一字未动，
#      那份 r71 的旧报告本来能原样冒充 r72 的凭据（门禁第 15 项的 E/F 两个反例就是这件事）。
#
#   用法：bash build/freeze_evidence.sh 72
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # 仓库根自适应（原来写死本机路径）
cd "$ROOT" || exit 1
NN=${1:-}
case "$NN" in (''|*[!0-9]*) echo "用法: bash build/freeze_evidence.sh <构建编号，如 72>"; exit 2;; esac
D=build/evidence_r$NN
GT=build/r${NN}_gates.txt
TMP=$(mktemp -d)
# 台架/构建的原始 console 所在目录（默认 /tmp/kx）。开这个口子是为了 `freeze_selftest.sh`：
# 沙箱必须看不见真机那份**正在写**的 run.log，否则它会凭空造出逐列读数件，
# 把 F1/F2 两条"空文件不许冒充凭据"的对照当场念成假话（2026-09-30 夜里撞见）。
KX=${KX_RUN_DIR:-/tmp/kx}

if [ ! -f "$GT" ] || ! grep -q "^GATES: ALL PASS" "$GT"; then
    echo "REFUSE：$GT 不是 ALL PASS，不冻结。"
    [ -f "$GT" ] && grep -a "FAIL\|——" "$GT" | head -8
    exit 1
fi
eval "$(bash build/rtl_fingerprint.sh)"          # fpver/files/top/rtl（定义见那个脚本的文件头）
TOPWANT=$top
RTLWANT=$rtl
TOPYES=$(sed -n 's/.*top_md5=\([0-9a-f]*\).*/\1/p' build/tb_v98_report.txt | head -1)
RTLYES=$(sed -n 's/.* rtl_md5=\([0-9a-f]*\).*/\1/p' build/tb_v98_report.txt | head -1)
MT=$(bash build/rtl_fingerprint.sh --match file "$TOPYES" "$TOPWANT" src/rtl/top/pl_video_top.v)
MR=$(bash build/rtl_fingerprint.sh --match rtl "$RTLYES" "$RTLWANT")
if [ "$MT" = "no" ] || [ "$MR" = "no" ]; then
    echo "REFUSE：tb_v98 报告(top=$TOPYES/$MT rtl=$RTLYES/$MR)与当前树(top=$TOPWANT rtl=$RTLWANT，norm1)不是同一次跑"
    echo "        ⇒ 先重跑：bash sim/run_one.sh tb_v98_top_seam && bash build/tb98_report.sh"
    exit 1
fi
[ "$MT" = "bridge" ] || [ "$MR" = "bridge" ] && \
    echo "NOTE：报告头部还是旧 raw 指纹，经 build/fingerprint_bridge.txt 对账到同一份内容"
NG=$(grep -acE ' (PASS|FAIL)$' "$GT")

mkdir -p "$D"
# 三件成品（位流/xsa/elf）+ Vivado 报告 + 三份自检 + 台架与门禁
# r77 起多带三件：#97 的边缘条带凭据、它自己的反例、以及"修之前红成什么样"的 C5 基线
#（少了后两件，冻结件里就只剩"绿"，没有"这条判据曾经红过"——那是 S15/门禁 15b 反复要的东西）。
#
# #192（2026-09-30，反过来查检查器那一轮）：原来"拷哪些件"与"给哪些件算 md5"是**两份分开维护的名单**，
#   结果是拷进冻结目录 19+6 份、MANIFEST 只盖章 11 份——没盖章的那十四份，被改动、甚至本来就没拷成，
#   都看不出来（每个 cp 后面还挂着 2>/dev/null，连一句抱怨都没有）。
#   修法不是把第二份名单补齐（补这一次，下一次加件照样漏），而是**盖章对象 = 目录里实际存在的文件**：
#   以后谁往这个目录多放一件，它自动进 MANIFEST；少一件也自动看得出来。
CORE="system.bit system.xsa ps_app.elf"
FILES="system.bit system.xsa ps_app.elf timing_summary.rpt utilization.rpt power.rpt \
       route_status.rpt methodology.rpt cdc.rpt clock_util.rpt multi_driven.txt \
       width_warnings.txt ports_check.txt tb_v98_report.txt r${NN}_gates.txt \
       r${NN}_benches.txt tb_edge_rim_r${NN}.txt rim_gate_ce_r${NN}.txt \
       tb_v98_c5_baseline.txt"
MISS=""
for f in $FILES; do
    if [ -f "build/$f" ]; then cp -f "build/$f" "$D/$f"; else MISS="$MISS $f"; fi
done
# 三件成品是"这套凭据属于哪一版"的唯一根据，缺一件就没有可冻结的东西（其余缺项记账不拦，
# 因为历史上有几轮的 cdc.rpt / benches 清单本来就没生成——把它们变成硬门会把冻结变成只能冻结今天）。
for c in $CORE; do
    case " $MISS " in *" $c "*) echo "REFUSE：三件成品缺 $c，冻出来的是残缺套，不如不冻"; exit 1;; esac
done
# 构建与台架的**原始 console**（今天它们在 /tmp，不在 build/）
# #193：以前这五路 cp 也是 `2>/dev/null` 一吞了之——源不在就静默少一件。现在缺项进 MISS，末尾一起念。
cp_tmp() {
    if [ -f "$1" ]; then cp -f "$1" "$D/$2"; else MISS="$MISS $2(源 $1 不在)"; fi
}
cp_tmp "$KX"/r${NN}_wrap.log         "r${NN}_build_console.txt"
cp_tmp "$KX"/r${NN}_tb98_console.txt "r${NN}_tb98_console.txt"
# #172：这份"逐列原始读数"过去叫 `.log`，而 `.gitignore` 里有 `*.log` ⇒ 它从来没进过 git，
#   冻结件里那份 `c2_shape.txt` 全靠它、仓库里却没有它（今天同一族已经撞过第二次：
#   `build/r94_flash.log` 被文档点名却进不了包）。冻结产物一律 `.txt`。
cp_tmp "$KX"/tb_v98_top_seam.run/run.log "r${NN}_tb_v98_run.txt"
cp_tmp "$KX"/tb_v98_top_seam.run/prov.txt "r${NN}_tb98_prov.txt"
# L1 全量回归：门禁第 15 项只盯顶层台架那一份，其余台架红着门禁也能全绿（今天撞见两次），
# 所以冻结件里必须留"这一版下所有台架各自的结论行"。
cp_tmp "$KX"/r${NN}_l1.log "r${NN}_l1_regress.txt"
# #193 的另一半：源 run 日志不在时，下面这条 grep 会**写出一个空文件**（重定向先把名字建出来），
#   而 MANIFEST 照旧点名"逐列读数见 rNN_c2_shape.txt"——指路指到一个空壳，就是"没有凭证的凭证"。
#   现在抽不出来就把那个空文件删掉，并让 MANIFEST 里那句话改成"这一版没有逐列读数"。
SHAPE_N=0
if [ -f "$D/r${NN}_tb_v98_run.txt" ]; then
    grep -a "^C2SHAPE\|^C2 row\|^C2IBAD\|^C2BLK\|^OBS lastcol\|^ID " \
         "$D/r${NN}_tb_v98_run.txt" > "$D/r${NN}_c2_shape.txt" 2>/dev/null
    SHAPE_N="$( { grep -ac '' "$D/r${NN}_c2_shape.txt" || true; } )"; SHAPE_N="${SHAPE_N:-0}"
    if [ "$SHAPE_N" = "0" ]; then rm -f "$D/r${NN}_c2_shape.txt"; MISS="$MISS r${NN}_c2_shape.txt(逐列标签 0 行)"; fi
fi
L1P=0; L1F=0
[ -f "$D/r${NN}_l1_regress.txt" ] && { L1P=$(grep -ac '^RESULT .* PASS' "$D/r${NN}_l1_regress.txt");
                                       L1F=$(grep -ac '^RESULT .* FAIL' "$D/r${NN}_l1_regress.txt"); }
GITHEAD=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
# 盖章 = 目录里除了这份清单本身以外的**全部**文件（见上面 #192 的说明）。
( cd "$D" && find . -type f ! -name 'MANIFEST.md5' ! -name 'MANIFEST.content.md5' | LC_ALL=C sort | sed 's|^\./||' | xargs md5sum ) > "$D/MANIFEST.md5"
# #148：同一批文件再盖一枚**内容章**（先剥掉 CR 再取 md5）。字节章管"当时盘上就是这些字节"，内容章管"内容有没有变"：
# 一次 checkout 把 .txt 翻成 CRLF 只会让前者红、后者仍绿 ⇒ `bash build/verify_evidence.sh <NN>` 能把
# "换行翻了"和"凭据被改了"分开说（两种情形的反例都在它的 --self 里，S2 钉的就是这件事）。
( cd "$D" && find . -type f ! -name 'MANIFEST.md5' ! -name 'MANIFEST.content.md5' | LC_ALL=C sort | sed 's|^\./||' | while IFS= read -r f; do printf '%s  %s\n' "$(tr -d '\r' < "$f" | md5sum | cut -c1-32)" "$f"; done ) > "$D/MANIFEST.content.md5"
NLANDED="$( { cd "$D" && find . -type f ! -name 'MANIFEST.md5' ! -name 'MANIFEST.content.md5' | grep -c '' || true; } )"; NLANDED="${NLANDED:-0}"
NSEALED="$( { grep -ac '' "$D/MANIFEST.md5" || true; } )"; NSEALED="${NSEALED:-0}"
if [ "$NLANDED" != "$NSEALED" ]; then
    echo "REFUSE：落地 $NLANDED 份、盖章 $NSEALED 份，两个数不相等 ⇒ 盖章这一环没覆盖全部件（#192）"
    exit 1
fi
{
  echo "# r$NN evidence —— 生成于 $(date -Iseconds)   git=$GITHEAD"
  echo "# 指纹：顶层 $TOPWANT / 整个 src/rtl $RTLWANT（门禁第 15 项按这两枚对账）"
  echo "# 本目录 $NLANDED 份件，MANIFEST 逐份盖章（盖章对象=目录里实际存在的文件，不是另一份名单）"
  echo "# **不写 QSPI/SPI flash**（2025.2.1 的写入路径未验），也不碰 FT2232 EEPROM。"
  echo "#"
  if [ -n "$MISS" ]; then echo "# 这一版没拷成的件（缺件也是凭据的一部分，不能当成「都齐了」念）：$MISS"; echo "#"; fi
  if [ -f "$D/r${NN}_l1_regress.txt" ]; then
    echo "# 机器判据：门禁 $NG 行明细（$GT）；L1 全量台架 PASS=$L1P FAIL=$L1F（r${NN}_l1_regress.txt）"
  else
    echo "# 机器判据：门禁 $NG 行明细（$GT）；**这一版没有全量 L1**，只有定向清单 r${NN}_benches.txt"
    echo "#            （改动的模块只被那一批台架看着；全量 L1 补跑之后请把它的日志一起放进本目录）"
  fi
  if [ "$SHAPE_N" -gt 0 ]; then
    echo "#           顶层台架逐列读数 $SHAPE_N 行，见 r${NN}_c2_shape.txt（C2SHAPE / C2IBAD / ID / OBS lastcol）"
  else
    echo "#           **这一版没有逐列读数**（源 run 日志不在，或里面没有 C2SHAPE/C2 row/ID 那些标签）"
  fi
  echo "#"
  echo "# 还欠眼睛/手的（这一版由用户签，见 board/README.md 对应行）："
  echo "#   第 30 项 #92 边缘那条带；第 31 项 #94 拔卡/暂停不丢画/sd remount（要一只手）；"
  echo "#   第 29 项 bilin A/B 的观感；#93 旋转大角度两条（用户 2026-09-26 明确"先放着最后再修"）"
} >> "$D/MANIFEST.md5"
rm -rf "$TMP"
echo "=== $D（落地 $NLANDED 份 / 盖章 $NSEALED 份）"
ls -1 "$D" | tr '\n' ' '; echo
echo "=== MANIFEST.md5 尾部"
tail -14 "$D/MANIFEST.md5"

#!/usr/bin/env bash
# make_submission.sh — 从当前 git 跟踪集导出选题指南 §3.3.5.4 那份目录（final_submission/）。
#
# 四条判据，每条都是为了处理"仓库里合理、交出去不合理"：
#  1) **按引用留凭据**：build/ 与 sim/ 跟踪了上千个文件。被交付文档、两份 README、skill/、板级
#     操作卡点名的才带；评委复核任何数字走的都是文档里那条指路，没被点名的留档在包里只是噪声。
#  2) **被否决的轮次不进包**（HARD_DROP）：failed_/red_/rejected/notadopted/_wip/aborted 这些目录
#     即使被文档点名也不带——文档还指着它们，就说明该改的是文档，不是把它们塞进包。
#  3) **交付名工程化**（SIM_MAP + 小写化）：§3.3.5.4 要求文件名纯英文小写；带轮次号的
#     `tb_v98_top_seam.v` 换成按职责命名的 `tb_video_pipeline_top.v`。**改名只发生在导出时**：
#     仓库里那几百处旧名是"当时看到的名字"，改它等于抹掉过程凭据。
#     ⇒ 证据类（build/reports/ 与 report/log/）的正文**不参与改写**，包里那份判据报告仍是跑当时
#       的原文；新旧名对上靠生成的 sim/NAMES.md。
#  4) **导出后自检**：活文档里的路径式指路必须在包内解析得出；被改名台架的旧名与本机绝对路径必须为 0。
#     任一不过就不落盘。这一条是防我自己。
#
# 用法：bash build/make_submission.sh [--dry]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(cd "$REPO/.." && pwd)/final_submission"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sub.XXXXXX")"
DRY=0
if [ "${1:-}" = "--dry" ]; then DRY=1; fi

# ---- 交付台架：旧名 -> 新名（只列要改的；原名已按职责的不列）----
declare -A SIM_MAP=(
  [tb_v98_top_seam]=tb_video_pipeline_top
  [tb_edge_rim]=tb_display_edge_rim
  [tb_osd_lines]=tb_osd_overlay
  [tb_v101_fb_bilin]=tb_fb_bilinear
  [tb_v6_ingress_integrity]=tb_eth_ingress_integrity
  [tb_v6_vblank_copy]=tb_fb_vblank_copy
  [tb_v6_pingpong]=tb_fb_pingpong
  [tb_v794_osd_glyph]=tb_osd_glyph_rom
  [tb_bilin_lerp]=tb_bilinear_core
  [tb_v92_seam_bleed]=tb_seam_bleed
  [tb_v93_split_ctrl]=tb_split_ctrl
  [tb_v94_zoom_sel]=tb_zoom_sel
  [tb_v102_src_life]=tb_src_life
)
SIM_PLAIN=(tb_link_monitor tb_zoom_mapper tb_rotate_window tb_cdc_capacity tb_icmp_rx_len)
# 台架取舍 = 下面这份手写名单 ∪ 被留下的脚本（gates.sh / run_one.sh / mut_control.sh）点名的。
# 名单里的是**招牌判据**（给新名字）；被脚本点名的按原名带出去（改名会让脚本找不到文件）。
# 其余回归台架不进包：交付文档里以裸名提到它们，说的是"过程里举过的例子"，不是"包里有这个文件"；
# 以**路径**提到的那部分由导出末尾的 _dropped_tb 规则就地改成"仓库回归台架"，不留空链接。
SIM_KEEP=("${!SIM_MAP[@]}" "${SIM_PLAIN[@]}")

# ---- 硬剔除：被否决的轮次、探针与构建中间物、零引用 RTL ----
HARD_DROP_RE='^build/(failed_|red_|multidrive_|exp_|strprobe|uram_probe|micro_rd|ps_obj|snap_|r[0-9]+_isolated|r[0-9]+_exp|build/|vivado_system/|__pycache__/)|^sim/(probes|msim|v98run|xtest|tagchk|syntaxchk|v100run2)/|^src/rtl/(axi/axi_frame_writer|eth/axi_frame_saver|video/frame_buffer_db|video/video_timing_720p)\.v$'
PRUNE_ONEOFF=(
  build/tcl/apply_cdc_report.tcl build/tcl/fix_bd_and_top.tcl build/tcl/rebuild_opt.tcl
  build/tcl/rebuild_zoom_out.tcl build/tcl/rebuild_cdc_fix.tcl build/tcl/micro_rd.tcl
  build/tcl/uram_presence.tcl build/tcl/uram_probe.tcl build/tcl/uram_sites.tcl
  build/tcl/dfx_runtime.txt build/tcl/retry_open_nr.log
  sim/run_zoom_only.tcl tight_setup_hold_pins.txt board/ddr_churn_r33_pair.md
  # `build/` 在包里只该有两类东西：**可复现的构建脚本**与**综合/实现报告**（用户看包时提的）。
  # 下面这些是仓里的开发工具，不在复现链上 —— 复现链的名单不是凭印象列的，是从
  # `gates.sh` / `board_verify.sh` 里 grep 出来的：gates.sh 会调 check_ports.py、freeze_evidence.sh、
  # gates_cdc_test.sh、tb98_report.sh、board_verify.sh，所以那几个**留**，其余走。
  build/_scan_align.mjs build/cleanup_wip.sh build/refresh_evidence.sh build/roll_isolated.sh
  build/trim_comments.py build/orphan_rtl.sh build/rim_gate_ce.sh build/tb98_gate_ce.sh
  build/ps_app.mjs build/tag_bench_labels.mjs build/_tmp_isolated_roll.tcl
  build/r90_phase1.sh build/r90_phase2.sh build/r90_phase3.sh build/r90_patch_icmp.py
  # `board/` 同理：留"上板工程 / 运行脚本 / 实测输出"，一次性探针走。
  # 名单不是凭印象 —— 先查过谁被指路：`rdddr.tcl` 被 BUILD.md 点名、`demo_rehearsal.txt` 被 gates.sh 用、
  # `pswhy.tcl` / `serial_bytes.ps1` / `uart_*.ps1` / `evidence_r41/` 都有文档指路 ⇒ 全部保留；
  # 下面这几个没有任何活文档或脚本指着 ⇒ 剪。
  board/boot27c.tcl board/rdbck.tcl board/ddr_churn_probe.mjs board/cmd_prime_demo.txt
  board/cmd_r84_osd.txt board/card_v2_preview.png
)
# `build/make_submission.sh` **留**：它是"这个包怎么生成的"那一步的脚本（MANIFEST 也点名它），
# 属于"可复现"，不属于开发工具。
BUILD_DEV_ONLY=(
  build/_scan_align.mjs build/cleanup_wip.sh build/refresh_evidence.sh build/roll_isolated.sh
  build/trim_comments.py build/orphan_rtl.sh build/rim_gate_ce.sh build/tb98_gate_ce.sh
  build/ps_app.mjs build/tag_bench_labels.mjs
)
# 赛程对照表也不进包（用户原话："那些什么与赛程对照啥的都丢掉，直接把这个项目说清楚就行，
# 不过是按照比赛的目录罢了"）：它是作者对着指南打勾用的工作记录，评审要的"比赛推荐的目录形状"
# 已经由摆放本身给出了，不需要在包里再放一张对照表。剪掉之后同样要把指路改口，别留死链接。
DOC_EXCLUDE=(report/log/CONTEST_CHECKLIST.md)

# ---- 无论有没有被点名都留着：跑起来的那一套 ----
KEEP_ALWAYS_RE='\.(sh|tcl|py|ps1|bat|xdc|f|v|c|h)$|^src/(rtl|ps|constraints)/|^data/golden/|MANIFEST|README'

cd "$REPO"
COMMIT="$(git rev-parse --short HEAD)"
DIRTY="$(git status --porcelain | wc -l)"
git archive --format=tar HEAD | tar -x -C "$TMP"
cd "$TMP"

: > _pruned.txt
MV=""
add_mv() { if [ "$1" != "$2" ]; then MV="$MV$1"$'\t'"$2"$'\n'; fi; }
prune() { if [ -e "$1" ]; then rm -rf "$1"; echo "$2 $1" >> _pruned.txt; fi; }

# ---- 1. docs/ -> report/，指路一并改写（只改目录不改指路 = 交一份满篇死链接的包）----
if [ -d docs ]; then
  mkdir -p report
  mv docs/*.md report/ 2>/dev/null || true
  if [ -d docs/log ]; then
    mkdir -p report/log
    for f in docs/log/*.md; do if [ -f "$f" ]; then mv "$f" "report/log/$(basename "$f")"; fi; done
  fi
  rm -rf docs
  # `*.csv` 也在改写名单里：`data/metrics.csv` 是"唯一那张数字表"，每行都点名凭据，
  # 漏改就等于把仓内路径原样搬进包里 ⇒ 评审照表去翻却翻到一个不存在的 `docs/`（D4c 在仓里看得见，在包里看不见）。
  { find . -type f \( -name '*.md' -o -name '*.sh' -o -name '*.tcl' -o -name '*.mjs' -o -name '*.py' \
      -o -name '*.v' -o -name '*.c' -o -name '*.h' -o -name '*.bat' -o -name '*.csv' \) -print; echo README.md; echo README.en.md; } |
  while read -r f; do
    if [ -f "$f" ]; then sed -i 's|\.\./docs/|../report/|g; s|docs/log/|report/log/|g; s|docs/|report/|g' "$f"; fi
  done
fi

# ---- 2. 剪 ----
for n in "${PRUNE_ONEOFF[@]}"; do prune "$n" "一次性脚本"; done
# 过程留档目录（`build/evidence_rNN/`、`build/frozen_rNN/`）默认不进包 —— 但
# **交付文档按路径点名的那些不能剪**：剪掉就等于亲手造出死链接，而包末尾的自检会因此拒绝落盘
# （2026-09-29 把两类目录一起剪时，`report/commands.md` 指着的 `build/evidence_r75/MANIFEST.md5`
# 就变死了，39 条死链全是这一类）。所以先读"活文档点哪些目录"，再决定剪谁。
CRED_DIRS=$( { grep -rhoE '(build|board)/(evidence|frozen)_[A-Za-z0-9_.-]+/' \
    report README.md README.en.md skill board/README.md data/metrics.csv 2>/dev/null; } | sort -u )
for d in build/evidence_* build/frozen_* board/evidence_* board/frozen_*; do
  if [ -d "$d" ]; then
    if printf '%s\n' "$CRED_DIRS" | grep -qF -- "$d/"; then
      echo "保留（交付文档点名要它） $d" >> _pruned.txt
    else
      prune "$d" "过程留档"
    fi
  fi
done
for f in "${DOC_EXCLUDE[@]}"; do prune "$f" "赛程对照（工作记录，不随包）"; done
find . -mindepth 1 2>/dev/null | sed 's|^\./||' | grep -E "$HARD_DROP_RE" |
while read -r n; do if [ -e "$n" ]; then rm -rf "$n"; echo "被否决轮次/中间物 $n" >> _pruned.txt; fi; done || true

LIVE_SCOPE=(report README.md README.en.md skill board data/metrics.csv)
{ grep -rhoE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,5}" "${LIVE_SCOPE[@]}" 2>/dev/null | sed 's|^\./||'; } > _cited.txt || true
{ grep -rhoE "src/host/[A-Za-z0-9_.-]+\.mjs" build/*.sh 2>/dev/null; } >> _cited.txt || true
sort -u -o _cited.txt _cited.txt

for f in src/host/*.mjs; do
  if [ -f "$f" ]; then
    { grep -hoE "from '\./[A-Za-z0-9_.-]+\.mjs'" "$f" 2>/dev/null | sed "s|from '\./||; s|'||" | sed 's|^|src/host/|'; } >> _cited.txt || true
  fi
done
sort -u -o _cited.txt _cited.txt

# 2a) 台架取舍 = 手写名单 ∪ 被留下的脚本点名的（gates.sh 要对它算 md5，指着不存在的文件就是包的缺陷）。
#     其余一律不带：交付文档里以裸名提到它们，说的是"过程里举过的例子"，不是"包里该有这个文件"。
: > _dropped_tb.txt
{ grep -rhoE "tb_[A-Za-z0-9_]+" build/gates.sh build/freeze_evidence.sh sim/run_one.sh sim/mut_control.sh 2>/dev/null |
  sed 's/\.v$//' ; } | sort -u > _script_tb.txt || true
for f in sim/*.v; do
  if [ -f "$f" ]; then
    b="$(basename "$f" .v)"
    hit=0
    for k in "${SIM_KEEP[@]}"; do if [ "$b" = "$k" ]; then hit=1; fi; done
    if grep -qxF "$b" _script_tb.txt; then hit=1; fi
    if [ "$hit" = "0" ]; then
      prune "$f" "回归台架（不随包，文档里的裸名提及指的是仓库）"
      echo "$b" >> _dropped_tb.txt
    fi
  fi
done

# 一条 awk 判完，不逐文件 spawn（Windows 上每个 grep 都要几十毫秒，1500 个文件就是几分钟）
find src/host build sim board data -type f 2>/dev/null | sed 's|^\./||' > _all.txt || true
grep -vE "$KEEP_ALWAYS_RE" _all.txt > _cand.txt || true
sed 's|.*/||' _cited.txt | sort -u > _cited_bases.txt
awk 'FILENAME=="_cited.txt" {c[$0]=1; next}
     FILENAME=="_cited_bases.txt" {b[$0]=1; next}
     { p=$0; n=split(p,a,"/"); bn=a[n]
       if (p in c) next
       # 逐轮留档（build/<frozen|evidence>_rNN/…）**只认路径式点名**：文档里写一句
       # "`cdc_details.rpt` 每轮都有" 不该把十几份 380 KB 的同名副本全拖进包里。
       if (p ~ /^build\/[a-z]+_r[0-9]/) { print "轮次留档未被按路径点名\t" p; next }
       if (p !~ /^src\/host\// && (bn in b)) next
       if (p ~ /^src\/host\//) print "未被活文档按路径点名\t" p
       else print "未被活文档点名\t" p }' _cited.txt _cited_bases.txt _cand.txt > _prune_list.tsv
while IFS=$'\t' read -r r f; do rm -f "$f"; echo "$r $f" >> _pruned.txt; done < _prune_list.tsv

# 2b2) 轮次留档目录里，**只有被按路径点名的**才留。上一版漏了这一层：KEEP_ALWAYS_RE 里的
#      `MANIFEST` 一条让每个 frozen_rNN/evidence_rNN 都靠一份清单活了下来 ⇒ 包里长出 37 个
#      归档目录，评委看到的是"仓库垃圾场"而不是"留档"。清单本身不是理由，被文档指过去才是。
find build -mindepth 2 -type f 2>/dev/null | sed 's|^\./||' |
grep -E '^build/[a-z]+_r[0-9]' |
while read -r f; do
  grep -qxF "$f" _cited.txt || echo "$f"
done > _round_prune.txt || true
while read -r f; do rm -f "$f"; echo "轮次目录里未被按路径点名（清单不算理由） $f" >> _pruned.txt; done < _round_prune.txt
rm -f _round_prune.txt
find build -mindepth 1 -type d -empty -delete 2>/dev/null || true

# 2d) `build/` 只留两样东西：**可复现的构建脚本 + 综合与实现报告**（用户原话"也就是 tcl 和报告"）。
#     逐轮的门禁/控制台留档与归档目录不进包 —— 那是作者的时间轴；活文档里按路径指着它们的句子
#     由 3.9b 就地改口成"仓库留档 <名>（不随包）"，改口与剪枝一一对得上，末尾的死链自检兜住。
#     反过来，**板级实测输出从 build/evidence/ 搬进 board/output/**：让 board/ 一眼就是
#     "上板工程 / 运行脚本 / 实测输出"三样东西（用户："里面是这三样东西我都没看到"）。
IMPL_REPORT_RE='^(system_top_)?(timing_summary|utilization|power|methodology|route_status|clock_util|cdc)\.rpt$|^(crit_paths|multi_driven|width_warnings)\.txt$'
BOARD_MOVE_TCL=(ps_jtag_boot.tcl ps_app_reload.tcl program_pl.tcl program_system.tcl program_and_check.tcl scan_jtag.tcl)
BUILD_PRUNED=()          # 逐条记下被剪的名字，3.9b 用它改口（不靠正则扫全文，避免误伤留下的实现报告）
PRUNED_DIRS=()

# 2d-0) 板上那一版的"门禁凭据"只带一份，并按板上那块的身份取，不靠轮次号
BIT12="$(md5sum "$REPO/build/system.bit" 2>/dev/null | cut -c1-12)"
GBIT=""
if [ -n "$BIT12" ]; then
  for c in "$REPO"/build/*gates*.txt "$REPO"/build/evidence/*gates*.txt "$REPO"/build/evidence_r*/*gates*.txt; do
    if [ -f "$c" ] && grep -q "$BIT12" "$c" 2>/dev/null; then GBIT="$c"; break; fi
  done
fi
if [ -n "$GBIT" ]; then mkdir -p build/reports; cp "$GBIT" build/reports/gates.txt; echo "带上板上那一版的门禁件 $(basename "$GBIT") -> build/reports/gates.txt" >> _pruned.txt; fi

# 2d-1) 板级实测输出：只搬 board/ACCEPTANCE.md 按路径点名的那几份，并把轮次号从包内名字里去掉
mkdir -p board/output
for f in $(grep -ohE 'build/evidence/[A-Za-z0-9_.-]+' board/ACCEPTANCE.md 2>/dev/null | sort -u); do
  if [ -f "$f" ]; then
    nb="$(printf '%s' "$(basename "$f")" | sed -E 's/^r[0-9]+_//; s/_r[0-9]+//')"
    mv "$f" "board/output/$nb"
    add_mv "$f" "board/output/$nb"
    echo "板级实测输出搬进包内板级目录 $f -> board/output/$nb" >> _pruned.txt
  fi
done

# 2d-2) 上板要用的 tcl 与串口脚本归到 board/（工程名在导出时改，仓库里的名字是工作日志引用的）
mkdir -p board/tcl board/scripts
for t in "${BOARD_MOVE_TCL[@]}"; do
  if [ -f "build/tcl/$t" ]; then mv "build/tcl/$t" "board/tcl/$t"; add_mv "build/tcl/$t" "board/tcl/$t"; fi
done
for f in board/*.ps1 board/cmd_*.txt board/*.png board/*.mjs; do
  if [ -f "$f" ]; then mv "$f" "board/scripts/$(basename "$f")"; add_mv "$f" "board/scripts/$(basename "$f")"; fi
done
# 板级剩下的 tcl（`pswhy.tcl` / `rdddr.tcl` 这类读回探针）也归到 board/tcl/：
# 用户要的"运行脚本"是一个能看到的地方，不是散在板级根目录的六个文件。
for f in board/*.tcl; do
  if [ -f "$f" ]; then mv "$f" "board/tcl/$(basename "$f")"; add_mv "$f" "board/tcl/$(basename "$f")"; fi
done

# 2d-3) build/ 根上的**逐轮过程留档**（名字里带轮次号的那些 txt/rpt/log/csv）不进包。
#       判据只用"名字里有没有 rNN"这一条，不另列白名单：实现报告（timing_summary.rpt 等）、
#       板级脚本、gates.sh 要调的 check_ports.py / gates_cdc_test.sh 都不带轮次号，自然留下；
#       而 245 份 `battery_rNN.txt`、`gates_rNN.txt` 是作者的时间轴（用户："其他多余的都删掉"）。
#       ⚠ 这里不要写成"白名单外一律剪"：上一版那样会把 `build/README.md` 和实现报告一起剪掉，
#         并把 gates.sh 还要调的 `gates_cdc_test.sh` 剪掉 —— 一次导出就把交付物砍成了空壳（2026-09-29 撞到）。
for f in build/*.txt build/*.rpt build/*.log build/*.csv; do
  if [ ! -f "$f" ]; then continue; fi
  bn="$(basename "$f")"
  # 例外先判：台架的判据报告**留着** —— `gates.sh` 第 15/16 项就是照名字找它们的，
  # 而交付文档里"这一轮的边缘台架读数"点的也是这份；它们不是过程噪声，是判据本身。
  case "$bn" in tb_edge_rim_r*|tb_v98_report.txt) continue ;; esac
  # 另一类多余件是**探针与扫描**的 console：`probe_*` / `*_console.txt` / `sweep_*` /
  # `*contaminated*` / `*_old.txt` / `*repro_*` / `uram_*` 都不随包。
  # ⚠ 这一条必须排在"名字里没有轮次号就跳过"之前：`probe_rot.txt` 不带 rNN，
  #   排后面等于不剪（第一版就是这么漏掉 8 份探针输出的，2026-09-29 22:27 干跑看到的）。
  case "$bn" in probe_*|*_console.txt|sweep_*|*contaminated*|*_old.txt|*repro_*|uram_*)
    BUILD_PRUNED+=("build/$bn"); prune "$f" "探针/扫描的过程输出（不随包）"; continue ;;
  esac
  case "$bn" in *r[0-9]*) ;; *) continue ;; esac
  if printf '%s' "$bn" | grep -qE "$IMPL_REPORT_RE"; then continue; fi
  BUILD_PRUNED+=("build/$bn"); prune "$f" "build 逐轮过程留档（不随包）"
done
for d in build/evidence build/evidence_* build/frozen_* build/isolated_* build/*_probe board/evidence_* board/frozen_*; do
  if [ -d "$d" ]; then PRUNED_DIRS+=("$d"); fi
done
for d in ${PRUNED_DIRS[@]+"${PRUNED_DIRS[@]}"}; do prune "$d" "归档目录（逐轮留档，不随包）"; done
# 板级目录里带轮次号的记录（`VERIFY_rNN.md` 那类）同理：用户要 board/ 里不留版本叙事。
for f in board/*; do
  if [ -f "$f" ]; then
    bn="$(basename "$f")"
    case "$bn" in *.md|*.tcl|*.mjs) ;; *) continue ;; esac
    case "$bn" in *r[0-9]*) BUILD_PRUNED+=("$f"); prune "$f" "board 里带轮次号的记录（不随包）" ;; esac
  fi
done
# 2c) 二进制一律不带，稍后只放回板上这一版
find . \( -name '*.bit' -o -name '*.xsa' -o -name '*.elf' -o -name '*.dcp' \) -type f 2>/dev/null |
while read -r f; do rm -f "$f"; echo "构建产物（由板上那一版补回） $f" >> _pruned.txt; done || true
find build sim board data src/host -type d -empty -delete 2>/dev/null || true

# ---- 3. 改名：报告展平、文档名小写、台架换名；一份 _map.sed 做全部指路改写 ----
mkdir -p build/reports

# 3.0 台架换名：手写的招牌判据优先；其余只是**去掉轮次号段**（`tb_v6_cover_gate`→`tb_cover_gate`）。
#     规则只有一条：包里的台架名不许带 rNN/vNN —— 那是作者本地的时间轴，不是职责。
declare -A NAME_MAP
for old in "${!SIM_MAP[@]}"; do NAME_MAP["$old"]="${SIM_MAP[$old]}"; done
# 报告文件名里的简称也一起换（`build/tb_v98_report.txt` → `.../tb_video_pipeline_top_report.txt`），
# 否则交付物里会剩下一串只有作者看得懂的 vNN。
NAME_MAP["tb_v98"]="tb_video_pipeline_top"
# 这条别名没有同名文件（它是"报告文件名与正文简称"用的），所以映射要显式登记，
# 否则 `build/tb_v98_report.txt` 与散在 RTL/脚本注释里的 `tb_v98` 换不掉，而旧名残留自检会抓住它。
add_mv "tb_v98" "tb_video_pipeline_top"
for f in sim/tb_*.v; do
  if [ ! -f "$f" ]; then continue; fi
  b="$(basename "$f" .v)"
  new="${NAME_MAP[$b]:-}"
  if [ -z "$new" ]; then
    case "$b" in
      tb_v[0-9]*_*) new="tb_${b#tb_v*_}" ;;
      *) new="$b" ;;
    esac
    if [ "$new" != "$b" ] && [ -e "sim/$new.v" ]; then new="$b"; fi
    NAME_MAP["$b"]="$new"
  fi
  if [ "$b" != "$new" ]; then
    mv "sim/$b.v" "sim/$new.v"
    add_mv "sim/$b.v" "sim/$new.v"
    add_mv "$b" "$new"
  fi
done

# 3.0b 板上那一版的落点也换（文档原来指 build/system.bit，那是仓库里的构建输出位置）
#      包里的位置是 `board/project/`：评委要找的"往板子上放的东西"和"怎么放"都在 board/ 一处。
mkdir -p board/project
for b in build/system.bit build/system.xsa build/ps_app.elf; do
  add_mv "$b" "board/project/$(basename "$b")"
done

# 报告展平：build/**.rpt|txt -> build/reports/[rNN_]名字（名字里带轮次号的换成新台架名）
while IFS= read -r f; do
  f="${f#./}"
  base="$(basename "$f")"
  for old in "${!NAME_MAP[@]}"; do
    case "$base" in *"$old"*) base="${base//$old/${NAME_MAP[$old]}}" ;; esac
  done
  tag="$(printf '%s' "$f" | grep -oE '(^|[^a-z])r[0-9]+' | grep -oE 'r[0-9]+' | head -1 || true)"
  if [ -n "$tag" ] && [ "${base#$tag}" = "$base" ] && [ "${base#*$tag}" = "$base" ]; then
    np="build/reports/${tag}_${base}"
  else
    np="build/reports/$base"     # 名字里本来就带着轮次的（gates_rNN.txt / rNN_*.rpt）不再加前缀
  fi
  if [ -e "$np" ]; then np="build/reports/$(basename "$(dirname "$f")")_$(basename "$base")"; fi
  if [ "$f" != "$np" ]; then mv "$f" "$np"; add_mv "$f" "$np"; fi
done < <(find build -type f \( -name '*.rpt' -o -name '*.txt' \) 2>/dev/null | grep -v '^./build/reports/' | grep -v '^build/evidence/' | sort)

# 交付文档名小写（§3.3.5.4 字面要求；README/LICENSE/MANIFEST 是指南自己用的大写名，留作例外）
# ⚠ 除了整条路径，**裸文件名也要一起进映射表**：文档索引里写的是 ``ARCHITECTURE.md`` 这种不带目录的名字，
#   只映射 `report/ARCHITECTURE.md` 的话，包里的文件已经变成小写、索引却还在指一个大写名 ——
#   死链自检抓不到它（它不是路径形状），但评委照着翻就是翻不到（2026-09-29 干跑时看到）。
for f in report/*.md report/log/*.md; do
  if [ -f "$f" ]; then
    b="$(basename "$f")"
    lb="$(printf '%s' "$b" | tr 'A-Z' 'a-z')"
    case "$lb" in readme.md|license|manifest.txt) lb="$b" ;; esac
    if [ "$b" != "$lb" ]; then
      mv "$f" "$(dirname "$f")/$lb"; add_mv "$f" "$(dirname "$f")/$lb"; add_mv "$b" "$lb"
    fi
  fi
done
for f in board/*.md; do
  if [ -f "$f" ]; then
    b="$(basename "$f")"; lb="$(printf '%s' "$b" | tr 'A-Z' 'a-z')"
    case "$lb" in readme.md) lb="$b" ;; esac
    if [ "$b" != "$lb" ]; then mv "$f" "$(dirname "$f")/$lb"; add_mv "$f" "$(dirname "$f")/$lb"; add_mv "$b" "$lb"; fi
  fi
done

printf '%s' "$MV" > _mv.tsv
: > _map.sed
while IFS=$'\t' read -r o n; do
  if [ -z "$o" ]; then continue; fi
  oe="$(printf '%s' "$o" | sed 's/[.[\*^$&/]/\\&/g')"
  ne="$(printf '%s' "$n" | sed 's/[&|\/]/\\&/g')"
  printf '%d\t%s\t%s\n' "${#o}" "$oe" "$ne"
done < _mv.tsv | sort -rn -k1,1 | cut -f2,3 |
while IFS=$'\t' read -r oe ne; do printf 's|%s|%s|g\n' "$oe" "$ne"; done > _map.sed

# 包里不带、但文档以**路径**提过的回归台架：把那条路径就地改成"仓库回归台架 <名>"。
# 评委照 sim/tb_xxx.v 去找会撞空 —— 空链接是包的缺陷，不是文档的缺陷，所以在这一步补掉。
while read -r b; do
  if [ -n "$b" ]; then
    printf 's|sim/%s\\.v|仓库回归台架 %s（不在本包内）|g\n' "$b" "$b" >> _map.sed
  fi
done < _dropped_tb.txt

# 改写只作用于" prose 与脚本"；证据类（build/reports/、report/log/）保持原文
find . -type f \( -name '*.md' -o -name '*.sh' -o -name '*.tcl' -o -name '*.py' -o -name '*.mjs' \
    -o -name '*.ps1' -o -name '*.bat' -o -name '*.v' -o -name '*.c' -o -name '*.h' -o -name '*.csv' \) 2>/dev/null |
grep -vE '^\./build/reports/|^\./report/log/' > _txt.txt || true
xargs -r sed -i -f _map.sed < _txt.txt

# 新旧名对照（生成的，所以永远与表一致）
{
  echo '# 台架名字对照（导出时由 build/make_submission.sh 生成）'
  echo
  echo '包里按**职责**命名；随包的判据报告是仓库里那一跑的**原始输出**，里面的名字没被改写——'
  echo '改它等于改证据。两边靠这张表对上。'
  echo
  echo '| 包内文件 | 仓库里的名字 | 钉住的结论 |'
  echo '|---|---|---|'
  for old in "${!NAME_MAP[@]}"; do
    if [ "$old" = "${NAME_MAP[$old]}" ]; then
      echo "| \`sim/$old.v\` | 同名（本来就按职责命名） | 见 \`build/reports/\` 里带它名字的那份 |"
    else
      echo "| \`sim/${NAME_MAP[$old]}.v\` | \`$old.v\` | 见 \`build/reports/\` 里带它名字的那份 |"
    fi
  done | sort
} > sim/NAMES.md

for b in build/system.bit build/system.xsa build/ps_app.elf; do
  if [ -f "$REPO/$b" ]; then cp "$REPO/$b" "board/project/$(basename "$b")"; fi
done

# ---- 3.9 被剪掉的**仓库工具**，活文档里的指路就地改口 ----
# 剪掉文件而不改指路 = 亲手造死链接（上一版就是这么被自检拒绝落盘的：25 条里全是这一类）。
# 改口只动"活文档"，`report/log/` 里的日记保持原样 —— 那里写的是"当时那天跑的是哪个脚本"，
# 把它改成"仓库里的"等于替史官改写历史。每改一处都记进 _pruned.txt，让这件事能被核对。
for f in README.md README.en.md report/*.md skill/*.md skill/*/*.md board/*.md sim/*.md \
         data/metrics.csv build/README.md build/tcl/README.md; do
  [ -f "$f" ] || continue
  for t in "${BUILD_DEV_ONLY[@]}"; do
    bn="$(basename "$t")"
    if grep -qF -- "$t" "$f" 2>/dev/null; then
      n="$(grep -cF -- "$t" "$f")"
      sed -i "s|${t//./\\.}|仓库里的 ${bn}（工具，不随包）|g" "$f"
      echo "改口 $f: $t → 仓库里的 ${bn}（$n 处）" >> _pruned.txt
    fi
  done
  # 文档级的排除同理处理：包名已被改成小写，指路可能还是大写，所以两边都匹配（I 标志）。
  for t in "${DOC_EXCLUDE[@]}"; do
    if grep -qiF -- "$t" "$f" 2>/dev/null; then
      n="$(grep -ciF -- "$t" "$f")"
      sed -i "s|${t//./\\.}|仓库里的工作记录（赛程对照，不随包）|Ig" "$f"
      echo "改口 $f: $t → 仓库里的工作记录（$n 处）" >> _pruned.txt
    fi
  done
done

# ---- 3.9b 被剪掉的 build 留档与归档目录：活文档里的**路径式**指路就地改口 ----
# 改口后的文字里不许再留着斜杠形状：死链自检就是照形状从文档里抓 `build/x.txt` 的，
# 留下形状等于留了个问题却没留下文件（"仓库回归台架"那一条定的就是同一写法：换说法，别留壳）。
# 一次生成 sed 表、一遍跑完：这里曾有 245 条剪枝名，逐条 spawn grep/sed 会把这个脚本变成十分钟。
: > _prune_map.sed
for t in ${BUILD_PRUNED[@]+"${BUILD_PRUNED[@]}"}; do
  esc="$(printf '%s' "$t" | sed 's|[][\\.*^$&/|]|\\&|g')"
  printf '%d\ts|%s|仓库留档 %s（逐轮过程件，不随包）|g\n' "${#t}" "$esc" "$(basename "$t")" >> _prune_map.sed
done
for d in ${PRUNED_DIRS[@]+"${PRUNED_DIRS[@]}"}; do
  esc="$(printf '%s' "$d" | sed 's|[][\\.*^$&/|]|\\&|g')"
  printf '9998\ts|%s/\\([A-Za-z0-9_.-]*\\)|仓库留档 \\1（归档件，不随包）|g\n' "$esc" >> _prune_map.sed
done
# 通用形状规则（排在目录规则之后、逐条名字之前）：**台架改名发生在指路改写里**，
# 于是 `build/tb_v98_report_contaminated_1245.txt` 到 3.9b 时已经变成
# `build/tb_video_pipeline_top_report_contaminated_1245.txt`，按仓库原名逐条匹配就漏了它
# （干跑里那 1 条死链就是这么来的）。按"名字里的过程件特征"再兜一遍，比补一张别名表稳。
printf '9997\ts|build/[A-Za-z0-9_./-]*contaminated[A-Za-z0-9_./-]*|仓库留档（被污染的旧报告，不随包）|g\n' >> _prune_map.sed
printf '9997\ts|build/[A-Za-z0-9_./-]*_console\\.[a-z]*|仓库留档（控制台留档，不随包）|g\n' >> _prune_map.sed
printf '9997\ts|build/[A-Za-z0-9_./-]*probe[A-Za-z0-9_./-]*|仓库留档（探针输出，不随包）|g\n' >> _prune_map.sed
printf '9997\ts|build/[A-Za-z0-9_./-]*sweep[A-Za-z0-9_./-]*|仓库留档（策略扫描留档，不随包）|g\n' >> _prune_map.sed
printf '9997\ts|build/[A-Za-z0-9_./-]*repro[A-Za-z0-9_./-]*|仓库留档（复现对照留档，不随包）|g\n' >> _prune_map.sed
printf '9997\ts|build/[A-Za-z0-9_./-]*uram[A-Za-z0-9_./-]*|仓库留档（URAM 探针留档，不随包）|g\n' >> _prune_map.sed
sort -rn _prune_map.sed | cut -f2- > _prune_map.sorted.sed && mv _prune_map.sorted.sed _prune_map.sed
{ ls README.md README.en.md data/metrics.csv 2>/dev/null
  ls report/*.md skill/*.md skill/*/*.md board/*.md sim/*.md build/README.md build/tcl/README.md 2>/dev/null; } |
xargs -r sed -i -f _prune_map.sed
echo "改口：逐轮留档与归档目录的指路，规则 $(grep -c '' _prune_map.sed) 条已作用于活文档" >> _pruned.txt
rm -f _prune_map.sed

# ---- 4. 自检 ----
# 死链清单写到树**外面**：包根目录里不留工作文件（上一版把 _all.txt/_cand.txt/… 九个中间件
# 一起落进了 final_submission/，而 MANIFEST 的"文件数"又把它们算进去 ⇒ 报的数与落地差 2）。
DEADLIST="${TMPDIR:-/tmp}/sub_dead_$(basename "$TMP").txt"
: > "$DEADLIST"
# 空目录在**这一步之前**收：真正让目录变空的是后面"没人点名就剪"那一道，
# 所以删空目录必须排在所有剪枝之后（第一次实现放在剪枝中间，落包时照样剩 10 个空壳）。
EMPTY_DEL=$(find . -type d -empty -delete -print 2>/dev/null | wc -l)
EMPTY_LEFT=$(find . -type d -empty 2>/dev/null | wc -l)
echo "空目录：删掉 $EMPTY_DEL 个，落包后余 $EMPTY_LEFT 个" >> _pruned.txt
echo "  空目录 删=$EMPTY_DEL 余=$EMPTY_LEFT"
# 判死链的范围 = "活文档"（评委照着跑的说明书），**不含 report/log/**：那里的路径是当时那天的名字，
# 台架删了、工具改名了、捕获清了都留在里面，那是过程记录，不该拿它判包不完整。
for f in README.md README.en.md report/*.md skill/*.md skill/*/*.md board/*.md sim/*.md build/*.md build/tcl/*.md data/*.csv; do
  if [ -f "$f" ]; then
    d="$(dirname "$f")"
    grep -oE '(src|sim|build|board|data|skill|report|docs)/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,6}' "$f" 2>/dev/null |
    sort -u | while read -r t; do
      case "$t" in *'*'*|*'<'*|*'$'*|*NN*) continue ;; esac
      case "$t" in *.log|*.out|board/uart_script_capture.txt) continue ;; esac
      if [ -e "$t" ] || [ -e "$d/$t" ]; then continue; fi
      echo "死链 $f -> $t"
    done
  fi
done > "$DEADLIST" 2>&1 || true
DEAD="$(grep -c '死链' "$DEADLIST" 2>/dev/null || true)"; DEAD="${DEAD:-0}"
if [ "$DEAD" = "0" ]; then DEAD=0; fi

# 旧名残留一次算完（每个名字 spawn 一次 grep 在这一千多个文件上要四分钟）
{ for old in "${!NAME_MAP[@]}"; do if [ "$old" != "${NAME_MAP[$old]}" ]; then echo "$old"; fi; done; } > _oldnames.txt
STALE=0
if [ -s _oldnames.txt ]; then
  bad="$( { grep -rlF -f _oldnames.txt --include='*.md' --include='*.sh' --include='*.tcl' --include='*.v' . 2>/dev/null |
            grep -vE '^\./report/log/|^\./build/reports/|^\./sim/NAMES.md' || true; } | tr '\n' ' ')"
  if [ -n "$bad" ]; then echo "残留旧台架名：$bad"; STALE=1; fi
fi

# 绝对路径只判"真被用到的"：注释里写"原来硬编码 D:/... 后来改了"是过程说明，不算违规
# ⚠ 管道末尾必须 || true：没有命中时 grep 退 1，而赋值语句的非零状态会被 set -e 直接杀掉整支脚本
ABS="$( { grep -rnE "D:[/\\]|C:[/\\]|/d/Software|/d/Xilinx" --include='*.sh' --include='*.tcl' --include='*.py' \
          --include='*.mjs' --include='*.ps1' --include='*.bat' --include='*.v' --include='*.c' --include='*.h' \
          --include='*.md' --include='*.xdc' --include='*.csv' \
          --exclude='make_submission.sh' . 2>/dev/null || true; } |
        grep -vE ':[0-9]+:[[:space:]]*(#|//|\*)' | grep -vE '^\./report/log/' | cut -d: -f1 | sort -u | tr '\n' ' ' || true)"
ABSN=0
if [ -n "$ABS" ]; then ABSN="$(printf '%s\n' $ABS | wc -l)"; fi

head -25 "$DEADLIST"
echo "== 自检：死链 $DEAD ／ 旧名残留 $STALE ／ 带绝对路径的脚本 $ABSN${ABS:+ （$ABS）} =="

# 工作文件不许落进包（上一版把九个中间件一起交出去了，而"文件数"又漏数了要交的那份 _pruned.txt）
rm -f _all.txt _cand.txt _cited.txt _cited_bases.txt _dropped_tb.txt _map.sed _mv.tsv \
      _oldnames.txt _prune_list.tsv _script_tb.txt _txt.txt

# ---- 5. 清单 ----
# 数的是"除了本清单以外"的文件：MANIFEST.txt 是在这一行之后才写出来的，
# 上一版把它漏在计数外 ⇒ 报 546、落地 547（#106 的第三次同族复发：计数与落地差一个）
files="$(find . -type f ! -name MANIFEST.txt | wc -l)"
bytes="$(du -sh . | cut -f1)"
removed="$(sort -u -o _pruned.txt _pruned.txt; { grep -c '' _pruned.txt || true; })"; removed="${removed:-0}"
BIT_MD5=""
if [ -f board/project/system.bit ]; then BIT_MD5="$(md5sum board/project/system.bit | cut -c1-12)"; fi
GATES_FOR_BIT="没有一份门禁报告写着这串 md5 ⇒ 这一版不作交付（诊断用）"
if [ -n "$BIT_MD5" ]; then
  hit="$( { grep -rl "$BIT_MD5" build/reports 2>/dev/null || true; } | head -1)"
  if [ -n "$hit" ]; then GATES_FOR_BIT="$hit"; fi
fi

cat > MANIFEST.txt <<EOF
导出时间: $(date '+%Y-%m-%d %H:%M:%S')
来源提交: $COMMIT（导出时工作区未提交改动 $DIRTY 条）
文件数  : $files，体积 $bytes，本次剪掉 $removed 条（逐条与理由见 _pruned.txt）
生成脚本: build/make_submission.sh（可重跑；四条判据写在脚本头部）

目录对照（选题指南 §3.3.5.4 推荐结构 -> 本仓库）
  README.md   项目简介 + 复现步骤   <- README.md（中）/ README.en.md（英）
  src/        设计源码              <- src/rtl/**（PL）+ src/ps/**（裸机固件）+ src/host/**（PC 侧）
  sim/        仿真脚本与结果        <- 支撑交付结论的台架 + run_one.sh/run_sim.tcl + mut_control.sh
                                      名字对照见 sim/NAMES.md，判据报告在 build/reports/
  build/      可复现构建 + 实现报告 <- tcl/build_system_axigpio.tcl（一条命令出位流）
                                     + reports/**（这一版的综合/实现报告）+ 入口脚本 gates.sh
  board/      工程/脚本/实测输出    <- project/**（板上那一版 .bit/.elf/.xsa）
                                     + tcl|scripts/**（JTAG 与串口脚本）+ output/**（实测输出）
  data/       测试数据与参考结果    <- data/golden/**、data/measured/**
  skill/      技能包                <- skill/**（README.md 是索引）
  report/     设计报告 + 协作记录   <- 仓库里的 docs/（交付文档），工作记录在 report/log/

板上那一份（位流与固件仓库不跟踪，按 md5 认身份，不靠文件名）：
$(for f in board/project/*; do if [ -f "$f" ]; then printf '  %-14s md5 %s\n' "$(basename "$f")" "$(md5sum "$f" | cut -c1-12)"; fi; done)  门禁凭据: $GATES_FOR_BIT

自检: 活文档死链 $DEAD 条（0 才算过）／被改名台架的旧名残留 $STALE／含本机绝对路径的脚本 $ABSN
EOF

echo
echo "导出提交 $COMMIT：$files 个文件 / $bytes，剪掉 $removed 条，死链 $DEAD，旧名残留 $STALE，绝对路径 $ABSN"
if [ "$DRY" = "1" ]; then echo "DRY RUN：$TMP 留着，自己看过再 rm -rf"; exit 0; fi
if [ "$DEAD" != "0" ] || [ "$STALE" != "0" ] || [ "$ABSN" != "0" ]; then
  echo "FAIL：死链 $DEAD ／ 旧名残留 $STALE ／ 绝对路径 $ABSN。不写 $OUT。"
  echo "      明细：$DEADLIST 与 $TMP/_pruned.txt"
  exit 1
fi
rm -rf "$OUT"
mv "$TMP" "$OUT"
cd "$REPO"        # 刚被 mv 走的 $TMP 就是上一秒的工作目录，站在里面 find 会直接失败
landed="$(find "$OUT" -type f | wc -l)"
if [ "$landed" != "$((files + 1))" ]; then
  echo "FAIL：MANIFEST 写 $files 个文件，落地数到 $landed（差 1 应该是 MANIFEST.txt 自己，不是就不是）"
  exit 1
fi
echo "-> $OUT（$landed 个文件，与 MANIFEST 的计数一致）"

#!/usr/bin/env bash
# 用途：从当前 git 跟踪集导出选题指南 §3.3.5.4 那份目录（final_submission/）
# 输入：命令行参数、board/uart_script_capture.txt
# 输出：build/reports/gates.txt、build/sim/names.md
# 退出码：0=跑完 1=非 0 分支（该文件 exit 1 那一行）
# make_submission.sh — 从当前 git 跟踪集导出选题指南 §3.3.5.4 那份目录（final_submission/）。
#
# 四条判据，每条都是为了处理"仓库里合理、交出去不合理"：
#  1) **按引用留凭据**：build/ 与 sim/ 跟踪了上千个文件。被交付文档、两份 README、skills/、板级
#     操作卡点名的才带；评委复核任何数字走的都是文档里那条指路，没被点名的留档在包里只是噪声。
#  2) **被否决的轮次不进包**（HARD_DROP）：failed_/red_/rejected/notadopted/_wip/aborted 这些目录
#     即使被文档点名也不带——文档还指着它们，就说明该改的是文档，不是把它们塞进包。
#  3) **交付名工程化**（SIM_MAP + 小写化）：§3.3.5.4 要求文件名纯英文小写；带轮次号的
#     `tb_v98_top_seam.v` 换成按职责命名的 `tb_video_pipeline_top.v`。**改名只发生在导出时**：
#     仓库里那几百处旧名是"当时看到的名字"，改它等于抹掉过程凭据。
#     ⇒ 证据类（build/reports/ 与 report/log/）的正文**不参与改写**，包里那份判据报告仍是跑当时
#       的原文；新旧名对上靠生成的 build/sim/names.md。
#  4) **导出后自检**：活文档里的路径式指路必须在包内解析得出；被改名台架的旧名与本机绝对路径必须为 0。
#     任一不过就不落盘。这一条是防我自己。
#
# 用法：bash build/make_submission.sh [--dry] [--allow-no-gates]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${VP_SUB_OUT:-$(cd "$REPO/.." && pwd)/final_submission}"   # 目标被别的进程占住句柄时可换目录导出（见 ISSUES #231 尾账）
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sub.XXXXXX")"
# 拒绝落盘时 $OUT 里留的是**上一版**：上一版看起来就是一份交付物，这是最坏的一种假绿
# （2026-10-04 实测：`final_submission/` 还是 08:13 从 ef68bb3 导的 519 个文件，根上写着 README.en.md）。
# 所以开局就把"当前这个目录是谁"念出来，别等交付时才发现包是陈的。
if [ -f "$OUT/MANIFEST.txt" ]; then
  echo "注意 $OUT 现在是上一版（$(head -2 "$OUT/MANIFEST.txt" | tr '\n' ' ')）——本轮若拒绝落盘，这个目录不算本轮交付"
fi
DRY=0
# --allow-no-gates：明确接受"诊断用"包（包里没有对应位流的门禁件）。默认**不接受**（F2，见 4x 段）。
ALLOW_NO_GATES=0
for _a in "$@"; do
  case "$_a" in
    --dry) DRY=1 ;;
    --allow-no-gates) ALLOW_NO_GATES=1 ;;
    *) echo "忽略未知参数：$_a（可用：--dry --allow-no-gates）" >&2 ;;
  esac
done

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
HARD_DROP_RE='^build/(failed_|red_|multidrive_|exp_|strprobe|uram_probe|micro_rd|ps_obj|snap_|r[0-9]+_|build/|vivado_system/|__pycache__/)|^docs/walkthrough/|^sim/(probes|msim|v98run|xtest|tagchk|syntaxchk|v100run2)/|^src/rtl/(axi/axi_frame_writer|eth/axi_frame_saver|video/frame_buffer_db|video/video_timing_720p)\.v$'
PRUNE_ONEOFF=(
  build/tcl/apply_cdc_report.tcl build/tcl/micro_rd.tcl
  build/tcl/uram_presence.tcl build/tcl/uram_sites.tcl
  build/tcl/retry_open_nr.log
  build/sim/run_zoom_only.tcl board/ddr_churn_r33_pair.md
  # `build/` 在包里只该有两类东西：**可复现的构建脚本**与**综合/实现报告**（用户看包时提的）。
  # 下面这些是仓里的开发工具，不在复现链上 —— 复现链的名单不是凭印象列的，是从
  # `gates.sh` / `board_verify.sh` 里 grep 出来的：gates.sh 会调 check_ports.py、freeze_evidence.sh、
  # gates_cdc_test.sh、tb98_report.sh、board_verify.sh，所以那几个**留**，其余走。
  # 2026-10-05 目录精简：下面这些名字已经从仓库里真删掉了，留在名单里只会让 `_pruned.txt` 念一条
  # 兜不住任何东西的死规则（#222 同族：规则要说真话），所以连着删掉；`prune()` 本来就有 `[ -e ]`
  # 挡着，少列名字不会漏剪：`build/tcl/uram_probe.tcl`、`build/tcl/dfx_runtime.txt`、
  # `build/roll_isolated.sh`、`build/trim_comments.py`、`build/tag_bench_labels.mjs`、`build/tcl/probe_reasm_fanout.tcl`、
  # `build/tcl/build_system.tcl`、`build/tcl/synth_pl_only.tcl`、`build/tcl/build_bitstream.tcl`、
  # `build/tcl/create_project.tcl`、`build/tcl/fix_bd_and_top.tcl`、`build/tcl/rebuild_opt.tcl`、
  # `build/tcl/rebuild_zoom_out.tcl`、`build/tcl/rebuild_cdc_fix.tcl`。
  # 例外两条：`build/roll_isolated.sh` 与 `build/_scan_align.mjs` 有交付文档按名字点着
  # （`report/build.md`、`report/optimization_log.md`、`report/perf_report.md`、`report/repro-check.md`），
  # 仓库里必须先留着，所以它们仍列在下面 —— 文档改口之后再一起删。
  build/_scan_align.mjs build/cleanup_wip.sh build/refresh_evidence.sh build/roll_isolated.sh
  build/orphan_rtl.sh build/rim_gate_ce.sh build/tb98_gate_ce.sh
  build/ps_app.mjs
  # rNN_ 开头的开发件现在由上面的形状规则统一剪掉，不再逐个列名字（列名就会漏，r92 漏过九个）。
  # `board/` 同理：留"上板工程 / 运行脚本 / 实测输出"，一次性探针走。
  # 名单不是凭印象 —— 先查过谁被指路：`rdddr.tcl` 被 build.md 点名、`demo_rehearsal.txt` 被 gates.sh 用、
  # `pswhy.tcl` / `serial_bytes.ps1` / `uart_*.ps1` / `evidence_r41/` 都有文档指路 ⇒ 全部保留；
  # 下面这几个没有任何活文档或脚本指着 ⇒ 剪。
  board/boot27c.tcl board/rdbck.tcl board/ddr_churn_probe.mjs board/cmd_prime_demo.txt
  board/cmd_r84_osd.txt board/card_v2_preview.png
)
# `build/make_submission.sh` **留**：它是"这个包怎么生成的"那一步的脚本（MANIFEST 也点名它），
# 属于"可复现"，不属于开发工具。
BUILD_DEV_ONLY=(
  build/_scan_align.mjs build/cleanup_wip.sh build/refresh_evidence.sh build/roll_isolated.sh
  build/orphan_rtl.sh build/rim_gate_ce.sh build/tb98_gate_ce.sh
  build/ps_app.mjs
)
# 赛程对照表也不进包（用户原话："那些什么与赛程对照啥的都丢掉，直接把这个项目说清楚就行，
# 不过是按照比赛的目录罢了"）：它是作者对着指南打勾用的工作记录，评审要的"比赛推荐的目录形状"
# 已经由摆放本身给出了，不需要在包里再放一张对照表。剪掉之后同样要把指路改口，别留死链接。
DOC_EXCLUDE=(report/log/contest_checklist.md)

# ---- 无论有没有被点名都留着：跑起来的那一套 ----
# `^build/report/` 是 §4.4 点名的交付层（资源 LUT/FF/BRAM/DSP/IO + 频率/WNS/TNS），两份 README 的
# 凭据就指在这里；它曾被 PRUNE_ONEOFF 当成"一次性脚本"整目录剪掉 ⇒ 包里连目录都没有，首页三条
# 凭据全成死链（2026-10-04 实测，台账 #371）。形状规则兜住，别再靠逐个点名。
# PS 裸机固件现在在 `src/ps/`（与 src/rtl、src/constraints 同级），不再是 src/host/ps。
# 这条形状规则要跟着改口。诚实说清它今天兜着什么、明天兜着什么：
#  · 旧口径下它是**承重**的——裁剪池 `find src/host …` 会把 src/host/ps/* 收进去，而下面那条
#    "src/host/ 下的件必须被活文档按路径点名"会把 main.c 剪掉，靠这一条才免检。
#  · 新口径下 src/ps 与 src/rtl 一样不在裁剪池里，所以这一条当下不兜东西；名单留着是把
#    "固件在哪"这件事写在脚本里，哪天有人把 src 加进 find，固件不会被静默剪出包。
KEEP_ALWAYS_RE='\.(sh|tcl|py|ps1|bat|xdc|f|v|c|h)$|^src/(rtl|ps|constraints)/|^build/report/|^data/golden/|MANIFEST|README|^submit/|^skills/'

cd "$REPO"
COMMIT="$(git rev-parse --short HEAD)"
DIRTY="$(git status --porcelain | wc -l)"
git archive --format=tar HEAD | tar -x -C "$TMP"
cd "$TMP"

: > _pruned.txt
MV=""
add_mv() { if [ "$1" != "$2" ]; then MV="$MV$1"$'\t'"$2"$'\n'; fi; }
prune() { if [ -e "$1" ]; then rm -rf "$1"; echo "$2 $1" >> _pruned.txt; fi; }

# ---- 0. 活文档射程：由 find 现算，不留手写名单 ----
# 手写名单会随目录长出新子树而**静默变窄**，而窄掉的那一层不会报错（规矩 47：射程漂移是无声的）：
#   · 技能包本轮改成 `skills/<类别>/<条目>/SKILL.md`（三级），旧名单只写了两级 ⇒ 58 个条目全掉出射程；
#   · `docs/` 重新成为交付层（那两次 docs→report 改名轮都退回了，见 report/log/issues.md），
#     而旧名单里根本没有它 ⇒ 126 条"死链"的形状就是"文件在包里、指路在文档里、射程里没有它"。
# 所以射程只由一条 find 算出，并打印**逐层计数**：某层归零即判这一层没扫成，不判这一层干净。
# 做成**函数**而不是快照：改名与剪枝都发生在射程计算之后，快照会漏掉刚被小写化的那批文件
# ——第一版就是这么把 `report/timing/round_r117.md` 的指路改口整个跳过的。
live_docs() {
  { find . -type f -name '*.md' ! -path './report/log/*' ! -path './build/reports/*'
    find . -type f -name '*.csv' ! -path './board/compare/*' ; } | sed 's|^\./||' | sort -u
}
live_docs > _live_docs.txt
LIVE_N="$(grep -c '' _live_docs.txt)"
ALL_CSV_N="$(find . -type f -name '*.csv' 2>/dev/null | wc -l)"
KEPT_CSV_N="$( { grep -c '\.csv$' _live_docs.txt || true; } )"; KEPT_CSV_N="${KEPT_CSV_N:-0}"
SCOPE_ROWS=""
for L in $(find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|^./||' | sort); do
  n="$( { grep -c "^$L/" _live_docs.txt || true; } )"; n="${n:-0}"
  SCOPE_ROWS="$SCOPE_ROWS $L=$n"
  md="$( { find "$L" -type f -name '*.md' 2>/dev/null; find "$L" -type f -name '*.csv' 2>/dev/null; } | wc -l )"; md="${md:-0}"
  if [ "$n" = "0" ] && [ "$md" != "0" ]; then
    echo "REFUSE：活文档射程里 $L/ 一层数到 0，而包内有这个目录 ⇒ 这是射程漂移，不是那一层没有文档" >&2
    exit 1
  fi
done
for must in README.md README_EN.md report/README.md skills/README.md report/src-map.md report/README.md; do
  if ! grep -qxF "$must" _live_docs.txt; then
    echo "REFUSE：射程里缺必看入口 $must（评委照着翻的第一批文件）" >&2
    exit 1
  fi
done
REPO_MD_N="$(git -C "$REPO" ls-files '*.md' | wc -l)"
if [ "$LIVE_N" -lt 40 ]; then
  echo "REFUSE：射程只数到 $LIVE_N 份活文档，而仓库 git 跟踪的 *.md 有 $REPO_MD_N 份 ⇒ 这一层多半没扫成" >&2
  exit 1
fi
echo "射程 活文档=$LIVE_N（仓库 *.md=$REPO_MD_N；排除 report/log/ 与 build/reports/ 两层过程/证据件）$SCOPE_ROWS csv 全树=$ALL_CSV_N 入射程=$KEPT_CSV_N（board/compare/ 是差分辨识表，按证据件排除）" | tee -a _pruned.txt

# ---- 1. 目录布局：仓库什么形状，包就什么形状（§3.3.5.4 的对照说明写在 MANIFEST 与 report/README.md）----
# 这里原来有一段 `docs/` 并入 `report/` 的迁移：那是 §4.5 定案里"下一次改名轮"的半成品，
# 而那一轮**两次尝试都退回了**（任务 #145），仓库现在是 `report/` + `docs/` 两层并存。
# 这一段的历史教训留着：当年只做了 `rm -rf docs` 却没改指路，包内 126 条引用指向一个自己不存在的目录。
# 2026-10-05 用户改口径：学习文档（`docs/course` 十章 + `docs/walkthrough`）从仓库撤掉、只在本地读，
# 所以这一层现在**既不入库也不随包**——`git archive HEAD` 里就没有它，导出器不再需要"保留那一层"。
# 随之必须成立的是：交付文档里不许再留指向 docs/course 或 docs/walkthrough 的活指路（下面那条计数判据就是干这个的）。
echo "布局 docs/ 不入库也不随包（学习文档按用户要求只留本地），report/ 随包；两层的指路都要走下一节的活引用自检" >> _pruned.txt
_livecoursecites=0
for _f in $(find report -type f -name '*.md' ! -path 'report/log/*'); do
  _n=$(grep -c 'docs/course\|docs/walkthrough' "$_f" 2>/dev/null || true)
  _livecoursecites=$((_livecoursecites + ${_n:-0}))
done
echo "活指路自检：report/（排除 report/log/）里指向 docs/course 或 docs/walkthrough 的行数 = $_livecoursecites（要求 0；这份学习文档已不在仓里）" >> _pruned.txt
if [ "$_livecoursecites" -ne 0 ]; then
  echo "REFUSE：学习文档已撤出仓库，但 report/ 里仍有 $_livecoursecites 行指向 docs/course 或 docs/walkthrough" >&2
  exit 3
fi

# ---- 2. 剪 ----
for n in "${PRUNE_ONEOFF[@]}"; do prune "$n" "一次性脚本"; done
# 过程留档目录（`build/evidence_rNN/`、`build/frozen_rNN/`）默认不进包 —— 但
# **交付文档按路径点名的那些不能剪**：剪掉就等于亲手造出死链接，而包末尾的自检会因此拒绝落盘
# （2026-09-29 把两类目录一起剪时，`report/commands.md` 指着的 `build/evidence_r75/manifest.md5`
# 就变死了，39 条死链全是这一类）。所以先读"活文档点哪些目录"，再决定剪谁。
CRED_DIRS=$( { grep -rhoE '(build|board)/(evidence|frozen)_[A-Za-z0-9_.-]+/' \
    report README.md README_EN.md skills board/README.md data/metrics.csv 2>/dev/null || true; } | sort -u )
for d in build/evidence_* build/frozen_* board/evidence_* board/frozen_*; do
  if [ -d "$d" ]; then
    if printf '%s\n' "$CRED_DIRS" | grep -qF -- "$d/"; then
      # #173：这一行以前写"保留"，可下面那圈 `PRUNED_DIRS` 无条件剪掉所有 build/evidence_* ⇒
      #   目录照样不随包，而包里的 `_pruned.txt` 留着一句假话。决定没变（凭据在仓库里按 md5 认，
      #   不复制进包），变的只是**说真话**：点名要它 ≠ 随包送它。
      echo "文档点名但仍不随包（按 §…决定不复制；仓库里按 md5 认） $d" >> _pruned.txt
    else
      prune "$d" "过程留档"
    fi
  fi
done
for f in "${DOC_EXCLUDE[@]}"; do prune "$f" "赛程对照（工作记录，不随包）"; done
# 学习文档（0 基础讲解、英文海报稿）按队伍 2026-10-04 的指令**不上传**：它们在 .gitignore 里
# （所以从来没进过 git），但导出器是从工作树复制的，不在这里剪掉就会随包送出去。
prune "report/study" "学习文档（用户指令：不上传）"
find . -mindepth 1 2>/dev/null | sed 's|^\./||' | grep -E "$HARD_DROP_RE" |
while read -r n; do if [ -e "$n" ]; then rm -rf "$n"; echo "被否决轮次/中间物 $n" >> _pruned.txt; fi; done || true

# 引用面 = 活文档全体 + 台账（`report/log/`，它的引用不算"包里必须有"，但它确实点了名，留着更稳）
# + 根上两份 README + `submit/`（评审阅读路径）+ `docs/`（本轮重新成为交付层；旧名单没有它，
# 于是只被 docs 点名的件会被判成"没人要"而剪掉 ⇒ 包内少文件、文档里留指路，两头都错）。
LIVE_SCOPE=(report skills README.md README_EN.md board data src sim build)
{ grep -rhoE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,5}" "${LIVE_SCOPE[@]}" 2>/dev/null | sed 's|^\./||'; } > _cited.txt || true
# 射程念出来：数到 0 的那一层要能看出来（旧写法里 `docs submit skill` 三个名字在包内不存在，
# grep 退 2 被 2>/dev/null 吃掉，set -e 直接把脚本打死——死因不在任何一行输出里）。
echo "指路射程 $(for g in "${LIVE_SCOPE[@]}"; do printf '%s=%s ' "$g" "$( { find "$g" -type f 2>/dev/null | wc -l; } )"; done)"
{ grep -rhoE "src/host/[A-Za-z0-9_.-]+\.mjs" build/*.sh 2>/dev/null; } >> _cited.txt || true
sort -u -o _cited.txt _cited.txt

for f in src/host/*.mjs; do
  if [ -f "$f" ]; then
    { grep -hoE "from '\./[A-Za-z0-9_.-]+\.mjs'" "$f" 2>/dev/null | sed "s|from '\./||; s|'||" | sed 's|^|src/host/|'; } >> _cited.txt || true
  fi
done
sort -u -o _cited.txt _cited.txt

# 2a) 台架取舍 = `sim/README.md` 表格里列出的（§2.4 那张表由台架文件头现生成，列到就必须随包，
#     否则包里那张表指着一个包里不存在的 .v ⇒ 死链，而这条门自己会拒绝落盘）
#     ∪ 手写名单 ∪ 被留下的脚本点名的（gates.sh 要对它算 md5，指着不存在的文件就是包的缺陷）。
: > _dropped_tb.txt
{ grep -rhoE "tb_[A-Za-z0-9_]+" build/gates.sh build/freeze_evidence.sh build/sim/run_one.sh build/sim/mut_control.sh 2>/dev/null |
  sed 's/\.v$//' ; } | sort -u > _script_tb.txt || true
{ grep -oE '^\|[[:space:]]*`?[a-z0-9_-]+\.v' sim/README.md 2>/dev/null | sed 's/^[^a-z]*//; s/\.v$//' | sort -u > _table_tb.txt || true; }
if [ ! -s _table_tb.txt ]; then echo "REFUSE：sim/README.md 表格一格台架名都没数到 ⇒ 这张表没生成，台架取舍没有依据" >&2; exit 1; fi
for f in sim/*.v; do
  if [ -f "$f" ]; then
    b="$(basename "$f" .v)"
    hit=0
    for k in "${SIM_KEEP[@]}"; do if [ "$b" = "$k" ]; then hit=1; fi; done
    if grep -qxF "$b" _script_tb.txt; then hit=1; fi
    if grep -qxF "$b" _table_tb.txt; then hit=1; fi
    if [ "$hit" = "0" ]; then
      prune "$f" "回归台架（不随包，文档里的裸名提及指的是仓库）"
      echo "$b" >> _dropped_tb.txt
    fi
  fi
done

echo "台架取舍 表格列=$(grep -c '' _table_tb.txt) 脚本点名=$(grep -c '' _script_tb.txt) 随包=$( { find sim -maxdepth 1 -name '*.v' | wc -l; } ) 剔=$( { [ -f _dropped_tb.txt ] && grep -c '' _dropped_tb.txt || echo 0; } )"

# 被取代的那一次尝试的中间件（文件名里自带 51pass_1fail）不随包：包里送的是**最终**那一份凭据
# `regression_v79_r46.txt`，attempt1 是仓库里的历史。没有任何活文档按路径点它（grep attempt1 在 *.md 里 0 命中），
# 所以剪它不会造出死链；留着随包就会撞上"未声明的红"这条门（白名单只允许 C5c）。
for f in build/sim/results/*attempt*.txt; do if [ -f "$f" ]; then prune "$f" "被取代的那一次尝试的中间件（最终件随包）"; fi; done

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

# 2d-1) 板级实测输出：把**交付文档按路径点名的**那几份搬进包内板级目录，并把轮次号从包内名字里去掉。
#   ⚠ 2026-10-02 修：这里原来只扫 `board/acceptance.md` 一个文件，而 2d-4 那一圈无条件删掉
#   `build/evidence/` 整目录 ⇒ 凡是只被 README / README.en / report/*.md 点名的凭据，
#   **文件被删、指路却留下**（当天实测：包内 README 引用 `r104_holdrow_stale_red.txt`，
#   而 `board/output/` 里 15 份没有它，末尾的死链自检还报 0 —— 那条自检照"斜杠形状"抓，
#   这条引用到那时已经不是斜杠形状了）。所以判据换成"哪份文档有资格让凭据随包"：
#   **交付文档全体的路径式点名**，但 `report/log/`（过程台账）除外——那一层导出器自己声明
#   "包内不可解析只报数、不参与包完整性"，让它决定谁随包会把 766 条历史引用一起拖进来。
mkdir -p board/output
# 扫描面可由 SUB_EVIDENCE_DOCS 覆盖——**只为让这条地板能被同一段代码证明会红**
# （规矩 38(c)：反例必须跑门禁自己跑的那条路，不能另写一份小复现）。平时不设就用默认的全交付文档。
EV_DOCS="${SUB_EVIDENCE_DOCS:-$(find . -name '*.md' -not -path './report/log/*' 2>/dev/null | sort)}"
# 扫描面的**形状**地板：README、README.en、ACCEPTANCE 这三份必须在射程里。
# 今天那个洞的准确形状就是"只扫 ACCEPTANCE"——它不从引用数上看得出来（少扫的文件根本没进引用集），
# 只有从"扫了哪几份文档"这个独立分母才看得出来（规矩 23(c)：分母不许由被检的那条分支算）。
for must in ./README.md ./README_EN.md ./board/acceptance.md; do
  printf '%s\n' "$EV_DOCS" | grep -qx "$must" || { echo "REFUSE：板级凭据的扫描面缺了 $must（今日洞的形状）" >&2; exit 1; }
done
EV_CITED=$(grep -ohE 'build/evidence/[A-Za-z0-9_.-]+' $EV_DOCS 2>/dev/null | sort -u)
EV_PRESENT=0; EV_MOVED=0; EV_CLASH=""
for f in $EV_CITED; do
  if [ -f "$f" ]; then
    EV_PRESENT=$((EV_PRESENT + 1))
    nb="$(printf '%s' "$(basename "$f")" | sed -E 's/^r[0-9]+[a-z]?_//; s/_r[0-9]+//')"
    # 去轮次号之后撞名 ⇒ **退让而不是覆盖**：先试原名（带着轮次号，仍然是个好读的名字），
    # 两边都一样才真冲突——那种情况记下来让下面那条地板拒绝落盘。
    # 今天第一次跑到这里就是撞在 `artifact_md5.txt` 上（`r85_…` 与另一轮的 `…_artifact_md5.txt`
    # 去掉编号后同名），按旧写法后一份会**静默覆盖**前一份，包里少一份凭据而计数看不出来。
    if [ -e "board/output/$nb" ]; then
      alt="$(basename "$f")"
      if [ -e "board/output/$alt" ]; then EV_CLASH="$EV_CLASH $f"; continue; fi
      echo "板级凭据去轮次号会撞名，这一份保留原名 $f -> board/output/$alt" >> _pruned.txt
      nb="$alt"
    fi
    if [ -e "board/output/$nb" ]; then EV_CLASH="$EV_CLASH $f"; continue; fi
    # 撞名不是小事：两份留档去掉轮次号后同名 ⇒ 后一份**静默覆盖**前一份，包里就少一份凭据。
    if [ -e "board/output/$nb" ]; then EV_CLASH="$EV_CLASH $f->$nb"; continue; fi
    mv "$f" "board/output/$nb"
    add_mv "$f" "board/output/$nb"
    EV_MOVED=$((EV_MOVED + 1))
    echo "板级实测输出搬进包内板级目录 $f -> board/output/$nb" >> _pruned.txt
  fi
done
# 射程地板（2026-10-02 与上面那条范围修同批）：**交付文档点了几份、盘上有几份、包里就得有几份**。
# 少了就是这一层在漏 —— 今天那个洞的形状正是"点名 29 份、只搬 15 份、剩下 14 份被整目录删掉，
# 而引用还被改成了不带目录的样子，死链自检照斜杠形状抓不到"。撞名也算漏，单独念出来。
if [ "$EV_MOVED" != "$EV_PRESENT" ]; then
  echo "REFUSE：板级凭据随包不完整 —— 点名且盘上 $EV_PRESENT 份，搬进包 $EV_MOVED 份；撞名被跳过：${EV_CLASH:-无}" >&2
  exit 1
fi
echo "板级凭据随包：交付文档点名 $(printf '%s\n' $EV_CITED | grep -c .) 份 / 盘上 $EV_PRESENT 份 / 搬进包 $EV_MOVED 份（撞名 ${EV_CLASH:-0}）"

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
# ⚠ `build/report/`（单数）这一层**原位不动**：它是 §4.4 点名的交付层，仓库里、包里、两份 README 里
#   指的是同一个路径。以前没有这条排除，包里 `build/report/power.rpt` 被搬成 `build/reports/power.rpt`，
#   而首页写的是 `build/report/{timing_summary,utilization,power}.rpt` —— 花括号缩写没有任何一条
#   逐路径改名规则能命中（改名规则是字面旧路径→新路径），于是评委一进包点首页第一条凭据就撞空
#   （2026-10-04 实测：`死链 README.md -> build/report/power.rpt` 中英各 3 条，台账 #368）。
#   同一列还有个哑 bug：`grep -v '^./build/reports/'` 永不生效（find 输出不带 `./`），这里一并改成字面 `^build/reports/`。
# ⚠ `|| true` 不能省：本脚本 `set -euo pipefail`，目录不存在时 find 的 1 会顺着管道把整条赋值
#   判成失败 ⇒ 脚本**一声不响地 exit 1**（2026-10-04 实测：日志只到 FLAT_KEEP_N=0，REFUSE 那句
#   根本没机会打印，任务通知还写 exit 0）。这一族的教训是 pipefail 下的计数子壳必须自己兜底。
FLAT_KEEP_N="$( { find build/report -type f \( -name '*.rpt' -o -name '*.txt' \) 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [ "$FLAT_KEEP_N" -lt 1 ]; then
  echo "REFUSE：暂存区里 build/report/ 一份 .rpt 都没有 ⇒ 首页 §4.4 那三条凭据指路没有目标，包不落盘" >&2
  exit 1
fi
FLAT_MOVE_N=0
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
# ⚠ 除了整条路径，**裸文件名也要一起进映射表**：文档索引里写的是 ``architecture.md`` 这种不带目录的名字，
#   只映射 `report/architecture.md` 的话，包里的文件已经变成小写、索引却还在指一个大写名 ——
#   死链自检抓不到它（它不是路径形状），但评委照着翻就是翻不到（2026-09-29 干跑时看到）。
# ⚠ 名单也要由 find 现算：上一版写死 `report/*.md report/log/*.md board/*.md`，于是
#   `report/timing/round_r117.md` 这类**大写名进了包、指路也没换**——小写化这一层对新加的 docs 层
#   什么都没做（同一族的射程漂移）。`skills/**/SKILL.md` 是**故意不进**这张表的：§3.3.5.2 点名的
#   条目外壳就叫 `SKILL.md`，把它小写化等于自己造死链接；大写路径的整体处置是待决项 Q-P21-2。
LOWER_SRC="$( { find . -name '*.md' ! -path './report/log/*' 2>/dev/null || true; } | sed 's|^\./||' | sort )"
LOWER_N="$(printf '%s\n' "$LOWER_SRC" | grep -c . || true)"
for f in $LOWER_SRC; do
  if [ -f "$f" ]; then
    b="$(basename "$f")"
    lb="$(printf '%s' "$b" | tr 'A-Z' 'a-z')"
    case "$lb" in readme.md|readme_en.md|license|manifest.txt) lb="$b" ;; esac
    if [ "$b" != "$lb" ]; then
      mv "$f" "$(dirname "$f")/$lb"; add_mv "$f" "$(dirname "$f")/$lb"; add_mv "$b" "$lb"
    fi
  fi
done
echo "小写化：候选 $LOWER_N 份（射程由 find 现算，不写层名——上一版点名 docs/，而包里没有这一层，find 退非零把整支脚本在 set -e 下打死且一行解释都不留），实际改名 $(printf '%s' "$MV" | grep -c '^[^\t]*\t[^\t]' || true) 条映射" >> _pruned.txt

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

# #195a：**通配形状**的凭据引用。上面的改名规则是逐条旧路径→新路径，可 `ls -1 build/tb_edge_rim_r*.txt`
# 这种带星号的引用没有任何一条字面规则能命中，于是只有名字被换了（`tb_edge_rim`→`tb_display_edge_rim`）、
# 目录还指着 `build/`，而文件已经被 3. 那段展平进 `build/reports/` 了 ⇒ 包里那份入口脚本找不到自己的凭据。
# 改名规则在同一次 sed 里排在前（按长度），所以这条补的是"改完名之后的形状"；第 4 步会当场数一遍有没有命中。
printf 's|build/\\(tb_display_edge_rim_r\\)|build/reports/\\1|g\n' >> _map.sed
# 同一族第二种形状：交付文档点名的**门禁凭据**是 `build/rNN_gates.txt`，而 `HARD_DROP_RE` 里
# `^build/r[0-9]+_` 把整条 rNN_ 前缀剪掉（那些是逐轮过程件），随包的那一份在下面 4x 段被复制成
# `build/reports/gates.txt` ⇒ 不补这条规则，首页"板上现在跑的是 rNN：门禁 24 项 23 绿 / 1 红"那句的
# 凭据在包里就是空的（仓库里必须继续写 `build/r118_gates.txt`，那是盘上真文件，D4b 认它）。
printf 's|build/r[0-9][0-9]*_gates_final\\.txt|build/reports/gates.txt|g\n' >> _map.sed
printf 's|build/r[0-9][0-9]*_gates\\.txt|build/reports/gates.txt|g\n' >> _map.sed

# 学习文档（`docs/walkthrough/`）**不随包**是队伍定的规矩，但协作记录/待办台账里成段抄着它们的路径
# ⇒ 上面 HARD_DROP 剪掉文件之后，那些路径就成了"照着翻翻不到"的空链接。这一条把路径形状换成
# 文字形状（和上面"仓库回归台架 X（不在本包内）"同一族）：**只改包里的指法，不改仓库里的原文**，
# 因为台账那句是"当时读的是哪一篇"的凭据。
printf 's|docs/walkthrough/\\([A-Za-z0-9_.-]*\\)\\.md|学习文档 \\1.md（本地留档，不随本包）|g\n' >> _map.sed

# 技能包 2026-10-04 重建（28 张平铺卡 → `skills/<组>/<条目>/SKILL.md`）之前的旧条目名还留在
# `report/*.md` 与协作记录里。包里**翻不到**的那些就地降级成文字，剩下的仍是指向真实条目的路径。
# 名单由"包内实际有没有这个文件"现算，不写死 ⇒ 条目以后再加/再改名，这一层自己跟着变（射程不漂）。
# ⚠ 这条正则是**射程本身**，只能按形状数、不能按层数写死：上一版写成 `skills/<一段>/<一段>.ext`，
#   于是三层深的 `skills/pitfalls/<条目>/SKILL.md` 全都不匹配 —— 现测"被引用的技能路径共数 18 个"，
#   而交付文档里点到 skills 的路径有 117 处 ⇒ 这一层几乎空转（少报方向，见台账 #373 的同类教训）。
SKILL_CITED="$( { grep -rhoE 'skills/[A-Za-z0-9_./-]+\.(md|sh|mjs|py)' --include='*.md' . 2>/dev/null || true; } | sort -u )"
# ⚠ 单独一个规则文件、单独一遍 sed（不并进 `_map.sed`）：上一版并进主映射后，实测主映射里的
# 其它规则先改写过同一行，`_map.sed` 的字面旧路径规则就再也匹配不上 ⇒ 打印"降级 73 个"而包内
# 三层深的 `skills/pitfalls/<旧条目>/skill.md` 原样留着 20 处（台账 #374）。
: > _skill_map.sed
SKILL_FIX_N=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  _pl="$(printf '%s' "$p" | tr 'A-Z' 'a-z')"
  if [ ! -e "$p" ] && [ ! -e "$_pl" ]; then
    printf 's|%s|技能包旧条目 %s（重建前的名字，未随本包；现有条目索引见 skills/README.md）|g\n' \
      "$p" "$(basename "$(dirname "$p")")/$(basename "$p")" >> _skill_map.sed
    SKILL_FIX_N=$((SKILL_FIX_N + 1))
  fi
done < <(printf '%s\n' "$SKILL_CITED")
echo "旧技能条目名就地降级 $SKILL_FIX_N 个（被引用的技能路径共数 $(printf '%s\n' "$SKILL_CITED" | grep -c . ) 个）" >> _pruned.txt

# 改写只作用于" prose 与脚本"；证据类（build/reports/、report/log/）保持原文
find . -type f \( -name '*.md' -o -name '*.sh' -o -name '*.tcl' -o -name '*.py' -o -name '*.mjs' \
    -o -name '*.ps1' -o -name '*.bat' -o -name '*.v' -o -name '*.c' -o -name '*.h' -o -name '*.csv' \) 2>/dev/null |
grep -vE '^\./build/reports/|^\./report/log/' > _txt.txt || true
xargs -r sed -i -f _map.sed < _txt.txt

# 技能旧名那一族单独一遍，跑完立刻**自证**：再数一次"包里还有多少 `skills/…` 引用落不到文件"。
# 上一版的错就是把规则并进主映射（别的规则先改写过同一行 ⇒ 字面旧路径再匹配不上），打印了
# "降级 73 个"却留下 20 条三层深的旧引用（台账 #374）。这条判据把"我说过改了"和"确实改完了"
# 绑在一起：残留 > 0 就 REFUSE，不再让这一层可以空转（[[feedback-ruler-teeth-empty-sets]]）。
# 第二遍 sed 的**可观测性**（#376 留下的三个候选，一次全照出来）：规则条数、清单行数、
# 两遍前后"含 skills 形状引用的文件数"。若规则>0 而命中文件数不变，问题在清单/射程；
# 若命中数下降但仍 >0，问题在规则本身；若 _skill_map.sed 是空的，问题在生成段。
SM_N="$( { grep -c '' _skill_map.sed || true; } )"
TX_N="$( { grep -c '' _txt.txt || true; } )"
HIT_BEFORE="$( { while IFS= read -r ff; do ff="${ff#./}"; [ -f "$ff" ] || continue; if grep -lqE 'skills/[A-Za-z0-9_./-]+\.(md|sh|mjs|py)' "$ff" 2>/dev/null; then printf 'X\n'; fi; done < _txt.txt; } | grep -c X || true )"
HIT_BEFORE="${HIT_BEFORE:-0}"
xargs -r sed -i -f _skill_map.sed < _txt.txt
HIT_AFTER="$( { while IFS= read -r ff; do ff="${ff#./}"; [ -f "$ff" ] || continue; if grep -lqE 'skills/[A-Za-z0-9_./-]+\.(md|sh|mjs|py)' "$ff" 2>/dev/null; then printf 'X\n'; fi; done < _txt.txt; } | grep -c X || true )"
HIT_AFTER="${HIT_AFTER:-0}"
echo "技能降级一遍可观测性：规则 $SM_N 条／改写清单 $TX_N 行／含 skills 引用的文件数 改前 $HIT_BEFORE → 改后 $HIT_AFTER" >> _pruned.txt
# ⚠ 残留计数必须与**改写射程同面**：上一版对着整棵暂存树数，把 `report/log/`、`build/reports/` 这些
#   按规矩**永不改写**的证据件也算进来 ⇒ 这一条永远不可能归零，REFUSE 成了假红（实测 47 个，
#   其中多数在证据层）。现在只数 `_txt.txt` 里那份"主改写实际处理过的文件清单"。
SKILL_LEFT="$( { while IFS= read -r ff; do ff="${ff#./}"; [ -f "$ff" ] || continue; grep -hoE 'skills/[A-Za-z0-9_./-]+\.(md|sh|mjs|py)' "$ff" || true; done < _txt.txt; } | sort -u | { while IFS= read -r q; do if [ -n "$q" ] && [ ! -e "$q" ] && [ ! -e "$(printf '%s' "$q" | tr 'A-Z' 'a-z')" ]; then printf 'X\n'; fi; done | grep -c X || true; } )"
SKILL_LEFT="${SKILL_LEFT:-0}"
echo "技能旧名独立一遍后仍未落地的引用 $SKILL_LEFT 个" >> _pruned.txt
if [ "$SKILL_LEFT" -gt 0 ]; then
  echo "REFUSE：技能旧名降级这一层没吃完（包内仍有 $SKILL_LEFT 个 skills 开头的引用落不到文件；规则 $SM_N 条／清单 $TX_N 行／含引用文件 改前 $HIT_BEFORE → 改后 $HIT_AFTER），不交一个自称改完过的包" >&2
  exit 1
fi

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
} > build/sim/names.md

for b in build/system.bit build/system.xsa build/ps_app.elf; do
  if [ -f "$REPO/$b" ]; then cp "$REPO/$b" "board/project/$(basename "$b")"; fi
done

# ---- 3.9 被剪掉的**仓库工具**，活文档里的指路就地改口 ----
# 剪掉文件而不改指路 = 亲手造死链接（上一版就是这么被自检拒绝落盘的：25 条里全是这一类）。
# 改口只动"活文档"，`report/log/` 里的日记保持原样 —— 那里写的是"当时那天跑的是哪个脚本"，
# 把它改成"仓库里的"等于替史官改写历史。每改一处都记进 _pruned.txt，让这件事能被核对。
for f in $(live_docs); do
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
# 通用对称（#341 的正面修法）：**剪掉一个具体文件，就必须有一条把它的指路改口的规则**。
# 原来只有 BUILD_DEV_ONLY / DOC_EXCLUDE / BUILD_PRUNED 三个**子集**在生成规则，而
# PRUNE_ONEOFF 那十几件与 2b 那一圈"没人点名就剪"只剪不改 ⇒ 包里留下成批死引用（本轮实测 15 条）。
# 现在规则直接从 `_pruned.txt` 现取（每行是"理由 路径"，取最后一栏），剪几条就长几条——
# 两半共用同一个来源，不对称就只能一起消失，不会一处改了另一处忘。
PRUNED_PATHS="$(awk '{print $NF}' _pruned.txt | grep -E '\.(md|sh|tcl|py|mjs|ps1|png|txt|rpt|v|c|h|bat|csv)$' | sort -u)"
PRUNED_N="$(printf '%s\n' "$PRUNED_PATHS" | grep -c .)"; PRUNED_N="${PRUNED_N:-0}"
PRUNE_RULES=0
for p in $PRUNED_PATHS; do
  if [ -e "$p" ]; then continue; fi   # 还在盘上 = 这一条没真剪掉（或只是目录），不生成改口
  esc="$(printf '%s' "$p" | sed 's|[][\\.*^$&/|]|\\&|g')"
  printf '9999\ts|%s|仓库留档 %s（剪枝件，不随包）|g\n' "$esc" "$(basename "$p")" >> _prune_map.sed
  PRUNE_RULES="$((PRUNE_RULES + 1))"
done
echo "改口对称：剪枝件路径 $PRUNED_N 条 ⇒ 生成逐条规则 $PRUNE_RULES 条（同一来源现取；两者不等就是这一层在漏）" >> _pruned.txt
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
# 这一轮的**工作件**（隔离滚的读数、`rNN_*.txt` 那类对照）本来就只留在仓库里：
# 交付文档 r90 那一节按路径点了它们的名字，所以也要改口 —— 注意 `build/reports/`、
# `build/rim_report.sh` 这些**要随包**的名字不能被 `r[0-9]` 误伤，所以判据是"r 后面紧跟数字"。
printf '9997\ts|build/isolated[A-Za-z0-9_./-]*|仓库留档（隔离构建的读数，不随包）|g\n' >> _prune_map.sed
printf '9997\ts|build/r[0-9][A-Za-z0-9_./-]*|仓库留档（本轮工作件，不随包）|g\n' >> _prune_map.sed
sort -rn _prune_map.sed | cut -f2- > _prune_map.sorted.sed && mv _prune_map.sorted.sed _prune_map.sed
live_docs | xargs -r sed -i -f _prune_map.sed
echo "改口：逐轮留档与归档目录的指路，规则 $(grep -c '' _prune_map.sed) 条已作用于活文档 $(live_docs | wc -l) 份（射程由 find 现算，不是手写名单）" >> _pruned.txt
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
# 判死链的范围 = "活文档"（评委照着跑的说明书），由 live_docs 现算；**不含 report/log/**：
# 那里的路径是当时那天的名字，台架删了、工具改名了、捕获清了都留在里面，那是过程记录，不该拿它判包不完整。
DEADSCAN=0
DEADSKIP=0
DEADSHIELD=0
# "这行不是指路"的同行声明词（一行只按字面判，不看上下文；命中数逐份打印，别让它变成万能免检）：
#   不随包 / 本地留档 / 不入库  —— 声明"这东西故意不在包里"（学习文档、厂商样例、一次性件都走这一类）
#   未写 / 未落地 / 尚未 / 规划 / 待装配 —— 声明"这个落点还不存在"，是计划不是链接
#   例如 / 示例 / 假想 / 不存在 —— 声明"这个名字是举例"（技能卡里的反例、模板里的占位路径）
SKIP_RE='不随包|本地留档|不入库|未写|未落地|尚未|规划|待装配|例如|示例|假想|不存在'
for f in $(live_docs); do
  if [ -f "$f" ]; then
    DEADSCAN="$((DEADSCAN + 1))"
    d="$(dirname "$f")"
    sk="$( { grep -cE "$SKIP_RE" "$f" 2>/dev/null || true; } )"; sk="${sk:-0}"
    DEADSKIP="$((DEADSKIP + sk))"
    # 这一层**实际挡下**几条指路：数的是"命中词的那些行里，本来会被判死的形状路径"。
    #   上一版把这串词表交给了 sed 的地址（默认 BRE），而 `|` 在 BRE 里是字面竖线 ⇒ 整行删除
    #   一条也没删掉，可"命中 840 行"照样打印 —— 报的是保护，做的是空转（2026-10-06 实测）。
    #   下面把"词表有命中、却一条指路都没挡住"判成空转并拒绝落盘，这一层就再也藏不住。
    sh="$(sed -e 's/-log[[:space:]]\{1,\}[^[:space:];"`]*/ /g' "$f" 2>/dev/null |
          grep -E "$SKIP_RE" 2>/dev/null |
          grep -oE '(src|sim|build|board|data|skills?|report|docs)/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,6}' 2>/dev/null |
          sort -u | wc -l)"; sh="${sh:-0}"
    DEADSHIELD="$((DEADSHIELD + sh))"
    # #172：先抹掉 `-log <路径>` 这类**工具自己创建的输出**（`vivado -mode batch -log sim/xsim.log` 那种），
    #   再抽指路。这不是把 `*.log` 整类放回免检名单 —— 那样就等于把自检买通；
    #   只有"这条命令要写出来的文件"不算死链，"文档点名的凭据"照样该存在。
    # 同行声明词的过滤用 grep -E（ERE 里 `|` 才是"或"；sed 那条是 BRE，会把整串词表当字面量）：
    #   命中词与路径在同一条句子里，说明这一行的那个名字本来就没打算让评委去翻 ⇒ **整行删掉再抽路径**。
    sed -e 's/-log[[:space:]]\{1,\}[^[:space:];"`]*/ /g' "$f" 2>/dev/null | grep -vE "$SKIP_RE" |
    grep -oE '(src|sim|build|board|data|skills?|report|docs)/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,6}' 2>/dev/null |
    sort -u | while read -r t; do
      case "$t" in *'*'*|*'<'*|*'$'*|*NN*) continue ;; esac
      # #172：`*.log` 从免检名单里去掉 —— 它当时是为了绕开"冻结件的逐列读数进不了 git"，
      #   结果把整条自检买通了。产物一律 .txt 之后，指到 `*.log` 的引用就是真死链，该报。
      case "$t" in *.out|board/uart_script_capture.txt) continue ;; esac
      if [ -e "$t" ] || [ -e "$d/$t" ]; then continue; fi
      echo "死链 $f -> $t"
    done
  fi
done > "$DEADLIST" 2>&1 || true
DEAD="$(grep -c '死链' "$DEADLIST" 2>/dev/null || true)"; DEAD="${DEAD:-0}"
if [ "$DEAD" = "0" ]; then DEAD=0; fi
# 空转地板（#195b 同族）：死链判的是"扫了多少份文档"，不是"死链有多少"。扫不到东西就是这把尺子没跑，
# 而不是包干净了 —— 上一版的射程是手写名单，名单漂了它自己不会说。
if [ "$DEADSCAN" -lt 40 ]; then
  echo "FAIL：死链自检只扫了 $DEADSCAN 份活文档（射程下限 40）⇒ 这一项什么都没查，不写 $OUT" >&2
  exit 1
fi
# 豁免层的空转判据（与上面同一族）：词表在文档里命中了行，却一条指路都没挡住，说明这一层
# 又退化成了"只报数不干活"（BRE/ERE 那次就是这样）⇒ 宁可停下，也别带着假保护落盘。
if [ "$DEADSKIP" -gt 0 ] && [ "$DEADSHIELD" -eq 0 ]; then
  echo "FAIL：同行声明词命中 $DEADSKIP 行、却一条指路都没挡住 ⇒ 豁免层空转，不写 $OUT" >&2
  exit 1
fi
echo "  死链射程 扫=$DEADSCAN 份活文档 抓=$DEAD 同行声明命中行=$DEADSKIP 其中真正挡下指路=$DEADSHIELD 条（词表：不随包/本地留档/不入库/未写/未落地/尚未/规划/待装配/例如/示例/假想/不存在）"

# 旧名残留一次算完（每个名字 spawn 一次 grep 在这一千多个文件上要四分钟）
{ for old in "${!NAME_MAP[@]}"; do if [ "$old" != "${NAME_MAP[$old]}" ]; then echo "$old"; fi; done; } > _oldnames.txt
STALE=0
if [ -s _oldnames.txt ]; then
  bad="$( { grep -rlF -f _oldnames.txt --include='*.md' --include='*.sh' --include='*.tcl' --include='*.v' . 2>/dev/null |
            grep -vE '^\./report/log/|^\./build/reports/|^\./build/sim/names.md' || true; } | tr '\n' ' ')"
  if [ -n "$bad" ]; then echo "残留旧台架名：$bad"; STALE=1; fi
fi

# ---- 3. 绝对路径分三层判：单位是"评审会不会照字面敲这一行" ----
# 甲) **可执行件**（.sh/.tcl/.py/.mjs/.ps1/.bat/.v/.c/.h/.xdc）：里面有本机路径 ⇒ 换一台机器就跑不动 ⇒ **硬 0**。
#     唯一例外是**同一行带 `abs-fixture` 标记**的：那是检查器自带的反例内容（与本机无关的通用形态字符串），
#     不是指令。豁免逐条计数打出来，免得这个标记变成万能免检（先例：#222"同行声明才放行"）。
# 乙) **复现入口文档**（两份 README、`submit/reproduce/`、`report/70-reproduce.md`、`report/build.md`、
#     `build/tcl/README.md`、`report/repro-check.md`、`report/acceptance-recipes.md`、`report/declarations.md`、
#     `report/submission-checklist.md`）：这些是"照着敲"的说明书，指令与本机盘符混在一行表格里的也算指令 ⇒ **硬 0**。
# 丙) 其余 markdown/csv 里的**叙述**（"当时读的是本机这份 PDF""工具原话打印的是 D:\Sof…"）：
#     改掉等于改写凭据 ⇒ **只报数不判红**，但逐文件计数打出来（同 #217 台账那一层的处理方式），
#     并给一条防空转地板：这一层数出 0 份被扫 = 尺子没跑，不是包干净了。
# ⚠ 管道末尾必须 || true：没有命中时 grep 退 1，而赋值语句的非零状态会被 set -e 直接杀掉整支脚本
ABS_RE='D:[/\\]|C:[/\\]|/d/Software|/d/Xilinx'
ABS_CODE="$( { grep -rnE "$ABS_RE" --include='*.sh' --include='*.tcl' --include='*.py' --include='*.mjs' \
          --include='*.ps1' --include='*.bat' --include='*.v' --include='*.c' --include='*.h' --include='*.xdc' \
          --exclude='make_submission.sh' . 2>/dev/null || true; } |
        grep -vE ':[0-9]+:[[:space:]]*(#|//|\*)' | grep -v 'abs-fixture' |
        cut -d: -f1 | sort -u | tr '\n' ' ' || true)"
ABSN_CODE=0
if [ -n "$ABS_CODE" ]; then ABSN_CODE="$(printf '%s\n' $ABS_CODE | wc -l)"; fi
ABS_FIXTURE="$( { grep -rnE "$ABS_RE" --include='*.sh' --include='*.tcl' --include='*.py' --include='*.mjs' \
          --exclude='make_submission.sh' . 2>/dev/null || true; } | grep -c 'abs-fixture' || true)"
ABS_FIXTURE="${ABS_FIXTURE:-0}"
ENTRY_SCANNED=0
ABSN_ENTRY=0
ABS_ENTRY=""
for g in README.md README_EN.md report/70-reproduce.md report/build.md build/tcl/README.md \
         report/repro-check.md report/acceptance-recipes.md report/declarations.md report/submission-checklist.md \
         $(ls submit/reproduce/*.md 2>/dev/null); do
  if [ ! -f "$g" ]; then continue; fi
  ENTRY_SCANNED="$((ENTRY_SCANNED + 1))"
  if grep -nE "$ABS_RE" "$g" 2>/dev/null | grep -qvE '^[0-9]+:[[:space:]]*(#|//|\*)'; then
    ABSN_ENTRY="$((ABSN_ENTRY + 1))"; ABS_ENTRY="$ABS_ENTRY ./$g"
  fi
done
if [ "$ENTRY_SCANNED" -lt 8 ]; then
  echo "FAIL：复现入口文档只扫到 $ENTRY_SCANNED 份（地板 8）⇒ 乙层什么都没查，不写 $OUT" >&2
  exit 1
fi
NARR_TMO="${TMPDIR:-/tmp}/sub_narr_$(basename "$TMP").txt"
: > "$NARR_TMO"
NARR_SCANNED=0
for g in $(live_docs); do
  case "$g" in *.md|*.csv) ;; *) continue ;; esac
  if [ ! -f "$g" ]; then continue; fi
  case " README.md README_EN.md report/70-reproduce.md report/build.md build/tcl/README.md report/repro-check.md report/acceptance-recipes.md report/declarations.md report/submission-checklist.md " in
    *" $g "*) continue ;;
  esac
  case "$g" in submit/reproduce/*) continue ;; esac
  NARR_SCANNED="$((NARR_SCANNED + 1))"
  n="$( { grep -cE "$ABS_RE" "$g" 2>/dev/null || true; } )"; n="${n:-0}"
  if [ "$n" != "0" ]; then echo "$n $g" >> "$NARR_TMO"; fi
done
NARR_LINES="$( { awk '{s+=$1} END{print s+0}' "$NARR_TMO"; } )"
NARR_FILES="$( { grep -c '' "$NARR_TMO" || true; } )"; NARR_FILES="${NARR_FILES:-0}"
if [ "$NARR_SCANNED" -lt 40 ]; then
  echo "FAIL：叙述层只扫了 $NARR_SCANNED 份 markdown/csv（地板 40）⇒ 这一层没跑成" >&2
  exit 1
fi
ABSN="$((ABSN_CODE + ABSN_ENTRY))"
ABS="$ABS_CODE $ABS_ENTRY"
echo "绝对路径：甲 可执行件=$ABSN_CODE${ABS_CODE:+ （$ABS_CODE）} 乙 复现入口件=$ABSN_ENTRY（扫 $ENTRY_SCANNED 份）${ABS_ENTRY:+ （$ABS_ENTRY）} 丙 叙述=行 $NARR_LINES／文件 $NARR_FILES（扫 $NARR_SCANNED 份，只报数：那一层记的是「当时读的是哪一份」的凭据，改掉等于改写证据） 甲层豁免=$ABS_FIXTURE 行（abs-fixture 反例内容）"

# ---- #217：台账（report/log/）的指路**只报数**，不判红 ----
# 上面的死链判据范围是"活文档"（评委照着跑的说明书），日记类不在里面——那里的路径是**当天在仓库里**的名字，
# 改名与剪枝都留在里面，那是过程记录（同 D1/D4c 划过的边界）。但"不在射程里"和"没人知道有多少"是两回事：
# 03:36 实测包内 `report/log/*.md` 有 **748 条引用在包内不可解析（547 个唯一目标）**，
# 而我第一次数出 0 —— 那是我那条命令的引号写坏了。所以这里把数**由工具打出来**，
# 并且给它一条防空转的方向：这一层如果打 0，说明多半没扫到文件，而不是台账变干净了。
LOGDEAD=0; LOGFILES=0
if [ -d report/log ]; then
  LOGFILES="$(ls report/log/*.md 2>/dev/null | wc -l)"
  LOGDEAD="$(for g in report/log/*.md; do
      [ -f "$g" ] || continue
      grep -oE '(src|sim|build|board|data|skill|report|docs)/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,6}' "$g" 2>/dev/null |
      sort -u | while read -r t; do
        case "$t" in *'*'*|*'<'*|*'$'*|*NN*) continue ;; esac
        case "$t" in *.out|board/uart_script_capture.txt) continue ;; esac
        [ -e "$t" ] && continue
        [ -e "report/log/$t" ] && continue
        echo x
      done
    done | wc -l)"
fi
echo "台账指路（report/log/，$LOGFILES 份）：包内不可解析 $LOGDEAD 条 —— **只报数不判红**：那里记的是当天在仓库里的路径，"
echo "  过程记录不参与「包完整性」判据；评委要核对读数请走活文档点名的 build/reports/ 那一份（那条由上面的死链自检与 D6 管）。"
if [ "${LOGFILES:-0}" -gt 0 ] && [ "${LOGDEAD:-0}" = "0" ]; then
  echo "  ⚠ 这一层数出 0 是可疑的：台账里从来都有路径引用。先确认 $LOGFILES 这份文件真的被扫到了，别把尺子坏了念成干净。"
fi

head -25 "$DEADLIST"
echo "== 自检：死链 $DEAD ／ 旧名残留 $STALE ／ 绝对路径（甲 可执行件 + 乙 复现入口件）$ABSN${ABS:+ （$ABS）} =="

# 工作文件不许落进包（上一版把九个中间件一起交出去了，而"文件数"又漏数了要交的那份 _pruned.txt）
rm -f _all.txt _cand.txt _cited.txt _cited_bases.txt _dropped_tb.txt _map.sed _mv.tsv \
      _oldnames.txt _prune_list.tsv _script_tb.txt _txt.txt _live_docs.txt

# ---- 5. 清单 ----
# 数的是"除了本清单以外"的文件：MANIFEST.txt 是在这一行之后才写出来的，
# 上一版把它漏在计数外 ⇒ 报 546、落地 547（#106 的第三次同族复发：计数与落地差一个）
files="$(find . -type f ! -name MANIFEST.txt | wc -l)"
bytes="$(du -sh . | cut -f1)"
removed="$(sort -u -o _pruned.txt _pruned.txt; { grep -c '' _pruned.txt || true; })"; removed="${removed:-0}"
BIT_MD5=""
if [ -f board/project/system.bit ]; then BIT_MD5="$(md5sum board/project/system.bit | cut -c1-12)"; fi
GATES_FOR_BIT="没有一份门禁报告写着这串 md5 ⇒ 这一版不作交付（诊断用）"
NO_GATES=1
if [ -n "$BIT_MD5" ]; then
  hit="$( { grep -rl "$BIT_MD5" build/reports 2>/dev/null || true; } | head -1)"
  if [ -n "$hit" ]; then GATES_FOR_BIT="$hit"; NO_GATES=0; fi
fi

cat > MANIFEST.txt <<EOF
导出时间: $(date '+%Y-%m-%d %H:%M:%S')
来源提交: $COMMIT（导出时工作区未提交改动 $DIRTY 条）
文件数  : $files，体积 $bytes，本次剪掉 $removed 条（逐条与理由见 _pruned.txt）
生成脚本: build/make_submission.sh（可重跑；四条判据写在脚本头部）

目录对照（选题指南 §3.3.5.4 推荐结构 -> 本仓库）
  README.md   项目简介 + 复现步骤   <- README.md（中）/ README_EN.md（英）
  src/        设计源码              <- src/rtl/**（PL）+ src/ps/**（裸机固件）+ src/host/**（PC 侧）
  sim/        仿真脚本与结果        <- 支撑交付结论的台架 + run_one.sh/run_sim.tcl + mut_control.sh
                                      名字对照见 build/sim/names.md，判据报告在 build/reports/
  build/      可复现构建 + 实现报告 <- tcl/build_system_axigpio.tcl（一条命令出位流）
                                     + reports/**（这一版的综合/实现报告）+ 入口脚本 gates.sh
  board/      工程/脚本/实测输出    <- project/**（板上那一版 .bit/.elf/.xsa）
                                     + tcl|scripts/**（JTAG 与串口脚本）+ output/**（实测输出）
  data/       测试数据与参考结果    <- data/golden/**、data/measured/**
  skills/      技能包                <- skills/**（README.md 是索引；条目外壳按 §3.3.5.2 就叫 SKILL.md）
  report/     设计报告 + 协作记录   <- 仓库里的 report/（交付文档），工作记录在 report/log/
  ——  以下两层是"其他组织方式"的一部分，对照说明同样写在 README.md / report/README.md：
  docs/       度量、名册与逐轮台账  <- 仓库里的 docs/（含 docs/timing/ 的逐时钟名册）；
                                      它与 report/ 的分工：report/ 讲结论，docs/ 放支撑结论的表与逐轮读数
  submit/     评审阅读路径          <- 仓库里的 submit/（八章分章 + reproduce/），不复制数字

板上那一份（位流与固件仓库不跟踪，按 md5 认身份，不靠文件名）：
$(for f in board/project/*; do if [ -f "$f" ]; then printf '  %-14s md5 %s\n' "$(basename "$f")" "$(md5sum "$f" | cut -c1-12)"; fi; done)  门禁凭据: $GATES_FOR_BIT

自检: 活文档死链 $DEAD 条（0 才算过，射程 $DEADSCAN 份活文档由 find 现算）／被改名台架的旧名残留 $STALE／绝对路径（甲 可执行件 + 乙 复现入口文档）$ABSN 条（另有叙述层 $NARR_LINES 行只报数，那些是"当时读的是哪一份"的凭据）
EOF

echo
echo "导出提交 $COMMIT：$files 个文件 / $bytes，剪掉 $removed 条，死链 $DEAD，旧名残留 $STALE，绝对路径 $ABSN"

# ---- 4x) 三条**内容/自洽**判定（2026-09-30 由"检查检查器"那一轮坐实，都是我自己读码确认过的）----
# #191：以前包里没有对应位流的门禁件时，MANIFEST 会写「这一版不作交付（诊断用）」而脚本 **exit 0**——
#       交付出去的东西自己声明自己不算交付，比不交更糟（评审第一页就读到）。根因在 gates.sh 只打
#       mtime、从不把 system.bit 的 md5 打进报告里 ⇒ 这一位永远查不到匹配（本轮补那一刀，这里先拒）。
# #190：随包的台架/门禁凭据从没被看过内容 ⇒ 一份写着 `RESULT … FAIL nfail=2` 的台架报告照发。
#       本项目故意留一条红（`C5c`/#98，公开在 report/known_issues.md 第一节），所以**不是**"有红就拒"，
#       而是"红必须在白名单里"——红得对与红得不明不白必须能区分（这条区分本身就是本项目的规矩）。
# #195a：入口脚本（门禁）在包里是按 **glob** 找凭据的，而本脚本把批判据报告展平进了 `build/reports/`；
#        改名规则是"逐条旧路径→新路径"，通配形状够不着 ⇒ 名字换了、目录没换，包里那份脚本会在
#        第 16 项对评审报"缺凭据"。这里把那些 glob 抽出来**在包里数一遍**，数不出东西就是包的缺陷。
GLOBCHK="${TMPDIR:-/tmp}/sub_glob_$(basename "$TMP").txt"
: > "$GLOBCHK"
{ grep -hoE 'ls -1 build/[^" ]*\*[^" ]*' build/gates.sh 2>/dev/null || true; } |
  sed 's/^ls -1 //' | sort -u |
while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    _n="$( { ls -1 $pat 2>/dev/null || true; } | wc -l )"
    echo "$_n $pat" >> "$GLOBCHK"
done || true
GLOBTESTED="$( { grep -c '' "$GLOBCHK" || true; } )"; GLOBTESTED="${GLOBTESTED:-0}"
GLOBMISS="$( { awk '$1==0{print $2}' "$GLOBCHK" || true; } | tr '\n' ' ' )"
echo "包内自洽：入口脚本按 glob 找凭据的引用共核对 $GLOBTESTED 条（核对数为 0 时这一条是空的，别念成绿）"
# #195b：光把这句写在输出里不够——写在输出里而退出码仍是 0，于是"扫到 0 条"照样出包。
# 入口脚本按设计至少有一条 glob 引用（它点名的是包内 reports/ 那批凭据），所以 0 只能说明
# **这条核对本身没跑成**：要么上游管道没产出、要么引用形状变了。这类"空集上的绿"本项目
# 记过一整族账（#193/#194），这里补成硬门。反证很简单：GLOBTESTED=0 走这一支、=1 放行，
# 两条都在链尾打印出来，别把"没有回归"念成"回归查过了"。
if [ "${GLOBTESTED:-0}" -eq 0 ]; then
  echo "FAIL：包内自洽这条核对扫到 0 条引用 ⇒ 这一项什么都没查（不是过了），不写 $OUT"
  echo "      查两处：入口脚本里的 glob 是否还在（形状变了就要一起改这条扫描），以及包内 reports/ 是否真落了凭据。"
  exit 1
fi
if [ -n "$GLOBMISS" ]; then
  echo "FAIL：包内入口脚本按这些 glob 找不到任何凭据 ⇒ 不写 $OUT：$GLOBMISS"
  echo "      要么把改名规则补成**路径形状**（3. 那一段末尾的通用规则），要么把这些件放回它点名的目录。"
  exit 1
fi
KNOWN_RED_RE='^[ ]*FAIL C5c'
redall=0; redunk=0
if [ -d build/reports ]; then
  for _r in build/reports/*.txt; do
    [ -f "$_r" ] || continue
    _n="$( { grep -c '^[ ]*FAIL ' "$_r" || true; } )"; redall="$((redall + ${_n:-0}))"
    _u="$( { grep '^[ ]*FAIL ' "$_r" | grep -vc "$KNOWN_RED_RE" || true; } )"; redunk="$((redunk + ${_u:-0}))"
  done
fi
echo "随包凭据内容判定：FAIL 行共 $redall，其中未声明的红 $redunk（白名单只允许 '$KNOWN_RED_RE'）"
if [ "$NO_GATES" = "1" ] && [ "$ALLOW_NO_GATES" != "1" ]; then
  echo "FAIL：找不到与这块位流（$(basename "${BIT_MD5:-?}")）同批的门禁件 ⇒ 不写 $OUT。"
  echo "      要么先跑出配对的门禁报告（门禁脚本得把 bit 的 md5 打进去，r99 那一刀），"
  echo "      要么明确接受诊断包：加 --allow-no-gates。"
  exit 1
fi
if [ "$redunk" != "0" ]; then
  echo "FAIL：随包凭据里有 $redunk 行没声明过的红 ⇒ 不写 $OUT（明细如下，先修它或把它公开进 KNOWN_ISSUES）"
  for _r in build/reports/*.txt; do
    [ -f "$_r" ] || continue
    grep '^[ ]*FAIL ' "$_r" | grep -v "$KNOWN_RED_RE" | sed "s|^|      $(basename "$_r"): |" | head -5 || true
  done
  exit 1
fi

if [ "$DRY" = "1" ]; then echo "DRY RUN：$TMP 留着，自己看过再 rm -rf"; exit 0; fi
if [ "$DEAD" != "0" ] || [ "$STALE" != "0" ] || [ "$ABSN" != "0" ]; then
  echo "FAIL：死链 $DEAD ／ 旧名残留 $STALE ／ 绝对路径 $ABSN。不写 $OUT。"
  echo "      明细：$DEADLIST 与 $TMP/_pruned.txt"
  exit 1
fi
# ⚠ 2026-10-02 03:23 踩过一次：`rm -rf "$OUT"` 报 `Device or resource busy` 之后脚本**继续往下走**，
#   照样打印"344 个文件 / 死链 0 / 未声明的红 0"这一堆好消息，只在最后一行留一个 rc=1，
#   而 `find final_submission -type f` 数是 **0**。半空的提交包比不导出更糟：它看起来是导出过的。
#   ⇒ 把 rm 的失败当**中止**处理。
#   （我第一版在这里还加过两条"当前目录在不在包内"的预检——**那是无效的，已删**：本脚本开头就 `cd "$REPO"`，
#    所以调用方的 cwd 与 $OUT 永远不会相等；而且实测"从包内那个目录调用本脚本"返回的是 rc=0。
#    也就是说**触发这次 busy 的真正原因没查明**，唯一确定的是"失败必须停"，所以只留这一手。
#    重跑就好：03:25 从父目录重跑，rc=0、345 个文件、死链 0。）
rm -rf "$OUT" || {
    echo "FAIL：删不掉旧包 $OUT（多半被某个进程占着句柄）。此刻包内可能是**半空**状态" >&2
    echo "      ⇒ 不要信「导出成功」那几行，先数一遍 $OUT 的文件数，再换一个时刻重跑本脚本。" >&2
    exit 1
}
mv "$TMP" "$OUT"
cd "$REPO"        # 刚被 mv 走的 $TMP 就是上一秒的工作目录，站在里面 find 会直接失败
landed="$(find "$OUT" -type f | wc -l)"
if [ "$landed" != "$((files + 1))" ]; then
  echo "FAIL：MANIFEST 写 $files 个文件，落地数到 $landed（差 1 应该是 MANIFEST.txt 自己，不是就不是）"
  exit 1
fi
echo "-> $OUT（$landed 个文件，与 MANIFEST 的计数一致）"

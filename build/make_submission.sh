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
SIM_PLAIN=(tb_link_monitor tb_zoom_mapper tb_rotate_window)
# 台架取舍与报告同一把尺：**交付文档引用了它的结论，它就必须在包里**（引用即支撑）。
# 手写映射只负责把"招牌判据"换成职责名；没进映射的 `tb_vNN_名字` 自动去掉轮次号段。
SIM_KEEP=("${!SIM_MAP[@]}" "${SIM_PLAIN[@]}")

# ---- 硬剔除：被否决的轮次、探针与构建中间物、零引用 RTL ----
HARD_DROP_RE='^build/(failed_|red_|multidrive_|exp_|strprobe|uram_probe|micro_rd|ps_obj|snap_|r[0-9]+_isolated|r[0-9]+_exp|build/|vivado_system/|__pycache__/)|^build/(evidence|frozen)_r[0-9]+[^/]*(rejected|notadopted|wip)/|^sim/(probes|msim|v98run|xtest|tagchk|syntaxchk|v100run2)/|^src/rtl/(axi/axi_frame_writer|eth/axi_frame_saver|video/frame_buffer_db|video/video_timing_720p)\.v$'
PRUNE_ONEOFF=(
  build/tcl/apply_cdc_report.tcl build/tcl/fix_bd_and_top.tcl build/tcl/rebuild_opt.tcl
  build/tcl/rebuild_zoom_out.tcl build/tcl/rebuild_cdc_fix.tcl build/tcl/micro_rd.tcl
  build/tcl/uram_presence.tcl build/tcl/uram_probe.tcl build/tcl/uram_sites.tcl
  build/tcl/ooc_newmods.tcl build/tcl/dfx_runtime.txt build/tcl/retry_open_nr.log
  sim/run_zoom_only.tcl tight_setup_hold_pins.txt
  build/_scan_align.mjs build/roll_isolated.sh build/cleanup_wip.sh
)

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
  { find . -type f \( -name '*.md' -o -name '*.sh' -o -name '*.tcl' -o -name '*.mjs' -o -name '*.py' \
      -o -name '*.v' -o -name '*.c' -o -name '*.h' -o -name '*.bat' \) -print; echo README.md; echo README.en.md; } |
  while read -r f; do
    if [ -f "$f" ]; then sed -i 's|\.\./docs/|../report/|g; s|docs/log/|report/log/|g; s|docs/|report/|g' "$f"; fi
  done
fi

# ---- 2. 剪 ----
for n in "${PRUNE_ONEOFF[@]}"; do prune "$n" "一次性脚本"; done
find . -mindepth 1 2>/dev/null | sed 's|^\./||' | grep -E "$HARD_DROP_RE" |
while read -r n; do if [ -e "$n" ]; then rm -rf "$n"; echo "被否决轮次/中间物 $n" >> _pruned.txt; fi; done || true

# 2a) 台架取舍放在 _cited 建好之后（判据与报告同源：文档引用了它的结论才带）

# 台架被引用的形态常常是裸名（"`tb_v98_top_seam` 的 C5c"），不带 .v，所以单独抽一张表；
# 门禁脚本点名的也算被引用（它在管的事就是这份包能不能自证）。
{ grep -rhoE "tb_[A-Za-z0-9_]+" "${LIVE_SCOPE[@]}" build/gates.sh build/freeze_evidence.sh sim/run_one.sh 2>/dev/null |
  sed 's/\.v$//' ; } | sort -u > _cited_tb.txt || true

for f in sim/*.v; do
  if [ -f "$f" ]; then
    b="$(basename "$f" .v)"
    hit=0
    for k in "${SIM_KEEP[@]}"; do if [ "$b" = "$k" ]; then hit=1; fi; done
    if grep -qxF "$b" _cited_tb.txt; then hit=1; fi
    if [ "$hit" = "0" ]; then prune "$f" "回归台架（交付文档没引用它的结论）"; fi
  fi
done

# 2b) 其余按"点没点名"剪
LIVE_SCOPE=(report README.md README.en.md skill board/README.md board/HANDS_ON.md)
{ grep -rhoE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,5}" "${LIVE_SCOPE[@]}" 2>/dev/null | sed 's|^\./||'; } > _cited.txt || true
{ grep -rhoE "src/host/[A-Za-z0-9_.-]+\.mjs" build/*.sh 2>/dev/null; } >> _cited.txt || true
sort -u -o _cited.txt _cited.txt

for f in src/host/*.mjs; do
  if [ -f "$f" ]; then
    { grep -hoE "from '\./[A-Za-z0-9_.-]+\.mjs'" "$f" 2>/dev/null | sed "s|from '\./||; s|'||" | sed 's|^|src/host/|'; } >> _cited.txt || true
  fi
done
sort -u -o _cited.txt _cited.txt

# 一条 awk 判完，不逐文件 spawn（Windows 上每个 grep 都要几十毫秒，1500 个文件就是几分钟）
find src/host build sim board data -type f 2>/dev/null | sed 's|^\./||' > _all.txt || true
grep -vE "$KEEP_ALWAYS_RE" _all.txt > _cand.txt || true
sed 's|.*/||' _cited.txt | sort -u > _cited_bases.txt
awk 'FILENAME=="_cited.txt" {c[$0]=1; next}
     FILENAME=="_cited_bases.txt" {b[$0]=1; next}
     { p=$0; n=split(p,a,"/"); bn=a[n]
       if (p in c) next
       if (p !~ /^src\/host\// && (bn in b)) next
       if (p ~ /^src\/host\//) print "未被活文档按路径点名\t" p
       else print "未被活文档点名\t" p }' _cited.txt _cited_bases.txt _cand.txt > _prune_list.tsv
while IFS=$'\t' read -r r f; do rm -f "$f"; echo "$r $f" >> _pruned.txt; done < _prune_list.tsv

# 2c) 二进制一律不带，稍后只放回板上这一版
find . \( -name '*.bit' -o -name '*.xsa' -o -name '*.elf' -o -name '*.dcp' \) -type f 2>/dev/null |
while read -r f; do rm -f "$f"; echo "构建产物（由板上那一版补回） $f" >> _pruned.txt; done || true
find build sim board data src/host -type d -empty -delete 2>/dev/null || true

# ---- 3. 改名：报告展平、文档名小写、台架换名；一份 _map.sed 做全部指路改写 ----
mkdir -p build/reports build/bitstream

# 3.0 台架换名：手写的招牌判据优先；其余只是**去掉轮次号段**（`tb_v6_cover_gate`→`tb_cover_gate`）。
#     规则只有一条：包里的台架名不许带 rNN/vNN —— 那是作者本地的时间轴，不是职责。
declare -A NAME_MAP
for old in "${!SIM_MAP[@]}"; do NAME_MAP["$old"]="${SIM_MAP[$old]}"; done
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
for b in build/system.bit build/system.xsa build/ps_app.elf; do
  add_mv "$b" "build/bitstream/$(basename "$b")"
done

# 报告展平：build/**.rpt|txt -> build/reports/[rNN_]名字（名字里带轮次号的换成新台架名）
while IFS= read -r f; do
  f="${f#./}"
  base="$(basename "$f")"
  for old in "${!NAME_MAP[@]}"; do
    case "$base" in *"$old"*) base="${base//$old/${NAME_MAP[$old]}}" ;; esac
  done
  tag="$(printf '%s' "$f" | grep -oE '(^|[^a-z])r[0-9]+' | grep -oE 'r[0-9]+' | head -1 || true)"
  if [ -n "$tag" ]; then np="build/reports/${tag}_${base}"; else np="build/reports/$base"; fi
  if [ -e "$np" ]; then np="build/reports/$(basename "$(dirname "$f")")_$(basename "$base")"; fi
  if [ "$f" != "$np" ]; then mv "$f" "$np"; add_mv "$f" "$np"; fi
done < <(find build -type f \( -name '*.rpt' -o -name '*.txt' \) 2>/dev/null | grep -v '^./build/reports/' | sort)

# 交付文档名小写（§3.3.5.4 字面要求；README/LICENSE/MANIFEST 是指南自己用的大写名，留作例外）
for f in report/*.md report/log/*.md; do
  if [ -f "$f" ]; then
    b="$(basename "$f")"
    lb="$(printf '%s' "$b" | tr 'A-Z' 'a-z')"
    case "$lb" in readme.md|license|manifest.txt) lb="$b" ;; esac
    if [ "$b" != "$lb" ]; then mv "$f" "$(dirname "$f")/$lb"; add_mv "$f" "$(dirname "$f")/$lb"; fi
  fi
done
for f in board/*.md; do
  if [ -f "$f" ]; then
    b="$(basename "$f")"; lb="$(printf '%s' "$b" | tr 'A-Z' 'a-z')"
    case "$lb" in readme.md) lb="$b" ;; esac
    if [ "$b" != "$lb" ]; then mv "$f" "$(dirname "$f")/$lb"; add_mv "$f" "$(dirname "$f")/$lb"; fi
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

# 改写只作用于" prose 与脚本"；证据类（build/reports/、report/log/）保持原文
find . -type f \( -name '*.md' -o -name '*.sh' -o -name '*.tcl' -o -name '*.py' -o -name '*.mjs' \
    -o -name '*.ps1' -o -name '*.bat' -o -name '*.v' -o -name '*.c' -o -name '*.h' \) 2>/dev/null |
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
      echo "| \`sim/${NAME_MAP[$old]}.v\` | \`sim/$old.v\` | 见 \`build/reports/\` 里带它名字的那份 |"
    fi
  done | sort
} > sim/NAMES.md

for b in build/system.bit build/system.xsa build/ps_app.elf; do
  if [ -f "$REPO/$b" ]; then cp "$REPO/$b" "build/bitstream/$(basename "$b")"; fi
done

# ---- 4. 自检 ----
: > _dead.txt
for f in README.md README.en.md report/*.md skill/*.md skill/*/*.md board/*.md sim/*.md build/*.md build/tcl/*.md; do
  if [ -f "$f" ]; then
    d="$(dirname "$f")"
    grep -oE '(src|sim|build|board|data|skill|report)/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,6}' "$f" 2>/dev/null |
    sort -u | while read -r t; do
      case "$t" in *'*'*|*'<'*|*'$'*|*NN*) continue ;; esac
      case "$t" in *.log|*.out|board/uart_script_capture.txt) continue ;; esac
      if [ -e "$t" ] || [ -e "$d/$t" ]; then continue; fi
      echo "死链 $f -> $t"
    done
  fi
done > _dead.txt 2>&1 || true
DEAD="$(grep -c '死链' _dead.txt 2>/dev/null || true)"; DEAD="${DEAD:-0}"
if [ "$DEAD" = "0" ]; then DEAD=0; fi

STALE=0
for old in "${!NAME_MAP[@]}"; do
  if [ "$old" = "${NAME_MAP[$old]}" ]; then continue; fi
  n="$( { grep -rl "$old" --include='*.md' --include='*.sh' --include='*.tcl' --include='*.v' . 2>/dev/null |
          grep -vE '^\./report/log/|^\./build/reports/|^\./sim/NAMES.md' || true; } | wc -l)"
  if [ "$n" != "0" ]; then echo "残留旧台架名 $old：$n 个文件"; STALE=$((STALE+1)); fi
done

# 绝对路径只判"真被用到的"：注释里写"原来硬编码 D:/... 后来改了"是过程说明，不算违规
ABS="$( { grep -rnE "D:/|C:/Users|/d/Software|/d/Xilinx" --include='*.sh' --include='*.tcl' --include='*.py' \
          --include='*.mjs' --include='*.ps1' --include='*.bat' --include='*.v' --include='*.c' --include='*.h' \
          --exclude='make_submission.sh' . 2>/dev/null || true; } |
        grep -vE ':[0-9]+:[[:space:]]*(#|//|\*)' | cut -d: -f1 | sort -u | tr '\n' ' ')"
ABSN=0
if [ -n "$ABS" ]; then ABSN="$(printf '%s\n' $ABS | wc -l)"; fi

head -25 _dead.txt
echo "== 自检：死链 $DEAD ／ 旧名残留 $STALE ／ 带绝对路径的脚本 $ABSN${ABS:+ （$ABS）} =="

# ---- 5. 清单 ----
files="$(find . -type f ! -name '_dead.txt' ! -name '_map.sed' ! -name '_mv.tsv' ! -name '_cited.txt' ! -name '_pruned.txt' | wc -l)"
bytes="$(du -sh . | cut -f1)"
removed="$(sort -u -o _pruned.txt _pruned.txt; grep -c '' _pruned.txt)"
BIT_MD5=""
if [ -f build/bitstream/system.bit ]; then BIT_MD5="$(md5sum build/bitstream/system.bit | cut -c1-12)"; fi
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
  build/      构建脚本 + 报告       <- tcl/**（入口 build_system_axigpio.tcl）+ gates.sh
                                      + reports/**（展平自仓库各轮留档）+ bitstream/**（板上那一版）
  board/      上板工程与实测输出    <- board/**（操作卡与验收表）
  data/       测试数据与参考结果    <- data/golden/**、data/measured/**
  skill/      技能包                <- skill/**（README.md 是索引）
  report/     设计报告 + 协作记录   <- 仓库里的 docs/（交付文档），工作记录在 report/log/

板上那一份（位流与固件仓库不跟踪，按 md5 认身份，不靠文件名）：
$(for f in build/bitstream/*; do if [ -f "$f" ]; then printf '  %-14s md5 %s\n' "$(basename "$f")" "$(md5sum "$f" | cut -c1-12)"; fi; done)  门禁凭据: $GATES_FOR_BIT

自检: 活文档死链 $DEAD 条（0 才算过）／被改名台架的旧名残留 $STALE／含本机绝对路径的脚本 $ABSN
EOF

echo
echo "导出提交 $COMMIT：$files 个文件 / $bytes，剪掉 $removed 条，死链 $DEAD，旧名残留 $STALE，绝对路径 $ABSN"
if [ "$DRY" = "1" ]; then echo "DRY RUN：$TMP 留着，自己看过再 rm -rf"; exit 0; fi
if [ "$DEAD" != "0" ] || [ "$STALE" != "0" ] || [ "$ABSN" != "0" ]; then
  echo "FAIL：死链 $DEAD ／ 旧名残留 $STALE ／ 绝对路径 $ABSN。不写 $OUT。"
  echo "      明细：$TMP/_dead.txt 与 $TMP/_pruned.txt"
  exit 1
fi
rm -f _cited.txt _dead.txt _map.sed _mv.tsv
rm -rf "$OUT"
mv "$TMP" "$OUT"
echo "-> $OUT"

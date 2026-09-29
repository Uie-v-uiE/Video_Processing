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
SIM_PLAIN=(tb_link_monitor tb_zoom_mapper tb_rotate_window tb_cdc_capacity)
# 台架取舍 = 下面这份手写名单 ∪ 被留下的脚本（gates.sh / run_one.sh / mut_control.sh）点名的。
# 名单里的是**招牌判据**（给新名字）；被脚本点名的按原名带出去（改名会让脚本找不到文件）。
# 其余回归台架不进包：交付文档里以裸名提到它们，说的是"过程里举过的例子"，不是"包里有这个文件"；
# 以**路径**提到的那部分由导出末尾的 _dropped_tb 规则就地改成"仓库回归台架"，不留空链接。
SIM_KEEP=("${!SIM_MAP[@]}" "${SIM_PLAIN[@]}")

# ---- 硬剔除：被否决的轮次、探针与构建中间物、零引用 RTL ----
HARD_DROP_RE='^build/(failed_|red_|multidrive_|exp_|strprobe|uram_probe|micro_rd|ps_obj|snap_|r[0-9]+_isolated|r[0-9]+_exp|build/|vivado_system/|__pycache__/)|^build/(evidence|frozen)_r[0-9]+[^/]*(rejected|notadopted|wip|abort)/|^sim/(probes|msim|v98run|xtest|tagchk|syntaxchk|v100run2)/|^src/rtl/(axi/axi_frame_writer|eth/axi_frame_saver|video/frame_buffer_db|video/video_timing_720p)\.v$'
PRUNE_ONEOFF=(
  build/tcl/apply_cdc_report.tcl build/tcl/fix_bd_and_top.tcl build/tcl/rebuild_opt.tcl
  build/tcl/rebuild_zoom_out.tcl build/tcl/rebuild_cdc_fix.tcl build/tcl/micro_rd.tcl
  build/tcl/uram_presence.tcl build/tcl/uram_probe.tcl build/tcl/uram_sites.tcl
  build/tcl/dfx_runtime.txt build/tcl/retry_open_nr.log
  sim/run_zoom_only.tcl tight_setup_hold_pins.txt board/ddr_churn_r33_pair.md
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

LIVE_SCOPE=(report README.md README.en.md skill board/README.md board/HANDS_ON.md data/metrics.csv)
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
  if [ -n "$tag" ] && [ "${base#$tag}" = "$base" ] && [ "${base#*$tag}" = "$base" ]; then
    np="build/reports/${tag}_${base}"
  else
    np="build/reports/$base"     # 名字里本来就带着轮次的（gates_rNN.txt / rNN_*.rpt）不再加前缀
  fi
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
  if [ -f "$REPO/$b" ]; then cp "$REPO/$b" "build/bitstream/$(basename "$b")"; fi
done

# ---- 4. 自检 ----
# 死链清单写到树**外面**：包根目录里不留工作文件（上一版把 _all.txt/_cand.txt/… 九个中间件
# 一起落进了 final_submission/，而 MANIFEST 的"文件数"又把它们算进去 ⇒ 报的数与落地差 2）。
DEADLIST="${TMPDIR:-/tmp}/sub_dead_$(basename "$TMP").txt"
: > "$DEADLIST"
# 判死链的范围 = "活文档"（评委照着跑的说明书），**不含 report/log/**：那里的路径是当时那天的名字，
# 台架删了、工具改名了、捕获清了都留在里面，那是过程记录，不该拿它判包不完整。
for f in README.md README.en.md report/*.md skill/*.md skill/*/*.md board/*.md sim/*.md build/*.md build/tcl/*.md data/*.csv; do
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

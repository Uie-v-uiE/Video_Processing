#!/usr/bin/env bash
# make_submission.sh — 从当前 git 跟踪集导出一份照赛程官方目录结构摆放的提交包。
#
# 官方结构（选题指南 §3.3.5.4）：
#   <项目>/README.md  src/  sim/  build/  board/  data/  skill/README.md  report/
#
# 三条设计决定，都是为了处理"仓库里合理、交出去不合理"的东西：
#  1) **目录映射**：仓库里交付文档在 `docs/`、工作记录在 `docs/log/`（本地按三类分着好用），
#     交出去必须是 `report/`。导出时改名，并把包内所有 `docs/…` 的指路**一并改写**成 `report/…`
#     —— 只改目录不改指路，等于交一份满篇死链接的包。
#  2) **按引用留凭据**：`build/` 与 `sim/` 跟踪了一千多个文件（每一轮的门禁输出、冻结集、
#     策略扫描日志）。判据不是"哪一轮的"，而是"**交付文档点没点名**"：被 `report/`、`README*`、
#     `skill/`、板级操作卡里任何一处按路径或文件名引用的就带，没被引用的不带。
#     理由：评委复核任何一个数字，走的都是文档里那条指路；没被点名的留档在包里只是噪声。
#  3) **导出后自检**：包内所有"路径式指路"必须在**包内**解析得出来，解析不出来就退出非 0、
#     不落盘。这一条是防我自己：剪多了文件而文档还在指它，是最容易犯也最难看的一种错。
#
# 用法：bash build/make_submission.sh [--dry]
#   --dry 只解出来看、不落到 ../submission/（临时目录留着，自己看过再 rm -rf）
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(cd "$REPO/.." && pwd)/submission"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sub.XXXXXX")"
DRY=0
[ "${1:-}" = "--dry" ] && DRY=1

# 一次性修复脚本：只修当年那一版 BD/顶层，没人再调用，别人照着跑只会困惑。
PRUNE_ONEOFF=(
  build/tcl/apply_cdc_report.tcl
  build/tcl/fix_bd_and_top.tcl
  build/tcl/rebuild_opt.tcl
  build/tcl/rebuild_zoom_out.tcl
  tight_setup_hold_pins.txt
)

# ---- 无论有没有被点名都留着：跑起来的那一套（源码与脚本本体）----
KEEP_ALWAYS_RE='\.(sh|tcl|py|ps1|bat|xdc|f|v|c|h)$|^src/(rtl|ps|constraints)/|^data/golden/|MANIFEST|README'

cd "$REPO"
COMMIT="$(git rev-parse --short HEAD)"
DIRTY="$(git status --porcelain | wc -l)"
git archive --format=tar HEAD | tar -x -C "$TMP"
cd "$TMP"

# ---- 1. 目录映射 docs/ -> report/，并改写包内指路 ----
if [ -d docs ]; then
  mkdir -p report
  mv docs/*.md report/ 2>/dev/null || true
  if [ -d docs/log ]; then mkdir -p report/log; mv docs/log/*.md report/log/ 2>/dev/null || true; fi
  rm -rf docs
  grep -rl "docs/" --include="*.md" --include="*.mjs" --include="*.sh" --include="*.tcl" \
        --include="*.v" --include="*.c" --include="*.h" --include="*.bat" . 2>/dev/null |
  while read -r f; do
    sed -i 's|\.\./docs/|../report/|g; s|docs/log/|report/log/|g; s|docs/|report/|g' "$f"
  done
fi

# ---- 2. 剪：只按"活文档点没点名"判，记录类不参与 ----
# 活文档 = 评委会当成说明去跟的那几页：report/ 顶层、两份 README、skill/、board/ 的操作卡。
# 记录类 = report/log/（ISSUES 与 OVERNIGHT_LOG 等）与 build/frozen_r*/、build/evidence_r*/：
#   里面的路径是**当时**的名字（台架删了、捕获清了、工具改名了都在那里留着），
#   既不能作为"这个文件还得带"的依据，也不该被拿来判死链——改它就是伪造过程记录。
: > _pruned.txt
for n in "${PRUNE_ONEOFF[@]}"; do
  [ -f "$n" ] || continue
  rm -f "$n"; echo "一次性脚本 $n" >> _pruned.txt
done

LIVE_SCOPE=(report README.md README.en.md skill board/README.md board/HANDS_ON.md)
grep -rhoE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,5}" "${LIVE_SCOPE[@]}" 2>/dev/null \
  | sed 's|^\./||; s|^report/|report/|' | sort -u > _cited.txt
# 交付文档里点名要跑的宿主脚本，即使正文没写全路径也算被点名（门禁与验收脚本会调它们）
grep -rhoE "src/host/[A-Za-z0-9_.-]+\.mjs" build/*.sh 2>/dev/null | sort -u >> _cited.txt
sort -u -o _cited.txt _cited.txt

# 被别的 .mjs import 的公共模块必须跟着走（现在只有一个：repo_path.mjs）。
# 不写死名字，改成"有被留着的文件 import 它就留"，免得以后加了新的公共模块又踩一次。
for f in src/host/*.mjs; do
  [ -f "$f" ] || continue
  grep -hoE "from '\./[A-Za-z0-9_.-]+\.mjs'" "$f" 2>/dev/null |
    sed "s|from '\./||; s|'||" | while read -r dep; do
      echo "src/host/$dep" >> _cited.txt
    done || true      # pipefail：没有 import 的文件 grep 返回 1，不该把整个导出带走
done
sort -u -o _cited.txt _cited.txt

for p in src/host build sim board data; do
  [ -d "$p" ] || continue
  find "$p" -type f | while read -r f; do
    echo "$f" | grep -qE "$KEEP_ALWAYS_RE" && continue
    grep -qxF "$f" _cited.txt && continue
    # 工具与留档两种口径：**工具**要按路径点名才带（HOST_GUIDE 里"作者留存"的那些是裸名，
    # 不该因此进包）；**留档**只要文件名被点名就带（文档里常写"`rNN_gates.txt` 第几行"这种）。
    case "$p" in src/host) ;; *) grep -qxF "$(basename "$f")" _cited.txt && continue ;; esac
    rm -f "$f"; echo "未被活文档点名 $f" >> _pruned.txt
  done
done
find build sim board data src/host -type d -empty -delete 2>/dev/null || true

find src/host -type d -empty -delete 2>/dev/null || true
removed="$(sort -u -o _pruned.txt _pruned.txt; grep -c '' _pruned.txt)"

# ---- 3. 自检：活文档里的路径式指路必须在包内解析得出 ----
: > _dead.txt
for f in README.md README.en.md report/*.md skill/*.md skill/*/*.md board/*.md; do
  [ -f "$f" ] || continue
  d="$(dirname "$f")"
  grep -oE '(src|sim|build|board|data|skill|report)/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,6}' "$f" 2>/dev/null |
  sort -u | while read -r t; do
    case "$t" in *'*'*|*'<'*|*'>'*|*'$'*|*NN*) continue ;; esac      # 通配与占位名不算指路
    # 生成物：跑脚本/跑构建才有的输出（*.log 与 *.elf 按 .gitignore 政策本来就不入库），
    # 包里没有是应该的；文档提到它们时说的是"什么东西被生成出来"
    case "$t" in *.log|*.elf|build/tb_v98_report.txt|board/uart_script_capture.txt|data/measured/ddr_dump.out) continue ;; esac
    [ -e "$t" ] && continue
    [ -e "$d/$t" ] && continue
    echo "死链 $f -> $t"
  done
done > _dead.txt 2>&1 || true
DEAD="$(grep -c '死链' _dead.txt || true)"; DEAD=${DEAD:-0}
head -20 _dead.txt
echo "== 自检：活文档死链 $DEAD 条（记录类不判，理由见上面第 2 步）=="

# ---- 3b. 位流与固件镜像：仓库里不跟踪（太大/是输出），但交出去必须能对上"板上是哪一版" ----
BIN_LINES=""
for b in build/system.bit build/ps_app.elf; do
  if [ -f "$REPO/$b" ]; then
    cp "$REPO/$b" "$b"
    BIN_LINES="$BIN_LINES  $b  md5 $(md5sum "$b" | cut -c1-12)$(printf '
')"
  fi
done
# 位流的身份**只能由它自己的 md5 去认**：哪一份门禁报告里写着这串 md5，就念那一份；
# 一份都没有 ⇒ 这一版没有全绿凭据，必须明说"不作交付"，绝不能拿"最新的那份报告"顶替
# （文件名排序的"最新"和"与这份位流同一次构建"是两件事，r81 就是活例子：它四滚全红）。
BIT_MD5=""; [ -f build/system.bit ] && BIT_MD5="$(md5sum build/system.bit | cut -c1-12)"
GATES_FOR_BIT=""
if [ -n "$BIT_MD5" ]; then
    GATES_FOR_BIT="$(grep -l "$BIT_MD5" build/*gates*.txt build/evidence/*.txt 2>/dev/null | head -1)"
    [ -n "$GATES_FOR_BIT" ] || GATES_FOR_BIT="没有一份门禁报告写着这串 md5 ⇒ 这一版不作交付（诊断用）"
fi

# ---- 4. 清单 ----
files="$(find . -type f | wc -l)"
bytes="$(du -sh . | cut -f1)"
cat > MANIFEST.txt <<EOF
导出时间: $(date '+%Y-%m-%d %H:%M:%S')
来源仓库: $REPO
来源提交: $COMMIT（导出时工作区未提交改动 $DIRTY 条）
文件数  : $files，体积 $bytes，本次剪掉 $removed 条（逐条与理由见 _pruned.txt）
生成脚本: build/make_submission.sh（可重跑；三条判据写在脚本头部）

目录对照（赛程推荐结构 -> 本仓库）
  README.md   项目简介 + 复现步骤   <- README.md（中文）/ README.en.md（英文）
  src/        设计源码              <- src/rtl/**（PL）+ src/ps/**（裸机固件）+ src/host/**（PC 工具）
  sim/        仿真脚本与结果        <- sim/**（台架与两个 runner；判据输出在 build/tb_*_rNN.txt）
  build/      构建脚本 + 报告       <- build/tcl/**（唯一入口 build_system_axigpio.tcl）+ 门禁与冻结脚本
                                      + **被交付文档点名的**那些 rNN 留档
  board/      上板工程与实测输出    <- board/**（操作卡、串口脚本、evidence_rNN/）
  data/       测试数据与参考结果    <- data/golden/**、data/measured/**
  skill/      技能包                <- skill/**（README.md 是索引，S 编号是对外接口）
  report/     设计报告 + 协作记录   <- 仓库里的 docs/（交付文档）；工作记录在 report/log/
                                      （仓库内叫 docs/log/，导出时改名并改写指路）

不带进提交包的（判据：评委照文档跑用不到，且文档也不指它）
  · src/host/ 里没有被活文档按路径点名的工具（判据与引用规则同源，见脚本第 2 步）——
    它们产出的数字已经写进 report/ 与 data/measured/，交脚本本身没有意义
  · 四个一次性 BD/顶层修复脚本（PRUNE_ONEOFF）
  · build/ 与 sim/ 里没有被 report/ 点名的留档，逐条见 _pruned.txt
  · 本地学习材料（仓库里 docs/study/，被 .gitignore 挡住，本来就不在跟踪集内）

板上的那一份（位流与固件镜像仓库不跟踪，这里按 md5 带出来，身份不靠文件名）：
$BIN_LINES  它的门禁凭据：$GATES_FOR_BIT

自检：包内路径式指路解析不出的有 $DEAD 条（0 才算过；不通过时本脚本不落盘）
EOF
rm -f _cited.txt _dead.txt

echo
echo "导出提交 $COMMIT：$files 个文件 / $bytes，剪掉 $removed 条，死链 $DEAD 条"
if [ "$DRY" = "1" ]; then
  echo "DRY RUN：$TMP 留着，自己看过再 rm -rf"
  exit 0
fi
if [ "$DEAD" != "0" ]; then
  echo "FAIL：包里有 $DEAD 条死链。要么把该带的留档放回来，要么改文档里的指路。不写 $OUT。"
  echo "      明细：$TMP/_dead.txt"
  exit 1
fi
rm -rf "$OUT"
mv "$TMP" "$OUT"
echo "-> $OUT"

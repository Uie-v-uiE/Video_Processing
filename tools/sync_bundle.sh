#!/usr/bin/env bash
# 作用：把包外可读副本 D:/Xilinx/Prj/Video_Processing 的"仓库半"重做成
#       交付分支 origin/main 的全部文件 + 过程分支 origin/all 独有的那批过程件（report/log、report/timing 等），
#       并保留副本自己的 LEARNING/ poster/ study_docs/ final_submission/ BUNDLE-Contents.md 与三支 learning 尺子。
# 输入：无参数（路径写死在本机，这一支不随包，所以不受交付判据的绝对路径规则管）。
# 输出：改写目标目录；打印每层文件数与四条判据。
# 退出码：0 = 四条判据全过；1 = 任一判据红（此时不动目标目录，除了第 0 步的备份）。
set -uo pipefail

REPO=/d/Xilinx/Prj/pro/Video_Processing
DST=/d/Xilinx/Prj/Video_Processing
REF="${1:-main}"          # 同步哪一支的交付形状：默认本地 main（=GitHub 默认分支）
TMP=$(mktemp -d)
BACKUP="$TMP/learning_tools"
MAIN_LIST="$TMP/main.txt" ALL_LIST="$TMP/all.txt" ONLY_ALL="$TMP/only_all.txt"

cd "$REPO" || { echo "REFUSE 找不到仓库 $REPO"; exit 1; }
[ -d "$DST" ] || { echo "REFUSE 找不到副本 $DST"; exit 1; }
git rev-parse --verify -q "$REF" >/dev/null || { echo "REFUSE 分支 $REF 不存在"; exit 1; }

# 0. 先把副本自己的三支尺子与清单备份出来（它们不在任何分支里）
mkdir -p "$BACKUP"
for f in build/learning_cite_check.mjs build/learning_anchor_spot.mjs build/learning_fix_cites.mjs; do
  [ -f "$DST/$f" ] && cp "$DST/$f" "$BACKUP/$(basename "$f")" || true
done
echo "备份 尺子=$(ls -1 "$BACKUP" | wc -l) 支（期望 3）"
# 这三支尺子只住在副本里（不在任何分支），所以第 1 步删 build/ 之前必须先把它们收走。
# 备份数不为 3 就 REFUSE 或从常驻镜像补：以前只打印不拦，于是一次中途失败的运行会把它们删掉，
# 下一次再跑时"备份=0"照样往下走 —— 判据没有牙就是这个样子。
MIRROR=/d/Xilinx/Prj/pro/learning_tools_mirror
if [ "$(ls -1 "$BACKUP" | wc -l)" -lt 3 ]; then
  if [ -d "$MIRROR" ]; then
    cp "$MIRROR"/learning_*.mjs "$BACKUP/" 2>/dev/null || true
    echo "从常驻镜像补齐：现在 $(ls -1 "$BACKUP" | wc -l) 支"
  fi
  [ "$(ls -1 "$BACKUP" | wc -l)" -eq 3 ] || { echo "REFUSE 尺子备份不齐（$(ls -1 "$BACKUP" | wc -l)/3），不动副本"; exit 1; }
fi

git ls-tree -r --name-only "$REF" | sort > "$MAIN_LIST"
git ls-tree -r --name-only origin/all   | sort > "$ALL_LIST"
comm -23 "$ALL_LIST" "$MAIN_LIST" > "$ONLY_ALL"
echo "射程 $REF=$(wc -l < "$MAIN_LIST") all=$(wc -l < "$ALL_LIST") all独有=$(wc -l < "$ONLY_ALL")"

# 1. 只删仓库半那几层，副本自己的四层不碰
for d in src sim build report board data skills vivado_system vitis; do rm -rf "$DST/$d"; done
for f in README.md README_EN.md LICENSE run_test.bat run_test.sh send_demo.bat .gitignore .gitattributes; do rm -f "$DST/$f"; done

# 2. 交付分支全量落地（**工程生成物两棵不进副本**：140 MB 工具产物，读它得开 Vivado，副本是给人读的），
#    再叠上 all 独有的过程件（同名不覆盖：$REF 是权威版本）
git archive "$REF" | tar -x --exclude=vivado_system --exclude=vitis -C "$DST" || { echo "REFUSE $REF 展开失败"; exit 1; }
# 一支 `git archive` 出一份档：以前写成 `xargs -n N git archive | tar -x`，而 GNU tar 读到**第一份档的
# EOF 块就停**，后面的 `git archive` 全被 SIGPIPE（141）杀掉，xargs 退 123 —— 在没有 pipefail 的那次
# 手工重跑里这表现为"文件明明少了几十支却一句错都不报"。（试过 --pathspec-from-file：本机的
# git 版不认识这个选项，会打 usage 并让 tar 报"不像 tar 档"。）改成一次调用把清单当 pathspec 传，
# 前提是清单里没有带空格的路径（有就 REFUSE，不静默拆词）。
if grep -q '[[:space:]]' "$ONLY_ALL"; then
  echo "REFUSE all 独有清单里有带空格的路径，不能当 argv 传"; exit 1
fi
git archive origin/all -- $(tr '\n' ' ' < "$ONLY_ALL") | tar -x -C "$DST" || { echo "REFUSE all 叠加失败"; exit 1; }
LANDED=$(while IFS= read -r p; do [ -e "$DST/$p" ] && echo x; done < "$ONLY_ALL" | wc -l)
if [ "$LANDED" -ne "$(wc -l < "$ONLY_ALL")" ]; then
  echo "REFUSE all 叠加只落地 $LANDED / $(wc -l < "$ONLY_ALL") 支"; exit 1
fi
echo "all 独有件叠加：清单 $(wc -l < "$ONLY_ALL") 支 / 落地 $LANDED 支"

# 3. 尺子放回
for f in "$BACKUP"/*.mjs; do [ -f "$f" ] && cp "$f" "$DST/build/$(basename "$f")"; done

# 4. 四条判据
FAIL=0
# 判据 1 的射程：仓库半 = `main` 的非厂商跟踪件 + `all` 独有叠加件 + 只住在副本里的三把 learning 尺子。
# 副本自己的本地层要按形状剪掉（LEARNING/ARCH/PDF/poster/study_docs/final_submission 六层 + 根下四份本地 md）；
# 早先这里只剪四层，新长出的 ARCH/、PDF/ 与根下本地件被算进了"仓库半"，计数看着像真读数（1227 vs 实际 1210）。
# 根下的本地媒体（`*.mp4`：SD 那一路的原始片源，两支分支都没跟踪它，2026-09-22 就在盘上）同属"副本自己的东西"，
# 2026-10-07 15:04 那次就是它把计数顶到 1218（期望 1217）——剪掉并打印件数，别让一个不随包的片源变成假 RED。
N_LOCAL_MEDIA=$(find "$DST" -maxdepth 1 -type f -name '*.mp4' | wc -l)
N_MAIN=$(find "$DST" -type f \
            \( -path "$DST/LEARNING/*" -o -path "$DST/ARCH/*" -o -path "$DST/PDF/*" -o -path "$DST/poster/*" \
               -o -path "$DST/study_docs/*" -o -path "$DST/final_submission/*" \
               -o -name 'BUNDLE-Contents.md' -o -name 'REVIEW-*.md' -o -name '提交表-*.md' -o -name '演示流程-*.md' \
               -o -name '*.mp4' \) -prune -o -type f -print \
         | wc -l)
echo "本地媒体剪掉 $N_LOCAL_MEDIA 支（只数副本根下一层）"
N_EXP=$(git ls-tree -r "$REF" --name-only | grep -vcE '^(vivado_system|vitis)/')
N_ONLYALL=$(wc -l < "$ONLY_ALL")
N_RULER=3
N_WANT=$((N_EXP + N_ONLYALL + N_RULER))
if [ "$N_MAIN" -ge 1200 ] && [ "$N_MAIN" -eq "$N_WANT" ]; then
  echo "判据1 仓库半文件数=$N_MAIN（= main 非厂商 $N_EXP + all 叠加 $N_ONLYALL + 本地尺子 $N_RULER = $N_WANT）OK"
else
  echo "判据1 仓库半文件数=$N_MAIN 与期望 $N_WANT（main 非厂商 $N_EXP + all 叠加 $N_ONLYALL + 尺子 $N_RULER）不符 RED"; FAIL=1
fi
for f in report/technical-document.md src/rtl/top/pl_video_top.v board/README.md board/tcl/flash_qspi.tcl; do
  if diff -q <(cd "$DST" && cat "$f") <(git show "$REF:$f") >/dev/null 2>&1; then
    echo "判据2 $f 与 $REF 逐字节相同 OK"
  else
    echo "判据2 $f 与 $REF 不同 RED"; FAIL=1
  fi
done
[ "$(wc -l < "$DST/report/technical-document.md")" -eq "$(git show "$REF:report/technical-document.md" | wc -l)" ] \
  && echo "判据3 交付文档行数=$(wc -l < "$DST/report/technical-document.md")（=$REF 那份）OK" \
  || { echo "判据3 交付文档行数与 $REF 不一致 RED"; FAIL=1; }
grep -q "三个创新点" "$DST/report/technical-document.md" \
  && echo "判据4 交付文档含「### 1.3 三个创新点」OK" || { echo "判据4 交付文档缺创新点 RED"; FAIL=1; }
for f in report/log/issues.md report/timing/round_r118.md; do
  [ -f "$DST/$f" ] && echo "判据5 过程件 $f 在 OK" || { echo "判据5 过程件 $f 丢了 RED"; FAIL=1; }
done
[ -f "$DST/BUNDLE-Contents.md" ] \
  && echo "判据6 本清单在盘上 OK（注意：这一条只量存在性，不判它有没有被人改过——旧说法「未被碰」超出了它真正做的比较）" \
  || { echo "判据6 清单丢了 RED"; FAIL=1; }
if [ -e "$DST/vivado_system" ] || [ -e "$DST/vitis" ]; then
  echo "判据7 副本根下出现了工程生成物（140 MB 工具产物不该进可读副本的仓库半）RED"; FAIL=1
else
  # 2026-10-07 18:3x：这一条的旧说法写的是「副本里没有 vivado_system/ 与 vitis/」，
  # 而它真正 test 的只有副本根这一层——交付包 final_submission/board/ 里现在就带着这两棵，
  # 所以那句话已经超出射程。改口成「根下没有」，并把包里那两棵的件数念出来（只报数，不判红：
  # 包的形状由仓库里的 build/make_submission.sh 自己那几条判据管）。
  echo "判据7 副本根下没有 vivado_system/ 与 vitis/（工程生成物不进仓库半）OK"
  N_PKG_VS=$(find "$DST/final_submission/board/vivado_system" -type f 2>/dev/null | wc -l)
  N_PKG_VT=$(find "$DST/final_submission/board/vitis" -type f 2>/dev/null | wc -l)
  echo "判据7 附带读数：交付包里有 vivado_system=$N_PKG_VS 支 / vitis=$N_PKG_VT 支（只报数——这一条不参与红绿）"
fi

echo "RESULT=$([ $FAIL -eq 0 ] && echo PASS || echo FAIL)  临时目录 $TMP"
exit $FAIL

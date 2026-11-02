#!/bin/bash
# 用途：把仓库里的 report/ 目录改成 report/，并且**带着还原能力**
# 输入：命令行参数
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 2=非 0 分支（该文件 exit 2 那一行）
# build/rename_docs_to_report.sh —— 把仓库里的 report/ 目录改成 report/，并且**带着还原能力**。
#
# 为什么要有这个脚本（而不是手工 mv + sed）：今晚已经试过两次，两次都在做到一半时退回，
# 卡点不是"改不动"，是"改坏了没法证明能全数还原"：
#   * 我第一次的待改清单是手工拼的（66 个文件），真实数是当场 grep 出来的 129 个 ⇒ "0 处残留"只在子集上成立；
#   * `git checkout -- .` 救不了**未跟踪与被 .gitignore 挡住**的文件（report/study/ 31 份本地学习件、
#     board/HANDS_ON.md、build/r94_*.py 那些一次性脚本的注释），而我当时用 `git status` 与
#     `CURRENCY: 干净` 判"已还原"，两者都只看跟踪件 ⇒ 安全感是假的（第十八条那一族的复发）。
# 所以这里把三件事写死在一个工具里：①当场枚举（不手工拼）；②改前快照含被忽略件，restore 能全数还原；
# ③"叙事句"跳过并打印出来给人读（`2026-09-28 把 report/ 拆成 docs/` 这种历史句子被 sed 改完就自相矛盾）。
#
# 用法：
#   bash build/rename_docs_to_report.sh snapshot     # 改前快照（必须先看它列出的数对不对）
#   bash build/rename_docs_to_report.sh dry          # 只报"会改哪些文件、跳过哪些叙事行"
#   bash build/rename_docs_to_report.sh apply        # 真改：翻 D4b、改 scope、mv 目录、重写指路
#   bash build/rename_docs_to_report.sh verify       # 四个检查器 + 扫描面与基线比对 + 残留清单
#   bash build/rename_docs_to_report.sh restore      # 从快照整体还原（含被忽略件）
set -u
cd "$(dirname "$0")/.." || exit 1
SNAP="${TMPDIR:-/tmp}/docs_rename_snapshot.tar"
LIST="${TMPDIR:-/tmp}/docs_rename_files.txt"
SKIP="${TMPDIR:-/tmp}/docs_rename_skipped.txt"
# 叙事行：这些词出现的行**不自动改**，打印出来给人读（历史叙述改不得，见 report/log 的既定口径）
NARR='拆成|当年|旧目录|曾经|历史|原名|改口|不再是|已经删掉|此前|那时|round-?two|formerly|once'
BASE_DOCENC=364      # 基线：改前 doc_enc_check 扫到 364 份手写件；改名轮之后必须持平
BASE_CITE=91         # 基线：line_cite_check 扫 91 份交付文档
files_with_docs() {   # 当场枚举：跟踪 + 未跟踪 + 被忽略
    { git ls-files -z; git ls-files -z --others; git ls-files -z --others --ignored --exclude-standard; } |
    xargs -0 -r grep -l "report/" 2>/dev/null | sort -u
}
case "${1:-}" in
snapshot)
    files_with_docs > "$LIST"; N=$(grep -c '' "$LIST")
    echo "枚举到带 report/ 的文件 $N 个（跟踪+未跟踪+被忽略）"
    grep -E '/(study|log)/' "$LIST" | head -3
    tar -cf "$SNAP" -T "$LIST" 2>/dev/null || tar -cf "$SNAP" $(cat "$LIST")
    echo "快照 = $SNAP（$(du -h "$SNAP" | cut -f1)）；restore 能还原包括被忽略的件"
    md5sum $(head -5 "$LIST") 2>/dev/null | cut -c1-60
    ;;
dry)
    [ -f "$LIST" ] || { echo "先跑 snapshot"; exit 1; }
    tot=0; sk=0
    while IFS= read -r f; do
        a=$(grep -c "report/" "$f" 2>/dev/null || true); a=${a:-0}
        s=$(grep -E "$NARR" "$f" 2>/dev/null | grep -c "report/" || true); s=${s:-0}
        tot=$((tot + a - s)); sk=$((sk + s))
        [ "$s" -gt 0 ] && grep -E "$NARR" "$f" | grep -n "report/" | sed "s|^|$f:|"
    done < "$LIST"
    echo "会重写 $tot 处；跳过含叙事词的行 $sk 处（上面逐行列出，要人工决定措辞）"
    ;;
apply)
    [ -f "$SNAP" ] || { echo "STOP: 没有快照就不许 apply（还原能力是前提）"; exit 1; }
    [ -d docs ] || { echo "STOP: report/ 不存在，可能已经改过了"; exit 1; }
    echo "-- 1) 翻 D4b：废弃目录名 report -> docs，并把 CITE_MD 的名改成 report"
    node build/rename_tool_patch.mjs || { echo "STOP: 工具补丁没全命中，一个字节都不留"; exit 1; }
    echo "-- 2) mv 目录（含 report/log 与 report/study）"
    mkdir -p report && mv report/study report/study 2>/dev/null
    git mv report/log report/log && for f in report/*; do b=$(basename "$f"); [ "$b" = log ] || [ "$b" = study ] || git mv "$f" "report/$b"; done
    find docs -type f 2>/dev/null | head -3 | sed 's/^/     docs 里还剩: /'
    rm -rf docs 2>/dev/null; [ -d docs ] && { echo "STOP: docs 没清空，看上面"; exit 1; } || echo "     docs 已消失 ✓"
    echo "-- 3) 重写指路 report/ -> report/（跳过叙事行）"
    files_with_docs > "$LIST"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        grep -vE "$NARR" "$f" > /dev/null 2>&1 || continue
        awk -v narr="$NARR" '{ if ($0 ~ narr) print; else { gsub("report/", "report/"); print } }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done < "$LIST"
    echo "     重写完 $(grep -c '' "$LIST") 个文件"
    ;;
verify)
    echo "-- 残留（应当只剩叙事行与被跳过的历史句）"
    { git ls-files; git ls-files --others; git ls-files --others --ignored --exclude-standard; } |
      sort -u | xargs -r grep -n "report/" 2>/dev/null | grep -vE "$NARR" | head -10
    echo "-- 四个检查器"
    node src/host/doc_enc_check.mjs 2>&1 | tail -1
    node src/host/doc_currency_check.mjs 2>&1 | tail -1
    node src/host/line_cite_check.mjs 2>&1 | grep -oE "扫 [0-9]+ 份交付文档|硬错 [0-9]+ 条" | tr '\n' ' '; echo
    node src/host/metric_recheck.mjs 2>&1 | grep -o "判 [0-9]* 行（红 [0-9]*）"
    echo "-- 扫描面与基线比对（$BASE_DOCENC / $BASE_CITE）"
    N=$(node src/host/doc_enc_check.mjs 2>&1 | grep -oE "扫了 [0-9]+" | grep -oE "[0-9]+" | head -1)
    M=$(node src/host/line_cite_check.mjs 2>&1 | grep -oE "扫 [0-9]+ 份交付文档" | grep -oE "[0-9]+" | head -1)
    [ "$N" = "$BASE_DOCENC" ] && echo "PASS doc_enc 扫 $N 份（持平）" || echo "FAIL doc_enc 扫 $N ≠ 基线 $BASE_DOCENC（扫描面漂了，见 #194）"
    [ "$M" = "$BASE_CITE" ] && echo "PASS line_cite 扫 $M 份（持平）" || echo "FAIL line_cite 扫 $M ≠ 基线 $BASE_CITE"
    ;;
restore)
    [ -f "$SNAP" ] || { echo "STOP: 没有快照"; exit 1; }
    tar -xf "$SNAP" && echo "已从快照还原 $(grep -c '' "$LIST" 2>/dev/null) 个文件"
    [ -d report ] && ! git ls-files report | grep -q . && echo "注意：report/ 里的未跟踪副本需手工处置（快照不含目录移动本身）"
    ;;
*)
    echo "用法：$0 snapshot|dry|apply|verify|restore"; exit 2;;
esac

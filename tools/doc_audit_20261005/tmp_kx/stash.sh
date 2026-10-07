#!/usr/bin/env bash
# 干跑探针：把候选删除件整树搬到 stash（保留相对路径），或从 stash 搬回。
# 用法：stash.sh mv|restore <files-list> <dirs-list>
set -u
REPO="D:/Xilinx/Prj/pro/Video_Processing"
KX="D:/Xilinx/Prj/pro/doc_audit_20261005/tmp_kx"
STASH="$KX/stash"
MODE="$1"; FILES="$2"; DIRS="$3"
cd "$REPO" || exit 1
if [ "$MODE" = mv ]; then
  mkdir -p "$STASH"
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    [ -e "$d" ] || continue
    mkdir -p "$STASH/$(dirname "$d")"
    mv "$d" "$STASH/$d" || echo "FAIL dir $d"
  done < <(sed 's|/$||' "$DIRS" | sort -u)
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -e "$f" ] || continue
    mkdir -p "$STASH/$(dirname "$f")"
    mv "$f" "$STASH/$f" || echo "FAIL file $f"
  done < "$FILES"
  echo "moved: $(find "$STASH" -type f | wc -l) 支文件已在 stash"
else
  cd "$STASH" || exit 1
  find . -mindepth 1 -type d | sed 's|^\./||' | sort -r | while IFS= read -r d; do
    mkdir -p "$REPO/$d"; rmdir "$STASH/$d" 2>/dev/null
  done
  find . -type f | sed 's|^\./||' | while IFS= read -r f; do
    mkdir -p "$REPO/$(dirname "$f")"
    mv "$STASH/$f" "$REPO/$f" || echo "FAIL restore $f"
  done
  echo "restored; stash 残留 $(find "$STASH" -type f 2>/dev/null | wc -l) 支"
fi

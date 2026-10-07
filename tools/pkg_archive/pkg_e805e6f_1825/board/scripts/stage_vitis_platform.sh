#!/usr/bin/env bash
# board/scripts/stage_vitis_platform.sh —— 把 Vitis 平台复制进 board/ 并**用复制出来的那份重建 ELF**
#
# 依赖：`vitis/platform/`（含 `hw/system.xsa`、`zynq_fsbl/`、域目录与 BSP）；
#       `arm-none-eabi-gcc`（在 Vitis 安装树 `<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/`）；
#       `build/ps_app.mjs`（应用构建入口）；`src/ps/` 的源码。
# 用法：PS_CC="<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe" \
#         bash board/scripts/stage_vitis_platform.sh
# 参数：
#   | 变量 | 作用 | 默认 |
#   | --- | --- | --- |
#   | `PS_CC` | 交叉编译器绝对路径（必填；机器相关所以不写死） | 空 ⇒ REFUSE |
#   | `VP_BOARD_VITIS` | 平台副本落点 | `board/vitis_platform` |
#   | `VP_SKIP_BUILD` | 设为 1 时只做复制与存在性核对，不重建 ELF | 未设 |
#
# 为什么要它：交付要求 `board/` 里放得上板工程，Vitis 那半边也要能独立取用。
# 只复制文件不证明它可用是不够的，所以这里的判据是**用副本里的 BSP 重新编译链接一遍 ps_app**：
# 链得出来且 ELF 非空 ⇒ 副本完整（缺 BSP、缺 xsa、路径不对都会直接 REFUSE）。
# 两颗 ELF 的 md5 与 section 大小如实打印，不拿"md5 必须相同"当判据——仓库里那颗比 `src/ps` 的源码旧，
# 重链必然不同（今晚实测 `.text` 小 52 B、`.rodata` 小 220 B），这条已在 `report/70-reproduce.md` 记着。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
say() { printf '%s\n' "$*"; }
die() { printf 'REFUSE: %s\n' "$*" >&2; exit 1; }

clean_platform_body() {
    [ -n "${VP_STAGE_KEEP_ALL:-}" ] && { say "KEEP all（VP_STAGE_KEEP_ALL=1）"; return 0; }
    find "$dst" -mindepth 1 -maxdepth 1 -not -name vitis-comp.json -not -name resources -exec rm -rf {} +
    say "CLEAN kept=vitis-comp.json,resources 平台正文（hw/ 域目录 zynq_fsbl/）不入库，重建路见 board/README.md 第 1 节"
    left="$(grep -rlE '[A-Za-z]:[/\\]' "$dst" 2>/dev/null || true)"
    if [ -n "$left" ]; then say "REFUSE: 留下来的文本件里还有本机绝对路径"; printf '%s\n' "$left" >&2; exit 1; fi
    say "VERIFY abs_path_files=0 kept_files=$(find "$dst" -type f | wc -l)"
}

[ -n "${PS_CC:-}" ] || die "设 PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe"
[ -f "$PS_CC" ] || die "找不到编译器 $PS_CC"
src="$root/vitis/platform"

dst="${VP_BOARD_VITIS:-$root/board/vitis_platform}"
[ -d "$src" ] || die "没有 $src（Vitis 平台本体不在；这一支要在装过 vitis/platform 的机器上跑，仓库里只跟踪描述件）"
rm -rf "$dst"
mkdir -p "$dst"
cp -r "$src/." "$dst/"

# 交付形状：`board/vitis_platform` 入库的只有 vitis-comp.json 与 resources/ 下 3 份 qemu_args.txt（4 份文本件），
# 平台正文（hw/system.xsa、域目录与 16 MB/983 支 BSP）不入库——README §1 给的是"从 board/project/system.xsa 重建平台"的路。
# 所以下面先用整份副本做判据，最后把正文清掉，让落点回到入库那一版。
[ -f "$dst/vitis-comp.json" ] || die "副本没有 vitis-comp.json"
node "$root/build/r125_normalize_platform_json.mjs" "$dst/vitis-comp.json"

# 平台里的 BSP：域目录下那份（不是 export 的副本），列出候选并取实际存在的那个
bsp=""
for c in "$dst"/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp \
         "$dst"/export/platform/sw/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp; do
    [ -d "$c" ] && bsp="$c" && break
done
[ -n "$bsp" ] || die "复制出来的平台里找不到 BSP（域目录形状变了？）"
say "STAGE_DST $dst"
say "STAGE_BSP $bsp"
for need in hw/system.xsa zynq_fsbl/build/fsbl.elf; do
    [ -f "$dst/$need" ] || die "副本缺 $need"
    say "STAGE_HAVE $need"
done

if [ -n "${VP_SKIP_BUILD:-}" ]; then say "STAGE_VITIS SKIPPED-BUILD"; clean_platform_body; exit 0; fi

# 判据是"用副本里的 BSP 能独立链出 ELF"。仓库里 `board/project/ps_app.elf` 是被跟踪的在板身份，
# 不能因为跑一次验证就被换掉，所以先备份、链完再还原，并把两颗的 section 大小一起打出来。
saved="$(mktemp /tmp/stage_ps_app.XXXX.elf)"
cp "$root/board/project/ps_app.elf" "$saved" || die "备份在板 ELF 失败"
trap 'cp "$saved" "$root/board/project/ps_app.elf"; rm -f "$saved"' EXIT
before="$(md5sum "$saved" | cut -d' ' -f1)"
PS_BSP="$bsp" node "$root/build/ps_app.mjs" > "$dst/stage_build.log" 2>&1 \
    || { tail -20 "$dst/stage_build.log" >&2; die "用副本 BSP 链应用失败，日志 $dst/stage_build.log"; }
after="$(md5sum "$root/board/project/ps_app.elf" | cut -d' ' -f1)"
SIZE_TOOL="${PS_CC%gcc.exe}size.exe"
"$SIZE_TOOL" -A "$saved" | grep -E '^\.text|^\.rodata' | tr -s ' ' > /tmp/stage_sz_before.txt
"$SIZE_TOOL" -A "$root/board/project/ps_app.elf" | grep -E '^\.text|^\.rodata' | tr -s ' ' > /tmp/stage_sz_after.txt
say "ELF_MD5_INREPO $before"
say "ELF_MD5_STAGED_BUILD $after"
say "SECTIONS_BEFORE $(tr '\n' '|' < /tmp/stage_sz_before.txt)"
say "SECTIONS_AFTER  $(tr '\n' '|' < /tmp/stage_sz_after.txt)"
# 两颗一致只说明"源码没动过"；不一致也不等于副本坏了——同一条命令用原始 BSP 也链出这颗，
# 差在仓库里那颗 ELF 比 src/ps 的源码旧。所以这里判的是"链得出来"，md5 只如实打印。
[ -s "$root/board/project/ps_app.elf" ] || die "链出来的是 0 字节"
say "STAGE_VITIS RESULT=OK 副本能独立编译链接（ELF 非空，$(stat -c%s "$root/board/project/ps_app.elf") 字节）"
clean_platform_body

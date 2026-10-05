#!/usr/bin/env bash
# board/scripts/make_boot_image.sh —— 把 FSBL + 位流 + PS 应用打成一个 QSPI 启动镜像 BOOT.bin
#
# 依赖：bootgen（Vivado/Vitis 2025.2.1 安装树里的 `bin/bootgen.bat`，不在 PATH）；
#       三份输入都在盘上：`vitis/platform/zynq_fsbl/build/fsbl.elf`、`build/system.bit`、`build/ps_app.elf`。
# 用法：VP_VIVADO_BIN="D:/Software/Vivado/2025.2.1/Vivado/bin" bash board/scripts/make_boot_image.sh
# 参数：
#   | 变量 | 作用 | 默认 |
#   | --- | --- | --- |
#   | `VP_VIVADO_BIN` | 含 bootgen.bat 的目录（必填，机器相关所以不写死） | 空 ⇒ REFUSE |
#   | `VP_BOOT_OUT`   | 输出目录 | `board/flash` |
#   | `VP_FSBL` / `VP_BIT` / `VP_APP` | 覆盖三份输入 | 见"依赖"那行 |
#
# bif 的写法是实测出来的（三种带逗号/带 `[boot]`/带 `configuration` 的写法都被 bootgen 判语法错）：
# Zynq-7000 这一支要的是 `the_design:` + 花括号里**逐行一个文件、不写逗号、不写属性**。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
say() { printf '%s\n' "$*"; }
die() { printf 'REFUSE: %s\n' "$*" >&2; exit 1; }

[ -n "${VP_VIVADO_BIN:-}" ] || die "设 VP_VIVADO_BIN=<Vivado>/bin（里面有 bootgen.bat）"
BG="$VP_VIVADO_BIN/bootgen.bat"
[ -f "$BG" ] || die "找不到 bootgen：$BG"

out="${VP_BOOT_OUT:-$root/board/flash}"
fsbl="${VP_FSBL:-$root/vitis/platform/zynq_fsbl/build/fsbl.elf}"
bit="${VP_BIT:-$root/build/system.bit}"
app="${VP_APP:-$root/build/ps_app.elf}"
for f in "$fsbl" "$bit" "$app"; do [ -s "$f" ] || die "输入缺件或为空：$f"; done

mkdir -p "$out"
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" | tr '\\' '/'; else printf '%s\n' "$1"; fi; }

bif="$out/boot.bif"
{
  printf 'the_design:\n{\n'
  win "$fsbl"
  win "$bit"
  win "$app"
  printf '}\n'
} > "$bif"

img="$out/BOOT.bin"
"$BG" -arch zynq -image "$(win "$bif")" -w -o "$(win "$img")" > "$out/bootgen.log" 2>&1 \
  || { tail -20 "$out/bootgen.log" >&2; die "bootgen 失败，日志 $out/bootgen.log"; }

[ -s "$img" ] || die "bootgen 报成功但 $img 不在盘上或为空"
say "BOOT_IMAGE $img"
say "BOOT_BYTES $(wc -c < "$img")"
say "BOOT_MD5   $(md5sum "$img" | cut -d' ' -f1)"
say "BIT_MD5    $(md5sum "$bit" | cut -d' ' -f1)"
say "BIT_MD5_12 $(md5sum "$bit" | cut -c1-12)"
say "APP_MD5    $(md5sum "$app" | cut -d' ' -f1)"
say "FSBL_MD5   $(md5sum "$fsbl" | cut -d' ' -f1)"
say "MAKE_BOOT_IMAGE DONE"

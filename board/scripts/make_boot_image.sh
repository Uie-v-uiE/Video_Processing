#!/usr/bin/env bash
# board/scripts/make_boot_image.sh —— 把 FSBL + 位流 + PS 应用打成一个 QSPI 启动镜像 BOOT.bin
#
# 依赖：bootgen（Vivado/Vitis 2025.2.1 安装树里的 `bin/bootgen.bat`，不在 PATH）；
#       三份输入都在盘上：`vitis/fin2_plat/zynq_fsbl/fsbl.elf`（旧布局 `vitis/platform/zynq_fsbl/build/fsbl.elf` 也认）、
#       `board/project/system.bit`、`board/project/ps_app.elf`。
# 用法：VP_VIVADO_BIN=<Vivado>/bin bash board/scripts/make_boot_image.sh
# 参数：
#   | 变量 | 作用 | 默认 |
#   | --- | --- | --- |
#   | `VP_VIVADO_BIN` | 含 bootgen.bat 的目录（必填，机器相关所以不写死） | 空 ⇒ REFUSE |
#   | `VP_BOOT_OUT`   | 输出目录 | `board/flash` |
#   | `VP_FSBL` / `VP_BIT` / `VP_APP` | 覆盖三份输入 | 见"依赖"那行 |
#
# bif 的写法是实测出来的（三种带逗号/带 `[boot]`/带 `configuration` 的写法都被 bootgen 判语法错）：
# Zynq-7000 这一支要的是 `the_design:` + 花括号里逐行一个文件、不写逗号；
# 但 FSBL 那一行**必须**带 `[bootloader]` 属性——不带的时候 bootgen 也报 "generated successfully"，
# 打出来的镜像却把 IHT 的分区表偏移三个字段留成 0，启动 ROM 读不懂（实测：DONE 不亮、串口零字节）。
# 依据：`bootgen -bif_help bootloader`（该属性 SUPPORTED 含 zynq）+ 厂商镜像头部同字段非 0 的对照。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
say() { printf '%s\n' "$*"; }
die() { printf 'REFUSE: %s\n' "$*" >&2; exit 1; }

[ -n "${VP_VIVADO_BIN:-}" ] || die "设 VP_VIVADO_BIN=<Vivado>/bin（里面有 bootgen.bat）"
BG="$VP_VIVADO_BIN/bootgen.bat"
[ -f "$BG" ] || die "找不到 bootgen：$BG"

out="${VP_BOOT_OUT:-$root/board/flash}"
fsbl="${VP_FSBL:-}"
if [ -z "$fsbl" ]; then
  for cand in "$root/vitis/fin2_plat/zynq_fsbl/fsbl.elf" "$root/vitis/platform/zynq_fsbl/build/fsbl.elf"; do
    [ -s "$cand" ] && { fsbl="$cand"; break; }
  done
fi
[ -n "$fsbl" ] || fsbl="$root/vitis/fin2_plat/zynq_fsbl/fsbl.elf"
bit="${VP_BIT:-$root/board/project/system.bit}"
app="${VP_APP:-$root/board/project/ps_app.elf}"
for f in "$fsbl" "$bit" "$app"; do [ -s "$f" ] || die "输入缺件或为空：$f"; done

mkdir -p "$out"
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" | tr '\\' '/'; else printf '%s\n' "$1"; fi; }
rel() { python -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]).replace("\\\\","/"))' "$1" "$2" 2>/dev/null || printf '%s\n' "$1"; }

bif="$out/boot.bif"
{
  printf 'the_design:\n{\n'
  # FSBL 必须标 [bootloader]（bootgen -bif_help bootloader：该属性支持 zynq）。
  # 不标的时候 bootgen 照样报 "Bootimage generated successfully"，但打出来的镜像头部
  # IHT+0x10/+0x14/+0x20（分区表偏移那一组）全是 0 ⇒ 启动 ROM 读不懂，冷上电零字节、DONE 不亮。
  # 对照：厂商 SD/BOOT.BIN 那三个位置是 0x00001700 / 0x00018008 / 0x00018008；
  #      补上 [bootloader] 之后我们这份变成 0x00001700 / 0x0001f6f4 / 0x0001f6f4（同一形状）。
  # BIF 里的路径相对 BIF 文件本身写，换一台机器解包也不会带着本机盘符。
  printf '   [bootloader] '; rel "$fsbl" "$out"
  rel "$bit" "$out"
  rel "$app" "$out"
  printf '}\n'
} > "$bif"

img="$out/BOOT.bin"
rm -f "$img"
# 在 BIF 所在目录跑：BIF 里的路径是相对 BIF 文件写的，bootgen 按当前目录解析。
# 生成前先删旧镜像 —— bootgen 读不到输入时也返回 0，旧文件会让“成功”变成假绿。
( cd "$out" && "$BG" -arch zynq -image boot.bif -w -o BOOT.bin ) > "$out/bootgen.log" 2>&1 \
  || { tail -20 "$out/bootgen.log" >&2; die "bootgen 失败，日志 $out/bootgen.log"; }
grep -q "\[ERROR\]" "$out/bootgen.log" && { tail -20 "$out/bootgen.log" >&2; die "bootgen 日志里有 ERROR"; }
grep -q "Bootimage generated successfully" "$out/bootgen.log" \
  || { tail -20 "$out/bootgen.log" >&2; die "bootgen 没有打印成功行"; }
[ -s "$img" ] || die "bootgen 报成功但 $img 不在盘上或为空"
say "BOOT_IMAGE $img"
say "BOOT_BYTES $(wc -c < "$img")"
say "BOOT_MD5   $(md5sum "$img" | cut -d' ' -f1)"
say "BIT_MD5    $(md5sum "$bit" | cut -d' ' -f1)"
say "BIT_MD5_12 $(md5sum "$bit" | cut -c1-12)"
say "APP_MD5    $(md5sum "$app" | cut -d' ' -f1)"
say "FSBL_MD5   $(md5sum "$fsbl" | cut -d' ' -f1)"
say "MAKE_BOOT_IMAGE DONE"

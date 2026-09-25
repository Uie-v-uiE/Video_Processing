#!/bin/bash
# build/wip_flash_r63.sh —— 把"刷 PL + 重启 PS app + 跑机器验收"三步固定下来，一条命令跑完。
#
# 为什么要有这个文件（而不是我半夜手敲三条命令）：这三步的顺序**有因果**，
#   ① 必须先 program_pl（Vivado 的 program_hw_devices）：xsdb 的 `fpga -file` 会复位 PS 侧，
#      之后 DAP 报 `APB AP transaction error 0xF0000021`，只能 `rst -system` 恢复 —— 而那又会把 PL 冲掉（死循环）。
#   ② 再 ps_app_reload.tcl：`rst -processor` 只复位 Cortex-A9 ⇒ 位流保得住；不重下 app 的话 AXI GPIO 控制字是旧的。
#   ③ 最后 board_verify（机器那一半验收：读回口 + 自检 + 电池 + geom）。
# 顺序错了的症状都很难看，所以钉在这里。
#
# 故意**不**做的事：不写 QSPI/SPI flash（2025.2.1 下绝不动那块 flash 是硬规矩）；不动 FT2232 EEPROM；
#   不在没有活板子时反复重试（板子没电的表现是 `No devices detected on target`，软件层面无解，见 env 备忘）。
set -u
ROOT=/d/Xilinx/Prj/pro/Video_Processing
# ⚠ 这两条命令都走 `cmd //c "反斜杠全路径"` 这个**实测可用**的形状：
#   `Vitis/bin/xsdb`（无扩展名）是 Linux 风格的 wrapper，从 Git Bash 起会报
#   `.../unwrapped/lnx64.o/rlwrap: No such file or directory`；而 `vivado` 不在 PATH 上，
#   直接后台起它会 127 退出**且不生成 log**（通知里还写着 exit 0）。
VIV='D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat'
XSDB='D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat'
cd "$ROOT" || exit 1

if tasklist //FI "IMAGENAME eq vivado.exe" 2>/dev/null | grep -qi "vivado.exe"; then
  echo "有 vivado.exe 在跑（构建没结束）⇒ 现在不能刷板：两条 Vivado 会撞内存，而且位流可能不是最终那份"
  exit 1
fi

echo "=== 0) 要刷的位流是哪一份（只认 md5，不认文件名）==="
md5sum build/system.bit build/system.xsa
echo "    r63b 参照：$(grep -a 'system.bit' build/evidence_r63b/MANIFEST.md5)"

echo "=== 1) program_pl（JTAG 只配 PL，不碰 QSPI）==="
cmd //c "$VIV -mode batch -nojournal -log build/r63_program_pl.log -source build/tcl/program_pl.tcl" > build/r63_program_pl_console.txt 2>&1
rc=$?
grep -aE "PROGRAMMED|NO xc7z020|NO BIT|No devices detected|ERROR" build/r63_program_pl_console.txt | head -6
if [ $rc -ne 0 ] || ! grep -qa "PROGRAMMED" build/r63_program_pl_console.txt; then
  echo "刷 PL 没成功 ⇒ 停在这里（板子没电/线没插是软件救不了的，见 env 备忘）。不继续假装验收。"
  exit 1
fi

echo "=== 2) 重启 PS app（rst -processor：只复位 A9，位流保留）==="
cmd //c "$XSDB build/tcl/ps_app_reload.tcl" > build/r63_ps_reload_console.txt 2>&1
rc=$?
grep -aE "PC_BEFORE_CON|PC_AFTER|elf|ERROR" build/r63_ps_reload_console.txt | head -8
if [ $rc -ne 0 ]; then echo "PS app 重启失败 ⇒ 板子里 PL 已是新位流、CPU 可能没跑 ⇒ 串口电池必然连红，先修这一步"; exit 1; fi

echo "=== 3) 机器那一半验收（读回口 + 自检 + 97 条电池 + geom 最后一跳）==="
bash build/board_verify.sh --battery --geom > build/r63_board_verify.txt 2>&1
echo "board_verify rc=$?"
grep -aE "PASS|FAIL|RESULT|不符|不一致|geom=|lane23" build/r63_board_verify.txt | tail -24

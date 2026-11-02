#!/usr/bin/env bash
# 用途：等 stage2 的门禁件落地，再跑 r117 那把刀的**预验**（不采纳，只出数）
# 输入：命令行参数
# 输出：build/r117_fb_pblock_console.txt
# 退出码：1=非 0 分支（该文件 exit 1 那一行）
# build/r116_stage3.sh —— 等 stage2 的门禁件落地，再跑 r117 那把刀的**预验**（不采纳，只出数）
set -u
cd "$(dirname "$0")/.."
say(){ printf '[stage3 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
for i in $(seq 1 200); do [ -f build/r116_gates.txt ] && break; sleep 60; done
[ -f build/r116_gates.txt ] || { say "等不到 r116_gates.txt，stage3 不走"; exit 1; }
say "stage2 的门禁件已在，开始 clk_fpga_0 的 pblock 预验（两滚 ≈ 18 分钟）"
bash build/r117_fb_pblock_fastlane.sh > build/r117_fb_pblock_console.txt 2>&1
say "预验 rc=$? —— 读数在 build/evidence/r117_fb_pblock/driver.log"

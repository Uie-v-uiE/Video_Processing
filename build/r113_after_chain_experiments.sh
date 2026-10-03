#!/usr/bin/env bash
# build/r113_after_chain_experiments.sh —— 等 r113 的链子跑完，然后把两支"只读 + 快车道"实验排上
#
# 为什么要等（两个理由都要能核对，不是"怕慢"这种含糊话）：
#   1) 这两支都要**开 dcp 起 Vivado**，而这台机只有 15.7 G 内存 / 12 个逻辑核——
#      台架 xsim 在飞时起 Vivado 会挤它（记忆：一台机上并发会污染墙钟类读数）。
#   2) 更要紧的是：链子自己后面还有 rim 台架与门禁两跑。中间任何一段"上一支已结束、下一支还没起"的
#      空隙都会让"没有 xsim"这个条件假成立 ⇒ 必须等**链子的出口件** `build/r113_gates.txt` 出现，
#      再叠加"没有 xsim/vivado 在飞"，两条同时成立才起飞。
#
# 排的两支（都直接服务"改时序要看全局"这一条，见 report/TIMING_GLOBAL.md 第 5 节与 #263）：
#   1) build/r113_roster_refanout.sh —— 用改好的探针重取名册，把 D6 那根"工具红"变成有凭据的读数
#      （实测根因：本工具的 report_design_analysis 没有 -fanout 模式）。
#   2) build/r114_maxfanout_ab.sh —— 同一份 opt.dcp 滚两遍（A 不加 / B 加 set_max_fanout），
#      判据是**逐时钟名册差分**而不是全局 WNS 的绝对差（rule 35）——这就是"下一刀不追最差那条"的落地。
#
# 活着的证据（记忆：块缓冲 ⇒ 0 字节日志什么都证明不了）：除了自己的日志，还去问工具自己的工作目录
#   （/tmp/kx/mf114/*/roll_console.txt、build/evidence/r113_fanout_raw.txt）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
GATES=build/r113_gates.txt
say() { printf '[ac %s] %s\n' "$(date +%m-%d_%H:%M:%S)" "$*"; }
say "bit=$(md5sum < build/system.bit | awk '{print substr($1,1,12)}')（排的是这一版的实验）"
deadline=$(( $(date +%s) + 5*3600 ))
while : ; do
    if [ -f "$GATES" ]; then
        if tasklist 2>/dev/null | grep -qiE '^(xsim|xsimk|vivado)\.exe'; then
            say "出口件有了但进程还没清：$(tasklist 2>/dev/null | grep -aiE '^(xsim|xsimk|vivado)\.exe' | awk '{print $1}' | sort -u | tr '\n' ' ')"
        else
            say "两条都成立：$GATES 在盘上，且没有 xsim/vivado 在飞"
            break
        fi
    else
        if tasklist 2>/dev/null | grep -qiE '^(xsim|xsimk|vivado)\.exe'; then
            say "链子还在跑：$(tasklist 2>/dev/null | grep -aiE '^(xsim|xsimk|vivado)\.exe' | awk '{print $1}' | sort -u | tr '\n' ' ')"
        else
            say "没有 xsim/vivado，但 $GATES 还没出现（链子可能停在某段 node 检查之间；继续等）"
        fi
    fi
    if [ "$(date +%s)" -gt "$deadline" ]; then
        say "TIMEOUT: 5 小时没等到（不猜、不硬抢；链子状态见 build/r113_chain2 的日志）"
        exit 3
    fi
    sleep 60
done
say "开始 1) 名册重取（把 D6 变成有凭据的读数）"
bash build/r113_roster_refanout.sh > build/evidence/r113_refanout_run.txt 2>&1
R1=$?
say "1) rc=$R1 差分：$(grep -a '^ROSTERDIFF-SUMMARY' build/evidence/r113_roster_diff_rf.txt | tail -1)"
say "   探针自己的计数：$(grep -a 'FANOUT_EXISTS=\|FANOUT_ROWS=' build/evidence/r113_roster_rf_console.txt | tail -2 | tr '\n' ' ')"
say "   原始名册件：$(ls -la build/evidence/r113_fanout_raw.txt 2>/dev/null | awk '{print $5" bytes", $9}')"
say "开始 2) set_max_fanout 单变量 A/B（约 2 x 8~10 分钟）"
bash build/r114_maxfanout_ab.sh > build/evidence/r114_mf_ab_run.txt 2>&1
R2=$?
say "2) rc=$R2"
say "   两滚的进度问它们自己的工作目录：$(ls -la /tmp/kx/mf114/A/roll_console.txt /tmp/kx/mf114/B/roll_console.txt 2>/dev/null | awk '{print $5, $9}' | tr '\n' ' ')"
say "   判读：$(grep -a '^MF-SUMMARY' build/evidence/r114_mf/verdict.txt | tail -1)"
say "两支都排完：rc1=$R1 rc2=$R2（非零不是失败，是判据在说话——读 build/evidence/ 里那两份）"
exit 0

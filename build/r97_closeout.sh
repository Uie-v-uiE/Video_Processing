#!/bin/bash
# build/r97_closeout.sh —— 等整屏台架复跑结束，然后把"报告 → 门禁 → 试冻结"这三步按顺序跑完并落件。
# 为什么写成脚本：这三步之间有严格先后（报告必须晚于复跑、门禁必须晚于报告、冻结必须晚于门禁），
# 手工盯 xsim 结束再一条条敲，会把人钉在屏幕前 —— 而这正是本项目反复记录的"半夜手工串命令、别人复现不了"那一族。
# ⚠ 这个脚本**不改任何 src/rtl 或 sim/ 里的文件**（规矩：链在飞期间不动被链读的东西），
#   也不做"采纳/不采纳"的决定：它只把每一步的判定原样落成 .txt，判定由人读。
set -u
cd "$(dirname "$0")/.." || exit 1
export VP_VIVADO_BIN=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
OUT=build/r97_closeout_console.txt
say() { echo "[closeout $(date '+%F %H:%M:%S')] $*"; }

# ① 等复跑：run.log 里出现 RESULT 行、且没有活的 xsim/xsimk，才算它真的跑完（第十八条：只认产物自己的成功语）
LOG=/tmp/kx/tb_v98_top_seam.run/run.log
deadline=$(( $(date +%s) + 5400 ))            # 最多等 90 分钟
while :; do
    if grep -aqE '^RESULT tb_v98_top_seam (PASS|FAIL)' "$LOG" 2>/dev/null \
       && ! tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe" \
       && ! tasklist //FI "IMAGENAME eq xsimk.exe" 2>/dev/null | grep -qi "xsimk.exe"; then
        say "复跑已结束：$(grep -aE '^RESULT tb_v98_top_seam' "$LOG" | tail -1)"
        break
    fi
    if [ "$(date +%s)" -gt "$deadline" ]; then say "STOP: 等了 90 分钟还没结束，交给人判"; exit 1; fi
    sleep 30
done

# ② 出报告（它会重新盖 top_md5 / tb_md5 / rtl_md5，门禁第 15 项就按这三枚对账）
say "② tb98_report.sh"
bash build/tb98_report.sh > build/r97b_tb98_report_step.txt 2>&1
say "   报告头：$(sed -n '1,3p' build/tb_v98_report.txt | tr '\n' ' ' | cut -c1-170)"
say "   报告里的 FAIL 行数=$(grep -ac '^FAIL ' build/tb_v98_report.txt)"

# ③ 门禁 20 项（改后的 gates.sh 会把三件成品的 md5 打进抬头，这是 #191 补的那一刀）
say "③ gates.sh（20 项）"
bash build/gates.sh > build/r97b_gates.txt 2>&1; RC=$?
say "   门禁退出码 rc=$RC"
say "   $(grep -aE '^GATES:' build/r97b_gates.txt | tail -1)"
say "   $(grep -aE '^身份：|^      system' build/r97b_gates.txt | tr '\n' ' ')"
grep -a " FAIL" build/r97b_gates.txt | sed 's/^/        /' | head -8

# ④ 试冻结：现在门里还有红项的话，freeze_evidence.sh 必须 REFUSE（这条"该红就红"是要看的证据）
say "④ 试冻结（预期：红项还在 ⇒ REFUSE，冻结集继续留在 r75）"
bash build/freeze_evidence.sh 97 > build/r97b_freeze_attempt.txt 2>&1; RCF=$?
say "   冻结退出码 rc=$RCF；头三行：$(head -3 build/r97b_freeze_attempt.txt | tr '\n' '|' | cut -c1-170)"
ls -d build/evidence_r97 2>/dev/null && say "   ⚠ 竟然建出了 evidence_r97 目录，去看 MANIFEST" || say "   没有新冻结目录（与预期一致）"

say "⑤ 到此为止：提交、重导包与首页/文档数字由人接着做（导出器现在会拦未声明的红与不对批的门禁件）"

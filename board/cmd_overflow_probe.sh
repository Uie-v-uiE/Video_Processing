#!/usr/bin/env bash
# 用途：ISSUES #167 那条 `cmd_buf` 越界一字节的两端夹逼探针（任务 #131/#170 批）
# 输入：命令行参数
# 输出：stdout
# 退出码：0=跑完 2=非 0 分支（该文件 exit 2 那一行） 3=非 0 分支（该文件 exit 3 那一行）
# board/cmd_overflow_probe.sh —— ISSUES #167 那条 `cmd_buf` 越界一字节的两端夹逼探针（任务 #131/#170 批）。
#
# 为什么要单独一支探针而不是塞进 `board/cmd_battery_v81.txt`：电池的行数（"105 条串口命令"）本身就是
# 被文档引用的数（#229 那一课：改判据的条数要连着改每一句念它的文案）。等采纳那一笔一起动。
#
# 机理（读码定死的，见 report/log/issues.md 的 #167）：`rx_fill()` 把 CR 折成 LF，所以一行 **CRLF 会产生
# 两次"追加行尾"**；载荷支有界（`cmd_len < CMD_BUF-1`），换行支只判 `cmd_len > 0` ⇒
# 127 个载荷字节 + CRLF：第一次写 `cmd_buf[127]`（合法，最后一格）、第二次写 `cmd_buf[128]` **越界一字节**，
# `cmd_len` 变 129 ⇒ 派发那两个 `for (i < cmd_len)` 读到数组外一格 ⇒ 用户**明明发了一整行**，
# 固件却回一句"line unfinished（残包）"把它丢掉。所以这一条的指纹不是"有没有提示"，而是
# **"一行以换行结尾却被判成没写完"** —— 那在定义上不成立。
#
# ⚠ 现场纪律（第一跑就是被这一条逼出来的，教训记在 ISSUES）：固件的行缓冲**跨进程保留**，
#   上一跑没写完的字节会串进下一跑 —— 我第一次连着发，`STAT` 都被当成"dropped 17 trailing byte(s)"，
#   读出来三条全红，而红的是我的激励不是固件。所以现在：
#     ① 开场先把缓冲洗干净（连发空行 + 歇过残包计时），
#     ② 再要一次**已知会答的基线**（`STAT` 必须回显 `[STAT]`），拿不到就 REFUSE（不判红也不判绿），
#     ③ 界内那一侧用**短控制**（40 字节）证明这条通道本身不误报，
#     ④ 才轮到 126 / 127 两档。每档之间歇 `GAP` 秒（>残包计时 3000 ms 的两倍）。
#   每条判据一行；退出码 0=绿、2=现场不可信（REFUSE）、3=判红。
set -u
cd "$(dirname "$0")/.."
PORT=${VP_PORT:-COM6}
GAP=${VP_GAP:-9}
RES=/tmp/kx
mkdir -p "$RES"

send() {   # $1=要发的行 $2=捕获秒数 $3=落地文件
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File board/serial_bytes.ps1 \
        -Cmd "$1" -Seconds "${2:-5}" -Out "$3" >/dev/null 2>&1
}
cnt() { grep -ac "$2" "$1" 2>/dev/null || true; }   # $1=文件 $2=模式

A126=$(printf 'A%.0s' $(seq 1 126)); A127=$(printf 'A%.0s' $(seq 1 127)); A40=$(printf 'A%.0s' $(seq 1 40))

# ① 洗缓冲 + ② 基线：拿不到 `[STAT]` 就不许判任何东西
send "" 3 "$RES/of_w0.txt"; sleep 4; send "" 3 "$RES/of_w1.txt"; sleep "$GAP"
send "STAT" 5 "$RES/of_base.txt"
if [ "$(cnt "$RES/of_base.txt" '\[STAT\]')" = 0 ]; then
    echo "PROBE-REFUSE: 基线 STAT 那条命令没回显 [STAT]（现场不可信：缓冲没洗干净 / COM6 被别处占着 / 板子不在这台）。"
    echo "              捕获在 $RES/of_base.txt；确认可以中断串口后再重跑（--dry 思路同 uart_cmd_check）。"
    exit 2
fi
echo "PROBE baseline STAT replied OK（现场可用）"
sleep "$GAP"

# ③ 短控制：同一支探针、同一条通道，40 字节必须一个提示都不出
send "$A40" 5 "$RES/of_040.txt"; c40=$(cnt "$RES/of_040.txt" 'CMD!')
echo "PROBE O0 control(40B+CRLF): CMD!-hits=$c40 => $([ "$c40" = 0 ] && echo PASS || echo FAIL)"
sleep "$GAP"

# ④ 界内 / 界外两档
send "$A126" 5 "$RES/of_126.txt"; r126=$(cnt "$RES/of_126.txt" 'line unfinished'); t126=$(cnt "$RES/of_126.txt" 'CMD!')
echo "PROBE O1 in-bounds(126B+CRLF): unfinished=$r126 CMD!-hits=$t126 => $([ "$r126" = 0 ] && [ "$t126" = 0 ] && echo PASS || echo FAIL)"
sleep "$GAP"
send "$A127" 5 "$RES/of_127.txt"; r127=$(cnt "$RES/of_127.txt" 'line unfinished'); t127=$(cnt "$RES/of_127.txt" 'CMD!')
echo "PROBE O2 boundary(127B+CRLF): unfinished=$r127 CMD!-hits=$t127 => $([ "$r127" = 0 ] && echo PASS || echo FAIL)"
sleep 4
send "STAT" 5 "$RES/of_end.txt"; rend=$(cnt "$RES/of_end.txt" '\[STAT\]')
echo "PROBE O3 recovery(STAT after O2): [STAT]-hits=$rend => $([ "$rend" != 0 ] && echo PASS || echo FAIL)"
echo "PROBE captures: $RES/of_040.txt $RES/of_126.txt $RES/of_127.txt $RES/of_end.txt (PORT=$PORT GAP=${GAP}s)"
if [ "$c40" != 0 ] || [ "$r126" != 0 ] || [ "$t126" != 0 ] || [ "$r127" != 0 ] || [ "$rend" = 0 ]; then
    echo "RESULT cmd_overflow_probe RED（O2 的 unfinished>0 就是 #167 那一字节越界的指纹；O0/O1 也红就先查激励）"
    exit 3
fi
echo "RESULT cmd_overflow_probe PASS"
exit 0

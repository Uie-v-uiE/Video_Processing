#!/usr/bin/env bash
# 用途：r118 的最后四步，不依赖 r118_rotate.py（首页已经在 04:49 改口成功：
# 输入：命令行参数
# 输出：build/r118_finish_console.txt、build/r117_docrotated.marker
# 退出码：4=非 0 分支（该文件 exit 4 那一行）
# build/r118_tail2.sh —— r118 的最后四步，不依赖 r118_rotate.py（首页已经在 04:49 改口成功：
# wrote=10 mismatch=0、行数不变；那支脚本只是死在它自己的检查器包装上，与文档内容无关）。
#
# 步骤与硬停：
#   1) 两道尺子复核改口后的文档（metric_recheck 红 0 且解析满行；doc_currency 除"D1c 计数暂时不吻合"
#      之外不留别的红，D1c 空转一律不放行）→ 过了才落 marker；
#   2) 最终门禁两跑（文档已冻结，必须逐字节一致）；
#   3) 重导提交包，并按盘上文件数核（不读导出器的 stdout，#106/#169 那一族）；
#   4) 流水补记 + 提交 + 推送；任何一步不过就停，不造空提交、不带未核过的首页往下走。
set -u
cd "$(dirname "$0")/.."
say(){ printf '[t2 %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a build/r118_finish_console.txt; }

node src/host/metric_recheck.mjs > /tmp/kx/mr2.txt 2>&1
node src/host/doc_currency_check.mjs > /tmp/kx/dc2.txt 2>&1
python - <<'PY'
import io, re
mr = io.open("/tmp/kx/mr2.txt", encoding="utf-8", errors="replace").read().splitlines()
dc = io.open("/tmp/kx/dc2.txt", encoding="utf-8", errors="replace").read().splitlines()
reds = [l for l in mr if l.startswith("RED ")]
shape = None
for l in mr:
    m = re.search(r"解析到\s*(\d+)/(\d+)\s*行", l)
    if m:
        shape = m
rows = [l.strip() for l in dc
        if l.startswith("  ") and not l.strip().startswith("同行写了") and not l.strip().startswith("ADV ")]
allow = [l for l in rows if ("D1c" in l and "空转" not in l and "没接上" not in l)]
block = [l for l in rows if l not in allow]
print("RULER metric 红=%d 解析=%s" % (len(reds), shape.group(0) if shape else "读不到"))
for l in reds[:6]:
    print("   " + l[:140])
print("RULER doc_currency 行=%d 允许=%d 阻塞=%d" % (len(rows), len(allow), len(block)))
for l in (block[:6] + allow[:2]):
    print("   " + l[:140])
ok = (not reds) and (not block) and shape and shape.group(1) == shape.group(2)
io.open("/tmp/kx/ruler_ok.txt", "w", encoding="utf-8").write("1" if ok else "0")
print("RULER verdict=%s" % ("GREEN" if ok else "RED"))
PY
[ "$(cat /tmp/kx/ruler_ok.txt)" = "1" ] || { say "停：尺子没过，不落 marker、不跑最终门禁"; exit 4; }
printf 'rotated after r118 board flash\n' > build/r117_docrotated.marker
say "marker 落地，文档冻结"

bash build/gates.sh > /tmp/kx/ga.txt 2>&1
A=$?
bash build/gates.sh > /tmp/kx/gb.txt 2>&1
B=$?
if cmp -s /tmp/kx/ga.txt /tmp/kx/gb.txt; then ID=identical; else ID=different; fi
cp -f /tmp/kx/ga.txt build/r118_gates_final.txt
G=$(grep -c " PASS$" build/r118_gates_final.txt)
RED=$(grep -c " FAIL$" build/r118_gates_final.txt)
say "最终门禁 rcA=$A rcB=$B 两跑=$ID 绿=$G 红=$RED"
say "红项：$(grep -a ' FAIL$' build/r118_gates_final.txt | tr '\n' '|')"

bash build/make_submission.sh > /tmp/kx/sub2.txt 2>&1
S=$?
N=$(find ../submission -type f 2>/dev/null | wc -l)
say "make_submission rc=$S 盘上文件数=$N"

if [ "$RED" = 1 ] && [ "$ID" = identical ] && [ "$S" = 0 ]; then
    python - <<'PY'
import io, subprocess
g = io.open("build/r118_gates_final.txt", encoding="utf-8", errors="replace").read().splitlines()
green = sum(1 for l in g if l.endswith(" PASS"))
red = sum(1 for l in g if l.endswith(" FAIL"))
reds = [l.split()[0] + " " + l.split()[1] for l in g if l.endswith(" FAIL")]
board = io.open("build/evidence/r118_board/board_now.txt", encoding="utf-8", errors="replace").read().splitlines()[0]
b1 = ""
for l in io.open("build/evidence/r118_strict_b1.txt", encoding="utf-8", errors="replace"):
    if l.startswith("B1 pairs_compared"):
        b1 = l.strip()
n = subprocess.run(["find", "../submission", "-type", "f"], capture_output=True, text=True).stdout.count("\n")
entry = ("\n## §118 r118（2026-10-04 04:18–04:52）：最后一轮——只带 τ=31 的收口眼心上板\n\n"
         "* 判据：B1 严格名册（对 r114 逐格，件 `build/evidence/r118_strict_b1.txt`）%s；B2 机构中性（本版不挂复制钩子）；"
         "B3 资源中性；B4 发布门 24 项红数回到 %d 绿 / %d 红（红项：%s），两跑逐字节一致。\n"
         "* 板侧：%s\n"
         "* 同一夜里两把刀各自有了判语：C9 强制复制 239 引脚广播网在 r117 官方构建上**赢一格跌四格**（含最紧两格）"
         "⇒ 按 H7 判负（`build/r117_verdict_declined.txt`）；RGMII 输入窗绑上就把自家发布门的 4 条硬项判红"
         "⇒ 退回候选件（`VP_R116_IO_WINDOW=1` 复现），首页那一行明写这 5 个端点当前未检查、未检查不等于满足（H5）。\n"
         "* 工具账 #325–#329；提交包重导到 %d 个文件。\n" % (b1, green, red, "、".join(reds) or "无", board, n))
with io.open("report/log/overnight_log.md", "a", encoding="utf-8", newline="\n") as f:
    f.write(entry)

msg = "\n".join([
  "r118 上板并改口收口：只带 tau=31 的收口眼心；名册 8 对逐位复现 r114，最终门禁 %d 绿 / %d 红两跑逐字节一致" % (green, red),
  "",
  "- 板上：" + board,
  "- B1 严格名册：" + b1,
  "  τ=31 只动 I/O 单元的抽头 ⇒ 片内名册逐位不变正是这一刀的中性证明；收益在片外（眼心 +0.315 ns，"
  "件 build/evidence/r115_window/probe3_console.txt）。不写成 WNS 收益（规矩 35）。",
  "- 最终门禁：判定 24 项 绿 %d / 红 %d，两跑逐字节一致（件 build/r118_gates_final.txt）；红项：%s" % (green, red, "、".join(reds) or "无"),
  "- 首页/英文首页/metrics 由 build/r117_fill_docs.py + build/r117_doc_templates.txt 从件里取数改写（10 行，写后回读 mismatch=0、行数不变）；"
  "board/ACCEPTANCE 两处板态身份句同步到 r118。",
  "- C9 与 RGMII 输入窗都留在树里当候选件并写明判负/退回原因；本版无输入窗 ⇒ 那 5 个收口端点未检查（H5）。",
  "- 提交包重导：%d 个文件（按盘上数核）。流水补记 report/log/overnight_log.md §118。" % n,
  "- 工具账 #325–#329（首页门禁句的形状属于尺子射程；名册对照必须同生成器；catch 返回码当哨兵打死成功的官方 run；"
  "25%% 门槛与严格判据不一致；改口脚本会把首页写空——彩排+备份+行数地板）。",
  "",
])
io.open("/tmp/kx/msg_r118.txt", "w", encoding="utf-8").write(msg)
print("MSG+DIARY written")
PY
    say "落提交并推送"
    python build/r118_commit.py >> build/r118_finish_console.txt 2>&1
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if git push origin main > /tmp/kx/push2.txt 2>&1; then say "PUSH-OK try=$i"; break; fi
        say "push try=$i 失败：$(tail -1 /tmp/kx/push2.txt)"
        sleep 40
    done
    say "$(git status -sb | head -1)"
else
    say "不提交：最终门禁红数不是 1、或两跑不一致、或提交包导出失败 —— 交回人判断"
fi
say "TAIL2 END"

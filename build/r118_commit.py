#!/usr/bin/env python3
# build/r118_commit.py —— 把 r118 的交付面（首页/指标表/两份结果页/门禁与名册件/位流身份）落一次提交。
#
# 为什么单独一个文件：多行提交信息必须走文件 + `git commit -F`（heredoc/printf 那一条踩过：
# #324 的提交信息写着一次没有发生的改动，因为 assert 挂了而 `;` 串着的 git 照样成功）。
# 这里把信息**从件里读出来**再写：门禁绿/红、位流 md5、B1 那行——不是我抄的（规则 44/52）。
import io, os, subprocess

def read(p):
    return io.open(p, encoding="utf-8", errors="replace").read()

g = read("build/r118_gates_final.txt").splitlines()
green = sum(1 for l in g if l.endswith(" PASS"))
red = sum(1 for l in g if l.endswith(" FAIL"))
reds = [l.split()[0] + " " + l.split()[1] for l in g if l.endswith(" FAIL")]
bit = read("build/evidence/r118_bit/md5.txt").strip()
b1 = ""
for l in read("build/evidence/r118_strict_b1.txt").splitlines():
    if l.startswith("B1 pairs_compared"):
        b1 = l
board = read("build/evidence/r118_board/BOARD_NOW.txt").splitlines()[0]
n_sub = subprocess.run(["find", "../submission", "-type", "f"], capture_output=True, text=True).stdout.count("\n")

msg = "\n".join([
  "r118 最后一轮上板：只带 tau=31 的收口眼心；名册 8 对逐位复现 r114，交付文档改成官方读数",
  "",
  "- 板上：" + board + "（位流存档 build/evidence/r118_bit/，md5 " + bit + "）",
  "- B1 严格名册（对 r114，同生成器逐格）：" + b1,
  "  τ=31 只动 I/O 单元的抽头，片内名册逐位不变正是这一刀的**中性证明**；它的收益在片外：",
  "  收口眼心余量 +0.315 ns（件 build/evidence/r115_window/probe3_console.txt）。写成 WNS 收益是规矩 35 禁的那种读法。",
  "- 最终门禁：判定 24 项，绿 %d / 红 %d，两跑逐字节一致（件 build/r118_gates_final.txt）；红项：%s" % (green, red, "、".join(reds) or "无"),
  "- 留在树里但**不进构建**的两件，都写明为什么：C9 复制广播网判负（build/r117_verdict_declined.txt，"
  "赢 1 格跌 4 格含最紧两格；复现开关 IMPL_POST_PLACE_HOOK），RGMII 输入窗退回候选件"
  "（src/constraints/r116_rgmii_input_window.xdc；复现开关 VP_R116_IO_WINDOW=1；绑窗时 4 条发布硬门红）。",
  "- 首页那一行明写：本版没有输入窗 ⇒ 那 5 个收口端点是未检查状态，未检查不等于满足（提示词 H5）。",
  "- 提交包：build/make_submission.sh 重导，盘上 %d 个文件（按盘上数核，不读它的 stdout）。" % n_sub,
  "- 工具账 #325–#329：首页门禁句的形状属于尺子射程；名册对照必须同生成器；catch 的返回码当哨兵会打死成功的官方 run；"
  "25 % 门槛与严格判据对同一份数据判语不同（两边都不放宽，严格那把独立成件）；"
  "改口脚本会把首页写成空文件——彩排 + 备份 + 行数地板才是它的正确落地顺序。",
  "",
])
io.open("/tmp/kx/msg_r118.txt", "w", encoding="utf-8").write(msg)

paths = ["README.md", "README.en.md", "data/metrics.csv", "report/TIMING_GLOBAL.md", "report/log/ISSUES.md",
         "report/KNOWN_ISSUES.md", "report/ACCEPTANCE.md", "board/ACCEPTANCE.md",
         "docs/timing", "build/r118_chain.sh", "build/r118_finish.sh", "build/r118_commit.py",
         "build/r118_rotate.py", "build/r118_console.txt", "build/r118_finish_console.txt",
         "build/r118_verdict.txt", "build/r118_gates.txt", "build/r118_gates_final.txt",
         "build/r118_build_console.txt", "build/r118_roster_console.txt", "build/r118_post_readings_console.txt",
         "build/evidence", "build/timing_summary.rpt", "build/setup_paths.rpt", "build/hold_paths.rpt",
         "build/utilization.rpt", "build/r117_doc_templates.txt", "build/r117_fill_docs.py",
         "build/r117_verdict_declined.txt", "build/r117_a1_read.sh", "build/r117_pair_fix.sh"]
exist = [p for p in paths if os.path.exists(p)]
missing = [p for p in paths if p not in exist]
print("COMMIT paths exist=%d missing=%s" % (len(exist), ",".join(missing) or "无"))
subprocess.run(["git", "add", "-A", "--"] + exist)
staged = subprocess.run(["git", "diff", "--cached", "--name-only"], capture_output=True, text=True).stdout.splitlines()
print("COMMIT staged=%d" % len(staged))
if staged:
    r = subprocess.run(["git", "commit", "-F", "/tmp/kx/msg_r118.txt"], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr.strip())
    print(subprocess.run(["git", "log", "--oneline", "-1"], capture_output=True, text=True).stdout.strip())
else:
    print("COMMIT 没有暂存内容（文档与件都没变？停下来查，不造空提交）")

import io, os, datetime

ROOT = r"D:\Xilinx\Prj\pro\Video_Processing"
TSV = os.path.join(os.environ.get("TEMP", "/tmp"), "marker_rows.tsv")
PATS = ["【待验证】", "【未核实】", "【未实测】", "【队伍未确认】", "【待你补】", "NOT_MEASURED"]

ACTION = {
    "【待你补】": "队伍/持板人给这一项的具体值（型号、线材规格、限流、供电口径）；不给则这一步保持 `【不可复现】`，第三方只能验到第 1/5 节",
    "【队伍未确认】": "队伍在 `docs/questions-for-team.md` 里答对应那条 `Q-*`（动机、主张强度、可公开范围、接线参数只能由人陈述，agent 不许代答）",
    "【未实测】": "补一次实测：需要仪器/板子/一轮构建。要队伍点名\"这一批里哪几条补测\"并批时间窗，否则维持未实测",
    "【未核实】": "补一次可留出处（URL 或本地文件 + 核对日期）的核对；拿不到出处就保持降级，不许写成事实",
    "【待验证】": "跑这一行点名的那条尺子并留件（多数要 `VP_VIVADO_BIN`，少数要板子 + 批准）",
    "NOT_MEASURED": "见状态列：token 类无需动作；空格类要把缺的输入补齐后重跑那条命令；留痕类不参与补齐",
}

def impact(rel):
    if rel.startswith("report/40") or rel.startswith("report/50") or rel in (
        "report/comparison-notes.md", "report/OPTIMIZATION_LOG.md", "report/PERF_REPORT.md", "report/TIMING_GLOBAL.md"):
        return "性能与资源优化效果(20)"
    if rel.startswith("report/log/") or rel.startswith("report/study/"):
        return "—（追加式日记，按本仓规矩不参与核对）"
    if rel.startswith("report/figures/") or rel.startswith("report/io/"):
        return "功能正确性与设计完整性(20)"
    if rel.startswith("report/"):
        return "文档质量与可复现性(15)"
    if rel.startswith("board/"):
        return "功能正确性与设计完整性(20) + 文档质量与可复现性(15)"
    if rel.startswith("docs/walkthrough"):
        return "文档质量（学习文档，不随包）"
    if rel.startswith("docs/"):
        return "文档质量与可复现性(15)"
    if rel.startswith("skill/"):
        return "大模型协作与技能包(15)"
    if rel.startswith("submit/"):
        return "文档质量与可复现性(15)"
    if rel == "README.md":
        return "文档质量与可复现性(15)"
    return "文档质量与可复现性(15)"

def status(rel, pat, c):
    if rel.startswith("report/log/") or rel.startswith("report/study/"):
        return "留痕：历史日记/台账，不补齐也不删除（删它等于毁证据）"
    if rel.startswith("skill/scripts/selftest/fixtures/"):
        return "夹具：故意含标记的自检输入，不补齐（改了它 `--self` 会失真）"
    if rel.startswith("skill/scripts/_out/"):
        return "生成物：由脚本重生成即刷新，不手改"
    if rel.endswith((".mjs", ".sh", ".py")):
        return "token：脚本/模板源码里的三态字符串本身，删了会破坏\"读不到输入 ≠ 通过\"的输出契约 ⇒ 无需动作"
    if pat == "NOT_MEASURED" and rel.startswith("skill/templates/"):
        return "token：模板给的三态占位，由使用者填 ⇒ 无需动作"
    if pat == "NOT_MEASURED" and rel in ("skill/_meta/naming-and-format.md", "skill/_meta/entry-template.md",
                                        "skill/references/checker-convention-shapes/tokens-and-exit-codes.md",
                                        "skill/references/checker-convention-shapes/SKILL.md"):
        return "token：判据定义处的三态词 ⇒ 无需动作"
    if pat == "NOT_MEASURED":
        return "空格：这条判据的输入本次不可得 ⇒ 输入到位后重跑该行点名的命令（需批准）"
    if rel.startswith(("report/40", "report/50", "report/comparison-notes")):
        return "归同伴章节 P18b 收口（本次不代它补）"
    if rel.startswith(("report/20", "report/30", "report/figures")):
        return "归同伴章节 P18a 收口（本次不代它补）"
    if rel.startswith("board/"):
        return "需人给料 + 需批准的上板动作（P16a/P16c 队列项）"
    if rel.startswith("skill/"):
        return "归 P04/P08/P09 队列（`docs/run-queue.md` 里状态=进行中/部分）"
    if rel.startswith("docs/walkthrough"):
        return "归 P11 队列（5 篇因缺前置未写）"
    if rel.startswith("submit/"):
        return "需一次来源核对或一次实测；submit 侧由 P21 终审统一收口"
    if rel.startswith("docs/questions-for-team"):
        return "需队伍逐条回答（这张表就是问题清单本体）"
    return "需人给料/需批准，按本行的\"需要我做什么\"列执行"

rows = []
with io.open(TSV, encoding="utf-8") as fh:
    lines = [l.rstrip("\n") for l in fh if not l.startswith("#")]
    stamp = ""
    with io.open(TSV, encoding="utf-8") as h2:
        stamp = h2.readline().strip().lstrip("# ").strip()
for l in lines:
    rel, pat, c, linetxt, txt = l.split("\t")
    rows.append((rel, pat, int(c), linetxt, txt))

out = []
n = 0
for rel, pat, c, linetxt, txt in rows:
    n += 1
    txt2 = txt.replace("`", "'")
    if len(txt2) > 78:
        txt2 = txt2[:78] + "…"
    out.append("| OI-%03d | %s | `%s` 行 %s（%d 处）| %s | %s | %s | %s |"
               % (n, pat, rel, linetxt.replace("|", "/"), c, txt2, ACTION[pat], impact(rel), status(rel, pat, c)))

body = "\n".join(out)
with io.open(os.environ.get("TEMP", "/tmp") + "/open_items_body.md", "w", encoding="utf-8") as fh:
    fh.write(body)
print("rows written:", n, " sum of counts:", sum(r[2] for r in rows), " snapshot:", stamp)

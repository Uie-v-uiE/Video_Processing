#!/usr/bin/env bash
# build/r117_a1_read.sh —— 把 A1（机制）那条读数从**两个**地方问回来，不许只读顶层控制台。
#
# 为什么要有这一支（03:59 预检发现的陷阱，登记为 ISSUES #327）：
#   `STEPS.PLACE_DESIGN.TCL.POST` 挂的钩子是在 **impl_1 那个 run 自己的进程**里执行的，
#   它的 `puts` 落在 `vivado_system/zynq_video_sys.runs/impl_1/runme.log`，
#   而 `build/r117b_chain.sh` 判 A1 时 grep 的是顶层 `build/r117_build_console.txt`。
#   ⇒ 顶层那份**可能一行 R117HOOK 都没有**，于是 A1 会被读成 `MECHANISM_INERT`——
#   那是尺子接错了出水口，不是机制没动（提示词附录 1 明令这两种情况不许混）。
#   本脚本不做任何判定，只把两处的原文与三个数（引脚 before/after、replica 颗数）一起印出来。
set -u
cd "$(dirname "$0")/.."
RUN=vivado_system/zynq_video_sys.runs/impl_1/runme.log
TOP=build/r117_build_console.txt
echo "A1SRC date=$(date '+%F %T')"
for f in "$TOP" "$RUN"; do
    printf 'A1SRC file=%s exists=%s\n' "$f" "$([ -f "$f" ] && echo yes || echo no)"
    [ -f "$f" ] || continue
    grep -a "R117HOOK" "$f" | sed 's/^/  /' | tail -6
done
echo "A1SRC top_console_R117HOOK_count=$(grep -ac 'R117HOOK' "$TOP" 2>/dev/null)"
echo "A1SRC runme_log_R117HOOK_count=$(grep -ac 'R117HOOK' "$RUN" 2>/dev/null)"
# 机制闭合等式：引脚减少数 == replica 颗数 == 端点增加数（三者对不上就是"看起来动了"）
python - <<'PY'
import re, os
p = "vivado_system/zynq_video_sys.runs/impl_1/runme.log"
if not os.path.exists(p):
    print("A1EQ-NOLOG runme.log 还没生成"); raise SystemExit(0)
t = open(p, encoding="utf-8", errors="replace").read()
def g(k):
    m = re.findall(k + r"[= ]([0-9]+)", t)
    return m[-1] if m else "NA"
b, a, r = g("pins_before"), g("pins_after"), g("replica_cells")
print("A1EQ pins_before=%s pins_after=%s replica_cells=%s folded=%s" %
      (b, a, r, (int(b) - int(a)) if b != "NA" and a != "NA" else "NA"))
print("A1EQ verdict=%s" % ("OK(等式可算)" if r != "NA" and b != "NA" and a != "NA" and
                            int(r) >= 1 and int(b) - int(a) == int(r) else
                            "CHECK(机制数与折叠数对不上或还没跑，别写成收益也别写成 INERT)"))
PY

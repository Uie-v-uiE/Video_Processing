#!/usr/bin/env python3
# 用途："""build/r114_io_verdict.py —— 把快车道那一滚（build/tcl/r114_io_roll.tcl 的控制台）判成一张表
# 输入：命令行参数
# 输出：stdout
# 退出码：0=跑完 4=非 0 分支（该文件 exit 4 那一行）
# -*- coding: utf-8 -*-
"""build/r114_io_verdict.py —— 把快车道那一滚（build/tcl/r114_io_roll.tcl 的控制台）判成一张表。

为什么单独一支判据脚本（而不是"人看一眼 WNS"）：
  * 用户那一问的要害就是"别只盯最差那条"。一滚会打 30+ 行 IROW（四根头条钟 × setup/hold × 两滚两状态），
    人的眼睛一定会先去看最大的那个数，所以这张表**逐钟**判，并把"WNS 没动"明确排除在收益/回归之外
    （规矩 35：WNS 的绝对差既不是收益也不是回归；组排除下的路本来就不进 WNS，所以 #266 那四条界
    数得出条数才算打到东西）。
  * 每条判据一行、末列是判定（规矩：计数是整数、每条一轮一行、判定放最后一列）。
  * **正控制内置**：J4 要求 base 滚的 datapath_only 计数为 0 而 io 滚 ≥ 4 —— 只念"加了以后有 4 条"
    的那把尺子可以在解析断掉时永远绿（规矩 46：每个解析层都要有真件计数地板，且要能红）。
  * NA 一律不当 0：解析不出来 = 尺子断了 = IO_AB=INVALID_RULER，而不是"没有违例"。

用法：python build/r114_io_verdict.py [控制台文件]     默认 build/evidence/r114_io_roll_console2.txt
退出码：0 = GREEN，1 = RED，4 = 尺子自己断了/件不存在。
"""
import io, os, re, sys

CON = sys.argv[1] if len(sys.argv) > 1 else "build/evidence/r114_io_roll_console2.txt"
CLOCKS = ["eth_rxc", "clk_fpga_0", "clkout0_1", "sys_clk"]
if not os.path.exists(CON):
    print("IO_AB=INVALID_RULER reason=no_console_file:%s" % CON)
    sys.exit(4)
txt = io.open(CON, encoding="utf-8", errors="replace").read()

def kv(line):
    d = {}
    for part in line.split("|")[1:]:
        if "=" in part:
            k, v = part.split("=", 1)
            d[k] = v
        else:
            d.setdefault("_tail", []).append(part)
    return d

debt = {}
rows = {}
head = {}
for line in txt.splitlines():
    if line.startswith("DEBT|"):
        d = kv(line)
        tag = line.split("|")[1]          # base / base_after_route / io_before / io_after_route
        if tag:
            d["tag"] = tag
            debt[tag] = d
    elif line.startswith("IROW|"):
        d = kv(line)
        rows[(d["tag"], d["clk"], d["kind"])] = d
    elif line.startswith("IHEAD|"):
        d = kv(line)
        head[d["tag"]] = d

out = []
red = 0
bad_ruler = 0

def judge(name, meas, want, ok, note=""):
    global red
    v = "GREEN" if ok else "RED"
    if not ok:
        red += 1
    out.append("IOAB %-26s %s want=%s %s %s" % (name, meas, want, v, note))
    return ok

def num(s):
    try:
        return float(s)
    except Exception:
        return None

# ---- J0 件本身在不在：DEBT/IROW/IHEAD 三类行都要有 ----
judge("J0_pieces_present", "debt=%d rows=%d head=%d" % (len(debt), len(rows), len(head)),
      "debt>=2&rows>=32&head>=4", len(debt) >= 2 and len(rows) >= 32 and len(head) >= 4)
if red:
    bad_ruler = 1

# ---- J1 解析不许断：两滚的四个 debt 数都必须是整数 ----
def debt_int(tag, key):
    d = debt.get(tag) or {}
    v = d.get(key, "NA")
    return None if v in ("NA", "") else int(float(v))

need_tags = [("base_after_route", "no_in"), ("io_after_route", "no_in"),
             ("base_after_route", "no_out"), ("io_after_route", "no_out"),
             ("base_after_route", "datapath_only_hits"), ("io_after_route", "datapath_only_hits")]
miss = ["%s.%s" % (t, k) for t, k in need_tags if debt_int(t, k) is None]
judge("J1_debt_parsed", "missing=%d" % len(miss), "0", not miss, (" ".join(miss[:4]) if miss else ""))
if miss:
    bad_ruler = 1

# ---- J2 名册行齐全且 slack 解析出来（NA 不算数） ----
na_rows = [k for k in rows if rows[k].get("slack", "NA") == "NA"]
judge("J2_roster_rows_parsed", "rows=%d slack_NA=%d" % (len(rows), len(na_rows)),
      "rows>=32&slack_NA=0", len(rows) >= 32 and not na_rows,
      (" ".join("%s/%s/%s" % x for x in list(rows.keys())[:0] + na_rows[:3])))
if na_rows:
    bad_ruler = 1

if bad_ruler:
    print("\n".join(out))
    print("IO_AB=INVALID_RULER reason=parse_broken（NA 不当 0 念，规矩 46）")
    sys.exit(4)

bi, ii = debt_int("base_after_route", "no_in"), debt_int("io_after_route", "no_in")
judge("J3_input_debt_cleared", "base_no_in=%d io_no_in=%d" % (bi, ii), "base=5&io=0", bi == 5 and ii == 0)

bo, io_ = debt_int("base_after_route", "no_out"), debt_int("io_after_route", "no_out")
out.append("IOAB J3b_output_debt_advisory base_no_out=%d io_no_out=%d（TMDS/LED 那 6 个端口的窗缺规范出处，"
           "本笔不动、如实挂着，见 #188） ADVISORY" % (bo, io_))

bdm, idm = debt_int("base_after_route", "datapath_only_hits"), debt_int("io_after_route", "datapath_only_hits")
judge("J4_async_bounds_present", "base_dp_only=%d io_dp_only=%d" % (bdm, idm), "base=0&io>=4",
      bdm == 0 and idm >= 4)

bh, ih = head.get("base_route", {}), head.get("io_route", {})
bs, is_ = num(bh.get("fail_setup", "NA")), num(ih.get("fail_setup", "NA"))
bhp, ihp = num(bh.get("fail_hold", "NA")), num(ih.get("fail_hold", "NA"))
judge("J5_no_new_failing_endpoints", "base_fail_s=%s/%s io_fail_s=%s/%s" % (bs, bhp, is_, ihp),
      "io_fail_s=0&io_fail_h=0", is_ == 0 and ihp == 0)

bw, iw = num(bh.get("whs", "NA")), num(ih.get("whs", "NA"))
judge("J6_hold_headline_nonneg", "base_whs=%s io_whs=%s" % (bw, iw), "io_whs>=0",
      iw is not None and iw >= 0,
      "（加了真实到达窗之后 hold 还站得住吗——这是这一刀唯一可能伤到全局的地方）")

# ---- 逐钟差分：一条都不许从 MET 变 VIOLATED；余量按周期百分比念 ----
for c in CLOCKS:
    for kind in ("setup", "hold"):
        b = rows.get(("base_route", c, kind))
        i = rows.get(("io_route", c, kind))
        if not b or not i:
            out.append("IOAB J7_%s_%s missing_row RED（两滚都该有这一格）" % (c, kind))
            red += 1
            continue
        sb, si = num(b["slack"]), num(i["slack"])
        per = num(i.get("period", "NA")) or 1.0
        flip = (b["state"] == "MET" and i["state"] != "MET")
        meas = "%s: %s->%s ns(相对余量 %.2f%%->%.2f%%)" % (
            c, b["slack"], i["slack"], 100.0 * sb / per, 100.0 * si / per)
        judge("J7_%s_%s_no_flip" % (c, kind), meas, "state 不翻负", not flip,
              "levels %s->%s route%% %s->%s" % (b.get("levels"), i.get("levels"),
                                               b.get("route_pct"), i.get("route_pct")))

print("\n".join(out))
print("IOAB_SUMMARY judged=%d red=%d head_io=wns=%s/whs=%s" % (len(out), red,
      ih.get("wns", "NA"), ih.get("whs", "NA")))
print("IO_AB=%s" % ("GREEN" if red == 0 else "RED"))
sys.exit(0 if red == 0 else 1)

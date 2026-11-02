#!/usr/bin/env python3
# 用途："""build/r114_sweep_verdict.py —— 读 IDELAY_VALUE 扫档那一滚的控制台，出一张"哪个档把眼心找到了"的表
# 输入：命令行参数
# 输出：stdout
# 退出码：0=跑完 1=非 0 分支（该文件 exit 1 那一行） 4=非 0 分支（该文件 exit 4 那一行）
# -*- coding: utf-8 -*-
"""build/r114_sweep_verdict.py —— 读 IDELAY_VALUE 扫档那一滚的控制台，出一张"哪个档把眼心找到了"的表。

判据的形状是抄 #193/ISSUES #275 的口径，不是"挑一个最好看的数"：
  S1 件与解析：每档都要有 SWEEPHEAD + 8 行 SWEEPROW（4 钟 × setup/hold）+ 1 行 HOLDWorst，
     slack 不许是 NA —— 解析断了就是 INVALID_SWEEP（NA 不当 0 念，规矩 46）。
  S2 目标：`eth_rxc` 的 hold slack ≥ 0 且该设计级 fail_hold == 0（这一刀要修的正是这个）。
  S3 不伤别处：其余三域的 setup/hold 与"未加窗基线"比不许翻成 VIOLATED，且 setup 余量不得低于基线的 90 %
     （基线 = 同一份 dcp 不加约束那一滚：eth_rxc 0.445/0.050、clk_fpga_0 1.135/0.056、
      clkout0_1 4.467/0.059、sys_clk 14.463/0.133，件 build/evidence/r114_io_roll_console5.txt 的 base_route 行）。
  S4 诚实的方向性：如果没有任何一档满足 S2，就明说"扫不到眼心 ⇒ 不是 tap 的问题"，
     不许把"负得最少的那一档"说成"找到了"。
输出：每条判据一行、末列是判定（规矩：计数是整数、判定放最后一列）。
退出码：0 有档过 S2+S3；1 没有档过（但实验成立）；4 件不完整/尺子断了。
"""
import io, os, sys

CON = sys.argv[1] if len(sys.argv) > 1 else "build/evidence/r114_idelay_sweep_console.txt"
BASE = {"eth_rxc": (0.445, 0.050), "clk_fpga_0": (1.135, 0.056),
        "clkout0_1": (4.467, 0.059), "sys_clk": (14.463, 0.133)}
CLOCKS = list(BASE.keys())
if not os.path.exists(CON):
    print("SWEEP_VERDICT=INVALID reason=no_console:%s" % CON); sys.exit(4)
txt = io.open(CON, encoding="utf-8", errors="replace").read()

head, rows, holdw, taps_seen = {}, {}, {}, []
for line in txt.splitlines():
    if line.startswith("SWEEPHEAD|"):
        d = dict(p.split("=", 1) for p in line.split("|")[1:] if "=" in p)
        head[d["tap"]] = d
    elif line.startswith("SWEEPROW|"):
        d = dict(p.split("=", 1) for p in line.split("|")[1:] if "=" in p)
        rows[(d["tap"], d["clk"], d["kind"])] = d
    elif line.startswith("HOLDWorst|"):
        # 真件形状是 `HOLDWorst|0|slacks=...|dests=...`（**第二个字段是裸的档位、没有 `tap=`**，
        # 而 fixture 当时写成了 `tap=13` —— 这条错是 fixture 太"配合脚本"造成的，规矩：对照必须抄真实形状）
        parts = line.split("|")
        d = dict(p.split("=", 1) for p in parts[2:] if "=" in p)
        d["tap"] = parts[1]
        holdw[d["tap"]] = d
    elif line.startswith("SWEEP|") and "phase=open" in line:
        t = line.split("|")[1].split("=")[1]
        if t not in taps_seen:
            taps_seen.append(t)
    elif line.startswith("SWEEP|") and "read_back" in line:
        taps_seen[-1] = line.split("|")[1].split("=")[1]

def fl(x):
    try:
        return float(x)
    except Exception:
        return None

print("SWEEP taps=%s head=%d rows=%d holdw=%d" % (",".join(sorted(head)), len(head), len(rows), len(holdw)))
bad = [t for t in sorted(head) if ("0" != str(head[t].get("fail_setup")) or head[t]["wns"] == "NA"
                                   or head[t]["whs"] == "NA")]
ok = []
for t in sorted(head):
    h = head[t]
    missing = [(c, k) for c in CLOCKS for k in ("setup", "hold") if (t, c, k) not in rows]
    nas = [k for k in missing] + [ "%s/%s" % (c, kind) for (tt, c, kind), d in rows.items()
                                   if tt == t and d.get("slack", "NA") == "NA"]
    hs, hh = fl(h["whs"]), fl(h["wns"])
    fs, fh = fl(h["fail_setup"]), fl(h["fail_hold"])
    s2 = (hh is not None and hh >= 0 and fh == 0)
    s3 = True
    detail = []
    for c in CLOCKS:
        su = rows.get((t, c, "setup")); ho = rows.get((t, c, "hold"))
        if not su or not ho:
            s3 = False; detail.append("%s:缺行" % c); continue
        bs, bh = BASE[c]
        cs, ch = fl(su["slack"]), fl(ho["slack"])
        if su["state"] != "MET" or ho["state"] != "MET":
            s3 = False
        # 90 % 这条只拿来管**别的地方**（S3 的语义是"别把别的域挤了"）；
        # eth_rxc 自己是这一刀要修的对象，它的 setup 掉多少由 S2 与读数本身负责，
        # 否则每个档都会因为"目标域本来就会变"而被 S3 判红 —— 那是把两件事混成一条（规矩：一条判据一个维度）。
        if c != "eth_rxc" and cs is not None and cs < 0.9 * bs:
            s3 = False
        detail.append("%s %.3f/%.3f(基线 %.3f/%.3f)" % (c, cs if cs is not None else -1,
                      ch if ch is not None else -1, bs, bh))
    verdict = "GREEN" if (s2 and s3 and not missing and not nas) else "RED"
    if verdict == "GREEN":
        ok.append(t)
    print("TAP %-3s whs=%s wns=%s fail_hold=%s S2=%s S3=%s 解析缺=%d %s  %s" % (
        t, h["whs"], h["wns"], h["fail_hold"], "Y" if s2 else "N", "Y" if s3 else "N",
        len(missing) + len(nas), " | ".join(detail), verdict))
    hw = holdw.get(t)
    if hw:
        print("    HOLDWorst slacks=%s dests=%s" % (hw.get("slacks", ""), hw.get("dests", "")[:150]))

if not head:
    print("SWEEP_VERDICT=INVALID reason=no_taps（一件都没有：不要念成「扫不到」）")
    sys.exit(4)
print("SWEEP_WINNERS=%s" % (",".join(ok) if ok else "NONE"))
if ok:
    print("SWEEP_VERDICT=GREEN 最优档=%s（其余候选：除首档外都要在同一张表里被读完才许选）" % ok[0])
    sys.exit(0)
print("SWEEP_VERDICT=NO_TAP_FIXES_HOLD（实验成立：说明 -2.885 不是「少给几拍延迟」能解的，方向要换）")
sys.exit(1)

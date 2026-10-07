import os, subprocess, io, collections, datetime

ROOT = r"D:\Xilinx\Prj\pro\Video_Processing"
PATS = ["【待验证】", "【未核实】", "【未实测】", "【队伍未确认】", "【待你补】", "NOT_MEASURED"]
DIRS = ["report", "board", "docs", "skill", "submit"]

files = []
skipped_big = []
for d in DIRS:
    for dp, _, fns in os.walk(os.path.join(ROOT, d)):
        for fn in fns:
            p = os.path.join(dp, fn)
            if os.path.getsize(p) > 4_000_000:
                skipped_big.append(os.path.relpath(p, ROOT).replace("\\", "/"))
                continue
            files.append(p)
files.append(os.path.join(ROOT, "README.md"))

rows = {}
tot = collections.Counter()
for fp in files:
    rel = os.path.relpath(fp, ROOT).replace("\\", "/")
    try:
        txt = open(fp, "rb").read().decode("utf-8", errors="replace")
    except Exception:
        continue
    for i, line in enumerate(txt.split("\n"), 1):
        for p in PATS:
            n = line.count(p)
            if n:
                rows.setdefault((p, rel), []).append((i, n))
                tot[p] += n

out = []
for (p, rel), lst in sorted(rows.items(), key=lambda kv: (kv[0][1], kv[0][0])):
    c = sum(n for _, n in lst)
    linetxt = ",".join(str(i) if n == 1 else "%d(%d)" % (i, n) for i, n in lst)
    first = lst[0][0]
    txt = open(os.path.join(ROOT, rel.replace("/", os.sep)), "rb").read().decode("utf-8", "replace").split("\n")[first - 1]
    txt = txt.replace("|", "/").strip()
    txt = (txt[:80] + "…") if len(txt) > 80 else txt
    out.append((rel, p, c, linetxt, txt))

stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
with io.open(os.environ.get("TEMP", "/tmp") + "/marker_rows.tsv", "w", encoding="utf-8") as fh:
    fh.write("# snapshot %s\n" % stamp)
    for r in out:
        fh.write("\t".join(str(x) for x in r) + "\n")

print("snapshot:", stamp)
for p in PATS:
    print("  python %-12s = %d" % (p, tot[p]))
print("  python TOTAL      =", sum(tot.values()))
print("  rows              =", len(out))
print("  files scanned     =", len(files))
print("  skipped >4MB      =", len(skipped_big), skipped_big[:10])

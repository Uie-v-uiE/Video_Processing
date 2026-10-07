import io

def fix(path, pairs):
    s = io.open(path, encoding="utf-8", newline="").read()
    for a, b in pairs:
        n = s.count(a)
        if n != 1:
            raise SystemExit("MISS %s :: %s :: %d" % (path, a[:40], n))
        s = s.replace(a, b)
    io.open(path, "w", encoding="utf-8", newline="").write(s)
    print("OK", path, "CR=", s.count("\r\n"), "ff=", s.count("\x0c"))

fix("REVIEW-20261007.md", [
    ("，现 50 行）", "，现 56 行）"),
    ("  两版的计数是 15:1x", "  三版的计数是 15:1x"),
])
fix("BUNDLE-Contents.md", [
    ("（54 行，四个作品名称候选", "（56 行，四个作品名称候选"),
    ("`REVIEW-20261007.md`（245 行", "`REVIEW-20261007.md`（247 行"),
])

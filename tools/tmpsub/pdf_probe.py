import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
from pypdf import PdfReader
p = sys.argv[1]
r = PdfReader(p)
txt = "\n".join((pg.extract_text() or "") for pg in r.pages)
print("PAGES", len(r.pages))
print("CHARS", len(txt))
for tok in sys.argv[2:]:
    print(f"MATCH[{tok}]={txt.count(tok)}")
# 打含 --fps 的行
for line in txt.splitlines():
    if "--fps" in line or "health_read" in line:
        print("LINE:", line.strip()[:180])

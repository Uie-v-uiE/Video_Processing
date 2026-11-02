import os
# 扫 UG471（7-series SelectIO 官方手册）整本，问一句话：本机到底有没有 DVI/HDMI 接收端的窗口数。
# 用法：python build/tmds_source_scan.py。输出命中页号 + 含关键词的行。
# 它是 report/timing/debt_ledger.md §2 里那句"查过的否定"的凭据生成器：正文第 95 页只给
# I/O 标准与属性（Table 1-52、50Ω 上拉、TMDS_33 限 HR bank / VCCO 3.3V），没有任何 setup/hold 或 UI 数。
import pypdfium2 as pdfium
p = os.environ.get("VP_P", "")  # 机器相关路径改由环境变量给（原来是写死的 本机资源目录 Material/6-Xilinx Zynq系列部分官方手册/ug471_7Series_SelectIO.pdf）
if not p:
    raise SystemExit("需要环境变量 VP_P（这台机器上的资源目录，交付包里不该写死）")
doc = pdfium.PdfDocument(p)
print("PAGES=", len(doc))
hits = []
for i in range(len(doc)):
    tp = doc[i].get_textpage()
    t = tp.get_text_range()
    low = t.lower()
    if "tmds" in low and ("setup" in low or "hold" in low or "skew" in low or "ui" in low):
        hits.append((i, t))
print("HIT_PAGES=", [i for i, _ in hits])
for i, t in hits[:6]:
    print("=" * 20, "PAGE", i + 1, "=" * 20)
    lines = [ln.strip() for ln in t.split("\n") if ln.strip()]
    keep = [ln for ln in lines if any(k in ln.lower() for k in ["tmds", "setup", "hold", "skew", "ui ", "unit interval", "data to clock", "clock to data"])]
    for ln in keep[:40]:
        print("  |", ln)

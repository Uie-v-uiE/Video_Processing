import subprocess, re, sys

EV = re.compile(r"^(build/|board/measured|board/evidence|board/compare|report/log|data/metrics\.csv)")
NEEDLES = ["D:/Xilinx", "D:\\Xilinx", "d:/Xilinx", "d:\\Xilinx",
           "D:/Software", "D:\\Software", "d:/Software", "d:\\Software"]

files = [f for f in subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split("\n")
         if f and f.split("/")[0] in ("vivado_system", "vitis", "src", "board", "build", "report", "sim", "skills", "data")]
txt_bad, bin_bad, ev_bad = [], 0, 0
for f in files:
    try:
        b = open(f, "rb").read()
    except Exception:
        continue
    if not any(n.encode() in b for n in NEEDLES):
        continue
    if b"\x00" in b:
        bin_bad += 1
    elif EV.match(f):
        ev_bad += 1
    else:
        txt_bad.append(f)
print("仍含本机盘符：二进制 %d 份（不改字节）；证据/留档 %d 份（不改正文）；非证据层文本 %d 份" % (bin_bad, ev_bad, len(txt_bad)))
for f in txt_bad[:15]:
    print("   ", f)

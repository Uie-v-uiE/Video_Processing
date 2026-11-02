# -*- coding: utf-8 -*-
from pathlib import Path

root = Path(r"D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline\rtl")
for f in root.rglob("*.v"):
    data = f.read_bytes()
    # strip BOM
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    text = data.decode("utf-8", errors="replace")
    lines = text.splitlines()
    # remove bad timescale lines
    out = []
    for i, line in enumerate(lines):
        s = line.strip().lstrip("﻿")
        if s.startswith('"timescale') or s.startswith("`timescale"):
            continue
        out.append(line)
    body = "\n".join(out)
    if not body.endswith("\n"):
        body += "\n"
    f.write_bytes(b"`timescale 1ns/1ps\n" + body.encode("utf-8"))
    print("fixed", f.name)
print("done")

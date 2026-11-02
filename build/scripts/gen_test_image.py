#!/usr/bin/env python3
"""Generate assets/test_pattern.png for UDP sender."""
from pathlib import Path
import numpy as np

W, H = 640, 360
out = Path(__file__).resolve().parents[1] / "assets" / "test_pattern.png"

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("pip install pillow")

img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
bars = [
    (255, 255, 255),
    (255, 255, 0),
    (0, 255, 255),
    (0, 255, 0),
    (255, 0, 255),
    (255, 0, 0),
    (0, 0, 255),
    (0, 0, 0),
]
bw = W // len(bars)
for i, c in enumerate(bars):
    d.rectangle([i * bw, 0, (i + 1) * bw - 1, H], fill=c)
# circle
d.ellipse([W // 2 - 80, H // 2 - 80, W // 2 + 80, H // 2 + 80], outline=(0, 0, 0), width=3)
d.line([0, 0, W, H], fill=(32, 32, 32), width=2)
out.parent.mkdir(parents=True, exist_ok=True)
img.save(out)
print("wrote", out)

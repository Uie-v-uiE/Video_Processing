# -*- coding: utf-8 -*-
"""Golden model: rotation + effects matching RTL conventions.

Coordinate transform (matches rotate_mapper + reference matlab):
  xp = x - W/2
  yp = H/2 - y
  xr = (cos*xp + sin*yp) >> 8
  yr = (-sin*xp + cos*yp) >> 8
  sx = xr + W/2
  sy = H/2 - yr
where cos/sin = round(cos(angle_deg)*256), round(sin(angle_deg)*256)
"""
from __future__ import annotations
import math
from pathlib import Path
import numpy as np

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("pip install pillow")

W, H = 640, 360
OUT = Path(__file__).resolve().parents[1] / "sim_out"
OUT.mkdir(parents=True, exist_ok=True)


def sincos_q8(angle_deg: int):
    a = math.radians(angle_deg)
    return int(round(math.sin(a) * 256)), int(round(math.cos(a) * 256))


def map_xy(x: int, y: int, angle: int):
    sin_v, cos_v = sincos_q8(angle)
    xp = x - (W // 2)
    yp = (H // 2) - y
    xr = (cos_v * xp + sin_v * yp) >> 8
    yr = ((-sin_v) * xp + cos_v * yp) >> 8
    sx = xr + (W // 2)
    sy = (H // 2) - yr
    oob = not (0 <= sx < W and 0 <= sy < H)
    return sx, sy, oob


def rotate_image(img: np.ndarray, angle: int) -> np.ndarray:
    out = np.zeros_like(img)
    for y in range(H):
        for x in range(W):
            sx, sy, oob = map_xy(x, y, angle)
            if not oob:
                out[y, x] = img[sy, sx]
    return out


def gray(img: np.ndarray) -> np.ndarray:
    r = img[:, :, 0].astype(np.int32)
    g = img[:, :, 1].astype(np.int32)
    b = img[:, :, 2].astype(np.int32)
    y = (r * 77 + g * 150 + b * 29) >> 8
    return np.stack([y, y, y], axis=-1).astype(np.uint8)


def binary(img: np.ndarray, thr: int = 80) -> np.ndarray:
    y = gray(img)[:, :, 0]
    m = (y >= thr).astype(np.uint8) * 255
    return np.stack([m, m, m], axis=-1)


def invert(img: np.ndarray) -> np.ndarray:
    return (255 - img).astype(np.uint8)


def box_blur(img: np.ndarray) -> np.ndarray:
    """3x3 box blur matching RTL *57>>9 on RGB565-like 5/6/5 — use 8b approx."""
    p = np.pad(img, ((1, 1), (1, 1), (0, 0)), mode="edge")
    out = np.zeros_like(img)
    for c in range(3):
        s = (
            p[0:-2, 0:-2, c].astype(np.int32)
            + p[0:-2, 1:-1, c]
            + p[0:-2, 2:, c]
            + p[1:-1, 0:-2, c]
            + p[1:-1, 1:-1, c]
            + p[1:-1, 2:, c]
            + p[2:, 0:-2, c]
            + p[2:, 1:-1, c]
            + p[2:, 2:, c]
        )
        out[:, :, c] = ((s * 57) >> 9).astype(np.uint8)
    return out


def sobel(img: np.ndarray) -> np.ndarray:
    g = gray(img)[:, :, 0].astype(np.int32)
    p = np.pad(g, 1, mode="edge")
    gx = -p[0:-2, 0:-2] - 2 * p[1:-1, 0:-2] - p[2:, 0:-2] + p[0:-2, 2:] + 2 * p[1:-1, 2:] + p[2:, 2:]
    gy = -p[0:-2, 0:-2] - 2 * p[0:-2, 1:-1] - p[0:-2, 2:] + p[2:, 0:-2] + 2 * p[2:, 1:-1] + p[2:, 2:]
    mag = np.abs(gx) + np.abs(gy)
    mag = np.clip(mag, 0, 255).astype(np.uint8)
    return np.stack([mag, mag, mag], axis=-1)


def pipeline(img, en="11111", thr=80):
    out = img.copy()
    if en[0] == "1":
        out = gray(out)
    if en[1] == "1":
        out = binary(out, thr)
    if en[2] == "1":
        out = box_blur(out)
    if en[3] == "1":
        out = sobel(out)
    if en[4] == "1":
        out = invert(out)
    return out


def make_source() -> np.ndarray:
    """Synthetic source with clear geometry for rotation check."""
    img = Image.new("RGB", (W, H), (20, 20, 40))
    d = ImageDraw.Draw(img)
    # 8 color bars
    colors = [
        (255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
        (255, 0, 255), (255, 0, 0), (0, 0, 255), (32, 32, 32),
    ]
    bw = W // 8
    for i, c in enumerate(colors):
        d.rectangle([i * bw, 0, (i + 1) * bw - 1, H // 2], fill=c)
    # L-shape in lower half for orientation
    d.rectangle([80, 200, 140, 320], fill=(255, 128, 0))
    d.rectangle([140, 280, 320, 320], fill=(255, 128, 0))
    d.ellipse([400, 180, 520, 300], outline=(0, 255, 128), width=4)
    d.line([0, 0, W - 1, H - 1], fill=(80, 80, 80), width=2)
    return np.asarray(img)


def write_rgb565_mem(img: np.ndarray, path: Path):
    r = (img[:, :, 0] >> 3).astype(np.uint16)
    g = (img[:, :, 1] >> 2).astype(np.uint16)
    b = (img[:, :, 2] >> 3).astype(np.uint16)
    pix = (r << 11) | (g << 5) | b
    lines = [f"{int(v):04x}" for v in pix.flatten()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    src = make_source()
    Image.fromarray(src).save(OUT / "src.png")
    write_rgb565_mem(src, OUT / "frame_640x360.mem")

    for ang in (0, 30, 45, 90, 180, 270):
        rot = rotate_image(src, ang)
        Image.fromarray(rot).save(OUT / f"rot_{ang:03d}.png")
        print(f"rot {ang:3d} ok")

    # dual pane preview (angle=0, all effects)
    proc = pipeline(src, "11111", 80)
    Image.fromarray(proc).save(OUT / "proc_all.png")
    Image.fromarray(pipeline(src, "00111", 80)).save(OUT / "proc_00111.png")
    Image.fromarray(pipeline(src, "10000", 80)).save(OUT / "proc_10000.png")

    # dual-pane 1280x360 (without 2x scale for quick view)
    dual = np.zeros((H, W * 2, 3), dtype=np.uint8)
    dual[:, :W] = src
    dual[:, W:] = proc
    Image.fromarray(dual).save(OUT / "dual_preview.png")
    print("wrote", OUT)
    print("mem lines", W * H)


if __name__ == "__main__":
    main()

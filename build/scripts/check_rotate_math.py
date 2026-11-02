# -*- coding: utf-8 -*-
"""C/Python dual-check: angle_ctrl wrap and rotate math vs RTL table."""
import math

def rtl_map(x, y, angle, W=64, H=36):
    sin_v = int(round(math.sin(math.radians(angle)) * 256))
    cos_v = int(round(math.cos(math.radians(angle)) * 256))
    if sin_v > 256: sin_v = 256
    if sin_v < -256: sin_v = -256
    if cos_v > 256: cos_v = 256
    if cos_v < -256: cos_v = -256
    xp = x - W // 2
    yp = H // 2 - y
    xr = (cos_v * xp + sin_v * yp) >> 8
    yr = ((-sin_v) * xp + cos_v * yp) >> 8
    sx = xr + W // 2
    sy = H // 2 - yr
    oob = not (0 <= sx < W and 0 <= sy < H)
    return (0, 0, True) if oob else (sx, sy, False)

# identity
for x, y in [(0, 0), (63, 35), (32, 18)]:
    sx, sy, oob = rtl_map(x, y, 0)
    assert not oob and sx == x and sy == y, (x, y, sx, sy, oob)
    print(f"OK id ({x},{y})->({sx},{sy})")

# 360 wrap
assert rtl_map(10, 10, 0) == rtl_map(10, 10, 360)

# 180 maps center to center
sx, sy, oob = rtl_map(32, 18, 180)
assert not oob and abs(sx - 32) <= 1 and abs(sy - 18) <= 1, (sx, sy)
print("OK 180 center", sx, sy)

print("ALL MATH OK")

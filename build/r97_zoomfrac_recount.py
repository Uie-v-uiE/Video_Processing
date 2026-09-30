# build/wip_zoomfrac_recount.py —— 独立复算 #189：旋转支 Y 的"有没有小数"判据看错位宽，到底影响多少像素
# 用 RTL 的表达式逐位复刻（Verilog 语义：>>> 是算术右移 = Python 的 >>；rot_ys[15:8] = (v>>8)&0xFF），
# 与"真值"（floor/frac 必须自洽于 Y_disp = C - (yr_pix + r/65536)）对账。
W, H = 512, 300
CX, CY = W // 2, H // 2


def s24(v):  # 24 位有符号截断（xr_m/yr_m 是 reg signed [23:0]）
    v &= (1 << 24) - 1
    return v - (1 << 24) if v >= (1 << 23) else v


def s32(v):  # 32 位有符号截断（rot_xs/rot_ys 是 wire signed [31:0]）
    v &= (1 << 32) - 1
    return v - (1 << 32) if v >= (1 << 31) else v


def recount(angle, sin_v, cos_v, inv):
    row_err = sub_ls = oob_flip = tot = 0
    for y in range(H):
        for x in range(W):
            xp = x - CX
            yp = CY - y                      # yp_math = H/2 - y
            yr_m = s24(-xp * sin_v + yp * cos_v)
            rot_ys = s32(yr_m * inv)
            yr_pix = rot_ys >> 16            # 算术右移 = 朝 -inf 取整
            r = rot_ys & 0xFFFF              # 真正的 16 位小数（φ = r/65536）
            f8 = (rot_ys >> 8) & 0xFF        # RTL 看的那一字节
            rtl_sy = CY - yr_pix - (1 if f8 != 0 else 0)
            true_sy = CY - yr_pix - (1 if r != 0 else 0)
            ideal_f8 = 256 - ((r + 255) // 256) if r != 0 else 0
            rtl_fx = (rot_ys >> 8) & 0xFF
            tot += 1
            in_r = 0 <= rtl_sy < H
            in_t = 0 <= true_sy < H
            if in_r != in_t:
                oob_flip += 1
            if rtl_sy != true_sy:
                row_err += 1                 # 取到相邻另一行
            elif (r != 0 and f8 == 0):
                sub_ls += 1
    return tot, row_err, oob_flip, ideal_f8


for angle, s, c, invs in [(30, 128, 222, [259, 472, 509]),
                          (7, 31, 254, [259, 509]),
                          (58, 217, 136, [509, 259]),
                          (0, 0, 256, [256, 259])]:
    for inv in invs:
        tot, err, oob, ideal = recount(angle, s, c, inv)
        print("angle=%3d sin=%3d cos=%3d inv=%3d : 像素=%6d 错行=%5d oob翻转=%3d  (r∈[1,255] 时 ideal_frac=%d)"
              % (angle, s, c, inv, tot, err, oob, ideal))

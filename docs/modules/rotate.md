# 旋转模块（0–359°）

## 组成
| 文件 | 作用 |
|------|------|
| `angle_ctrl.v` | KEY1 +1°，KEY2 -1°，0..359 环绕 |
| `sin_rom.v` / `cos_rom.v` | 360 项 Q8 查表，`round(sin/cos(θ)*256)` |
| `rotate_mapper.v` | 画布坐标 → 源坐标 + OOB |

## 端口（rotate_mapper）
| 方向 | 名 | 说明 |
|------|----|------|
| in | clk, rst_n | |
| in | angle[8:0] | 0..359 |
| in | enable | 0 时恒等映射 |
| in | x_in, y_in[11:0] | 画布坐标 |
| out | x_out, y_out[11:0] | 源坐标（OOB 时 0） |
| out | oob | 越界 |

## 算法（与 Image_Rotate 参考 / matlab roation.m 一致）
```
xp = x - W/2
yp = H/2 - y          // 图像 Y 翻转到数学坐标
xr = (cos*xp + sin*yp) >>> 8
yr = (-sin*xp + cos*yp) >>> 8
sx = xr + W/2
sy = H/2 - yr         // 再翻回图像坐标
oob = sx∉[0,W) || sy∉[0,H)
```

## 自检
- Python：`scripts/check_rotate_math.py`（恒等、180° 中心）  
- xsim：`sim/tb_rotate_mapper.v` PASS  
- 图片：`scripts/golden_model.py` 生成 `sim_out/rot_*.png`

## 上板操作
- KEY1：角度 +1（例如 0→1→…→359→0）  
- KEY2：角度 -1  
- 左右两屏同时旋转；旋转时右屏仅剩逐像素效果  

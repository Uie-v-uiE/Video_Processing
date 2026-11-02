# 效果流水线

## 级联顺序（en[0] → en[4]）
| bit | 模块 | 功能 |
|-----|------|------|
| 0 | `proc_gray` | 0.299R+0.587G+0.114B（77/150/29>>8） |
| 1 | `proc_binary` | 亮度 ≥ threshold → 白，否则黑 |
| 2 | `proc_box_blur` | 3×3 均值，行缓存，`*57>>9` |
| 3 | `proc_sobel` | 3×3 Gx/Gy，L1 范数 |
| 4 | `proc_invert` | RGB565 取反 |

## 使能语义
- `effect_en[i]=1` → 模块工作；`=0` → bypass 直通  
- `rotate_active=1` → blur/sobel 强制 bypass（邻域在非顺序取样下无效）

## 串口映射
```
字符串: c0 c1 c2 c3 c4
        │  │  │  │  └ invert
        │  │  │  └──── sobel
        │  │  └─────── blur
        │  └────────── binary
        └───────────── gray
"00111" → 5'b11100 → blur+sobel+invert
```

## 公共接口
每个模块：
```
clk, rst_n, bypass, de_in, din[15:0] → de_out, dout[15:0]
```
blur/sobel 额外需要 `x_in,y_in` 与 vs。

## 黄金参考
`scripts/golden_model.py` 的 `pipeline(img, en)` 与 RTL 同序。

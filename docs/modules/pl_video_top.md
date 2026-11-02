# pl_video_top — PL 视频顶层

## 职责
把「帧源 → 旋转取源 → 效果流水线 → 左右分屏 → HDMI」串成一条实时通路，并接收 PS 的 effect_en/threshold/src_sel。

## 端口
| 方向 | 名 | 说明 |
|------|----|------|
| in | sys_clk, sys_rst_n | 50 MHz |
| in | axi_clk, axi_rst_n | 100 MHz PS FCLK |
| in | effect_en[4:0] | 异步，内部同步 |
| in | threshold[7:0] | 二值阈值 |
| in | src_sel | 0=彩条写 BRAM，1=AXI 从 DDR 灌帧 |
| in | key1_n, key2_n | 低有效，角度 ±1° |
| out | led[1:0] | 心跳 / 效果指示 |
| out | tmds_* | HDMI 差分 |
| AXI | m_axi_* | 只读 master，64-bit，burst=整行 |
| out | status[31:0] | {locked, rot_active, angle[8:0], en[4:0], src_sel} |

## 内部结构
1. `clk_gen` → 75M / 375M  
2. `key_debounce` + `angle_ctrl` → angle 0..359  
3. `video_timing_720p`  
4. `axi_frame_writer` 或 `color_bar` → `frame_buffer`  
5. `rotate_mapper` 把画布 (cx,cy) 映到 (sx,sy)  
6. `proc_pipeline` 在左窗顺序处理  
7. `split_display` + `rgb2dvi`

## 数据流
```
frame_start (src_sel=1)
  → axi_frame_writer 逐行 burst 读 DDR
  → 写入 frame_buffer[addr=y*640+x]

每个显示像素 (x,y):
  cx = x<640 ? x : x-640
  cy = y>>1
  (sx,sy,oob) = rotate_mapper(cx,cy,angle)
  src = oob ? 0 : frame_buffer[sy*640+sx]
  if x<640: 输出 src
  else:     输出 proc_line[cx]   // 左窗期间流水线写入
```

## 注意
- 角度≠0 时 `rotate_active=1`，blur/sobel 旁路  
- 左窗 640 拍内流水线约 6 级延迟，右窗边缘可能有极少量像素滞后（可忽略）  
- 彩条模式每拍连续写 BRAM，静态图案可接受  

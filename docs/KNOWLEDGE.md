# 关键知识点（吃透本工程）

按「必须搞懂」排序，每条对应可打开的源文件。

---

## A. 为何旋转时关掉 blur / sobel

`proc_pipeline.v`：

```verilog
wire by2 = ~effect_en[2] | rotate_active;  // blur
wire by3 = ~effect_en[3] | rotate_active;  // sobel
```

**blur / sobel 是 3×3 窗口滤波**，需要源图中「扫描顺序上的邻域」。  
逆映射旋转后，屏幕上相邻像素对应的源坐标可能不相邻，窗口取到的是无关像素，结果错误。

**gray / binary / invert 是点运算**，只依赖当前像素，与旋转兼容。

| 角度 | gray | binary | blur | sobel | invert |
|------|------|--------|------|-------|--------|
| 0° | ✓ | ✓ | ✓ | ✓ | ✓ |
| 1–359° | ✓ | ✓ | ✗ 自动关 | ✗ 自动关 | ✓ |

角度回 0 后自动恢复，无需重发命令。若要「旋转+窗滤」，需先旋转到帧缓再滤波（多一帧延迟与带宽），本工程未做。

---

## B. 双窗流水线对齐

- 效果链固定多级延迟；rotate_mapper 3 拍；BRAM 读 1 拍  
- de/x/y/left 等 sideband 统一 **延迟 4 拍**  
- angle=0 旁路 mapper 时，对 cx/cy 也做 3 拍延迟，避免 2 拍错位  

对不齐的症状：右窗错位、分隔线附近花屏、效果与原图不同步。

---

## C. AXI HP0 拆包

64-bit beat = 4×RGB565（每像素 2 字节，小端）：

```
rdata[15:0]   → 像素 0
rdata[31:16]  → 像素 1
rdata[47:32]  → 像素 2
rdata[63:48]  → 像素 3
```

**每个 beat 锁存后拆 4 拍写入 BRAM**，不能每个 rvalid 只写 1 个像素。  
行地址必须 **32 位**：`row * 512 + xw`；行字节 `row * 1024`。12 位左移会溢出回绕。

诊断：`FILL` 四色块 + 细线；大色块看不出 4 像素组内错位。

---

## D. UDP 包为何带 offset

包格式：`[u32 LE offset][RGB565 data]`

UDP 不保证顺序。无 offset 时按到达顺序 memcpy，乱序即整帧错位。  
有 offset 则写到 `DDR_BASE+offset`，乱序也能拼对。

收满 307200 字节后 `Xil_DCacheFlushRange`，再 `src_sel=1`。

---

## E. 为何源是 512×300

| 约束 | 数值 |
|------|------|
| 帧大小 | 512×300×2 = 307200 B |
| BRAM | ~2.34 Mbit（7020 约 4.9 Mbit） |
| UDP @30fps | ~74 Mbps（千兆足够） |
| AXI 读 @60Hz | ~18 MB/s（HP0 64b@50M 峰值 400 MB/s） |

再提分辨率主要卡 **片上 BRAM**，不是网口。720p 全帧放不进 7020 BRAM，需外缓存或降色深。

---

## F. 为何不用 EMIO GPIO

本板 PS EMIO bank 读回恒 0，控制无效。改用 GP0 **AXI GPIO @ 0x41200000**。  
控制字：`en[4:0] | thr[7:8] | src[16]`。

---

## G. 0–359° 逆映射

```
xp = x - W/2;  yp = H/2 - y
xr = ( cos*xp + sin*yp) >> 8
yr = (-sin*xp + cos*yp) >> 8
sx = xr + W/2;  sy = H/2 - yr
```

- Q8：256=1.0；**cos(0) 必须是 256，不能 255**  
- OOB 填黑；反色不能把 OOB 变白  
- KEY 边沿触发 ±1°，无连发  

---

## H. 双窗数据流

效果只对 **左半屏** `de && left` 跑一遍，写入 `line_cache`。  
右半屏从同一 `line_cache` 按 cx 读出，保证左右同源可对比。  
中间蓝线 x=511,512。

---

## I. Cache 一致性

PS 写 DDR 走 cache；PL HP0 读物理 DDR。  
必须在整帧写完后 `Xil_DCacheFlushRange`，否则 PL 读到旧数据或半帧。

---

## J. 串口与第三方助手

固件在 `\r`/`\n` 处解析。助手需 **CR+LF**、无流控、115200 8N1。  
Vitis 终端默认带换行，故好使。

---

## K. FFmpeg

必须用带 **H.264 decoder** 的完整版。精简 Ghost 版只有 mjpeg/vp8/vp9，解不了 mp4。  
缩放建议 `lanczos`；2376×1080→512×300 本身就会糊，属分辨率限制。

---

## L. 下载流程

Vitis **Run** = FSBL + ps7_init + bit + ELF。  
仅 xsdb `dow` 而不跑 `ps7_init`，UART 可能无输出。

脚本下载须含：

```
loadhw -hw system.xsa
source ps7_init.tcl
ps7_init / ps7_post_config
rst -processor / dow / con
```

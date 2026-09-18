# 模块详解（第三版）

对应路径均在 `src/rtl/` 下。

---

## 1. top/system_top.v

**职责：** PS Block Design + PL 视频 + PL 以太网顶层连线。

**要点：**
- `design_1_wrapper`：PS7 + AXI GPIO + HP0
- `eth_udp_video_top`：协议栈
- `pl_video_top`：显示/效果/缩放
- `.zoom_en(1'b1)`：右屏无极缩放上电常开
- `clk_gen`：另供 200 MHz 给 IDELAYCTRL

---

## 2. top/pl_video_top.v（显示主通路）

**职责：** 双窗扫描、坐标映射、FB 时分读、右窗效果、OSD、HDMI。

| 子块 | 说明 |
|------|------|
| `zoom_ctrl` / `zoom_mapper` | 右屏自动缩放；INV_LO=256，INV_HI=512，STEP=2 |
| `rotate_mapper` | 左窗旋转；右窗缩放后可再旋转 |
| FB 读地址 | `left_d[2]` 选择 rotate 或 zoom 坐标；`rd_addr` 移位加法后打拍 |
| `proc_pipeline` | 仅在右窗 `de` 上运行；输入为缩放后像素 |
| `split_display` | 左右独立 oob；中间蓝线 |
| `osd_overlay` | 状态叠加 |
| CDC | `ze*`/`ef*`/`fs*` 标 `ASYNC_REG` |

**延迟：** mapper3 + addr1 + BRAM1 + proc7，sideband 与此对齐。

---

## 3. eth/ — 协议栈

### 3.1 rgmii_rx / rgmii_tx
BUFIO + IDDR（SAME_EDGE_PIPELINED）/ ODDR；IDELAY_VALUE=15。

### 3.2 arp / icmp / udp
- ARP：who-has → 板卡 MAC `00:11:22:33:44:55`
- ICMP：echo reply；载荷 **自写 `sync_fifo`**；tx 启动延迟 20 拍
- UDP：解析后交 `frame_reasm`

### 3.3 frame_reasm
协议 `[u32 LE offset][RGB565]`；`wr_addr=offset/2`；满 307200 B 帧完成；坏帧计数不重传。

### 3.4 自写 FIFO

**sync_fifo.v（同钟）**
- 深度 `2^ADDR_W`，读出寄存一拍
- `empty`/`full` 用指针最高位比较
- **存储阵列无复位** + `ram_style="block"` → 推断 BRAM  
  （避免异步复位导致落到寄存器堆，拖垮 eth_rxc@125M 时序）

**dc_fifo.v（跨钟）**
- 写 `wr_clk` / 读 `rd_clk` 独立
- 指针转 Gray，两级同步到对侧
- 打包 36-bit：`{1'b0, addr[18:0], data[15:0]}`，读 `dout[34:16]` / `[15:0]`
- 写口无复位，便于 BRAM

### 3.5 axi_frame_writer / axi_frame_saver
PS `FILL` 或 DDR 诊断路径；ETH 主路径为 BRAM 直写。

---

## 4. video/

| 模块 | 说明 |
|------|------|
| video_timing_1024x600 | H=1344 V=625 @50M |
| frame_buffer | 512×300×16b 双口 BRAM |
| split_display | 左右像素选择 + oob_l/oob_r + 蓝线 |
| osd_overlay | 三行状态；3× 放大；空格空白字模 |
| color_bar | 彩条源；右路用 zoom 后坐标采样 |
| line_cache | 历史模块，**top 中已不再例化** |

---

## 5. process/

### 5.1 proc_pipeline
```
gray → binary → box_blur → sobel → invert
```
每级 `bypass`；固定约 7 拍延迟。窗滤行缓地址用**右窗屏幕坐标**（目标域）。

### 5.2 rotate/*
`rotate_mapper` 逆映射 + sin/cos ROM；`angle_ctrl` 按键 ±1°。

### 5.3 zoom/*

**zoom_ctrl.v**
- 输出 `inv_scale[9:0]` Q8
- 默认 INV_LO=256（1.0× 最大），INV_HI=512（0.5×），STEP=2
- `enable=0` 时锁定 256
- `dir`：0 向缩小，1 回原始

**zoom_mapper.v**
```
// 无旋转
sx = W/2 + ((x-W/2)*inv)>>8
sy = H/2 + ((y-H/2)*inv)>>8
// 有旋转：先 Q8 旋转再 *inv，inv=256 时与 rotate_mapper 一致
```
- `inv` 用 **10-bit 有符号**（避免 256 被当成 −256）
- 3 级流水；OOB 黑；`frac_x/frac_y` 预留双线性

---

## 6. 时钟与复位

- `clk_gen`：MMCM 50 / 250 / 200
- `eth_rst_n`：sys_clk 计数约 168 ms
- ETH 逻辑：`eth_rst_n & mmcm_locked`

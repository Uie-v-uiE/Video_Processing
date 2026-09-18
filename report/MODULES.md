# 模块详解

## 1. rtl/top/system_top.v

**职责：** 顶层连接 PS BD、PL 视频、PL 以太网。

**端口：**
- DDR / FIXED_IO：PS 外设
- sys_clk / key / led / HDMI TMDS
- eth_rxc / eth_rx_ctl / eth_rxd[3:0]：PHY2 RGMII 收
- eth_tx_* / eth_mdc / eth_mdio / eth_rst_n：PHY2 发与管理

**内部：**
- `design_1_wrapper`：PS7 + AXI GPIO + HP0
- `clk_gen`：生成 200 MHz 给 IDELAYCTRL
- `eth_udp_video_top`：完整协议栈
- `pl_video_top`：显示流水线

---

## 2. rtl/eth/ — 以太网协议栈

### 2.1 rgmii_rx.v / rgmii_tx.v

- RX：`BUFG`（逻辑钟）+ `BUFIO`（IO 钟）+ `IDELAYE2` + `IDDR`（SAME_EDGE_PIPELINED）
- TX：`ODDR` 双沿输出
- IDELAY_VALUE=15（约 1.2 ns，78 ps/tap）

### 2.2 arp_rx.v / arp_tx.v

- 解析 who-has，目标 IP = BOARD_IP 时置 `arp_rx_done`
- `eth_ctrl` 在非忙时发起 `arp_tx` 应答
- 应答含 FCS（`crc32_d8`）

### 2.3 icmp_rx.v / icmp_tx.v

- 解析 echo request (type 8)，导出 `src_mac/src_ip`
- 回显 reply (type 0)，载荷经 `sync_fifo` 回传
- TX 启动延迟 20 拍，确保 FIFO 写完

### 2.4 udp_rx.v / udp_tx.v

- 解析 Eth+IPv4+UDP，输出 `rec_en/rec_data/rec_pkt_done`
- 视频路径只用 RX；TX 保留（可回传状态）

### 2.5 frame_reasm.v

**协议：** `[u32 LE offset][RGB565 data]`

```
收到 4 字节 offset
之后每 2 字节组装一个像素
wr_addr = offset/2
wr_data = {high, low}
```

- 累计载荷字节，达到 307200 时 `frame_done`
- 坏包计入 `stat_bad`，不重传，下一帧自动恢复

### 2.6 dc_fifo.v / sync_fifo.v

- `sync_fifo`：同钟，gray 指针，分布式/块 RAM
- `dc_fifo`：跨钟，gray 同步
- **打包：** `{1'b0, addr[18:0], data[15:0]}` → 读 `dout[34:16]`/`dout[15:0]`

### 2.7 axi_frame_saver.v

- 将像素经 HP0 写 DDR（1 像素/拍，2 字节 strobe）
- 可选路径；显示主路径为 BRAM 直写

---

## 3. rtl/video/

### 3.1 video_timing_1024x600.v

1024×600@50MHz，H=1344，V=625。

### 3.2 frame_buffer.v

512×300×16b 双口 BRAM，`addr = y*W+x`。

### 3.3 osd_overlay.v

- 3× 字号，玫红色 `FF0090`
- 三行：`FPS=xx`、`ANG=xxx`、`EN=xxxxx`
- 空格用空白字模（索引 31），避免显示成「0」

### 3.4 split_display.v

左原图 / 右处理结果，中间蓝线，OOB 黑。

---

## 4. rtl/process/

### 4.1 proc_pipeline.v

```
gray → binary → box_blur → sobel → invert
```

各模块 `bypass` 直通。窗滤不再因旋转强制关闭。

### 4.2 rotate_mapper.v

逆映射 + Q8 sin/cos ROM，3 级流水。

### 4.3 proc_box_blur / proc_sobel

行缓 3×3，地址用**屏幕坐标**（目标域）。

---

## 5. 时钟与复位

- `clk_gen`：MMCM 50/250/200
- PHY 复位：`eth_rst_n` 由 `sys_clk` 计数约 168 ms
- ETH 逻辑复位：`eth_rst_n & mmcm_locked`

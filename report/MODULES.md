# 模块详解（第三版 + 第四版 V6 数据通路见 §7）

对应路径均在 `src/rtl/` 下。
**时效声明（2026-09-23 加）**：本文按"模块职责"写，不随版本作废；但里面提到的
`axi_frame_saver` / `axi_frame_writer` / `frame_buffer` 这一组**已被 V6/V7 的
`axi_frame_saver64` + `frame_buffer_w64` + `frame_commit_lock` 取代**（保留在树里只为可追溯），
当前模块清单与文件地图看 `report/ARCHITECTURE.md`（本地学习版另有
`study/02_架构/03_模块与文件地图.md`，随仓库不发布）。

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

### 3.2 arp / icmp / udp（V7.9.6 起，收侧换成自研那一对）
- ARP：who-has → 板卡 MAC `00:11:22:33:44:55`；ICMP：echo reply；载荷 **自写 `sync_fifo`**；tx 启动延迟 20 拍
  —— 这两个仍是厂商实现。
- **发**：`udp_tx` + `crc32_d8`（IP/UDP/Ethernet 头与 FCS 都在 `udp_tx` 里）。厂商的 `udp` 包装层
  已不再被任何顶层例化 —— 它会把 `udp_rx` 一起拖进来。
- **收（自研一对）**：
  - `gmii_rx_mac`：去前导码/SFD，按字节数与**自己算的 FCS-32** 判好坏。为什么要自算：
    RGMII 只有 4 数据 + 1 控制，`rgmii_rx.v` 把 RX_CTL 只当 `gmii_rx_dv` 用，
    **两块板上都没有 RX_ER 这根线**（`gmii_rx_er` 恒接 0）—— 不自算就一个错误源都没有。
    判据常数 `0xC704DD7B` = 标准余数 `0xDEBB20E3` 经 `crc32_d8` 的位反序，Node 独立核过。
  - `udp_rx_parser`：按下标解 IPv4/UDP，带**目的端口过滤**（`UDP_PORT` 参数），
    吐 `p_data/p_valid/p_sof/p_eof/p_good` + 三个统计脉冲 `stat_drop_bad/stat_drop_filt/stat_udp_ok`。
  - 判据：`sim/tb_v795_rx_fcs.v`（FCS 那一级）+ `sim/tb_v795_rx_chain.v`（成对，C1–C5）。
- `frame_reasm.p_good` 从此接**真值**（原来是 `1'b1`）⇒ `stat_bad` 活了：Z7 的 health 读回与
  KU5P 遥测里的 `bad` 字段都不再是构造性为 0 的死数字。
- **还接了但没人消费的口（别当 bug 也别当特性）**：`eth_ctrl` 的 `rec_en/rec_data`（及其内部
  `fifo_tx_*`）在两块板上都没有下游，V7.9.6 只把它的 `udp_rec_data/udp_rec_en` 改喂 parser 的
  `p_data/p_valid`（宁可传真字节，不硬接 0）；parser 那三个统计脉冲同样还没接到任何可读寄存器上 ——
  **"被端口过滤掉的包数"要不要变成可读数字是个独立小决定**，登记在 `report/ISSUES.md` #38 末尾。

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

---

## 7. 第四版 V6.x 数据通路（UDP → DDR 乒乓 → V-blank 原子拷贝）

第四版把「边收边写显示 BRAM」改成「入包写 DDR 乒乓 bank → 提交锁在 V-blank 窗口把整帧
拷进显示 BRAM」。第三版的 `axi_frame_saver` / `axi_frame_writer` / `frame_buffer`
仍在树内（`sim/tb_v5_saver.v` 等历史 TB 使用），但已不在综合路径上。

| 模块 | 位置 | 职责 | 关键点 |
|------|------|------|--------|
| `eth_udp_video_top` | `src/rtl/eth/` | RGMII→ARP/ICMP/UDP→reasm→CDC→打包器 的容器 | V6.1 起 CDC 读侧每拍一条；V6.2 起 `dc_fifo ADDR_W=13` + `sv_full` 反压 |
| `frame_reasm` | `src/rtl/eth/` | offset 拼帧 + 提交门限 | `rows_hit==IMG_H` **且** 累计 `FRAME_BYTES`；`stat_bad` 每帧一次 |
| `axi_frame_saver64` | `src/rtl/eth/` | 16bit→64bit 打包 + AXI3 写 | **V6.3：AW/W 同拍挂出、`OST=8` 在途、B 只回收计数**；**V6.4：`WSTRB` 按 16bit lane 生成**（部分字不再互相覆盖）；`AWLEN=0`；`FW=9` 不可加深（DRC UTLZ-1） |
| `frame_buffer_w64` | `src/rtl/video/` | 64bit 宽显示帧 BRAM，双窗时分读 | — |
| `axi_frame_writer_gated` | `src/rtl/axi/` | 提交后整帧 DDR→显示 BRAM，只在 `allow_wr` 窗口内发 AR/写 BRAM | `MAX_OUT=4`、`BEATS=16`、`SK=6` |
| `frame_commit_lock` | `src/rtl/video/` | 新帧就绪锁到 V-blank 上升沿才启动拷贝；拷贝未完不换 bank | `allow_rise` 边沿触发 |
| `pl_video_top` | `src/rtl/top/` | 显示主通路 + 拷贝调度 + 观测位 | `disp_quiet`（V-blank + 尾部保护）、`copy_overrun`→`led[0]` |

### 为什么根因在 `axi_frame_saver64` 的写通道
`AWLEN=0` 的单拍写若走完 `AW→W→B` 才发下一笔，在途深度恒为 1 ⇒ 吞吐 = 64bit ÷ 往返延迟。
HP0 空手 RTT ≈40 拍 ⇒ 上限 20 MB/s，而主机给 15 MB/s（仅 1.3× 余量），显示拷贝一抢端口
RTT 就涨到上百拍 ⇒ 平均掉到 15 MB/s 以下，每包包尾按 16bit 粒度被丢（= 拖影/黑横纹）。
改成 AW/W 并行挂出、各自保持到被接收后，吞吐由握手决定（≤2 拍/字 ≈ 400 MB/s）。
板级验证：15/30/60 fps 回读全部 100.0%，见 `report/V6_BOARD_MEASUREMENT.md`。

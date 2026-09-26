# 系统架构与数据通路（Zynq-7020 主线）

工程：`Video_Processing` · Zynq-7020 · PL 以太网视频 + 右半窗旋转/无极缩放  
工具：Vivado / Vitis 2025.2.1  
版本：本文描述的是**当前主线结构**（V7.7 的功能面 + V7.9 的三笔 CDC 收紧）；
逐轮改动与门禁数字在 `report/CHANGELOG_V7.md`、`report/VERSION_LINEAGE.md`、`report/OVERNIGHT_LOG.md`。  
**范围声明**：本文只讲 Z7 这块板。第二块板（RK-XCKU5P-F / UltraScale+，同一套自研以太网栈 +
每秒一包 UDP 遥测 + 自研发送仲裁器）的工程文档是 `ku5p/README.md`，学习文档是
`study/02_架构/04_跨器件移植_Zynq到UltraScale.md`；两板共用哪些文件、不能共用哪些，
写在后者的 §1/§7 与 `report/VERSION_LINEAGE.md` §6。

---

## 1. 总体框图

```
┌─────────────┐   UDP 5001    ┌──────────────────┐
│  PC 上位机   │ ────────────► │  PL ETH PHY2     │
│ video_sender │  RGB565      │  RGMII BANK33    │
└─────────────┘  512×300      └────────┬─────────┘
                                       │ rgmii → arp/icmp/udp → frame_reasm
                                       ▼
                              ┌──────────────────┐
                              │ frame_buffer     │  BRAM 512×300×16b
                              │ (ETH 直写)        │
                              └────────┬─────────┘
                                       │ 随机读（左/右窗时分复用）
                                       ▼
┌─────────────┐  AXI GPIO     ┌──────────────────┐
│   UART PS   │ ────────────► │  pl_video_top    │
│  115200     │  sel/thr/src  │  旋转+缩放+效果   │
└─────────────┘               └────────┬─────────┘
                                       │ TMDS
                                       ▼
                              ┌──────────────────┐
                              │ HDMI 1024×600    │
                              │ 左原图 | 右缩放+效果│
                              │ OSD: FPS/Src/Pipe│
                              └──────────────────┘
```

**PS 不收 UDP 视频包**，仅控制面。备份：`FILL` 可写 DDR，`axi_frame_writer` 回读。

---

## 2. PL 显示数据通路（当前实现）

```
video_timing_1024x600
        │ x,y,de,hs,vs,frame_start
        ▼
   left_pane = (x < 512)
   cx = x 或 x-512
   cy = y >> 1                 ← 垂直 2×（300→600 行）
        │
        ├─────────────────────────────┬──────────────────────────────┐
        ▼ 左窗                          ▼ 右窗
   rotate_mapper                  zoom_ctrl + zoom_mapper
   (angle≠0)                      inv_scale 三角波（默认常开）
        │                             │ 可叠加 rotate
        │                             ▼
        │                        zoom 逆映射 (sx,sy)
        │
        └──────────┬──────────────────┘
                   ▼
            FB 地址时分复用
            左: rotate 后坐标
            右: zoom 后坐标
                   │ rd_addr 打拍 + BRAM 读
                   ▼
        ┌──────────┴──────────┐
        ▼                     ▼
   左窗像素 (原图)        右窗像素 (缩放后源像素)
        │                     │
        │                     ▼
        │              proc_pipeline（九位 stage_sel，一位一级）
        │              级0 gamma → 颜色(灰度/反色) → 滤波(模糊/锐化)
        │                       → Sobel → 阈值(二值化±判决) → 形态学(腐蚀/膨胀)
        │              （目标域 3×3，挂在右窗光栅上）
        │                     │
        ▼                     ▼
              split_display
         左=orig  右=proc  中间蓝线
                   │
                   ▼
         osd_overlay (OSD 五行：FPS/Src/Pipe/Rot/Split/Temp)
                   │
                   ▼
              rgb2dvi → HDMI
```

### 2.1 关键设计点

| 点 | 说明 |
|----|------|
| FB 单口读 | 左右窗扫描时间不重叠，按 `left_pane` 选择地址 |
| 延迟对齐 | mapper 3 拍 + rd_addr 1 拍 + BRAM 1 拍 + proc **15 拍**（顶层只取 `u_pipe.LATENCY`，不许再数一遍）；sideband 延到匹配 |
| 效果位置 | **右窗缩放后数据流**；左窗始终原图，便于对比 |
| 缩放 | 原始尺寸为最大（1.0×），自动缩小再回到原始；OOB 黑边 |
| line_cache | 旧「左扫效果→右读行缓」路径已废弃，不再接入 top |

---

## 3. PL 以太网协议栈

```
RGMII (IDDR/IDELAY, IDELAY=15)
    → gmii_to_rgmii
    → arp_rx / arp_tx
    → icmp_rx / icmp_tx   ← 载荷走自写 sync_fifo
    → udp_rx / udp_tx
    → eth_ctrl            ← 发送仲裁（v7.9 起：要求"两路都空闲"+ `arp_pend` 记账，见 ISSUES #37）
    → frame_reasm         ← [u32 LE offset][RGB565]
    → dc_fifo (eth_rxc→axi_clk) → BRAM 写
```

`eth_ctrl` 这条仲裁规则的原文是 `arp_rx_flag && (udp_tx_busy==0 || icmp_tx_busy==0)`，
语义是"**任一**空闲"⇒ 会在别人帧中间切 mux；v7.9 改成"全部空闲"并给一拍宽的请求补了记账位。
KU5P 侧同一位置换成了自研 `ku5p_tx_arb`（只认当前 owner 的 `done`）。判据：`sim/tb_ku5p_tx_arb.v`。

跨钟：`dc_fifo` Gray 码指针 + 双级同步；同钟：`sync_fifo`。均为 **RTL 手写**，非厂商 FIFO IP。

---

## 4. 时钟

| 时钟 | 频率 | 来源 | 用途 |
|------|------|------|------|
| sys_clk | 50 MHz | 板载 W17 | MMCM 输入、按键 |
| clk_pix (clkout0_1) | 50 MHz | MMCM OUT0 | 像素、效果、HDMI |
| clk_pix5x | 250 MHz | MMCM OUT1 | TMDS 5× |
| clk_200m | 200 MHz | MMCM OUT2 | IDELAYCTRL |
| axi_clk / clk_fpga_0 | 100 MHz | PS FCLK0 | AXI、GPIO、HP0 |
| eth_rxc | 125 MHz | PHY2 | RGMII 收包 |

MMCM：VCO=1000 MHz（50×20），÷20 / ÷4 / ÷5。

1024×600：H=1344，V=625；50 MHz 代替 50.25 MHz，误差约 0.5%。

**约束要点：** `set_clock_groups -asynchronous` 必须用 `-include_generated_clocks sys_clk` 覆盖 MMCM 生成钟，否则 eth→像素钟会被误分析。见 `OPTIMIZATION_LOG.md`。

---

## 5. 带宽与资源

| 项 | 数值 |
|----|------|
| 一帧 | 512×300×2 = 307200 B |
| 30 fps 入口 | ≈9.2 MB/s ≈74 Mbps |
| 显示 BRAM 读 | 307200 B × 60 Hz ≈18.4 MB/s |
| frame_buffer | 2.34 Mbit（7020 约 4.9 Mbit） |
| 双缓冲 | 资源不够，未采用 |
| 优化后占用 | LUT≈20%，FF≈19%，BRAM Tile≈59%，DSP≈6% |

---

## 6. 控制字（两只 AXI GPIO）

`0x41200000` = `gpio_o`（老那 32 位；PS 每次控制都**整字**重写）：

```
bit[4:0]   保留，恒写 0 —— V7 的 effect_en 五位于 2026-09-26 从 RTL 删净，PL 侧已无读者
           （位还占着：set_src.tcl / health_read.mjs 按位写这只字，重排等于把老工具全判红）
bit[15:8]  threshold
bit[16]    src_sel     0=图卡  1=视频
bit[17]    zoom_en     右窗呼吸缩放的开/关（V7.7 起不再是 RTL 里的常数 1'b1）
bit[18]    ps_publish  片源发布的翻转位
bit[19]    bilin_en    右窗双线性 / 最近邻
bit[24:23] 片源模式码、bit[22] 它的翻转位（`src 0|1|2` 钉住哪一路）
bit[26]/[31:27] 由观测工具写（gapclr / lane 选择）⇒ PS 一重写就被抹掉，见 PLAN §7a 规矩②
```

`0x41220000` = `gpio_cfg1`（V8 的新字）：**效果链只有一套口径 = 九位 `stage_sel`**（一位一级，
串口 `pipe <九个 0/1>` 写的就是它），同字 `[28:26]/[29]` 是缩放档与手动旗标、`[22:13]` 等 19 位是几何；
通道 2（`+0x08`）是 gamma 窗口 + 只给 OSD 看的 `gamma_disp` 与温度。

⇒ `effect_ctrl` 没有第二个入口、也没有"新字为 0 时顶上老五位"那道合流，OSD 的 `Pipe:` 那一格与
    `proc_pipeline` 吃的是**同一个** `stage_sel`（理由与退役过程写在 `effect_ctrl.v` 文件头）。

勿用 EMIO：本板 bank2 读回恒 0。

---

## 7. 无极缩放

```
inv_scale Q8: 256=1.0×（最大） ↔ 512=0.5×（最小）
每帧 STEP=2，三角波循环

无旋转:
  sx = W/2 + ((x-W/2)*inv)>>8
  sy = H/2 + ((y-H/2)*inv)>>8

有旋转: 在缩放偏移上再套 rotate_mapper 的 Q8 公式
```

`zoom_ctrl` 按 `frame_start` 更新；`zoom_mapper` 3 级流水，与 rotate 同拍对齐。

---

## 8. 旋转

同前版：Q8 sin/cos ROM，逆映射，`cos(0)=256` 不可饱和为 255。可与缩放叠加。

---

## 9. 自写 FIFO / OSD

| 模块 | 文件 | 要点 |
|------|------|------|
| sync_fifo | `src/rtl/eth/sync_fifo.v` | 同钟；存储无异步复位，`ram_style=block` |
| dc_fifo | `src/rtl/eth/dc_fifo.v` | 跨钟 Gray；打包 `{1'b0,addr[18:0],data[15:0]}` |
| osd_overlay | `src/rtl/video/osd_overlay.v` | 五行（FPS/Src/Pipe/Th/Gamma/Rot/Zoom/Split/Latency/Temp），3× 字模，空格空白字模；`Pipe:` 那一格由 `stage_sel[8:0]` 组合 |

---

## 10. 模块文件对照

| 模块 | 文件 |
|------|------|
| 系统顶层 | `src/rtl/top/system_top.v` |
| 视频顶层 | `src/rtl/top/pl_video_top.v` |
| ETH 顶层 | `src/rtl/eth/eth_udp_video_top.v` |
| 缩放 | `src/rtl/process/zoom/zoom_ctrl.v`, `zoom_mapper.v` |
| 旋转 | `src/rtl/process/rotate/*` |
| 效果 | `src/rtl/process/proc_*.v` |
| FIFO | `src/rtl/eth/sync_fifo.v`, `dc_fifo.v` |
| 约束 | `src/constraints/rk_zynq7020.xdc` |
| 构建 | `build/tcl/build_system_axigpio.tcl` |

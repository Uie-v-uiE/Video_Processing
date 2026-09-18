# 系统架构与数据通路

## 1. 总体框图

```
┌─────────────┐   UDP 5001    ┌──────────────────┐
│  PC 上位机   │ ────────────► │  PL ETH PHY2     │
│ video_sender │  RGB565      │  RGMII BANK33    │
└─────────────┘  512×300      └────────┬─────────┘
                                       │ rgmii_rx → mac → arp/icmp/udp
                                       ▼
                              ┌──────────────────┐
                              │ frame_reasm      │
                              │ offset 协议拼帧   │
                              └────────┬─────────┘
                         ┌─────────────┼─────────────┐
                         ▼             ▼             ▼
                   frame_buffer    AXI HP0 写      状态计数
                   (BRAM 直写)     DDR 0x10000000   (OSD)
                         │
                         ▼
┌─────────────┐  AXI GPIO     ┌──────────────────┐
│   UART PS   │ ────────────► │  PL 视频流水线    │  仅控制面
│  115200     │  en/thr/src   │  旋转+效果+OSD    │
└─────────────┘               └────────┬─────────┘
                                       │ TMDS
                                       ▼
                              ┌──────────────────┐
                              │ HDMI 1024×600    │
                              │ 左原图 | 右处理  │
                              └──────────────────┘
```

**PS 不再收 UDP 视频包。** 备份路径：PS `FILL` 仍可写 DDR 供 `axi_frame_writer` 回读。

---

## 2. PL 内部数据通路

```
video_timing_1024x600
        │ x,y,de,hs,vs,frame_start
        ▼
   left_pane = (x < 512)
   cx = x 或 x-512          ← 每半屏内的 0..511
   cy = y >> 1              ← 垂直 2× 放大（300 行 → 600 行）
        │
        ├──────────────────────────────┐
        ▼                              ▼
   rotate_mapper                  color_bar
   (angle≠0 时启用)               (SRC0 时用)
        │ sx,sy,oob                    │
        ▼                              │
   frame_buffer 读                      │
   addr = sy*512+sx                     │
        │ fb_rd                        │
        ▼                              ▼
    src_pix = src_sel ? ddr_pix : colorbar
        │
        ├──────────────────────────────┐
        ▼                              │
   proc_pipeline（仅左半屏 de）          │
   gray→binary→blur→sobel→invert       │
        │ pipe_dout                    │
        ▼                              ▼
   line_cache 一行                      │
        │ proc_rd                      │
        ▼                              ▼
              split_display
         左=orig  右=proc  中间蓝线
                    │
                    ▼
              osd_overlay → rgb2dvi → HDMI
```

**同步策略：** rotate_mapper 固定 3 拍；BRAM 读 1 拍；sideband（de/x/y/left）延迟 4 拍对齐。angle=0 时旁路 mapper，对 cx/cy 做同样 3 拍延迟。

---

## 3. PL 以太网协议栈

```
RGMII (IDDR/IDELAY)
    → gmii_to_rgmii
    → arp_rx / arp_tx     ← 回答 who-has（PC 才能 ping/推流）
    → icmp_rx / icmp_tx   ← ping 回显
    → udp_rx / udp_tx     ← 视频载荷
    → eth_ctrl            ← ARP/ICMP/UDP 发送仲裁
    → frame_reasm         ← [u32 offset][data] 拼帧
    → BRAM 直写 + 可选 AXI 写 DDR
```

**模块来源：** 协议栈结构与 RGMII 时序参考板卡已验证工程 `13_UDP_STACK`，接入本项目视频 sink。

---

## 4. 时钟

| 时钟 | 频率 | 来源 | 用途 |
|------|------|------|------|
| sys_clk | 50 MHz | 板载 W17 | MMCM 输入 |
| clk_pix | 50 MHz | MMCM OUT0 | 像素、效果、HDMI |
| clk_pix5x | 250 MHz | MMCM OUT1 | TMDS 5× 串化 |
| clk_200m | 200 MHz | MMCM OUT2 | IDELAYCTRL |
| axi_clk | 100 MHz | PS FCLK_CLK0 | AXI HP0、GPIO |
| eth_rxc | 125 MHz | PHY2 RXC | RGMII 收包 / GMII |

MMCM：VCO=1000 MHz（50×20），OUT0÷20=50M，OUT1÷4=250M，OUT2÷5=200M。

1024×600 时序：H=1344（1024+44+88+188），V=625（600+3+6+16），HSYNC+，VSYNC−。规格像素钟 50.25 MHz，用 50 MHz 误差 0.5%。

---

## 5. 带宽估算

### 5.1 UDP 入口

- 分辨率 512×300×2 B = **307200 B/帧**
- 30 fps → **9.2 MB/s ≈ 74 Mbps**
- 千兆网余量充足；UDP 包 1400 B，约 220 包/帧

### 5.2 AXI HP0

- 显示回读：307200 B × 60 Hz ≈ **18.4 MB/s**
- ETH 写 DDR（可选）：30 fps ≈ **9.2 MB/s**
- HP0 64-bit @ 100 MHz 理论 **800 MB/s**，占用 <5%

### 5.3 BRAM

- frame_buffer：512×300×16b = **2.34 Mbit**
- line_cache：512×16b
- XC7Z020 BRAM 约 4.9 Mbit
- **双缓冲 2×2.34=4.68 Mbit，与其它逻辑合计超 7020 容量**，故未采用

### 5.4 为何源选 512×300

| 方案 | 帧字节 | BRAM | 说明 |
|------|--------|------|------|
| 512×300 | 307 KB | 2.3 Mb | 当前，余量充足 |
| 640×360 | 460 KB | 3.5 Mb | 可升级 |
| 1280×720 | 1.8 MB | 13.8 Mb | 超出 7020 BRAM |

---

## 6. 控制字（AXI GPIO）

基址 **0x41200000**，DATA 寄存器 0x00。

```
bit[4:0]   effect_en
             bit0 gray
             bit1 binary
             bit2 blur
             bit3 sobel
             bit4 invert
bit[15:8]  threshold（二值化）
bit[16]    src_sel  0=彩条  1=DDR
```

**不要用 EMIO：** 本板 PS EMIO GPIO bank2 读回恒 0，已验证不可用。

---

## 7. 五效果流水线

级联顺序：**gray → binary → blur → sobel → invert**。

每个模块有 `bypass`：`bypass=1` 时数据直通。

**目标域窗滤（重构后）：**  
blur/sobel 在**旋转后的光栅序**上做 3×3，任意角可用。详见 `ROTATION_AND_EFFECTS.md`。

---

## 8. 任意角旋转

屏幕坐标 (cx,cy) 反算源坐标：

```
xp = cx - W/2
yp = H/2 - cy          // Y 翻转到数学坐标
xr = ( cos*xp + sin*yp) >> 8
yr = (-sin*xp + cos*yp) >> 8
sx = xr + W/2
sy = H/2 - yr
```

- sin/cos 为 Q8 定点（256=1.0），ROM 0..359°
- **cos(0)=256，绝不能饱和成 255**
- 越界 `oob` 填黑
- angle=0 时旁路整个 mapper（避免符号运算翻转）

---

## 9. HDMI 输出

- 左窗 x∈[0,511]：原图（src_pix）
- 右窗 x∈[512,1023]：处理图（line_cache 读出）
- x=511,512：蓝色分隔线
- 垂直 2×：同一 cy 显示两行
- OSD：左上角叠加状态文字

---

## 10. 模块文件对照

| 模块 | 文件 | 职责 |
|------|------|------|
| 系统顶层 | `rtl/top/system_top.v` | PS BD + PL 视频 + PL ETH |
| 视频顶层 | `rtl/top/pl_video_top.v` | 主数据通路 |
| ETH 顶层 | `rtl/eth/eth_udp_video_top.v` | 协议栈 + 视频 sink |
| RGMII | `rtl/eth/rgmii_rx.v` / `rgmii_tx.v` | IDDR/ODDR |
| ARP | `rtl/eth/arp*.v` | who-has 应答 |
| ICMP | `rtl/eth/icmp*.v` | ping |
| UDP | `rtl/eth/udp*.v` | 视频载荷 |
| 拼帧 | `rtl/eth/frame_reasm.v` | offset 协议 |
| 时序 | `rtl/video/video_timing_1024x600.v` | 1024×600 |
| 帧缓 | `rtl/video/frame_buffer.v` | 512×300 BRAM |
| 效果链 | `rtl/process/proc_pipeline.v` | 五级级联 |
| 旋转 | `rtl/process/rotate/*` | 映射 + ROM + 按键 |
| OSD | `rtl/video/osd_overlay.v` | 状态叠加 |
| HDMI | `rtl/hdmi/*` | TMDS |

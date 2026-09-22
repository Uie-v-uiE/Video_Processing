# DDR 双缓冲链路分析与定稿方案

## 0. 结论先说

| 项 | 结论 |
|----|------|
| 根因 | **不是 DDR 带宽不够**。带宽余量约 20×。 |
| 真正原因 | ① 显示没用 DDR 双缓冲（走 64 深 FIFO 直写 BRAM）② 提交时机用固定 2048 拍 drain，可能提交半帧 ③ saver 满时静默丢像素 ④ 双份 BRAM 帧缓冲在 7020 上爆资源 |
| 方案 | ETH → DDR bank A/B（完整帧才 commit）→ vsync 时 `axi_frame_writer` 回读到**单份**显示 BRAM → 旋转/效果读 BRAM |
| 不改 | 分辨率 512×300、HDMI 刷新时序、UDP offset 协议、效果流水线 |

---

## 1. 全链路（当前 noghost 实际接线）

```
PC UDP [u32 offset][RGB565]
  → RGMII/PHY2 → gmii_rx(125MHz)
  → udp → frame_reasm（按 offset 写，乱序可接受）
  → fb_wr_en/addr/data  + frame_done
       │
       ├─► eth_udp_video_top 内部：
       │     dc_fifo(1024) → axi_frame_saver（单拍随机写）→ DDR bank
       │     frame_done → 固定 2048 拍 drain → commit_tog + rd_bank
       │
       └─► pl_video_top 内部（错误）：
             dc_fifo(64!) → frame_buffer_db 双份 BRAM → 显示
             eth_commit / eth_bank 被接到顶层但**没用于显示**
```

显示读的是 BRAM，不是 DDR。DDR 写路径成了旁路。

---

## 2. 为什么会出现雪花 / 拖影 / 卡帧

| 现象 | 机制 |
|------|------|
| 雪花/错位 | 64 深 CDC FIFO 掉像素；或 `axi_frame_saver` full 时 `if (wr_en && !full)` **静默丢弃** |
| 拖影 | 边收边写显示 BRAM，未覆盖的旧像素仍在；或读到写一半的 bank |
| 卡帧/黑屏 | 旧实验里 `wait(fifo_empty)` 死等（下一帧已在灌）；或 `frame_start` CDC 丢脉冲 |
| 资源爆 | `frame_buffer_db` 双份 512×300×16 ≈ 4.9 Mbit，**等于 7020 全部 BRAM** |
| FPS=59/60 | 曾用 display vsync 计数，测的是刷新不是发送 |

**带宽核算（证明不是瓶颈）：**
- 写：50fps × 307200 B ≈ 15 MB/s
- HP0 理论：64-bit @ 100 MHz ≈ 800 MB/s（BD 实际约 400–600）
- 读显示：一帧 153600 px，流水回读约 0.5–1 ms 量级
- Vblank：25 行 × 1344 × 20 ns ≈ **672 µs**（偏紧，见 §4）

---

## 3. 开源对照（NexEBAZ4205 / Groovy_MiSTer）

调研结论与本地一致，可直接借鉴的硬约束：

1. **1-beat burst 会马赛克** → 最小 16 beats（128 B）
2. **异步 FIFO ≥ 2 整包** → 深度 2048–4096
3. **写侧切 bank**：`frame_done && wr_fifo_empty`（不能 fixed drain）
4. **读侧切 bank**：仅 display vsync
5. **没有 READY 帧就保持上一帧**，不显示半成品
6. 多位跨域禁止直接二进制打两拍；用 toggle+2FF 或 gray
7. 写满必须反压或整包丢弃，不能静默丢一半

NexEBAZ4205 地址：https://github.com/nexfieldsolution/NexEBAZ4205_OV5640_PS

---

## 4. 本工程约束：为什么不能「只读 DDR 行缓冲」

显示侧有 **任意角旋转**，`rd_addr = sy*W+sx` 是随机地址。  
行预取只适合 angle=0。因此：

- **显示仍需要一份可随机读的帧 BRAM**（300 KB，7020 放得下，且只放一份）
- DDR 负责「完整帧的提交与双缓冲」
- BRAM 负责「旋转/效果的随机读」

Vblank 仅 672 µs，整帧回读若超过会侵入下一场。对策：

1. `axi_frame_writer` 流水化（AR 与 unpack 重叠），目标 ≤ 600 µs
2. 在 display `frame_done`（最后一场有效行后）立即启动，而不是等 vs 脉冲中部
3. 若仍偶发顶部撕裂，属可接受 tradeoff；**不再用边收边写 BRAM**

---

## 5. 定稿数据通路

```
frame_reasm (125MHz)
    │ pixel stream
    ▼
dc_fifo DEPTH=2048 (gray, 带 bank 标签)
    │ axi_clk 100MHz
    ▼
axi_frame_saver
    │ 单拍随机写（offset 乱序）+ 完成计数 + 非满才收
    ▼
DDR  bank0 @ 0x1000_0000
     bank1 @ 0x1010_0000   （1MB 对齐，帧 0x4B000）

提交条件（axi_clk）：
  frame_done 已见 && wr_pixels[done_bank] >= 153600 && saver 空闲
  → commit_tog 翻转，rd_bank = done_bank

显示回读（触发在 clk_pix 的 frame_done）：
  commit_pending → axi_frame_writer(base=rd_bank)
                 → 单份 frame_buffer BRAM
  帧中不写 BRAM → 无边收边写拖影

显示读：
  frame_buffer 随机读 → rotate → effects → OSD → HDMI
```

### Bank / 信号

| 信号 | 时钟域 | 含义 |
|------|--------|------|
| `wr_bank_eth` | gmii_rx | 当前写入 bank，frame_done 时翻转 |
| `done_bank` | gmii_rx | 刚写完的 bank |
| `wr_pixels[bank]` | axi_clk | 已写入 DDR 的像素数 |
| `commit_tog` | axi_clk | 完整帧就绪（toggle） |
| `rd_bank` | axi_clk | 显示应读的 bank |
| `copy_pending` | clk_pix | vsync/frame_done 时若为 1 则启动回读 |

### 与旧方案差异

| 旧 | 新 |
|----|----|
| 显示走 64 深 FIFO 直写 BRAM | 显示走 DDR commit 后回读 |
| `frame_buffer_db` 双 BRAM | 单 `frame_buffer` |
| 固定 2048 拍 drain 提交 | 像素计数 + saver 空闲 |
| saver 满丢像素 | FIFO 深 2048，满则丢整拍并计数（后续可加整包丢） |
| `eth_has_frame` 在 eth_link 时置位 | 首次 commit 后才置位 |
| FPS=vsync | FPS=`eth_frame`（发送侧） |

---

## 6. 影响面（改一处会动哪里）

| 改动 | 影响 |
|------|------|
| 去掉 live BRAM 写 | 未 commit 前无 ETH 画面；首帧前显示彩条/旧 FILL —— 正确 |
| 单 BRAM | 资源下降，综合不再爆 BRAM |
| 回读占用 HP0 AR | 与 saver AW 并行；同 HP 口仲裁，回读期间写延迟略增，FIFO 深度覆盖 |
| 回读时长 | 与 vblank 竞争；用 frame_done 触发 + 流水 writer |
| PS FILL | 仍可写 DDR；与 ETH 互斥由 `src_sel && !eth_link` 控制 |
| 仿真 | 需覆盖：commit 前不显示、commit 后整帧、FIFO 排空、双 bank 乒乓 |

---

## 7. 实现顺序

1. `axi_frame_saver`：完成脉冲、空闲、满计数（不静默当成功）
2. `eth_udp_video_top`：像素计数提交，去掉 fixed drain
3. `pl_video_top`：删 live 写；commit → writer → 单 BRAM
4. 仿真 `tb_saver_commit` / 扩展 `tb_saver_writer`
5. 再出 bit

**在仿真通过前不烧板。**

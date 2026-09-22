# DDR 多缓冲帧管理（FBM）设计

## 0. 目标

解决 DDR 路径上的 **花屏 / 拖影 / 撕裂 / 卡住**，规则：

1. 多 Frame Slot，禁止「单帧直写直读」同一地址
2. UDP 只写当前 Receiving Slot，显示绝不读正在写的帧
3. 完整性通过后才 `READY` 提交
4. 显示只读已提交帧；仅在 VSYNC/消隐边界原子切换
5. 坏帧/丢包/超时/OOB 整帧丢弃，下一帧恢复
6. Slot 状态：`FREE / RECEIVING / READY / DISPLAYING / INVALID`

---

## 1. 历史根因（为何会花屏/拖影/卡住）

| 现象 | 根因 | 本方案对策 |
|------|------|------------|
| 花屏/雪花 | `pix_push` 计数了**所有** `fb_wr_en`，但 CDC FIFO 满时像素被丢；`snap_cnt==NEED` 仍提交半帧 | 只计 **FIFO 实际接受** 的像素；`accepted < NEED` 一律 INVALID |
| 花屏 | `frame_reasm` OOB offset 仍 `wr_en`，且计入 cover | OOB 不写、不计 cover，置 `frame_err` → INVALID |
| 拖影 | 边收边写显示 BRAM；读到未写完的 DDR bank | 显示 BRAM 仅由 **VSYNC 后** 的 DMA 填充；源 slot 必须 READY |
| 撕裂 | DMA 回读与显示重叠；或半帧被提交 | 回读在 `frame_done`/消隐启动；仅 READY slot |
| 卡住 | `wait(fifo_empty)` 死等；无 READY 时停更 | 超时丢弃；无 READY 则保持上一帧 BRAM |
| 带宽浪费 | 每像素 AW+W+B 串行 | saver 流水 outstanding 写（HP outstanding=8） |

带宽本身不是瓶颈（写 ~15 MB/s，HP0 ~400+ MB/s）。

---

## 2. 地址规划

```
0x1000_0000  Slot0  Original   1 MB stride, 帧占用 0x4B000
0x1010_0000  Slot1  Original
0x1020_0000  Slot2  Original
0x1030_0000  Slot3  Processed 预留（显示效果仍在 PL 流水线）
0x1040_0000  Slot4  Processed 预留
0x1050_0000  Slot5  Processed 预留
```

- `STRIDE = 1 MB`，slot id 译码简单，避免与相邻帧重叠
- 512×300×16bit = 307200 B = `0x4B000` < 1 MB
- 当前产品路径：Original 3 slot 全量实现；Processed 为地址预留（效果在 `proc_pipeline`）

---

## 3. Slot 状态机

```
                    alloc (frame start / RR)
         ┌──────────────────────────────────────┐
         ▼                                      │
      ┌──────┐   frame_done & OK    ┌─────────┐ │
      │ FREE │ ───────────────────► │RECEIVING│ │
      └──────┘                      └────┬────┘ │
         ▲                               │      │
         │                    complete   │      │ incomplete/timeout/OOB/drop
         │                               ▼      ▼
         │                         ┌───────┐ ┌─────────┐
         │                         │ READY │→│ INVALID │──► FREE
         │                         └───┬───┘ └─────────┘
         │                             │ VSYNC & writer idle
         │                             ▼
         │                       ┌────────────┐
         └──── copy_done ────────│ DISPLAYING │  (DMA→BRAM 源)
                                 └────────────┘
```

**READY 条件（全部满足）：**

1. `frame_done` 已到（reasm cover 达帧字节数）
2. eth 侧 **accepted 像素 == 153600**（FIFO 实收）
3. 本帧 `drop==0` 且 `oob==0`
4. axi saver **idle** 且该 slot `wr_count >= 153600`

**INVALID 条件（任一）：** 上述失败、提交超时、frame_err。

---

## 4. Original / Processed 切换逻辑

当前实现：

- **Original**：ETH → 3× DDR Slot → VSYNC DMA → 显示 BRAM
- **Processed**：同一 BRAM 读出后在 `proc_pipeline`（灰度/二值/模糊/Sobel/反色）实时生成，不回写 DDR

因此「双窗」共用一份 Original 源；Processed 不占用 DDR slot（地址已预留）。若后续 PS/PL 需要持久化处理结果，再接第二组 FBM 写通道即可，状态机相同。

---

## 5. VSYNC 原子切换规则

1. 显示侧 `frame_done`（最后一场有效行之后）CDC → `axi_clk` 得 `vsync_axi`
2. 若存在 READY slot 且 writer 空闲：
   - 选 **最新** READY（generation 最大）
   - `READY → DISPLAYING`，锁存 `copy_base`
   - 启动 `axi_frame_writer` DMA 到显示 BRAM
3. DMA 期间显示继续扫 **旧 BRAM**（不撕裂）
4. DMA `copy_done`：`DISPLAYING → FREE`
5. **无 READY**：不启动 DMA，保持上一帧（不卡死、不半帧）

禁止在有效显示期改写 BRAM。

---

## 6. AXI 读写路径划分

| 通道 | 模块 | 时钟 | 说明 |
|------|------|------|------|
| HP0 Write | `axi_frame_saver` | axi 100 MHz | 接收槽写入，流水 outstanding≤8，单拍 INCR + lane strobe |
| HP0 Read | `axi_frame_writer` | axi 100 MHz | READY 槽 16-beat burst 读出到 BRAM |
| 写优先策略 | — | — | 回读与写共享 HP0；FIFO 2048 覆盖仲裁尖峰 |

---

## 7. 花屏 / 撕裂 / 拖影避免机制

| 机制 | 作用 |
|------|------|
| 像素级 slot 标签进 CDC FIFO | 两帧交叠时写不串槽 |
| 只提交 accepted==NEED | 半帧不上屏 |
| READY 才 DMA | 不读写中槽 |
| VSYNC 后 DMA | 不在有效区改 BRAM |
| 无 READY 保持旧帧 | 避免黑屏/卡死循环 |
| OOB/drop/timeout → INVALID | 坏帧丢弃可恢复 |
| saver 流水 + FIFO 2048 | 降低满丢概率 |

---

## 8. 验证方法

### 仿真（已实现 `tb_frame_buf_mgr.v`）

1. 完整帧 → READY → VSYNC → copy → FREE，数据与模型一致
2. 故意丢像素 → 不得 READY，旧帧保持
3. 连续 4 帧 RR 写 3 slot，无「写中读」
4. 超时 → INVALID → 下一帧可恢复
5. `tb_saver_writer` 回归 AXI 数据通路

### 上板

1. `video_sender.py` 正常动画：无雪花、无残影
2. 人为高 FPS/丢包：仅掉帧，不花屏
3. OSD FPS 仍按发送侧 eth_frame
4. 旋转/效果开启无额外撕裂

---

## 9. 与旧双 bank 方案差异

| 旧 | 新 |
|----|----|
| 2 bank + snap 计数含丢弃 | 3 slot + 状态机 + 实收计数 |
| commit 仅看 push | commit 看 push∧wr_count∧idle |
| bank 1bit | slot 2bit + 基址表 |
| 无 INVALID/超时恢复语义 | 明确 INVALID→FREE |
| saver 串行 B | outstanding 流水写 |

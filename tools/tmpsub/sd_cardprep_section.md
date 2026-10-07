
## 10. 卡的准备（一次性、要提权；2026-10-07 19:5x 补）

**先说清凭据状态**：当年那一次"把一张卡整盘重建成 FAT32"**没有留命令记录**——
`grep -rI "diskpart" report/ board/ ARCH/ LEARNING/ study_docs/` 在 2026-10-07 现查是 **0 命中**，
只有结果留在挂载回显里。所以下面这一节是**按固件要求 + 卡的实测几何重写的配方**，不是那一次的逐字记录；
凡是推导出来的参数都标着"推"，凡是量出来的都给了件名与行号。

**量出来的几何**（来源：`board/measured/qspi_selfboot_uart_capture_2026-10-07_1935.txt:200`，19:35 冷上电自启那一次）

| 字段 | 读数 | 含义 |
|---|---|---|
| `part_lba` | 2048 | 分区起点在第 2048 扇区 = **1 MiB 对齐**（1024 KiB / 512 B） |
| `spc` | 32 | 每分区簇 32 扇区 ⇒ 簇 = 32 × 512 = **16 KiB**（⇒ Windows 格式化时"分配单元大小"选 16 KB） |
| `rootclus` | 2 | 根目录起始簇号 |
| `data_lba` | 34816 | 数据区起点 = `part_lba + 保留区 + FAT 区` 算出来的 |

同一份件里 `:201` 还有 `frames=4398 fps=30.000 measured=29.800 files=9 frame=307200B`，
`:213` 是 `[SD] 9 file(s), 4398 frame(s) total`，`:202-210` 是逐文件行数：`VIDEO000.BIN` 到 `VIDEO007.BIN` 各 512 帧、
`VIDEO008.BIN` **302** 帧 ⇒ `8 × 512 + 302 = 4398` 对平。算术（`node` 现算）：满块 512 × 307 200 = **157 286 400 B = 150.0 MiB**；
全卡内容 4398 × 307 200 = **1 351 065 600 B ≈ 1.26 GiB**；每文件占 157 286 400 / 16 384 = **9600 簇**。

**为什么"必须是自己格式化过的 FAT32"，两条都是代码事实**
1. 固件**不用 FatFs**：BSP 的 `libsrc` 里没有 `xilffs`（只有 `sdps`），所以 `sd_play.c` 自己解 MBR/BPB/目录项/簇链
   （来源：`src/ps/sd_play.c:4-6`）。它只认 FAT32 的 BPB 形状——exFAT/NTFS 不是"慢一点"，是**解不出来**。
2. 目录扫描**只认 8.3 名**：`if (d[11] == 0x0Fu) continue;  /* LFN：本项目不产生 */`（来源：`src/ps/sd_play.c:251`）。
   ⇒ 长文件名条目被**跳过**而不是读错：你把文件改名成 `video_0.bin` 之类，Windows 会另存一串 LFN 项，
   而我们的短名比对里那个文件就"不存在"了。这也是制片工具一律写 `VIDEO000.BIN` / `META.TXT` 的原因
   （来源：`src/host/make_sd_video.mjs:13`）。

**那个 1 GiB 的界**（今天补这段时顺手把话说明白）：目录项里首簇是**两个 16 位小端字**拼的——偏移 26 是低 16 位、
偏移 20 是高 16 位。历史上这里按大端拼，于是"首簇 ≥ 65 536"（= 文件数据起点在数据区 **1 GiB** 之后）的文件簇号被翻成天文数字，
就是 ISSUES #50 那个"定点坏点"（来源：`src/ps/sd_play.c:230-234` 的注释与 `clus_of()`；`65536 × 16 KiB = 1 073 741 824 B` 是同一把算术）。
现在拼法是对的，但**它解释了为什么卡上别的东西不要塞太满**：分区一大、文件往后放，跨 1 GiB 是常态而不是极端。

**配方（要管理员权限；只动那张卡，不碰板子，更不碰板上 EEPROM）**

```
diskpart                      ← 下面每一行都在 diskpart 里敲
  list disk                   ← 先看容量！按 GB 数认出那张卡，别看序号
  select disk N               ← N 必须是卡的号；选错就是一条清掉整块系统盘的操作
  clean                       ← 不可逆：整盘分区与数据全没
  create partition primary align=1024        ← 推：对齐到 1 MiB ⇒ part_lba=2048
  format fs=fat32 quick unit=16384           ← 推：16 KB/簇 ⇒ spc=32（与上表同一把数）
  assign
```

拷内容（制片在上一节：`node src/host/make_sd_video.mjs --in 你的.mp4`，默认出到 `./sd_stage`）：
把暂存目录里的 `VIDEO000.BIN … META.TXT` **全部**拷到卡的**根目录**（不要放进子目录——我们的目录扫描只解根目录簇链）。

**拷完怎么确认**（板子不必重刷，串口三行就够）

```
sd remount     →  [SD] FAT32 part_lba=2048 spc=32 rootclus=2 data_lba=34816
sd files       →  [SD] N file(s), M frame(s) total   然后逐行 #i VIDEOxxx.BIN 512 frame(s) first=k
autoplay 1     →  下一次冷上电就自己播（今天这条已被 #473 的自启复验证过）
```

**读不到时按这三条分岔查**（每条都有唯一的回声，别凭感觉）
- `mount failed: card absent or CMD sequence failed` ⇒ 卡的物理/命令层就没过（`src/ps/sd_play.c:490`）：换槽、换卡、看是不是没插到底，与文件系统无关。
- 挂上了但 `[SD] file not found: META.TXT` ⇒ 十有八九是**名字被改成 LFN**（上面第 2 条）或者拷进了子目录。
- `META FRAME_BYTES != compiled FRAME_BYTES (rebuild to match the card)`（`src/ps/sd_play.c:335`）⇒ 制片工具与固件的画幅常数不一致，
  **重编固件匹配卡**（或重制片），不是卡坏了：这一条把"两套真相"分开是当年故意设计的。

**留给自己的一句话**：这一节里两个"推"（`align=1024`、`unit=16384`）之所以站得住，是因为它们**被量到的几何反算验证**
（`part_lba=2048`、`spc=32`）。下一个人若要改分块大小或画幅，先把这张表重新量一遍，别沿用这里的数。

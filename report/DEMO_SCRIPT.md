# 演示与答问脚本（3 分钟版 + 追问弹药）

> 目的：明早板子起来后，**照着念就能演示**，并且每句对外说的话都能立刻指到仓库里的文件与数字。
> 纪律（也是比赛口径）：**只说板上演示过的**；没跑过的写"开发中/未验证"，不当成结论用。
> 出处一律给路径，别在台上凭记忆报数。

---

## 0. 起板（一次性，约 2 分钟）

```bat
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
set XSDBAT=D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat
%VIVADO% -mode batch -nojournal -source build\tcl\program_pl.tcl   :: 只配 PL
%XSDBAT%                                                          :: 进交互会话，下面四行在里面敲
    source  build/tcl/ps_jtag_boot.tcl                            :: 拉 PS（ps7_init 自动从 xsa 解出）
    targets -set -filter {name =~ "ps7_cortexa9_0*"}
    download build/ps_app.elf
    con                                                           :: 串口应出现 [BOOT] ... SD PLAY STOP FRAME0 BILIN0 STAT
%XSDBAT% build\tcl\set_src.tcl                                    :: 另开一次：0x41200000 = 0x000B0000
```
（`ps_jtag_boot.tcl` 里没有 `download`：仓库没有 Vitis 平台工程，elf 是在同一个 xsdb 会话里手动下的。）

下 bit 前 **先 `md5sum build/system.bit`，必须以 `534f7760` 开头**（= build#18：V7.7 同一功能 +
R22 两笔 CDC + R23 的 `copy_abort` 翻转同步，WNS +1.002 / WHS +0.050 / 0 违例；
**回退链**：build#17 `11998af8` 在 `build/frozen_r17_cdc/`，build#13 `0f46ec91` 在 `build/frozen_r13/`；
同名文件会被构建原地覆盖，今晚真发生过 —— 判据见 `report/OVERNIGHT_LOG.md` §9.5 第 1 步）。

推流：`node src/host/video_sender.mjs --ip 192.168.1.10 --port 5001 --test move --fps 15`

---

## 1. 三幕（每幕 40 秒，每幕都有一句"可核对的数字"）

### 第一幕：一条完整的 PL 以太网视频链，不看屏幕也能判断健康
1. 推流 → HDMI 右半窗出画面（左半窗是**未旋转的原画面**，用来做对照）。
2. 敲 `STAT` / 跑 `node src/host/health_read.mjs`：屏上 OSD 与读回计数一致
   （`DROP`、`STALL`、帧序号）。
3. **拔掉网线**：OSD 的 `STALL` 立刻钉 **9999**，`hb_slow` 变 1；插回去自动恢复。
   讲法：*"很多人做'屏上有黑纹才算坏'，我们把链路健康做成运行期可读的两个计数。"*

可核对数字（`data/measured/board_measure_r09.md`、`report/OVERNIGHT_LOG.md` R08–R10）：
拔线/插线两轮共 **200 次健康采样零误报**；`--gapclr` 对账误差 **0.1%**。

### 第二幕：几何 —— 逐度旋转 + 无极缩放（右半窗）
1. 按 key1/key2：右窗**逐度**转（`angle_ctrl.v` 是 +1/−1、0..359 环绕），左窗不转。
2. 缩放是自动呼吸（`inv_scale` 256→512 循环，256=原始大小/最大，512=0.5×）；
   `ZOOM0` 停、`ZOOM1` 起（V7.7 起这条命令才真的生效）。
3. 讲法：*"缩放与旋转是同一条逆映射链，旋转用 4 个 ROM + 2 个 DSP48 乘加，
   不写浮点、不查表插值，因此每像素周期一次取数就够。"*

### 第三幕：SD 卡本地回放（证明不依赖 PC 也能出图）
1. `SD` → 打印 `FAT32 part_lba=… frames=4398 fps=15.000 files=9`（只读 FAT32 解析，裸 SPI/SDIO，无文件系统库）。
2. `FRAME123` 单帧跳、`PLAY` 循环播、`STOP` 停；**先拔网线**再播，画面**不撕裂**
   （撕裂的判据不是眼睛：`ps_publish` 的发布握手 + 每场只在 V-blank 内原子提交）。
   讲法：*"PS 只负责把一帧的 DMA 目标地址准备好并翻转一根发布线，PL 只在帧尾取用一次。"*
3. 若 `SD` 报 `card absent`：说明卡不在 BSP 的那个 SDIO 控制器上，先查 PS 配置，不要改固件。

### 第四幕（**只有 KU5P 板级验证通过之后才讲**）：第二块板自己说话
1. 另开一个窗口：`node src/host/ku5p_stats.mjs` → 应该看到每秒一行
   `frames=… pkts=… bytes=… bad=0 oob=0 rows_miss=0 …`。
   讲法：*"同一套自研以太网栈，在 UltraScale+ 上只换了 RGMII 那三个文件；
   它现在不光会应答，还会每秒主动上报自己收到了什么、有没有错。"*
2. 追问"错是怎么量的"：`bad`/`oob`/`rows_missed` 全部来自 `frame_reasm` 的硬件计数，
   不是软件统计；这包数据的**线上格式**由 `sim/tb_ku5p_telem.v` 逐字节钉住
   （Ethernet/IP/UDP 头字段 + 载荷 36 字节 + 用网卡同样的方法验 CRC）。
3. **板级没过之前**，这一幕的口径只能是："移植已综合/实现收敛（WNS +2.081 ns、0 违例），
   遥测与发送仲裁**有台架判据**，板级验证在路上" —— 不要说"板上已经在发包"。

---

## 2. 资源与时序（一句话 + 出处）

*"xc7z020 上，140 个 BRAM 用到 90.5（64.64%），Slice LUT 13.50%、寄存器 5.45%，
动态功耗 2.184 W，时序 WNS +1.002 / WHS +0.050，约束全部满足、12496 根线全布通 0 错误。"*
（出处：`build/utilization.rpt`、`build/timing_summary.rpt`、`build/power.rpt`、
`build/route_status.rpt` —— 与 `build/system.bit`（md5 前缀 `534f7760`，build#18）**同一次构建**；
每次重跑之后这一句要跟着换，别沿用旧数字。）

| 说什么 | 数字 | 出处（现场可打开） |
|--------|------|--------------------|
| 帧缓存不是瓶颈了 | BRAM **98.93% → 64.64%**（按 2 的幂拆两块，省 48 个 tile） | `report/CHANGELOG_V7.md` V7.1(R04)；对照实验 `sim/probes/` |
| 打包缓冲不再吃触发器 | Slice Registers **51.30% → 9.02%**（打包 FIFO 改分布式 RAM） | 同上 V7.0(R02) |
| 入包链丢帧 | 15 fps × 200 帧：**198/198 帧完整落地，缺失 0/76800 个 16bit 字** | `data/measured/README.md`、`board_measure_15fps.txt` |
| 拖影 | 从 **42~52%** 最新帧占比 → **0**（offset 拼帧 + DDR 乒乓 + 消隐期原子提交） | `report/CHANGELOG_V6.md` §0、V7 前言 |
| 时序 | build#13：**WNS +0.426 / WHS +0.025 / 0 违例端点** | `build/timing_summary.rpt`（与 `build/system.bit` 成套） |
| 功耗 | Total ≈ **2.36 W**（Dynamic 2.18 W） | `build/power.rpt` |

---

## 3. 被追问时的弹药

- **"丢了包怎么恢复？"** 每包带 32bit 全局偏移 + 16bit frameid，乱序/重传直接按偏移写；
  缺包不阻塞其它行，整帧缺一行就标 `bad_frame` 不提交。判据：`sim/tb_v6_ingress_integrity.v`；
  为什么不用"按序到达"：`skill/udp_offset_reasm.md`、`skill/frameid_loss_signature.md`。
- **"为什么不用 PS 跑协议栈？"** PS 只做控制面（GPIO + SD 回放），视频数据全程在 PL：
  `report/PS_VS_PL.md`；RGMII 收流在 125 MHz 域做解析、50 MHz 域拼帧，跨域只有显式 CDC。
- **"旋转时画质为什么不掉？"** 诚实答案：**目前右窗是最近邻**，斜向有栅格闪烁；
  双线性已经写完（组件 + 集成 + 台架全过；当时 L1 **37/37**，主线现在 **40/40** 里仍包含这两个 bilin 台架），但 250 MHz 分时读口差最后
  **0.327 ns** 没收口 ⇒ 没进主线，实现打在 tag `v7.8-bilinear-wip`。
  要现场给评委看一眼"插值长什么样"：临时下 `build/failed_r24/system_r24_WNS-0.327.bit`，
  串口 `BILIN0/BILIN1` 现场对比；**看完必须换回 `build/system.bit` 并重新校验 md5**
  （那块 bit 时序未收口，只作观察，不作交付）。
- **"换到 UltraScale+ 要改多少？"** 已经改完并收敛：`ku5p/README.md` +
  `study/02_架构/04_跨器件移植_Zynq到UltraScale.md`（`MMCME2_BASE→MMCME4`、
  `IDDR/ODDR` 单时钟、RGMII 用 `IDDRE1+BUFIO`、没有 `IDELAYE2`；
  同一套协议栈在 `xcku5p-ffvb676-2-i` 上 **WNS +1.840 / WHS +0.012 / 0 失败端点 / 0 CRIT WARN**，
  BRAM 72、LUT 2268）。上板项（ping/收流）留白天。
- **"这套东西的瓶颈在哪？"** HP0 带宽不是瓶颈（实测结论 `skill/zynq_ddr_bandwidth.md`）；
  真正卡住画质升级的是**显示帧缓存只有 1 个读口/每像素一次**，解法与代价见
  `skill/derived_clock_port_mux.md`（同相 5 倍时钟分时 5 次读、零新增 BRAM）。

---

## 4. 千万别说的五句

1. 不要说"板上已有双线性插值" ⇒ 主线 bit 没有；说"组件与集成已完成并通过台架，正在收最后一笔时序"。
2. 不要说"拔线能立刻看出" ⇒ 拔线后 PHY **不停发 RXC**，只是慢到约 **1/49**；
   所以判据是"沿够不够快"（`hb_slow`），这句本身就是我们的加分点，讲出来比吹"实时检测"更有说服力。
3. 不要说"时序余量很大"也不要说"WHS 快翻了" ⇒ build#18 是 **WNS +1.002 / WHS +0.050 / 0 违例**；
   口径是"全部约束满足、零失败端点；setup 余量约一个周期的 12%，hold 余量小属于布局紧"。
   **hold 不是 PVT 风险点**：低压高温时单元与布线一起变慢，数据延迟变大 ⇒ hold 反而更稳，
   会恶化的是 setup（`ku5p/README.md` §10 把这条讲清楚了，被问"PVT 怎么办"就用它）。
4. 不要说"KU5P 已经在板上发包了" ⇒ 今晚只有**台架级**证据（逐字节 + CRC 判据 + 门禁全绿的构建）；
   口径是"移植与遥测已完成并通过仿真与实现门禁，板级验证在路上"。
5. 不要把 KU5P 遥测里的 `bad≈0` 说成"没有错包" ⇒ 它目前是**构造性为 0**（顶层没接 FCS/ER 判定，
   ISSUES #38）；能当健康证据的是 `oob`、`rows_miss` 与 flags 里的 `abort_seen`。

---

## 5. 万一现场不对

| 现象 | 先查 | 依据 |
|------|------|------|
| 无输出/黑屏 | LED0 心跳在不在；`md5sum build/system.bit` 对不对；SRC 位是不是 1 | §9.5 第 1、5 步 |
| 画面撕裂/半新半旧 | `health_read.mjs` 读 `copy_overrun`；拷贝是否超出一场 V-blank | `pl_video_top.v` 的 VBLANK_AXI_CYC 注释 |
| 推流没画面但 PC 能 ping 通 | ARP：板子只有点对点直连验证过，过交换机不保证 | `skill/board_eth_uart.md` |
| SD 打不开 | `SD` 的报错文本（`card absent` 是控制器问题，不是文件系统问题） | `src/ps/sd_play.c` 的 `sd_err()` |

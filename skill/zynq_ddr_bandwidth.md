# S4 · Zynq-7020 DDR / HP0 带宽账（先算再动）

## 适用场景
- 要在 PS7 的 HP 口上做 PL 读写整帧、PS 写帧、乒乓双缓冲，或只是想知道
  「画面丢字到底是带宽问题还是别的问题」。
- 选分辨率 / 决定缓冲放片上还是 DDR 之前。
- 不适用：AXI Interconnect 上还有其它主设备抢同一条 HP 口的系统（本设计只有 PL 视频通路在用）。

## 使用方法（本仓库里怎么算这笔账）
1. 帧字节 = W×H×2（RGB565）⇒ 512×300 = **307200 B**，64bit 字 = 38400 个
   （`docs/ARCHITECTURE.md` §5）。
2. 时钟与位宽按实：`axi_clk / clk_fpga_0 = 100 MHz`（PS FCLK0，64-bit HP0）
   ⇒ 峰值 **800 MB/s**，不是按 50 MHz 算出来的 400 MB/s（`docs/log/V6_ROOT_CAUSE.md` §3）。
3. 显示拷贝的预算要按**窗口**算，不是按平均速率算：
   `1024×600 @50 MHz` 的 V-blank = 25 行 × 1344 像素 = 67200 个 axi 周期 ≈ 672 µs，
   整帧 38400 拍 ⇒ 下限 0.571 拍/周期 ≈ **457 MB/s**（`docs/log/V6_ROOT_CAUSE.md` §3）。
4. **吞吐 = 在途深度 ÷ 往返延迟**，先数在途再谈总线峰值：
   `AWLEN=0` 逐字等 B 时 HP0 RTT≈40 拍 ⇒ 上限 **20 MB/s**（`docs/MODULES.md` §「为什么根因在
   `axi_frame_saver64` 的写通道」）。读侧同理：`src/rtl/axi/axi_frame_writer_gated.v:40,46`
   取 `BEATS=16`（64bit ⇒ 128 B/burst）× `MAX_OUT=4` = 64 拍在途。
5. PS 写完 DDR 必须 `Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES)`，PL 才看得到新帧
   （`src/ps/main.c:136`；`FRAME_ADDR=0x10000000` 见 `:24`，与乒乓 BANK0 同一块，
   `src/rtl/eth/ddr_bank_commit.v:17`）。
6. 提分辨率 / 加缓冲前先问「片上还是 DDR」：一块 512×300 显示帧缓存就吃掉 128/140 个
   RAMB36（`build/util_hier.rpt`，`docs/log/OVERNIGHT_LOG.md` R04），所以资源顺序是
   先解片上，再谈网口与 DDR。
7. 复算工具：`build/tcl/report_mem_hier.tcl`（层次化 BRAM 归属）、
   `SIM_TB=tb_v6_vblank_copy vivado -mode batch -source sim/run_sim.tcl`（按限速从机测拷贝周期）。

## 已验证效果
- 拷贝窗口预算被仿真按四档从机速率钉住（生产几何 512×300 / 1344×625 / 100 MHz）：
  800 MB/s → `copy_cycles=38441`、560 → 54894、480 → 64036 都在一个 V-blank 内完成，
  320 MB/s 溢出到后续消隐（1708873 拍）但**不写有效行、不重复、不越界**，20 ms 看门狗不误杀
  （`docs/log/V6_ROOT_CAUSE.md` §3；`sim/results/regression_v77_r13.txt` 的 `RESULT tb_v6_vblank_copy PASS`）。
- 「入包丢字不是深度问题、是排空速率问题」有定量证明：CDC 512→8192 + 反压后仿真 100%、
  板上仍 **42~52%**（`docs/log/ISSUES.md` #30）；再往下算清"吸收一次 V-blank 拷贝需 ≈84 个 BRAM tile
  而全片只有 140" ⇒ 加深这条路**结构上不可行**（`docs/log/OVERNIGHT_LOG.md` U3）。
  ⇒ 这一条的值钱之处在于：**"再加缓冲"是被一道算术题否掉的，不是被一次失败劝退的**。
  测量方法（怎么得到 42~52% 这类数）在 [S9](frameid_loss_signature.md)，不在本页。
- 流水化写通道后同一判据的板级结果：15/30/60 fps 全部 **100.0%**、包内各带 **0.0%**、
  半字错帧 **0/76800**（`docs/log/ISSUES.md` #31；`data/measured/board_measure_r06_r07.md` 三档复测）。
- 入口负载实测很小：30 fps ≈ **9.2 MB/s**、显示侧 BRAM 读 307200 B × 60 Hz ≈ **18.4 MB/s**
  （`docs/ARCHITECTURE.md` §5），而千兆线速上限 125 MB/s、排空侧 ≈200 MB/s
  ⇒ 所以 `--no-pace` 洪水在板上压不满 CDC（`data/measured/board_measure_r08.md` §反例复现）。
- 片上账已清：帧缓存按 2 的幂拆两块后 BRAM **98.93% → 64.64%**（90.5/140，剩 49.5 tile），
  WNS 同时由 +0.596 升到 **+0.819**（`docs/log/OVERNIGHT_LOG.md` §5 R04 行）；
  一行的行缓存只要 **1 个 tile**（512×16bit，`docs/log/OVERNIGHT_LOG.md` U2）⇒ 剩下的余量够做插值。
- 双读口这条路是**实测出局**的：一块 1W2R 的存储会把 BRAM 数量**正好翻倍**（探针数字与写法在
  [S10](derived_clock_port_mux.md) §一，那是它的唯一住处）⇒ 算完发现超过全片总量，只能回头做分时。
  **教训与器件无关**：想在"再加一个读口"和"再深一层缓冲"之间选，先把这两笔算术都写完。

## 失效条件

1. **公式对、参数错的那一类**：本仓库旧文里写过"HP0 理论 400 MB/s"，那是按 50 MHz 算的，而 BD 里
   FCLK0 是 100 MHz（`docs/ARCHITECTURE.md` §4）。同一句话在自己文档里传了十几版没人复核 ⇒
   **引用任何带宽数字前先按实钟/实位宽重算一遍**，别看它眼熟。
2. **算不出出处的数字就删掉**：旧文里的"720p 全帧 ≈13.8 Mbit"在本仓库找不到依据（按 W×H×2 重算
   1280×720×2 = 1.84 Mbit）⇒ 记为**未验证**，不许引用（可追溯的只有 `docs/ARCHITECTURE.md` §5 那几条）。
3. HP 口的位宽 / ARSIZE / burst 长度必须与 BD 里那条 HP 一致；本工程是 AXI3，
   **burst > 16 拍非法**（`BEATS=16` 已贴上限）。换到 AXI4 这条限制就变了，要重读协议版本。
4. 未 `Xil_DCacheFlushRange` 时 PL 读到的是旧数据 —— 这条**只覆盖 PS 写 DDR 的那两条路径**
   （FILL 与 SD 回放），外设直接 DMA 进 DDR 的入包链不经过 A9 缓存，别拿它去解释入包链的现象。
5. "上板双窗稳定"属**画质/肉眼**判据，本轮没有重新肉眼确认；有数据面证据的只有入包链
   （`docs/log/V6_BOARD_MEASUREMENT.md` §5 观察项 2/3 写的就是"肉眼待确认"）。
   这一眼怎么要、由谁签，见 [S23](eye_acceptance_loop.md)。
6. 功耗与温升数字（`docs/log/OVERNIGHT_LOG.md` §5 R05 行：Total 2.350 W / Dynamic 2.176 W / Tj 52.1 °C）
   置信度是 **Low**（没有 SAIF / 开关活动文件，`build/power.rpt` §1 `Confidence Level = Low`）⇒
   只能做相对比较，不能当绝对功耗引用（未竟项 U4）。**念任何估算类数字都要把置信度一起念出来。**

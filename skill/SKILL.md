# Skill：Zynq-7020 以太网视频流水线（PL 自研协议栈 + 0–359° 旋转 + 无极缩放）

> 本文件是 `skill/` 的索引与入口。**每一篇 skill 都按比赛要求写成四段**：
> 适用场景 / 使用方法 / 已验证效果 / 失效条件。
> "已验证效果"里只有跑出来的数字；没跑过的写"未验证"，不当成结论用。

## 一、适用场景（什么时候该用这一套）

- 工程是**本仓库**（`Video_Processing/`），或另一块板上要复用同一套 PL 以太网/视频 RTL。
- 板卡：RK-ZYNQ7020-F，`xc7z020clg484-2`；第二块板 RK-XCKU5P-F，`xcku5p-ffvb676-2-i`。
- 工具链：**Vivado / Vitis 2025.2.1**，装在 `D:\Software\Vivado\2025.2.1\`
  （版本必须一致：BD、`ps7_init`、xsa 与实现策略都是按这个版本验证的）。
- 问题类型：以太网收流丢帧/拖影、HDMI 双窗几何、跨时钟域、BRAM/时序门禁、上板不亮。

**不适用**：任何走 PS(lwIP) 的视频通路（本工程 PS 只做控制面 + SD 回放）；
Xilinx 官方 Ethernet MAC/UDP IP 的用法；非 Zynq/UltraScale 器件。

## 二、使用方法（正确的路径，按"从零复现"顺序）

| 我要做什么 | 跑什么 |
|------------|--------|
| 建工程 + BD + 综合 + 实现 + bit + xsa | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` |
| 只要 PL 综合冒烟 | `build/tcl/build_pl_full.tcl` / `build/tcl/create_project.tcl` |
| 一次性跑完全部台架 | `vivado -mode batch -source sim/run_sim.tcl`（37 个 tb，约 9 min） |
| 只跑某个台架 | `SIM_TB=tb_ps_publish vivado -mode batch -source sim/run_sim.tcl`（可加 `SIM_VERBOSE=1`） |
| 下 bit（PL-only 演示） | `build/tcl/program_pl.tcl` |
| 下整套 system.bit | `build/tcl/program_system.tcl` |
| 不写 flash 把 PS 拉起来 | `xsdb.bat build/tcl/ps_jtag_boot.tcl`（**ps7_init.tcl 会自动从 `build/system.xsa` 里解出来**；也可显式传路径或用 `PS7_INIT` 环境变量） |
| 选显示源（写 GPIO） | `xsdb.bat build/tcl/set_src.tcl`（现为 `0x000B0000`：src + zoom + bilin） |
| 上位机推流 | `node src/host/video_sender.mjs --ip 192.168.1.10 --port 5001` |
| 读硬件链路健康计数 | `node src/host/health_read.mjs`（`--gapclr` 先清帧间隔统计） |
| 生成 SD 卡帧库 | `node src/host/make_sd_video.mjs <mp4> <outdir>` |
| 编 PS 应用 | `node build/ps_app.mjs`（需 `PS_BSP` 指向一个已 generate 的 zynq BSP） |
| 门禁复核 | `build/timing_summary.rpt` `utilization.rpt` `cdc.rpt` `methodology.rpt` `power.rpt` `route_status.rpt` |

工程自身的文档入口是 **`README.md`**（`report/ARCHITECTURE.md`、`report/CHANGELOG_V7.md`、
`report/OVERNIGHT_LOG.md` 依次是架构、版本变更、每一轮的判据与数字）。

## 三、已验证效果（这一套换来的东西，都有出处）

- 拖影（ghosting）从量化值 **42~52%** 的最新帧占比 → **0**：改成 offset 拼帧 + DDR 乒乓
  + 消隐窗口内原子提交（`report/CHANGELOG_V7.md` V7 前言、`board/` 的 L4 记录）。
- BRAM 从 **98.93% → 64.64%**：帧缓存按 2 的幂拆两块（对照实验在 `sim/probes/`），
  打包/显示侧 skid 改分布式 RAM 又拿回 ~5 万 FDRE 与 30+ 个百分点的 Slice。
- 时序：**WNS +0.540 / WHS +0.042 / 0 失败端点 / 12500 根线全布通**（build#12）；
  一次因 OSD 里 32 bit 十进制除法（45 级组合链）导致 **WNS −6.765** 的失败已定位并改成
  十六进制显示 + 14 bit 两级流水（`report/OVERNIGHT_LOG.md` R08 那一段）。
- 链路健康可以**不看屏幕**判断：`DROP/STALL` 上 OSD + GPIO 读回，拔线/插线两轮实测
  与 `--gapclr` 对账误差 **0.1%**（`data/measured/board_measure_r09.md`）。
- 一项被证伪的假设：网线拔掉后 RTL8211F **没有停发 RXC**，而是慢到约 **1/49**
  ⇒ "有没有沿"永远查不出拔线，只能判"沿够不够快"（`hb_slow`）。
- 一块**只 80 行**的新需求也带回了资源：把旋转只留在右窗 ⇒ DSP48 13→9、LUT −182。

## 四、失效条件（出现这些情况，本 skill 的结论先作废、去重测）

1. **换了工具版本**：`ps7_init`、BD 地址分配与实现策略都是 2025.2.1 的产物；换版本 ⇒
   `build/tcl/*.tcl` 与门禁数字都要重跑，不能沿用。
2. **换了器件/板子**：`src/rtl/eth/rgmii_rx.v` 用的是 7 系列专有 `IDELAYE2/IDELAYCTRL`，
   `src/rtl/hdmi/tmds_serializer.v` 用 `OSERDESE2`，`clk_gen.v` 用 `MMCME2_BASE`
   ⇒ 这些在 UltraScale+ 上**不存在**，必须换原语（KU5P 移植见 `ku5p/`）。
   其余 RTL（协议栈、拼帧、CDC、帧缓存、效果链）是可移植的，并且已经拿综合验证过。
3. **两块板同时插着**：两个 FT2232 桥的**序列号 programmed 成同一个 `0ABC01`** ⇒
   同一时刻只有一块板可被 `hw_server` 看到；换板必须重启 `hw_server`（这不是驱动问题）。
4. **上位机网卡不在 192.168.1.100/24、或经了交换机**：本工程是按**点对点直连**验证的；
   协议栈的 ARP 只缓存**一个**对端，且接受广播帧 ⇒ 多人同网段时结论会漂（详见
   `report/OVERNIGHT_LOG.md` 与 `skill/udp_offset_reasm.md` 的失效段）。
5. **改了 `IMG_W/IMG_H/BASE_ADDR/UDP_PORT/BOARD_MAC/BOARD_IP` 中的任意一个而没同步另一侧**：
   RTL 参数、`src/ps/main.c` 的 `FRAME_*`、`src/host/*.mjs` 的默认值是三处独立写死的，
   任何一处不同步都会表现为"连上了但画面错位/收不到"。
6. **台架没有输出 `RESULT tb_xxx PASS`**：`sim/run_sim.tcl` 现在把"什么都没断言"判为 **FAIL**
   （以前会计 pass），所以一个绿色的 `SIM DONE pass=N fail=0` 才代表真的验过。
7. **改了像素时钟或 5 倍时钟的比例**（`src/rtl/clocks/clk_gen.v` 的 `CLKOUT0_DIVIDE_F` /
   `CLKOUT1_DIVIDE`）：显示读口"每像素周期 5 个快槽、右窗 4 + 左窗 1 恰好占满"是**按 5:1 算的**，
   比例一变，`tap_sched` 的整张槽位表与 `fb_rd5x` 的 `LAT` 全作废 ⇒
   必须重跑 `tb_tap_sched`/`tb_fb_rd5x`（后者用唯一平移量搜索**重新量** LAT），
   不能沿用顶层那几个由它推导的抽位常数。推导过程见 `skill/derived_clock_port_mux.md`。
8. **`build/system.bit` 没核对 md5 就下板**：同名文件会被每次构建原地覆盖
   （今晚就发生过"恢复成已验证版、22 分钟后又被失败构建盖掉"）⇒
   §9.5 明早清单第 1 步现在带 md5 断言，不一致就去 `build/frozen_*/` 取。

## 五、篇目

| 文件 | 一句话 |
|------|--------|
| `zynq-video-rtl-debug/SKILL.md` | 上板不亮/画面异常时的分层定位顺序（L0–L4） |
| `pl_rgmii_udp_offload.md` | 把以太网整条链路搬进 PL 的判据与代价 |
| `udp_offset_reasm.md` | 每包带 offset 的拼帧协议，为什么它比"按序到达"更抗丢包 |
| `frameid_loss_signature.md` | 用 `frameid` 区分"丢了包"与"丢了整帧" |
| `rotate_window_target_domain.md` | 窗口类滤波必须做在**目标域**，否则旋转角一起抖 |
| `zynq_ddr_bandwidth.md` | HP0 带宽实测与"拖影不是带宽问题"的结论 |
| `board_eth_uart.md` | 点对点直连、静态 IP、COM 口每次重扫 |
| `axi_stream_verify.md` | 无厂商 IP 时怎么自证 AXI 通路正确 |
| `llm_fpga_debug_workflow.md` | 与 LLM 协作的边界：判断必须能追溯到文件与数字 |
| `derived_clock_port_mux.md` | 用同相 N 倍时钟把单口 BRAM 分时成 N 次读：4 ns 预算、成对采集、延迟要量出来钉住 |

# 时序：余量在哪里，边界在哪里

r171（2026-10-22 候选）在实现后的读数是 WNS **1.341 ns**、WHS **0.025 ns**，TNS 和 THS 都为 0，失败端点 0。WNS 与 r169 相同，仍是 `phy_rst_cnt_reg[23] → rst_lm_sync2_reg/CLR` 的复位恢复路径（数据 1.927 ns，其中走线 1.443 ns）；WHS 从 0.048 变 0.025，仍为正，最差 hold 换到像素域 `u_blur/dout_reg[15] → u_sharp/q22_reg[15]`（数据 0.428 ns，0.346 ns 是时钟偏斜），是布局扰动而不是新逻辑。r171 相对 r169 的功能改动是 `axi_frame_saver64` 满 FIFO + flush 的尾字保持（#508）和 `play` 续播（#507）。下面 r162 的段是上一版历史，保留作对照。

| 时钟域（r171） | 周期 | WNS | WHS |
|---|---:|---:|---:|
| `clk_fpga_0`（AXI / PS FCLK0） | 10 ns | 2.159 ns | 0.060 ns |
| `clkout3`（ETH 逻辑） | 8 ns | 1.727 ns | 0.068 ns |
| `clkout0_1`（像素） | 20 ns | 3.264 ns | 0.025 ns |
| `eth_rxc`（PHY 恢复） | 8 ns | 3.247 ns | 0.071 ns |
| `sys_clk`（100 MHz 输入） | 20 ns | 14.797 ns | 0.067 ns |

r162 在实现后的读数是 WNS 1.378 ns、WHS 0.046 ns，TNS 和 THS 都为 0，失败端点 0。这里说的是布线后的报告，不是综合阶段的估算。

| 时钟域 | 周期 | WNS | WHS |
|---|---:|---:|---:|
| `clk_fpga_0`（AXI / PS FCLK0） | 10 ns | 2.208 ns | 0.046 ns |
| `clkout3`（ETH 逻辑） | 8 ns | 1.461 ns | 0.090 ns |
| `clkout0_1`（像素） | 20 ns | 3.894 ns | 0.071 ns |
| `eth_rxc`（PHY 恢复） | 8 ns | 2.833 ns | 0.080 ns |
| `sys_clk`（100 MHz 输入） | 20 ns | 13.332 ns | 0.099 ns |

全设计最差的那条不在数据路径上，而是 `clkout3` 上的复位恢复路径：`rst_l_sync2_reg` 到 `arp_rx_done_reg/CLR`，slack 1.378 ns，数据路径 5.913 ns（logic 0.494 ns，route 5.419 ns）。最紧的 hold 在 AXI 域的 `u_lat/c2_cyc_reg[26] → q_c2_reg[26]` 上，余量 0.046 ns，仍然是正的。

## 时钟域是怎么分的

恢复时钟只用于 IDDR 采样和异步 FIFO 写侧。协议逻辑在 MMCM 产生的 125 MHz；显示在 50 MHz；控制面是 100 MHz 的 AXI 时钟。像素时钟和串化时钟来自同一颗 MMCM，保持 5:1 的固定关系；ETH 逻辑时钟来自另一颗 MMCM。

两颗 MMCM 的输出被 Vivado 当成同主钟下的相关时钟，于是 50 MHz 到 125 MHz 的最紧沿差被算成 4 ns。实际上两颗 MMCM 的 VCO 各自独立，这个 4 ns 没有可签字的相位界。设计的正确性也不靠它：处理窗总线在源域整拍保持，目的域用三级同步器抓到翻转沿之后才采；总线至少保持一帧，远大于位间 skew 的预算。

r151 的最差路径正是这条总线（1.029 ns）。r152 新增 `src/constraints/cdc_quasi_static_impl.xdc`，对处理窗总线的 17 位、两条翻转同步链和 125→50 MHz 的链路电平用 `set_max_delay -datapath_only 10 ns` 约束位间 skew。改后这条路径还有 8.7 ns 余量，约束仍然在报告里，不是用 `set_false_path` 抹掉。

时钟组沿用原来的划分：恢复时钟、AXI 时钟、`sys_clk` 及其生成钟三组互相异步。跨域数据由结构保证：字节流走格雷码异步 FIFO，慢变量走翻转沿快照，单 bit 电平和复位走三级同步器。

## 五轮优化

第一轮是时钟域重构和准静态跨域契约。协议逻辑离开恢复时钟，处理窗总线用 10 ns 的位间 skew 约束，r151 的 1.029 ns 路径不再是瓶颈。

第二轮针对仲裁器的 `owner_eth`。它要驱动搬运器的地址、数据和控制 mux，实测扇出 234，r152 的最差 setup 就是它到帧缓存写地址（route 7.46 ns）。r154 给这个寄存器加 `max_fanout`，综合按 32 复制同一拍更新的副本；AXI 域从 1.201 ns 提到 1.950 ns，r156 进一步到 2.318 ns。代价是 8 个触发器，功能不变。

第三轮针对 125 MHz 域。帧重组的行覆盖判决在 r152 已经寄存一拍；r156 又把 `stat_bad` 的 32 位计数器使能寄存成单 bit，并把 ICMP 首部校验的第二拍从 6 项加法拆成 4 项加 3 项。ETH 逻辑域从 1.245 ns 提到 1.502 ns。

第四轮针对复位树，部分成功。给 `rst_l_sync2` 加 `max_fanout` 没有触发复制（触发器数没变）；r157 改用 BUFG 把复位送上全局网络，WNS 反而降到 1.078 ns，已经撤回。r161 换了一个小切口：把 link-monitor 的本地复位树复制一份，WNS 从 1.104 提到 1.172，不再让 3002 个清零端共用同一个驱动。

第五轮针对 UDP 发送的 IPv4 头校验和。r161 把 10 项加法压在一拍内完成，功能是对的，但它成了全设计最差路径：WNS 1.172 ns，6 级 CARRY4，logic 2.921 ns，route 3.565 ns。r162 拆成四拍：cnt0 加 5 项、cnt1 再加 5 项、cnt2 折叠高低半字、cnt3 再折叠并取反写入 `ip_head[2][15:0]`。四支 ETH 台架复验后，WNS 提到 1.378 ns，代价是 38 个 LUT、12 个触发器。拆完以后最差路径回到复位恢复，下一步要动的是复位树，不是继续拆校验和。

被否的一轮：r163 试过给 ARP 和 ICMP 各加一对本地复位同步器，想把 `rst_l_sync2 → arp_rx_done_reg/CLR` 这条 1.378 ns 的 CLR 树就近落地。结果是 post-place WNS 0.642、post-route WNS 0.920（WHS 0.048），比 r162 更差；布局阶段就掉下去了，说明新增同步器把复位输入端挤成了新的长路径。源已按 r162 逐字节还原，r163 报告留在 `build/r163/` 作反例。要继续压这条，得换拓扑（例如把大块寄存器改成同步复位），不是再复制同步器。

第二个反例：r164 只把 `rst_l_sync2` 的 `max_fanout` 从 32 压到 8，WNS **1.316 ns**、WHS 0.058，WNS 退 0.062 ns，只换到 12 ps hold，否决；源已还原为 r162，报告留在 `build/r164/`。

第三个反例不是时序试验，而是功能修复的代价。r165 给帧重组加 4 ms 空闲超时，想关闭 #181（A9）的混帧提交；台架改前红、改后绿，但 post-route WNS **0.986 ns**（WHS 0.048），比 r162 低 0.392 ns。最差路径从 ARP 的 CLR 换到 `rst_lm_sync2 → lm_bus_reg[140]/CLR`，新增计数器不在这条路上，退让来自布局扰动。功能修复不能拿 0.39 ns 的时序去换，尤其是当前最差路径本来就在复位树上。r165 否决，源与台架已按 r162 还原，报告留在 `build/r165/`。A9 的下一刀改用 `hdr < last_hdr`，不再加宽计数器。

第四个反例说明那条“下一刀”也不便宜。r166 只加一个 32 位 `last_hdr` 和一次比较，台架 6/7 段红转绿、17 支回归 `fail=0`，但 post-route WNS **1.293 ns**（WHS 0.039），比 r162 低 0.085 ns；最差路径仍回到复位恢复（`rst_l_sync2 → u_cdc/wbin_reg[12]/CLR`），新比较器不在这条路上。按 WNS 优先，r166 也否决，源与台架已还原；报告留在 `build/r166/`。A9 仍未修，而且两版都说明：在当前布局上动 `frame_reasm` 的清零锥，代价不是那几级逻辑本身。

下一步要动的是复位的**性质**，不是再复制同步器或调 fanout。r162 的最差路径是 `rst_l_sync2 → arp_rx_done_reg/CLR` 的恢复检查；r163 给 ARP/ICMP 各加本地同步器，仍然走异步 CLR，结果 0.920；r164 只压 fanout，1.316。真正能把这条恢复路径变成普通 setup 的做法，是把协议模块里那几个大块的异步复位改成同步复位（复位仍在同一个时钟域产生，只是从 CLR 端挪到 D 端的清零分支）。这会改变 `arp_rx`/`icmp_rx` 的复位语义，必须先跑 ARP/ICMP 台架和全量回归，再谈 WNS；当前没有做，交付仍是 r162。

## 能红的判据

帧重组的台架在“字节数已经够、但只覆盖 3/4 行”的激励下要求不提交；如果把行计数改成每写一个字加一，台架会报 `FAIL commit with full byte count but only 3/4 rows`。真实的 RTL 下这条判据是绿的。

r162 的 UDP 校验和由四支台架复验：`tb_udp_telemetry` 从 GMII 口按帧偏移抓取字节，逐字节比对以太网头、IP 目的地址、UDP 端口与载荷；`tb_eth_top_rgmii` 走完整的 RGMII 到 AXI 通路；`tb_rows` 与 `tb_udp_reasm` 覆盖重组侧。四支全过，日志在 `build/msim/r162_tx_checksum_sim.txt`。这四支原来只比对以太网头、IP 目的地址、UDP 端口与载荷，**没有验 IPv4 头校验和**：2026-10-22 给 `tb_udp_telemetry` 补了“把 IP 头 10 个 16 bit 字相加（含校验和字段）再折叠，结果应为 `16'hffff`”这一条。故意少加一项时，T1/T2 都报 `FAIL ip checksum sum=003c`；恢复源码后四支全过。日志：`build/msim/r162_checksum_mutation_fail3.txt`、`build/msim/r162_checksum_final4.txt`。

## hold 与“还能不能再优化”

最紧的 hold 路径在时延计数器的跨拍路径上：`u_lat/c2_cyc_reg[26]` 到 `q_c2_reg[26]`，数据路径 0.328 ns（logic 0.128 ns，route 0.200 ns），时钟偏差 0.265 ns，余量 0.046 ns。它在快速工艺角下仍然是正的，但已经没有多少空间。

为了确认默认流程是否还有可挤的余量，r153 打开 post-route phys_opt（AggressiveExplore）重跑了一遍。同一份 RTL、同一块器件，结果 WNS 1.201、WHS 0.048，与 r152 逐位相同。没有采纳这一版，也没有把这条旋钮写进生产流程。在 r156 的布线后网表上单独跑 `phys_opt_design -hold_fix`，WHS 仍然是 0.048，WNS 也没有变。这条 hold 路径的余量不是布线器还留着没拿，而是寄存器到分布式 RAM 的时钟偏差决定的；再往下要动写口结构。

继续压 setup 的收益已经很小，继续压 hold 要动 `axi_frame_saver64` 的写口结构，风险和收益不成比例。r162 的 1.378 ns 和 0.046 ns 就是当前这套结构的实际边界。

## 发送侧的物理边界

RGMII 的 TskewT 规格是 ±0.5 ns。本板的 RGMII 引脚都在 HR bank，没有 ODELAYE2，0° 转发时实测仍有约 0.845 ns 的保持余量缺口。试过 90° 相位和 −45° 补偿：前者直接把链路打断，后者把缺口减到 0.366 ns，但板上 ping 只剩 1/6，已经撤回。

当前生产位流使用 0°、时钟也过 ODDR 的方案，板上长时间 ping 稳定。这个缺口是 pinout 和 bank 类型决定的，不是再调几行 RTL 能消掉的。报告里把它写成边界，不写成“已解决”。

## CDC 报告里还剩什么

处理窗总线的两条翻转同步链各有一条 CDC-11，原因是同一个 `pv_tog` 扇出到 `ts` 与 `hs` 两条三级链。两条都受同一条 10 ns 的 max_delay 约束，属于通用 `snap_cross` 接口留下的双链结构，不是未约束路径。CDC 报告里其余条目都是已声明的异步组或带 ASYNC_REG 的同步器。2026-10-22 采纳 r162 时把这版报告升为基线（`build/evidence_r162/cdc.rpt`），`clkout0_1>clkout3 19 2` 记进 `cdc_baseline.txt`；门禁现在与 r162 比，后续新增配对或 unsafe 增长仍判红。

时序数字的原始报告在 `build/r162/timing_summary.rpt` 与 `build/r162/cdc.rpt`；当前副本在 `build/reports/`。r157 的 BUFG 试验留在 `build/r157/`。约束正文在 `src/constraints/` 下的两个实现期文件。

# KU5P 第二块板：把同一套自研以太网视频栈跑在 UltraScale+ 上

板卡：RIGUKE **RK-XCKU5P-F V1.2**，器件 `xcku5p-ffvb676-2-i`（无 ARM PS、32 bit DDR4、
480 × RAMB36E2 + 64 UltraRAM、1824 DSP）。工具链与主工程同一个 **Vivado 2025.2.1**。

## 1. 这个目录证明什么、不证明什么

**证明**（可复跑、有数字）：主工程 `src/rtl/eth/` 里那套**不含任何厂商 IP** 的
GMII MAC / ARP / ICMP / UDP / offset 拼帧 / 帧计数与健康计数，
**换掉 RGMII 物理层那三个文件 + 把厂商的 GMII 发送 mux 换成自研仲裁器**，
就能在 UltraScale+ 上综合通过、实现收敛并出 bit（§4 第 4 条写了为什么要换 mux）。
做法是把同一批 `.v` 直接 `add_files`（不复制、不改写），所以"可移植"不是文字承诺。
R23 之后还多证明了一件事：**这块板能主动把健康统计发回 PC**（每秒一包，
判据在 `sim/tb_ku5p_telem.v`，PC 侧解析器 `src/host/ku5p_stats.mjs --selftest` 双向对齐）。

**已跑出来的构建结果**（`ku5p/build/ku5p_*.rpt`；下表是 2026-09-23 05:43 那一次，
即加上"每秒一包 UDP 遥测 + 自研发送仲裁器"之后的版本；上一版（只有入口 + `fb_pack`）是
00:57 那次，WNS +2.081 / LUT 2415 / 端点 9600）：

| 项 | 值 | 说明 |
|----|----|------|
| WNS / WHS | **+1.916 / +0.010 ns** | 时钟只有一根：`create_clock -period 8.000`（125 MHz，PHY 恢复时钟）；`All user specified timing constraints are met` |
| 失败端点 / 总端点 | 0 / **11668** | 上一版是 9600 ⇒ 遥测 + 仲裁器多了 ~2000 个端点 |
| CLB LUT / FF | 3021（1.39%）/ 2799（0.65%） | 只装了入口 + 发包那一半，没有显示通路 |
| Block RAM | **72 tile（15.0% of 480）** | 与上一版**一模一样** ⇒ 新增逻辑没有要 RAM；推导见 §5 |
| URAM / DSP | 0 / 0 | 这块板有 64 块 UltraRAM，本设计一块没用（那是 §9 第 2 条的题） |
| 布线 | 7179 根全布通，**0 条布线错误** | `write_bitstream` 出 15.4 MB 的 `ku5p_eth.bit` |
| methodology | **0 条 Critical Warning** | 与 Zynq 侧同一口径的门禁 |
| `report_cdc` | 1 行 Critical：`input port clock → eth_rxc`，**16 端点全部 Unsafe=0**、异常已豁免（False Path） | 这一行是"没有公共主时钟"的结构性提示，不是没处理的跨域 |

**不证明**：
- 这块板**没有 HDMI 输出**（原理图 21 页里 `HDMI/TMDS/LCD` 零命中；显示要另配 FH1159 子卡），
  所以这里没有像素输出，也就没有效果链 / OSD / 缩放旋转那半边。
- 没有上板跑通过任何一件事：`ping` 应答、ARP、收流统计、**每秒一包的遥测**都还是
  **台架级证据**（`sim/tb_ku5p_telem.v`、`sim/tb_ku5p_tx_arb.v` 逐字节 + 逐相位验过），
  板上判据排在白天（§8）。写提交物时这两种"验过"要分开说。
- DDR4 没参与（MIG 是厂商 IP，且这块板的 DDR4 属于以后单独一次移植）。

## 2. 目录

```
ku5p/
├── src/rtl/
│   ├── ku5p_eth_top.v      ← 本工程的顶层（自研）
│   ├── ku5p_telem.v        ← 每秒一包的 UDP 遥测（自研，判据 sim/tb_ku5p_telem.v）
│   ├── ku5p_tx_arb.v       ← GMII 发送仲裁（自研，替掉厂商 eth_ctrl 的 mux；判据 sim/tb_ku5p_tx_arb.v）
│   （打包器在共用目录：../src/rtl/video/fb_pack.v，判据 ../sim/tb_fb_pack.v 12 条）
│   ├── gmii_to_rgmii.v ┐
│   ├── rgmii_rx.v      ├ 厂商 KU5P 例程原文，文件头标注了出处，未改一行（见 §6 授权）
│   └── rgmii_tx.v      ┘
├── src/constraints/ku5p_rk_xcku5p_f.xdc   引脚与时序约束（每条都有出处，见 §3）
├── build/tcl/ku5p_build.tcl               KU5P_SYNTH_ONLY=1 可只跑综合
└── build/*.rpt / *.log                    构建产物
```

## 3. 引脚与一处"差点写错"的教训

| 信号 | 引脚 | 电平 | 出处 |
|------|------|------|------|
| `sys_rst_n`(KEY1) | K9 | LVCMOS33 | 原理图 p5(bank86=+3.3 V)；厂商 `PHY_Pin.xdc` |
| `eth_rxc` | K22 | LVCMOS18 | 原理图 p4(bank66)；厂商 `PHY_Pin.xdc` |
| `eth_rx_ctl` / `eth_rxd[3:0]` | K23 / K26,K25,L25,L24 | LVCMOS18 | 同上 |
| `eth_txc` / `eth_tx_ctl` / `eth_txd[3:0]` | M25 / M26 / K20,L20,L22,L23 | LVCMOS18 | 同上 |
| LED1..4 | H9, J9, G11, H11 | LVCMOS33 | 原理图 p5；手册 p13 |

**教训（值得记进 skill）**：先从《用户手册》的中文叙述里读出的一套引脚
（"50 MHz 单端接 AK6"、"MDIO=AV23"、"PHY_RX_CLK=AY10 且 25 MHz 源同步"）
与原理图、厂商 XDC **两套证据全部冲突**：`AV24/AY10` 在整份原理图网表里根本不存在，
PHY 的 25 MHz 是它**自己的晶振**（Y501 的 XI/XTAL），不是给 FPGA 的 RX 时钟，
而厂商时序约束写的是 `create_clock -period 8.000`（= 125 MHz）。
⇒ 手册叙述里的引脚/频率不能单独当依据，必须与原理图 + 厂商 XDC 对得上；
`get_package_pins` 又要求有已打开的设计，所以"引脚存不存在"这种问题最省事的判据是
**直接让综合/实现去验**（错引脚是硬错误，不会静默通过）。

## 4. 移植到底改了什么（四条，其余照搬）

1. **RGMII 物理层换原语**：7 系列是 `BUFIO + IDELAYCTRL + IDELAYE2 + IDDR(SAME_EDGE_PIPELINED)`；
   UltraScale+ 里 `IDELAYE2/IDELAYCTRL` **不存在**，`IDDR` 也没有 `SAME_EDGE_PIPELINED` 这一档，
   正确组合是 `BUFG + BUFIO + IDDRE1`（发送侧 `ODDRE1`/`ODDR`）。
   顺带一条器件事实：UltraScale+ 的 `IDDR/ODDR` 端口是
   `IDDR(Q1,Q2,C,CE,D,R,S)` / `ODDR(Q,C,CE,D1,D2,R,S)` —— **单时钟、没有 CB、没有 DDR_CLK_EDGE**，
   所以 7 系列那份带参数的写法必须去掉参数（Unisim 定义文件是权威来源，别背）。
2. **整个入口变成单时钟域**：Zynq 版必须从 125 MHz 以太网域跨到 50 MHz 像素域
   （`dc_fifo` + 打包 + 乒乓 + 消隐期原子提交那一整套），这里没有像素消费者，
   所以 `eth_rxc` 一根时钟从头喂到尾，**MMCM 都不需要**。少掉的恰好是当初最难对的那部分。
3. **没有 PS ⇒ 没有 AXI GPIO / HP0**：状态改由 4 个 LED 表示，见下表。

| LED | 含义 | 为什么这么定 |
|-----|------|--------------|
| led[0] | 链路上出现过 GMII RX_DV | 最原始的"PHY 在吐东西" |
| led[1] | 帧完成 **且** 帧缓存内容变过 | 见 §5 的那次误判 |
| led[2] | 出现过拼帧失败（`frame_abort`） | 丢包/乱序的可见证据 |
| led[3] | 心跳 ≈3.7 Hz（125 MHz ÷ 2²⁴） | 证明"有时钟、复位已释放" |

4. **发送侧从"只会应答"升级成"会主动说话"，并把厂商的 GMII mux 换成自研仲裁器**：
   - `ku5p_telem` 每秒打一包 36 字节 UDP（帧数/包数/字节/错包/越界/缺行/上电秒数/标志位），
     PC 侧 `node src/host/ku5p_stats.mjs` 一行显示 ⇒ 这块板不再只能靠 4 个 LED 表达自己。
     **只有 ARP 学到对端才发**（`des_mac==0` 时厂商代码会往随机 MAC 发，那不是"发不出去"而是"发错地方"）。
   - 厂商 `eth_ctrl` 的三选一 mux 有一条真 bug：
     `arp_rx_flag && (udp_tx_busy==0 || icmp_tx_busy==0)` —— 那个 `||` 让"任一空闲"就能在
     **帧中间**把 mux 切给 ARP。今天只有 ARP/ICMP 交替时窗口很窄没暴露；有了周期性遥测就是常态。
     自研 `ku5p_tx_arb` 的规则只有一条：**拿到介质的那帧发完之前谁都不许换**，并且只认
     当前 owner 的 `done`。同一套激励下实测（改厂商代码**之前**）：**mux 在帧中间换源 1 次
     （那帧剩下的字节作废），自研仲裁器 0 次**（`sim/tb_ku5p_tx_arb.v` 的 T1–T4 是正向判据，
     V 组是拿厂商代码做对照的判据；厂商改好之后 V 组要求 `midbad=0 / arp=12 / udp=12`，实测已到）。
     主线那侧 v7.9 已经改掉了，但**不是一行**：`||`→`&&` 之后还要补一个 `arp_pend` 记账位，
     否则那一拍宽的 `arp_rx_flag` 会在"另一路还忙"时被吃掉（PC 要等 ARP 超时）。
     机理、两处改动和台架抓到的"脉冲高两拍 ⇒ ARP 发了 13 个字节"都登记在 `report/ISSUES.md` #37。

## 5. 一次必须记下来的误判：`SYNTH OK` 但 BRAM 只有 0.5 个

第一版综合"通过"，但 `Block RAM Tile = 0.5`（一块 512×300×2 的缓存该有几十块）。
两个原因叠在一起：
1. 读回累加器 `rd_sum` 只喂给 `_unused_ok`，**没有任何可观测终点** ⇒ 综合把读端口、
   整块 BRAM 连同写路径一起剪了；
2. 我为了修 (1) 补的 `rd_xor / data_alive` **声明了两次**（`Synth 8-9339/8-11152` 是
   CRITICAL WARNING，不是 error ⇒ 第二次声明被忽略 ⇒ 标志位成了无驱动隐式网 ⇒ 常量 ⇒ 又被剪）。

修法：读回改成 **XOR 折叠**（空白缓存恒 0，写过非零像素才会变），并让 led[1] 必须
"帧完成 且 折叠值变过"才亮 ⇒ 缓存既留在设计里，又是上板能看出来的判据。
结果：`Block RAM Tile = 72`，LUT 2320，FF 2002，0 CRITICAL WARNING。
⇒ **门禁看的是"证据"，不是"退出码"**：一个绿色构建完全可能在证明一件不存在的事。

**关于 72 tile：我先前那句"下界只有 7~8"是算错了 10 倍**（把 RAMB36 记成 368,640 bit，
真实是 **36,864 bit** = 32 Kb 数据 + 4 Kb 校验）。重算：`40960 × 64 = 2,621,440 bit`，
`2,621,440 / 36,864 = 71.1` ⇒ 下界就是 72 块，实测 71×RAMB36E2 + 2×RAMB18E2 = 正好等于下界。
Zynq 侧的 80 块同样是它自己的下界（64 bit 宽度时每块只有 32,768 bit 可用，校验位不能当数据）。
⇒ 80 vs 72 的差来自 **器件 RAM 组织方式**（E2 是 72 bit 宽），不是浪费也不是"更省"。
教训：资源结论必须写成"块数 × 每块多少 bit"再除；一个说不出来源的"下界"本身就是风险信号。
详细推导见 `study/02_架构/04_跨器件移植_Zynq到UltraScale.md §4`。

## 6. 授权与出处

`ku5p/src/rtl/{gmii_to_rgmii,rgmii_rx,rgmii_tx}.v` 逐字来自随板卡提供的厂商例程
`D:\Xilinx\Resource\KU5P\KU5P_DEMO\KU5P_DEMO\07_UDP_STACK\Source\`，文件头已加中文说明并注明路径，
除注释外未作修改。本仓库其余以太网/视频 RTL 是自研的（同一批文件在 Zynq 侧已上板验证）。
若厂商例程的再分发条款与本仓库 MIT 不兼容，就把这三个文件换成 `tools/` 下的外部路径引用，
不入库 —— 明天确认一下厂商目录里有没有 LICENSE 文件。

**2026-09-23 02:4x 确认结果**：整份厂商资料（`D:\Xilinx\Resource\KU5P\` 全树，含 `KU5P_DEMO`、
`Board_Resource`、`12_UDP_TEST`）里**没有任何 LICENSE / COPYRIGHT / 授权 / 协议 文件**，
PDF 手册与教程也没有给出再分发条款。⇒ 口径固定为：
1. 这三个文件是**第三方厂商样例代码**，本仓库只在文件头标注出处，**不计入"自研"清单**；
   比赛提交物里"自主实现"的部分只写我们自己的 RTL（其余 eth/视频/显示链全部自研，
   且同一批文件在 Zynq 侧已上板验证）。
2. 如果评审要求"仓库内不得含无授权第三方源码"，处理办法已经想好且代价可控：
   把这三份挪出仓库、构建脚本改成从本地厂商目录按需读入（`add_files` 支持绝对路径），
   或者由我们自己重写 GMII↔RGMII 桥（UltraScale+ 侧是 `BUFG+BUFIO+IDDRE1/ODDRE1`，
   约 150 行，但**没有板级验证之前不会替换** —— 见 §8 上板计划）。
3. 顺手修掉一处我自己写出来的脏东西：三个文件头里的厂商路径原本被写成含 **`\x07` 控制字符**
   的坏路径（`\0` 被当成转义吃掉，`07_UDP_STACK` 变成 `<BEL>_UDP_STACK`），
   现在已复原成真实存在的目录；并且全仓库（`src/rtl`、`sim`、`report`、`build/tcl`、`src/ps`、
   `ku5p`、`study`、`skill`）扫过一遍，C0 控制字符计数 = 0。
   教训：**用脚本写文件时不要手写反斜杠路径**，宁可 `chr(92)` 拼出来并当场读回校验。

## 7. 复现

```bash
cd Video_Processing
KU5P_SYNTH_ONLY=1 vivado -mode batch -nojournal -log ku5p/build/ku5p_synth.log \
                          -source ku5p/build/tcl/ku5p_build.tcl     # 只综合，几分钟
vivado -mode batch -nojournal -log ku5p/build/ku5p_impl.log \
       -source ku5p/build/tcl/ku5p_build.tcl                        # 到布线 + 报告 + bit
```
产物：`ku5p/build/ku5p_{util_synth,util,timing,methodology,cdc,route_status}.rpt`、`ku5p_eth.bit`。

## 8. 明天上板要做的事（按顺序做；**结果写到 `data/measured/ku5p_*.md`**，与主线的
`data/measured/board_measure_*.md` 同一套"每条都有判据与出处"的写法，不要只写在本 README 里）

1. 单独接 KU5P 的 JTAG（两块板的 FT2232 序列号同为 `0ABC01`，同时插只有一块可见；
   换板后必须重启 `hw_server`）。**只 JTAG 配置，绝不写 QSPI**（厂商自己的
   `program_qspi.bat` 写死 2023.1；用 2025.2.1 写高版本 flash 会锁死，见记忆里那条硬约束）。
2. `ping 192.168.1.11` → 通不通；`arping` 看 LED0。
3. `node src/host/video_sender.mjs --ip 192.168.1.11 --port 5001` → LED1/LED3 行为，
   以及**要不要补 IDELAY**（若 RGMII 走线没做延时补偿，125 MHz 源同步会收不全：
   判据 = LED1 是否亮 + 后续把统计做成 UDP 回包时丢包率是否为 0）。
4. **另开一个窗口**跑 `node src/host/ku5p_stats.mjs` → 应该每秒一行 `frames/pkts/bytes/bad/oob`。
   这一条同时回答三件事：TX 通道通不通、CRC/校验和被不被网卡接受、收流统计准不准。
   - 没有包但 ping 通 ⇒ 板子还没学到对端（`ku5p_telem` 的 `peer_known` 门），先 `ping` 一次；
   - 端口被占 ⇒ `--port` 只能改**监听**侧，板上源/目的端口写死 1234（厂商 `udp_tx` 里 `ip_head[5]`）；
   - `bad`/`oob` 持续增长 ⇒ 就是第 3 步说的 RGMII 采样问题，回来补 IDELAYE3。
5. 厂商授权这件事**今晚已经查过**（§6：整份资料里没有任何 LICENSE/授权文件），
   所以口径固定为"三份 RGMII 文件是第三方样例、不计入自研清单"。如果评审另有要求，
   §6 里写了两条退路（挪出仓库按需 add_files / 自己重写 IDDRE1 桥）。

## 9. 下一步（按价值排序）

**已经做完的（2026-09-23 R23）**：状态回包 —— `ku5p_telem` + `ku5p_tx_arb` +
`src/host/ku5p_stats.mjs`，三个台架判据 + 一次成套构建；上板那一步排在白天（§8）。

1. **让上报的每个数字都名副其实**（`report/ISSUES.md` #38）：遥测包里的 `bad`（错包数）现在是
   **构造性为 0** —— 顶层收包用厂商 `udp_rx`，它不看 ER / 帧长，`frame_reasm.p_good` 只能硬接 1。
   仓库里已经有自研的那一对：`gmii_rx_mac`（出 `m_good/m_bad`）+ `udp_rx_parser`
   （出 `p_good` 与三个 drop 统计，并且**本来就带目的端口过滤**），`sim/tb_udp_parser.v` 有判据。
   把顶层换成这一对，`bad` 就有真值、端口过滤顺带解决（那是主线 P0-C 最后一条债）。
   注意别说过头：`m_good` 是"无 ER + 长度合理"，**不是真 CRC-32 校验**。
2. **让 PC 能对这块板下命令**（现在它只会上报）。有了可用的 TX 通道，"回一个 ack"已经通了，
   下一步是把 `udp_rx` 收到的载荷当成命令字（例如清统计、改上报周期、触发一次快照），
   这样两板才能演成"KU5P 做前端节点、Zynq 做显示与总控"的异构结构（这也是比赛谱系里
   最有辨识度的那一条，见 `report/OVERNIGHT_LOG.md` §9 的口径）。
3. DDR4（MIG，厂商 IP）或 UltraRAM 版帧缓存，比较 tile 数与功耗。
   **先把算式写对**（这里我第一版算错过一次，写"约 2 块"）：
   512×300×RGB565 = 307,200 B = **2,457,600 bit**；UltraScale+ 的 UltraRAM 每块 **288 Kb = 294,912 bit**；
   `2,457,600 / 294,912 = 8.33` ⇒ 下界 **9 块**（片上 64 块的 14%），与 BRAM 那 **72 tile（15%）**
   是同一数量级占比（按缓冲的**实际**容量 40960 字 × 64 = 2,621,440 bit 算是 `8.89` → 同样是 9 块）。
   ⇒ **换 UltraRAM 的收益不在"省几块"，在功耗与释放 BRAM 给别的用途**，所以这一条必须实测
   （`report_power` + `report_utilization -hierarchical`）才好写进提交物。
   **今晚量了一半**（06:1x，`KU5P_FB=uram KU5P_TAG=uram` ⇒ 产物在 `ku5p/build/exp_uram/`）：
   开关确实生效（日志里能看到 `frame_buffer_uram` 被综合），但 Vivado 2025.2.1 **拒绝**
   `ram_style` 的 `ultramark` 与 `ultraram` 两种拼法（`WARNING [Synth 8-11376] ... not a valid value`），
   样式退回 `auto` 之后 **BRAM 仍 72、URAM 仍 0** ⇒ 量到的有用事实是：
   **这个形状（40960×64、1 写 1 读、输出带寄存器）工具不会自己选 UltraRAM**。
   所以"9 块"目前仍是算出来的不是量出来的；要真量，要么拿到 UG901 属性表里那个正确的强制 token，
   要么直接例化 `URAM1240` 原语。过程与两处失败拼法写在
   `ku5p/src/rtl_exp/frame_buffer_uram.v` 文件头（这个实验默认完全关闭，不影响交付的比特流）。
4. 显示半边：FH1159 FMC 子卡（要 GTY + 时钟芯片），或者把 KU5P 收到的流经第二块以太网口
   转给 Zynq 显示 —— 后者不需要任何新硬件。
5. 若上板发现 RGMII 收不全（125 MHz 源同步没做延时补偿），再考虑补 IDELAYE3；
   判据已经埋在 LED 与遥测里（`abort`/`bad` 计数不为 0 且 `rows_missed` 稳定增长）。

## 10. 关于那条 +13 ps 的保持余量：**先把概念摆正，再决定要不要动**

WHS 三次构建分别是 **+0.012 / +0.013 / +0.010 ns**（加了遥测与仲裁器之后那一次是 +0.010），
最坏路径一直是
`u_icmp/u_crc32_d8/crc_data_reg[11] → crc_data_reg[19]` —— CRC 的 XOR 树自己贴着自己。

**我先前把它写成"13 ps 在电压/温度漂移面前不算余量"，这句是概念错误，现在改正**：
*保持*时间随电压/温度的变化与*建立*时间是**同向补偿**的 —— 高温低压时细胞变慢，
组合路径延迟一起变大，hold 反而更不容易违例；真正随 PVT 恶化的是 **setup（WNS）**。
所以这条 +13 ps 是"布局挤出来的小余量"，不是明早演示的风险点；
而 `ku5p_setup.rpt` 里 WNS = **+2.081 ns**（§1 表里那一版；8 ns 周期的 26%）才是余量所在。

结论：**不动它**。要动也是在"下一次本来就要重跑实现"的时候顺手做，候选办法按代价排序：
1. `crc32_d8` 输出多打一拍（CRC 是逐字节累加，整链慢一拍，需连 `icmp_tx`/`udp_tx` 的等待一起看）；
2. 对该单元格加 `MAX_FANOUT` / 换 `phys_opt` directive；
3. CRC 拆两级流水（改动最大）。
⇒ 教训一句话：**报告里的数字要连着它的风险模型一起说**，"余量小"和"会翻"不是一回事；
把 hold 说成 PVT 风险，会让人在错误的地方花时间。

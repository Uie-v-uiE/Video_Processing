# KU5P 第二块板：把同一套自研以太网视频栈跑在 UltraScale+ 上

板卡：RIGUKE **RK-XCKU5P-F V1.2**，器件 `xcku5p-ffvb676-2-i`（无 ARM PS、32 bit DDR4、
480 × RAMB36E2 + 64 UltraRAM、1824 DSP）。工具链与主工程同一个 **Vivado 2025.2.1**。

## 1. 这个目录证明什么、不证明什么

**证明**（可复跑、有数字）：主工程 `src/rtl/eth/` 里那套**不含任何厂商 IP** 的
GMII MAC / ARP / ICMP / UDP / offset 拼帧 / 帧计数与健康计数，
**只替换 RGMII 物理层那三个文件**就能在 UltraScale+ 上综合通过并生成实现结果。
做法是把同一批 `.v` 直接 `add_files`（不复制、不改写），所以"可移植"不是文字承诺。

**已跑出来的构建结果**（`ku5p/build/ku5p_*.rpt`；下表是 2026-09-23 00:57 那一次，
即把打包逻辑抽成 `fb_pack` 并由 `sim/tb_fb_pack.v` 的 12 条判据验过之后的版本）：

| 项 | 值 | 说明 |
|----|----|------|
| WNS / WHS | **+2.081 / +0.013 ns** | 时钟只有一根：`create_clock -period 8.000`（125 MHz，PHY 恢复时钟） |
| 失败端点 / 总端点 | 0 / 9600 | `All user specified timing constraints are met` |
| CLB LUT / FF | 2415（1.11%）/ 2087（0.48%） | 只装了入口那一半，没有显示通路 |
| Block RAM | **72 tile（15.0% of 480）** | 见 §5：这个数字既是证据也是待查项 |
| DSP | **0** | 本设计不含乘加；也说明入口侧零 DSP 依赖 |
| 布线 | 5954 / 5954 全布通，0 错误 | `write_bitstream` 出 15.4 MB 的 `ku5p_eth.bit` |
| methodology | **0 条 Critical Warning** | 与 Zynq 侧同一口径的门禁 |

**不证明**：
- 这块板**没有 HDMI 输出**（原理图 21 页里 `HDMI/TMDS/LCD` 零命中；显示要另配 FH1159 子卡），
  所以这里没有像素输出，也就没有效果链 / OSD / 缩放旋转那半边。
- 没有上板跑通过任何一件事：`ping` 应答、ARP、收流统计都还是**待验证**（需要白天人在线）。
- DDR4 没参与（MIG 是厂商 IP，且这块板的 DDR4 属于以后单独一次移植）。

## 2. 目录

```
ku5p/
├── src/rtl/
│   ├── ku5p_eth_top.v      ← 本工程的顶层（自研）
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

## 4. 移植到底改了什么（三条，其余照搬）

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

## 8. 明天上板要做的事（按顺序）

1. 单独接 KU5P 的 JTAG（两块板的 FT2232 序列号同为 `0ABC01`，同时插只有一块可见；
   换板后必须重启 `hw_server`）。**只 JTAG 配置，绝不写 QSPI**（厂商自己的
   `program_qspi.bat` 写死 2023.1；用 2025.2.1 写高版本 flash 会锁死，见记忆里那条硬约束）。
2. `ping 192.168.1.11` → 通不通；`arping` 看 LED0。
3. `node src/host/video_sender.mjs --ip 192.168.1.11 --port 5001` → LED1/LED3 行为，
   以及**要不要补 IDELAY**（若 RGMII 走线没做延时补偿，125 MHz 源同步会收不全：
   判据 = LED1 是否亮 + 后续把统计做成 UDP 回包时丢包率是否为 0）。
4. 确认厂商目录里有没有 LICENSE 文件（§6 那句前提）。

## 9. 下一步（还没做，按价值排序）

1. **状态回包**：把 `udp` 模块本来就有的发送口（`tx_start_en/tx_data/tx_byte_num`）用起来，
   每秒向 PC 发一包本板统计（帧数/包数/字节/abort/rows_missed）。做完之后 KU5P 就不再靠
   LED 表达自己，`ping` + 回包也才是"能对接的异构节点"。这是**下一步里最值钱的一件**。
2. DDR4（MIG，厂商 IP）或 UltraRAM 版帧缓存，比较 tile 数与功耗。
3. 显示半边：FH1159 FMC 子卡（要 GTY + 时钟芯片），或者把 KU5P 收到的流经第二块以太网口
   转给 Zynq 显示 —— 后者不需要任何新硬件。

## 10. 时序侧的下一个具体目标：那条 +13 ps 的保持余量

WHS 两次构建都是 **+0.012 / +0.013 ns**，而且 `ku5p/build/ku5p_hold.rpt` 指出最坏路径是
`u_icmp/u_crc32_d8/crc_data_reg[11] → crc_data_reg[19]` —— **CRC 的 XOR 树自己贴着自己**。
它现在是"满足"，但 13 ps 在电压/温度漂移面前不算余量，换 `-1` 速度等级或加逻辑就可能翻。
可选的收敛办法（按代价从小到大，都要实测再说效果）：
1. 让 `crc32_d8` 的输出多打一拍（CRC 是逐字节累加，加一级寄存器等价于整条链慢一拍，
   只要发送侧等得到就行 —— 需要连 `icmp_tx`/`udp_tx` 的时序一起看）；
2. `phys_opt_design` 换 directive / 对 CRC 单元格加 `MAX_FANOUT`/`PULDOWN` 类提示；
3. 把 CRC 拆成两级流水（改动最大，但最彻底）。

**这条是明天之后第一件事的候选，不是今晚的**：现在设计是干净的（0 违例），
动它要重跑一次实现（~15 min）才能报数，不适合放在板上演示前的最后时刻。

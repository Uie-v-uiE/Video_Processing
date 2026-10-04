# 硬件接法、供电与外设（P16a · 可复原的物理侧）

给谁用：没摸过这套装置的人（陌生队伍 / 后续 agent），照本文件把同一套东西摆起来。
本文件只管**物理与工程侧**；上板命令序列在 `board/README.md` §2 与 `board/run/`，
每步该看到什么在 `board/bringup-checklist.md`，镜像身份在 `board/firmware/`。

写本文件的规矩（照 P16a 铁律）：

- 每一项都点名它的**仓库出处**；读不到的写 `【待你补】`，**绝不猜引脚、绝不猜电压、绝不猜线材**。
- "现在应该是 X"这类状态句后面一定跟一次**回读动作**（怎么当场验），不跟就不写。
- 本次运行**没有执行任何板级写入**（不写 flash/EEPROM、不刷板、不开串口）。风险步骤只写流程。

---

## 0. 型号与版本在哪里声明（本文件不复述）

| 项 | 值 | 权威出处（仓库内） |
|---|---|---|
| 板卡 | RK-ZYNQ7020-F | `report/BOARD_PINS.md:1`、`src/constraints/rk_zynq7020.xdc:1` |
| 器件 | XC7Z020-**CLG484-2**（含封装与速度等级） | `report/BOARD_PINS.md:3`、`build/README.md:5`、`board/README.md:10` |
| 工具 | Vivado / Vitis **2025.2.1** | `build/README.md:5`、`report/study/05_验证与上板/03_上板流程与踩坑.md:117` |
| 上位机 OS / Shell | Windows（Git Bash 跑 `.sh`，`cmd //c` 调 `.bat`） | `report/study/05_验证与上板/03_上板流程与踩坑.md:121-123` |
| Node（判据工具用） | v24（本机 `node --version` 实测 `v24.21.0`，2026-10-04） | 口径出处 `report/BUILD.md:15` |

⚠ **P16a 铁律 1 要求的单一权威声明文件 `docs/declarations.md` 在本仓库还不存在**
（`ls docs/` 实测：只有 `questions-for-team.md`、`run-queue.md`、`timing/`、`walkthrough/`；
`find . -iname "*declaration*"` 命中 0 个）。它由 P20 点名（`docs/run-queue.md:39`），本轮未开。
所以本文件暂以上表三处为声明源，**上表任何一处与 `docs/declarations.md` 将来不一致时以那份为准**；
这一条已进 `docs/questions-for-team-P16a.md`（Q-P16a-5）。

回读动作（当场验上表不是抄的）：

```bash
grep -n "RK-ZYNQ7020\|xc7z020clg484-2" report/BOARD_PINS.md build/README.md | head
ls docs/declarations.md 2>&1        # 现在必须是 "No such file"；哪天存在了就改引用它
```

---

## 1. 连接表（每条六件：起点 / 终点 / 线材 / 方向 / 供电 / 共地）

判定口径：**四件（起点·终点·线材·供电）齐全 = 齐**；缺的那件写 `【待你补】`。
"方向"与"共地"缺了同样算不可复原，单独列出来。

| # | 起点 | 终点（含引脚/针号/接口名） | 线材 | 方向 | 供电来源与限流 | 共地 | 四件 | 出处 |
|---|---|---|---|---|---|---|---|---|
| C1 | 市电插座 | 板卡 **DC 电源座**（板载，12 V） | 【待你补：适配器型号/插头/电流额定值】 | 单向 供电 | 板载从 12 V 生成；**限流值【待你补】**（仓库里没有任何一处写过适配器额定电流） | 不涉及（两芯/三芯由适配器定，【待你补】） | **缺 2**（线材、供电限流） | `report/BUILD.md:90`「12V 电源」；`report/study/05_验证与上板/03_上板流程与踩坑.md:114`「12 V 供电」 |
| C2 | PC 的 USB-A 口 | 板载 **USB-C**（板载桥 = FTDI FT4232：通道 A = JTAG/SWD DAP，通道 B = UART ⇒ Windows 的 **COM6**） | USB-C 线（长度/是否带屏蔽【待你补】） | 双向 | USB 总线 5 V；**板是否从 USB 取电未在本队取证 ⇒【待你补】** | PC 与板经 USB 屏蔽共地（**这条是推断，不是测量 ⇒【待你补】**） | **缺 2**（线材规格、供电口径） | `report/study/05_验证与上板/03_上板流程与踩坑.md:115`「FTDI FT4232（JTAG + 一个 VCP = COM6 @115200），USB-C 到板」；`report/log/OVERNIGHT_LOG.md:976`（`COM6` ← `FTDIBUS\VID_0403+PID_6010+0ABC01B`，通道 B） |
| C3 | 板卡 **HDMI OUT 座** | 显示器/面板 HDMI IN（1024×600 面板） | HDMI 线（版本/长度【待你补】） | 单向 板→屏 | 面板独立供电（**电压与适配器【待你补】**） | 屏与板是否共地【待你补】 | **缺 3**（线材、面板供电、共地） | `report/BUILD.md:90`；TMDS 8 根差分脚的封装位置：`report/BOARD_PINS.md:46-52` + `src/constraints/rk_zynq7020.xdc:12-19`（IOSTANDARD `TMDS_33`） |
| C4 | PC 有线网卡（静态 `192.168.1.100/24`） | 板卡 **PL 侧 RJ45（PHY2，Realtek RTL8211F）**，**不是 PS 网口** | 【待你补：线类别/是否直连自动交叉】（仓库只写了"网线直连千兆"） | 双向 | 不涉及（PHY 由板供电） | 不涉及 | **缺 1**（线材规格） | `data/measured/board_measure_r08.md:4`「PC 网卡 `192.168.1.100` ↔ 板子 **PL 侧** RJ45 `192.168.1.10`（直连千兆）」；`report/HOST_GUIDE.md:15-16`；RGMII 17 根脚的封装位置 `report/BOARD_PINS.md:24-38` + `src/constraints/rk_zynq7020.xdc:20-34`；协议参数（UDP 5001、MAC `00:11:22:33:44:55`）`report/ARCHITECTURE.md:126` |
| C5 | 板载 **SD 卡槽（PS 侧 SD0，MIO 按 BD 预设）** | 同一槽插入的 microSD 卡 | 不涉及（板载槽） | 单向 读（卡→板） | 板载 3.3 V（**卡槽限流未在本队取证 ⇒【待你补】**） | 板地 | **缺 1**（供电口径） | `report/BOARD_PINS.md:63`「QSPI / SD0 按 BD 预设」；文件系统与内容口径：`README.md:16`「SD 卡本地播放（FAT32 簇链自研解析，不依赖文件系统库）」、`board/HANDS_ON.md:25`（帧序列由 `node src/host/make_sd_video.mjs --in <mp4> --out E:` 生成）；**卡的品牌/容量/速度等级【待你补】** |
| C6 | 板载按键 **KEY1/KEY2**（`key1_n` W18 / `key2_n` V14，低有效） | PL 输入 | 不涉及（板载） | 单向 按下→PL | 板侧上拉：**KEY 那两只脚的 RC = 4.7 kΩ + 100 nF**（唯一出处见右列；**元件位号与供电轨【待你补】**——注意它与下面 PHY strap 那只 4.7 kΩ 不是同一处电路，别混用） | 板地 | **齐**（供电那一件写成了"上拉取值 + 位号待补"，位号缺） | `report/BOARD_PINS.md:13-14`、`src/constraints/rk_zynq7020.xdc:8-9`；RC 口径：`board/ACCEPTANCE.md:94`「板子断电 ≥10 s（让 4.7 kΩ/100 nF 那两只脚彻底放掉）」（这一句在 E6 那一格里，讲的就是 KEY 那两只脚）；对照：`docs/timing/ROUND_r116.md:31` 的 4.7K 上拉讲的是 **PHY2 的 RXDLY/TXDLY strap**，不是按键 |
| C7 | PL 输出 **led[0]** V15 / **led[1]** V13 | 板载 LED | 不涉及 | 单向 板→眼 | 板载 | 板地 | **齐**（限流电阻值在原理图，本仓库未抄 ⇒ 需要时【待你补】） | `report/BOARD_PINS.md:15-16`、`src/constraints/rk_zynq7020.xdc:10-11`；语义：`src/rtl/top/pl_video_top.v:1038-1039`「正常 = 1.5 Hz 心跳；发生过拷贝超出 V-blank 窗口 = 6 Hz 快闪」、`report/COMMANDS.md:22` |
| C8 | 板载 **MDIO**（`eth_mdc` AB20 / `eth_mdio` AB19）↔ PHY2 | 同一 PHY | 不涉及 | 双向 | 板载 | 板地 | **齐**（本工程数据面不用它：`report/BOARD_PINS.md:62`「ENET0 RGMII … MDIO 52–53（本工程数据面不用）」） | `report/BOARD_PINS.md:36-37` |
| C9 | PC 网卡的 ARP/ICMP 可达性（管理面，非线） | 板 PL 协议栈 `192.168.1.10` | 同 C4 | 双向 | — | — | — | `report/HOST_GUIDE.md:16`「`ping 192.168.1.10` 能通再推流 —— 通不通由 PL 里的 ICMP 应答决定，所以这一步同时验了位流」 |

### 1.1 缺口计数（P16a 质量判据 1 要求报数）

| 连接 | 缺的件数 |
|---|---|
| C1 板卡供电 | 2（线材规格、限流） |
| C2 USB（JTAG+UART） | 2（线材规格、USB 是否供电）＋共地口径未取证 |
| C3 HDMI + 面板 | 3（线材、面板供电、共地） |
| C4 网线 | 1（线类别） |
| C5 SD 卡 | 1（卡槽供电口径）＋卡型号未声明 |
| C6/C7/C8 | 0 |
| **合计** | **9 项缺** + 1 项（C5 卡型号）+ C7 限流电阻值 = **11 处 `【待你补】`**（逐条见 `docs/questions-for-team-P16a.md` Q-P16a-1 的 a…k） |

> 为什么这 9 项不能由我填：P16a 第 2 步「接线表与供电参数（给我逐项的值，缺的写 `【待你补】`）」
> 与停止条件「接线或供电参数拿不到就留 `【待你补】`，绝不猜引脚、绝不猜电压」。
> 仓库里能 grep 到的只有"12 V / USB-C / 千兆直连"这一层，没有适配器额定电流、没有线材规格、没有面板型号。

---

## 2. 外设与 BOM

| 件 | 型号/口径（仓库里有的） | 声明位置 | 状态 |
|---|---|---|---|
| 主控板 | RK-ZYNQ7020-F（XC7Z020-CLG484-2） | `report/BOARD_PINS.md:1-3` | 已声明 |
| 以太网 PHY | Realtek **RTL8211F-CG**（板载，RGMII，规格书 Track ID JATR-8275-15 Rev 1.4） | `docs/timing/debt_ledger.md:56-57`、`docs/timing/a1_sources.md:41` | 已声明（手册不在仓库内） |
| 显示面板 | HDMI，分辨率 1024×600；**品牌/型号/供电【待你补】** | 时序：`README.md:6-7`（像素钟 50 MHz、`H_TOTAL=1344`/`V_TOTAL=625` ⇒ 场频 59.5 Hz，出自 `src/rtl/video/video_timing_1024x600.v:18-20`） | 缺型号 |
| 板载调试桥 | FTDI FT4232（USB-C，通道 A=JTAG、通道 B=UART） | `report/study/05_验证与上板/03_上板流程与踩坑.md:115` | 已声明 |
| SD 卡 | FAT32；**容量/品牌/速度等级【待你补】** | `README.md:16`、`board/HANDS_ON.md:25` | 缺型号 |
| 12 V 适配器 | **【待你补】** | `report/BUILD.md:90` 只写"12V 电源" | 缺 |
| HDMI 线 / 网线 / USB-C 线 | **【待你补】**（长度与规格仓库未记） | — | 缺 |
| PC | Windows + Git Bash + Vivado/Vitis 2025.2.1 + Node v24 + Python 3（推流用） | `report/study/05_验证与上板/03_上板流程与踩坑.md:117-123`、`send_demo.bat:8-13` | 已声明 |

BOM 的位置：本仓库**没有**独立的 BOM 文件（`find . -iname "*bom*"` 命中 0）。
上表就是当前能给的最小 BOM；正式 BOM 归 P17/P20 的声明层，本轮不新建（未点名）。

---

## 3. 自制部分与图纸位置

- **自制部分：无。** 本装置由成品核心板 + 商用面板 + 商用线缆组成，仓库里没有自制板/转接板的
  工程文件（本轮实测：`find . -not -path "./.git/*" \( -iname "*.brd" -o -iname "*pcb*" \)` 命中 0、`find . -not -path "./.git/*" -iname "*bom*"` 命中 0）。
- 板卡原理图：`ZYNQ7020-F+V1.1原理图.pdf` **第 8 页**（PHY2 的 strap 引脚表：`23 TXDLY/RXD1`、
  `24 RXDLY/RXD0`）。出处：`docs/timing/rgmii_window_model.md:108-110`、
  `docs/timing/ROUND_r116.md:31`（结论："RXDLY/TXDLY 都由 4.7K 上拉到 IODVDD ⇒ PHY 把 2 ns 延时加在 RXC 上"）。
- 从原理图裁出来的图件在仓库内（随包性由导出器判）：`build/evidence/r115_sch_p8/`
  本轮实测有 4 个文件：`phy2_straps.png`、`rxd_area.png`、`strap_rxdly_1.png`、`strap_txdly_1.png`。
- PHY 时序参数抄件：`build/evidence/r115_rtl8211f_delay_source.txt`（Table 60 那一组，出处 `docs/timing/rgmii_window_model.md:90`）。
- ⚠ **原理图 PDF 与 PHY 规格书都不在仓库内**（在板卡资料目录，路径含机器字样 ⇒ 按 `report/BUILD.md:16-20`
  的规矩不写进交付文档）。陌生人拿不到 ⇒ 已在 `docs/questions-for-team-P16a.md`（Q-P16a-2）问：
  是否允许随包 / 是否给公开下载链接。**在此之前，第 8 页的那两处读数只能按"引文 + 裁图"复原，不能按原图复原。**

---

## 4. 上电与连接顺序（不可交换的那一段）

物理侧只有两条是硬顺序，逻辑侧的三条（PS→PL→应用）在 `board/bringup-checklist.md` §2：

1. **先接 C1（12 V）再接 C2（USB-C）**，反过来会在"USB 已枚举、板未上电"的状态下
   产生 `No devices detected`。这一条在本仓库有正向凭据：`build/r88_jtag_scan.txt:39-52`
   —— USB 侧（Composite Device / Serial Converter A / B / COM6）全部 `OK`，而 `scan_jtag` 报
   `ERROR: [Labtools 27-2269] No devices detected on target localhost:3121/xilinx_tcf/Xilinx/0ABC01A`，
   结论原话：「缺的是**板子供电**，不是驱动/线/PC」。
   回读动作：`bash board/run/env_probe.sh`（只看工具/端口/链，不碰板子）→
   再 `vivado -mode batch -source build/tcl/scan_jtag.tcl` 看 `=== DEVICES ===` 里有没有
   `xc7z020`（正常链的样张：`build/r90_jtag_scan.log:53-54`，`arm_dap_0` + `xc7z020_1` 各带一个非零 IDCODE）。
2. **网线（C4）接不接要先决定这一轮演哪一幕**：`report/BUILD.md:91-93` 写明
   PL 里 `link_active = |s_pkts` 是"自配置以来收过任何一个包"，**ARP 就够触发，拔线不清零、只有重配清零**
   （判据与改法在 `report/log/ISSUES.md` 的 #47）。所以演 SD 回放必须在**下 bit 之前**拔网线。
   回读动作：推流前后各读一次 `node src/host/health_read.mjs --json` 的 `src_state`（停流再读寄存器是
   `board/README.md:50` 的第二条注意点）。

---

## 5. 风险步骤（只写流程，**本轮一条都没执行**，全部需队伍批准）

| 步骤 | 为什么是风险 | 本项目的处置 | 需要谁的批准 |
|---|---|---|---|
| 向 QSPI/SPI flash 写入 | 会把"只能 JTAG 复现"变成"启动介质决定板上跑什么"，且擦除不可逆 | **本工程从不做**。原文口径：`README.md:38`「上板（只走 JTAG，本工程不向 QSPI/SPI flash 写入）」、`board/HANDS_ON.md:8`「永远不要写 QSPI/SPI flash，也不要碰 FT2232 的 EEPROM」、`report/DEMO_SCRIPT.md:28` | 不需要（被永久排除）；若将来要做，先由队伍批准并单开一轮 |
| 写板载 FT2232 EEPROM（改 USB 序列号） | 写坏了适配器就废了 | **不做**。背景：两块板的 FT2232 被写成同一个序列号 `0ABC01`，`hw_server` 只出一个 target，表现为"两块板抢端口"（`report/log/OVERNIGHT_LOG.md:966-984`）。给出的办法是**一次只插一块板的 USB-C**，不是动 EEPROM（同文 989 行那句"10 秒判别实验"） | 同上 |
| 断电重上电（冷上电） | 不可远程做，必须人手；而且是**唯一**已记录的 AP 不可达恢复手段 | 只在文档里写成恢复步骤：`report/log/ISSUES.md:10921-10926`（#235：「恢复要人手 —— 断电重上」）、`board/ACCEPTANCE.md:94`（冷上电 ≥10 s 的 E6 判据条件） | 队伍（人必须在板前） |
| 给板子上电 / 拔插 SD 卡与网线 | 物理动作，agent 不可达 | 全部写成"由人执行 + 回读"步骤（`board/bringup-checklist.md`） | 队伍 |
| 发破坏性激励（如 127 字节 + CRLF 的越界行） | 真实代价：一发就把 PS 的命令通道钉死，最后升级成整个 AP 不可达（`report/log/ISSUES.md:10915-10921`） | 探针 `board/cmd_overflow_probe.sh` 保留，但**必须先有断电重上的恢复手段 + 没人用板子的时间窗**（该 commit 61d1a2c 的"流程账"那段原话） | 队伍（时间窗） |
| 跑构建 / 刷板链 | 会原地覆盖 `build/system.bit`/`.xsa` 与六份报告（`report/BUILD.md:182`） | 本轮**一条都没跑**。流程见 `board/run/flash_chain.sh`（带 `--probe` 空跑） | 队伍 |

---

## 6. 我这次为了写本文件真跑过的只读探测（不含板级动作）

| 命令 | 输出摘要（原样） | 它钉住了哪句话 |
|---|---|---|
| `ls docs/` + `find . -iname "*declaration*"` | 无 `declarations.md`，命中 0 | §0 的"单一声明源还不存在" |
| `node --version` | `v24.21.0` | §0 表里 Node 那一行 |
| `netstat -an -p TCP \| grep 3121` | `TCP 0.0.0.0:3121 0.0.0.0:0 LISTENING` | hw_server **此刻**在听（不是"应该在"）；进程 `hw_server` PID 16328（`Get-Process` 实测） |
| `powershell "[System.IO.Ports.SerialPort]::GetPortNames()"` | `COM6` | COM6 此刻**存在**（枚举 ≠ 打开；本轮没有打开过串口） |
| `find . -not -path "./.git/*" \( -iname "*.brd" -o -iname "*pcb*" \)`、`find . -not -path "./.git/*" -iname "*bom*"` | 两条都命中 0 | §2/§3 的"没有自制部分、没有独立 BOM" |
| `ls build/evidence/r115_sch_p8/` | 4 个 png | §3 的图纸裁图位置 |

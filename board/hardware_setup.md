# 硬件接法、供电与外设

给第一次摆这套装置的人用：照这份文件把同一套东西接起来、供好电、当场验一遍。
这里只管**物理与工程侧**——上板命令序列在 `board/README.md` §2，每步该看到什么在 `board/acceptance.md`，
位流、XSA、ELF 三件的身份在 `build/provenance.md` 的身份表与 `board/measured/` 每一次跑的 IDENTITY 块里
（早先把三件身份写成摘要卡的那一层已经随目录精简删掉，不随包）。

三条填写口径：

- 每一项都点名它的仓库出处；仓库里查不到的写 `【待你补】`（这个标记的意思是「这一项仓库里没有记录，值要由队伍给」），
  不猜引脚、不猜电压、不猜线材。
- 状态句后面一定跟一次当场回读动作（怎么验），跟不上的就不写。
- 要断电、拔卡、重刷的动作只写流程与后果（见第 5 节），需要人站在板子前面做。

---

## 0. 型号与版本在哪里声明

单一权威源是 `report/declarations.md`：那份文件里 `<!-- BEGIN-AUTHORITATIVE -->` 块内的字段就是权威值。
下面这张表是抄写，右侧给的是各文件里的第一处出现；两处不一致时以 `report/declarations.md` 为准。

| 项 | 值 | 权威出处 |
|---|---|---|
| 板卡 | RK-ZYNQ7020-F | `report/declarations.md` 的 `board:` 字段，另见 `report/board_pins.md:1` |
| 器件 | XC7Z020-**CLG484-2**（含封装与速度等级） | 同文件 `part:` 字段；约束与构建入口写死同一串，见 `src/constraints/rk_zynq7020.xdc:1` |
| 工具 | Vivado / Vitis **2025.2.1**（build `6403652`） | 同文件 `vivado:` 与 `vivado_build:` 字段；任一报告头第一行也是这个串 |
| 上位机 OS / Shell | Windows（Git Bash 跑 `.sh`，`cmd //c` 调 `.bat`） | 同文件 `os:` 字段 |
| Node（上位机脚本用） | v24（本机 `node --version` 读到 `v24.21.0`） | 同文件 `node:` 字段 |

回读动作（当场验上表不是抄来的，在仓库根执行）：

```bash
grep -n "RK-ZYNQ7020\|xc7z020clg484-2" report/board_pins.md src/constraints/rk_zynq7020.xdc | head
sed -n '1,20p' report/declarations.md   # 权威块；上表每个值都要能与它对上
```

---

## 1. 连接表（每条六件：起点 / 终点 / 线材 / 方向 / 供电 / 共地）

口径：**四件（起点·终点·线材·供电）齐全 = 齐**；缺的那件写 `【待你补】`。
"方向"与"共地"缺了同样算不可复原，单独列出来。

| # | 起点 | 终点（含引脚/针号/接口名） | 线材 | 方向 | 供电来源与限流 | 共地 | 四件 | 出处 |
|---|---|---|---|---|---|---|---|---|
| C1 | 市电插座 | 板卡 **DC 电源座**（板载，12 V） | 【待你补：适配器型号/插头/电流额定值】 | 单向 供电 | 板载从 12 V 生成；**限流值【待你补】**（仓库里没有任何一处写过适配器额定电流） | 不涉及（两芯/三芯由适配器定，【待你补】） | **缺 2**（线材、供电限流） | `report/build.md:90`「12V 电源」；`report/study/05_验证与上板/03_上板流程与踩坑.md:114`「12 V 供电」 |
| C2 | PC 的 USB-A 口 | 板载 **USB-C**（板载桥 = FTDI FT4232：通道 A = JTAG/SWD DAP，通道 B = UART ⇒ Windows 的 **COM6**） | USB-C 线（长度/是否带屏蔽【待你补】） | 双向 | USB 总线 5 V；**板是否从 USB 取电没有记录 ⇒【待你补】** | PC 与板经 USB 屏蔽层共地（**这条是推断，不是测量 ⇒【待你补】**） | **缺 2**（线材规格、供电口径） | `report/study/05_验证与上板/03_上板流程与踩坑.md:115`「FTDI FT4232（JTAG + 一个 VCP = COM6 @115200），USB-C 到板」；夜轮记录（`COM6` ← `FTDIBUS\VID_0403+PID_6010+0ABC01B`，通道 B） |
| C3 | 板卡 **HDMI OUT 座** | 显示器/面板 HDMI IN（1024×600 面板） | HDMI 线（版本/长度【待你补】） | 单向 板→屏 | 面板独立供电（**电压与适配器【待你补】**） | 屏与板是否共地【待你补】 | **缺 3**（线材、面板供电、共地） | `report/build.md:90`；TMDS 8 根差分脚的封装位置：`report/board_pins.md:46-52` + `src/constraints/rk_zynq7020.xdc:12-19`（IOSTANDARD `TMDS_33`） |
| C4 | PC 有线网卡（静态 `192.168.1.100/24`） | 板卡 **PL 侧 RJ45（PHY2，Realtek RTL8211F）**，**不是 PS 网口** | 【待你补：线类别/是否直连自动交叉】（仓库只写了"网线直连千兆"） | 双向 | 不涉及（PHY 由板供电） | 不涉及 | **缺 1**（线材规格） | `data/measured/board_measure_r08.md:4`「PC 网卡 `192.168.1.100` ↔ 板子 **PL 侧** RJ45 `192.168.1.10`（直连千兆）」；`report/host_guide.md:17-16`；RGMII 17 根脚的封装位置 `report/board_pins.md:24-38` + `src/constraints/rk_zynq7020.xdc:20-34`；协议参数（UDP 5001、板卡 MAC，见下面那个参数块）架构章 |
| C5 | 板载 **SD 卡槽（PS 侧 SD0，MIO 按 BD 预设）** | 同一槽插入的 microSD 卡 | 不涉及（板载槽） | 单向 读（卡→板） | 板载 3.3 V（**卡槽限流没有记录 ⇒【待你补】**） | 板地 | **缺 1**（供电口径） | `report/board_pins.md:63`「QSPI / SD0 按 BD 预设」；文件系统与内容口径：README.md 的「项目简介（这个系统做什么）」一节（原引内容在本版 README 已无对应段落）「SD 卡本地播放（FAT32 簇链自研解析，不依赖文件系统库）」，帧序列由 `node src/host/make_sd_video.mjs --in <mp4> --out E:` 生成（这一步要本机有 ffmpeg/ffprobe）；**卡的品牌/容量/速度等级【待你补】** |
| C6 | 板载按键 **KEY1/KEY2**（`key1_n` W18 / `key2_n` V14，低有效） | PL 输入 | 不涉及（板载） | 单向 按下→PL | 板侧上拉：**KEY 那两只脚的 RC = 4.7 kΩ + 100 nF**（唯一出处见右列；**元件位号与供电轨【待你补】**——注意它与下面 PHY strap 那只 4.7 kΩ 不是同一处电路，别混用） | 板地 | **齐**（供电那一件写成"上拉取值 + 位号缺"） | `report/board_pins.md:13-14`、`src/constraints/rk_zynq7020.xdc:8-9`；RC 口径：`board/acceptance.md` 的 E6 那一行「板子断电 ≥10 s（让 4.7 kΩ/100 nF 那两只脚彻底放掉）」讲的就是 KEY 那两只脚；对照：那一轮的逐轮页 的 4.7K 上拉讲的是 **PHY2 的 RXDLY/TXDLY strap**，不是按键 |
| C7 | PL 输出 **led[0]** V15 / **led[1]** V13 | 板载 LED | 不涉及 | 单向 板→眼 | 板载 | 板地 | **齐**（限流电阻值在原理图，本仓库未抄） | `report/board_pins.md:15-16`、`src/constraints/rk_zynq7020.xdc:10-11`；语义：`src/rtl/top/pl_video_top.v:1038-1039`「正常 = 1.5 Hz 心跳；发生过拷贝超出 V-blank 窗口 = 6 Hz 快闪」、`report/commands.md:22` |
| C8 | 板载 **MDIO**（`eth_mdc` AB20 / `eth_mdio` AB19）↔ PHY2 | 同一 PHY | 不涉及 | 双向 | 板载 | 板地 | **齐**（本工程数据面不用它：`report/board_pins.md:62`「ENET0 RGMII … MDIO 52–53（本工程数据面不用）」） | `report/board_pins.md:36-37` |
| C9 | PC 网卡的 ARP/ICMP 可达性（管理面，不是线） | 板 PL 协议栈 `192.168.1.10` | 同 C4 | 双向 | — | — | — | `report/host_guide.md:17`「`ping 192.168.1.10` 能通再推流 —— 通不通由 PL 里的 ICMP 应答决定，所以这一步同时验了位流」 |

C4 与 C9 用到的板侧固定参数（写死在 PL 的协议栈里，出处 架构章）：

```text
MAC 00:11:22:33:44:55    UDP 视频端口 5001    板 IP 192.168.1.10 / 掩码 24
```

上位机推流命令里就是这三个值（`send_demo.bat` 双击走的是同一支脚本，只是全用默认参数）：

```bash
python src/host/video_sender.py --demo --ip 192.168.1.10 --port 5001 --fps 25
```

### 1.1 缺口计数

| 连接 | 缺的件数 |
|---|---|
| C1 板卡供电 | 2（线材规格、限流） |
| C2 USB（JTAG+UART） | 2（线材规格、USB 是否供电）＋共地口径没有记录 |
| C3 HDMI + 面板 | 3（线材、面板供电、共地） |
| C4 网线 | 1（线类别） |
| C5 SD 卡 | 1（卡槽供电口径）＋卡型号未声明 |
| C6/C7/C8 | 0 |
| **合计** | **9 项缺** + 1 项（C5 卡型号）+ C7 限流电阻值 = **11 处 `【待你补】`**（逐条对应上面两张表里点名的那一项，登记在 问队伍清单 的 Q-P16a-1） |

这 9 项不能由摆装置的人自填：接线与供电参数拿不到就留空，猜引脚、猜电压、猜线材都会把一套能跑的装置
变成一套跑不通的装置。仓库里能查到的只有"12 V / USB-C / 千兆直连"这一层，
没有适配器额定电流、没有线材规格、没有面板型号。

---

## 2. 外设与 BOM

| 件 | 型号/口径（仓库里有的） | 声明位置 | 状态 |
|---|---|---|---|
| 主控板 | RK-ZYNQ7020-F（XC7Z020-CLG484-2） | `report/board_pins.md:1-3` | 已声明 |
| 以太网 PHY | Realtek **RTL8211F-CG**（板载，RGMII，规格书 Track ID JATR-8275-15 Rev 1.4） | 时序债务账、出处核对 | 已声明（手册不在仓库内） |
| 显示面板 | HDMI，分辨率 1024×600；**品牌/型号/供电【待你补】** | 时序：README.md 的「关键数字与出处」一节（像素钟 50 MHz、`H_TOTAL=1344`/`V_TOTAL=625` ⇒ 场频 59.5 Hz，出自 `src/rtl/video/video_timing_1024x600.v:18-20`） | 缺型号 |
| 板载调试桥 | FTDI FT4232（USB-C，通道 A=JTAG、通道 B=UART） | `report/study/05_验证与上板/03_上板流程与踩坑.md:115` | 已声明 |
| SD 卡 | FAT32；**容量/品牌/速度等级【待你补】** | README.md 的「项目简介（这个系统做什么）」一节（原引内容在本版 README 已无对应段落）、`src/host/make_sd_video.mjs` | 缺型号 |
| 12 V 适配器 | **【待你补】** | `report/build.md:90` 只写"12V 电源" | 缺 |
| HDMI 线 / 网线 / USB-C 线 | **【待你补】**（长度与规格仓库未记） | — | 缺 |
| PC | Windows + Git Bash + Vivado/Vitis 2025.2.1 + Node v24 + Python 3（推流用） | `report/study/05_验证与上板/03_上板流程与踩坑.md:117-123`、`send_demo.bat:8-13` | 已声明 |

BOM 的位置：本仓库**没有**独立的 BOM 文件（`find . -iname "*bom*"` 命中 0）。
上表就是当前能给的最小 BOM，正式 BOM 属于声明层，不在这里新建。

---

## 3. 自制部分与图纸位置

- **自制部分：无。** 这套装置由成品核心板 + 商用面板 + 商用线缆组成，仓库里没有自制板或转接板的
  工程文件（`find . -not -path "./.git/*" \( -iname "*.brd" -o -iname "*pcb*" \)` 命中 0、
  `find . -not -path "./.git/*" -iname "*bom*"` 命中 0）。
- 板卡原理图：`ZYNQ7020-F+V1.1原理图.pdf` **第 8 页**（PHY2 的 strap 引脚表：`23 TXDLY/RXD1`、
  `24 RXDLY/RXD0`）。出处：收口输入窗模型、
  那一轮的逐轮页（结论："RXDLY/TXDLY 都由 4.7K 上拉到 IODVDD ⇒ PHY 把 2 ns 延时加在 RXC 上"）。
- 从原理图裁出来的 4 个图件（`phy2_straps.png`、`rxd_area.png`、`strap_rxdly_1.png`、`strap_txdly_1.png`）
  曾经入库，现已随目录精简删掉、**不随包**；这一节因此只保留图件名与它们所裁的那一页页码，
  拿不到裁图的人按上面两条引文（原理图第 8 页 + 收口输入窗模型）复原读数。
- PHY 时序参数抄件：`build/evidence/r115_rtl8211f_delay_source.txt`（Table 60 那一组，出处 收口输入窗模型）。
- 警告：**原理图 PDF 与 PHY 规格书都不在仓库内**（在板卡资料目录，路径含机器字样 ⇒ 按 `report/build.md:16-20`
  的规矩不写进交付文档）。拿不到原件的人只能按"引文 + 裁图"复原第 8 页的那两处读数，
  不能按原图复原。是否随包、或给公开下载链接，要由队伍答复；这一条与上面那 11 处同批登记在 问队伍清单。

---

## 4. 上电与连接顺序（不可交换的那一段）

物理侧只有两条是硬顺序；逻辑侧的三条（先起 PS、再烧 PL、最后重载应用）在 `board/README.md` §2：

1. **先接 C1（12 V）再接 C2（USB-C）**，反过来会在"USB 已枚举、板未上电"的状态下
   产生 `No devices detected`。这一条有正向凭据：`build/r88_jtag_scan.txt:39-52`
   —— USB 侧（Composite Device / Serial Converter A / B / COM6）全部 `OK`，而 `scan_jtag` 报
   `ERROR: [Labtools 27-2269] No devices detected on target localhost:3121/xilinx_tcf/Xilinx/0ABC01A`，
   结论原话：「缺的是**板子供电**，不是驱动/线/PC」。
   回读动作：在仓库根跑 `vivado -mode batch -source build/tcl/scan_jtag.tcl`，看 `=== DEVICES ===`
   里有没有 Zynq 那颗（正常链的样本：`build/evidence/r118_eyes/step2_program_pl.txt`，
   `arm_dap_0` 与 `xc7z020_1` 各占一行）。
2. **网线（C4）接不接要先决定这一趟演哪一幕**：`report/build.md:91-93` 写明
   PL 里 `link_active = |s_pkts` 是"自配置以来收过任何一个包"，**ARP 就够触发，拔线不清零、只有重配清零**
   （过程与改法记在 开发台账 的 #47）。所以演 SD 回放必须在**下 bit 之前**拔网线。
   回读动作：推流前后各读一次 `node src/host/health_read.mjs --json` 的 `src_state`
   （停流再读寄存器这件事是 `board/README.md` §2 末尾的两个注意点里的第二条）。

---

## 5. 风险步骤（只写流程与后果，都要人现场做、队伍批准）

| 步骤 | 为什么是风险 | 本项目的处置 | 需要谁的批准 |
|---|---|---|---|
| 向 QSPI/SPI flash 写入 | 会把"只能 JTAG 复现"变成"启动介质决定板上跑什么"，且擦除不可逆 | **2026-10-05 之前一直不做**；当晚按要求做过一次（`board/scripts/make_boot_image.sh` + `board/tcl/flash_qspi.tcl`，`PROGRAM.VERIFY` 是硬件回读比对，读数在 `board/measured/flash_qspi_2026-10-05.txt`），断电重上那一判没做。"擦除不可逆、启动介质决定板上跑什么"这条照旧成立。这一列的旧口径已随本次改口作废 | 本次即由队伍批准后单开一轮做的；下一次要写之前同样先取得同意 |
| 写板载 FT2232 EEPROM（改 USB 序列号） | 写坏了适配器就废了 | **不做**。背景：两块板的 FT2232 被写成同一个序列号 `0ABC01`，`hw_server` 只出一个 target，表现为"两块板抢端口"（夜轮记录）。给出的办法是**一次只插一块板的 USB-C**，不是动 EEPROM（同文 989 行那句"10 秒判别实验"） | 同上 |
| 断电重上电（冷上电） | 不可远程做，必须人手；而且是**唯一**有记录的 AP 不可达恢复手段 | 只作为恢复步骤写进文档：开发台账 的 #235「恢复要人手 —— 断电重上」、`board/acceptance.md` 的 E6（冷上电 ≥10 s 的条件） | 队伍（人必须在板前） |
| 给板子上电 / 拔插 SD 卡与网线 | 物理动作，脚本做不到 | 全部写成"由人执行 + 回读"步骤（`board/README.md` §2 与 `board/acceptance.md`） | 队伍 |
| 发破坏性激励（如 127 字节 + CRLF 的越界行） | 真实代价：一发就把 PS 的命令通道钉死，最后升级成整个 AP 不可达（开发台账 的 #235 那一段） | 探针 `board/cmd_overflow_probe.sh` 保留，但**必须先有断电重上的恢复手段 + 没人用板子的时间窗** | 队伍（时间窗） |
| 跑构建 / 刷板链 | 会原地覆盖 `build/system.bit`、`build/system.xsa` 与七份报告（`report/build.md:182`） | 流程见 `build/README.md` 第二节；现行逐轮链脚本是 `build/r118_chain.sh`，它要求 `VP_VIVADO_BIN` 与 `VP_XSDB` 两个变量，不给就中止 | 队伍 |

---

## 6. 现场核对用的只读命令（不碰板子，在任何机器上都能跑）

最后一列是作者机器上的一次读数，换机器值会变；这一节的作用是"上表哪句话被这条命令钉住"。

| 命令 | 样本读数 | 它钉住了哪句话 |
|---|---|---|
| `cat report/declarations.md` | 有 `board:`/`part:`/`vivado:` 那个块 | §0 的"单一权威源存在" |
| `node --version` | `v24.21.0` | §0 表里 Node 那一行 |
| `netstat -an -p TCP \| grep 3121` | `TCP 0.0.0.0:3121 0.0.0.0:0 LISTENING` | 本机 `hw_server` 此刻在听（不是"应该在"）；同一件事也可以 `Get-Process hw_server` 看进程 |
| `powershell "[System.IO.Ports.SerialPort]::GetPortNames()"` | `COM6` | COM6 此刻**存在**（枚举不等于打开；这一条不打开串口） |
| `find . -not -path "./.git/*" \( -iname "*.brd" -o -iname "*pcb*" \)`、`find . -not -path "./.git/*" -iname "*bom*"` | 两条都命中 0 | §2/§3 的"没有自制部分、没有独立 BOM" |
| `ls build/evidence/r115_sch_p8/` | 4 个 png | §3 的图纸裁图位置 |

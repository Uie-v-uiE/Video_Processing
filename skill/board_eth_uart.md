# S7 · 板级以太网与串口（可复用清单）

## 适用场景
- RK-ZYNQ7020-F 这类**双网口**板（PS GEM 与 PL PHY2 各一个 RJ45）+ 板载 USB-UART/JTAG 桥。
- 症状：ping 不通、ping 通但没画面、串口敲了没反应、`hw_server` 里找不到器件。
- 不适用：经交换机/多主机的网段，或需要 PS 侧 lwIP 收流的工程（本设计 PS 不做数据面）。

## 使用方法
1. 物理与地址（`board/README.md` §Hardware）：网线插**板卡 PL 网口（PHY2）**，不是 PS 口；
   PC 有线网卡静态 `192.168.1.100/24`；板 `192.168.1.10:5001`；HDMI 1024×600；12 V 供电。
2. PC 双网卡必须**绑源地址**，否则默认路由走 WLAN：`socket.bind(("192.168.1.100", 0))`
   （`report/ISSUES.md` §2）。本仓库脚本已内置 `--src`：
   `node src/host/video_sender.mjs --ip 192.168.1.10 --src 192.168.1.100 --fps 15`。
3. 存在性判据分两层：`ping 192.168.1.10` 验 ARP/ICMP 由 RTL 应答，
   推流后用 `node src/host/health_read.mjs` 读包计数（`pkts`/`bytes` 会涨）。
4. 串口 **115200 8N1**（`src/host/HOST_GUIDE.md` §4），一条命令行入口：
   `src/host/run_serial.bat COM6` 或 `python src/host/serial_ctrl.py --port COM6`。
   命令表：`00000`/`10000`/`00111` 效果位、`SRC0|SRC1`、`TH<n>`、`ZOOM0|ZOOM1`、`FILL`、`STAT`。
5. JTAG 侧：`vivado -mode batch -source build/tcl/scan_jtag.tcl` 先确认链上有 `xc7z020_1`，
   再 `xsdb.bat build/tcl/ps_jtag_boot.tcl <ps7_init.tcl>` → `build/tcl/program_pl.tcl` →
   `build/tcl/set_src.tcl`。**每次下 bit 后 PS 被复位，必须重新起 PS / 重跑 ELF**
   （`report/ISSUES.md` §23、`report/ETH_BRINGUP.md` §PS/Vitis）。

## 已验证效果
- 上述顺序在板上跑通过：`ps_jtag_boot`（`DDR_ECHO: 10000000: 5A5AA5A5`）→
  `program_pl`（`PROGRAMMED xc7z020_1`）→ `set_src`（GPIO `0x41200000 = 00010000`）→
  `ping 192.168.1.10` 发送=3 / 接收=3 / **丢失=0**、RTT 1–2 ms，全程 PS 不参与 ARP/ICMP
  （`report/OVERNIGHT_LOG.md` §「L4 执行」）。
- 包计数与控制面对上：`health_read.mjs` 读到的 `Δpkts/s = 3315 = 15 fps × 221 包/帧`，
  与上位机标称逐位吻合（个别秒 3536 是 1 秒采样边界）（`data/measured/board_measure_r09.md`）。
- 断链自愈：拔线期间 `pkts` 冻结、插回后立刻恢复且 `stall_ms` 归零，
  **不重启板子也不重下 bit**（`data/measured/board_measure_r08.md` §拔线实验，20:42:53）。
- 串口命令解析被固件明确接受：`src/ps/main.c:99` 以 `\r` **或** `\n` 作为结束符，
  `parse_bits` / `SRC*` / `TH*` / `ZOOM*` / `FILL` / `STAT` 走同一入口（`:100-120`）。
  所以「必须 CR+LF」不是协议要求，只是第三方串口助手不带结尾符时的稳妥发法
  （`src/host/HOST_GUIDE.md` §4 的「自动补 CR+LF」即为此）。
- 旧结论里唯一仍在本仓库可查的 PHY 侧记录：本设计**完全不配置 PHY**
  （`src/rtl/top/system_top.v:105-106` `eth_mdio = 1'bz`、`eth_mdc = 1'b0`，
  `:104` 由上电计数驱动 `eth_rst_n`），收包路径依赖 RTL8211 硬件默认自协商结果。

## 失效条件
1. **两块板同时插着时只有一块可见**：两颗板载 FT2232 的序列号被写成同一个 `0ABC01`
   ⇒ Windows 只给其中一个保留 `0ABC01` 实例名，`hw_server` 用串口号拼 cable URL，
   同名的第二根线**根本不产生第二个 target**；换板要重启 `hw_server`，这不是驱动或线材问题
   （`report/OVERNIGHT_LOG.md` §11，含 `Get-PnpDevice` 与 COM6/COM4 归属证据）。
2. **`DONE` 灯断电后常暗是预期**：本机只做 JTAG 下载、没有 `BOOT.BIN`，SD/QSPI 自启动才会配置 FPGA
   （`report/OVERNIGHT_LOG.md` §11 末）。不要用 DONE 判「bit 丢了」。
3. **PL 网口没加载 bit 时 ping 不通是正常**，不能反推网口坏
   （`report/OVERNIGHT_LOG.md` §「L4 尝试」把 ping 失败明确排除为判据）。
4. `CONFIG_LINKSPEED1000`（BSP 里写死速率）**只适用于 PS GEM/lwIP 那条通路**，
   本仓库当前 PL 侧不跑 MDIO，也没有 lwIP（`report/ETH_BRINGUP.md`）。
   这条在本工程状态下的证据只有历史记录 `report/VERSION_LINEAGE.md` §V1 与
   `study/00_前置知识/05_lwIP与PS侧以太网.md` §表格 4 ⇒ **本轮未复验**，不要写成现版战果。
5. Platform 重编会冲掉 `lwipopts` —— 同上，仅当仍使用 PS 网口时成立，本工程**未验证**。
6. 防火墙 / IP 不在同一网段 / 线材与变压器问题仍是第一嫌疑：本清单只覆盖
   「点对点直连 + 静态 IP + PL 口」这一种拓扑；换成交换机后 ARP 单对端缓存与广播接受
   会让结论漂移（见 `skill/pl_rgmii_udp_offload.md` 失效条件 7）。
7. 回读 DDR 之后 A9 被 `ddr_verify` 停住 ⇒ 串口看起来「没反应」其实是 PS 停跑，
   必须重跑三件套再判串口（`data/measured/board_measure_r06_r07.md` §环境确认）。

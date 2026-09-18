# 问题与修复记录

按时间顺序记录调试过程中的问题、定位方法与最终修复。

---

## 1. EMIO GPIO 读回恒 0

**现象：** 通过 PS EMIO 控制 PL 效果位，读回一直 0。  
**修复：** 改用 GP0 上的 **AXI GPIO**，基址 `0x41200000`。  
**教训：** 部分 Zynq 板 EMIO 异常，外设控制优先走 AXI GPIO。

---

## 2. PHY 自协商失败 `link_speed invalid`

**现象：** RTL8211 在 AUTODETECT 下报 link_speed invalid。  
**修复：** BSP `lwipopts.h` 设 `CONFIG_LINKSPEED1000`。  
**现状：** PS 不再用 lwIP 收视频；若仍用 PS 网口需保留此配置。

---

## 3. ping 通但 UDP 不到

**现象：** ping 正常，`rxcnt=0`。  
**原因：** PC 双网卡，默认路由走 WLAN。  
**修复：** `socket.bind(("192.168.1.100", 0))` 强制以太网源地址。

---

## 4. HDMI 只有窄条

**现象：** 彩条满屏，视频只有左侧窄带。  
**原因：** 64-bit beat 含 4 个 RGB565，旧逻辑每 rvalid 只写 1 像素。  
**修复：** `axi_frame_writer` 锁存整拍再拆 4 拍写 BRAM。

---

## 5. 行地址 12 位左移溢出

**现象：** 修复拆包后画面仍异常。  
**原因：** `(row+1) << 10` 在 12 位下回绕。  
**修复：** 全部改为 32 位运算。

---

## 6. 0° 旁路 mapper 导致流水线错位

**现象：** angle=0 时延迟从 3 拍变 1 拍，与 sideband 不对齐。  
**修复：** angle=0 时对 cx/cy 做同样 **3 拍寄存器延迟**。

---

## 7. UDP 乱序导致帧错位

**现象：** 流式视频块状错位。  
**原因：** UDP 不保证顺序；按到达顺序 memcpy 打乱布局。  
**修复：** 包头增加 **u32 小端 offset**，写到 `BASE+offset`。  
**协议：** `[offset:4][rgb565 payload]`，payload ≤1396 B。

---

## 8. 旋转时旁路 blur/sobel（旧架构）

**现象：** angle≠0 时窗口滤波花屏。  
**原因：** 3×3 依赖源图扫描邻域；逆映射后屏幕邻域 ≠ 源图邻域。  
**旧修复：** `bypass = ~en | rotate_active`。  
**新方案：** 目标域重构，任意角可用窗滤。见 `ROTATION_AND_EFFECTS.md`。

---

## 9. PL 网口 ARP 不通

**现象：** 网线插对、灯亮，但 PC ARP 表无条目。  
**排查：** 灯亮只说明 PHY 链路；FPGA 侧 RGMII/ARP 路径需单独验证。  
**修复：**  
1. 采用板卡已验证 `13_UDP_STACK` 的 RGMII（BUFIO+IDDR+IDELAY）与 ARP 状态机  
2. 前导码 FSM：IDLE 消费 1 个 `0x55` 后 PRE 再数 6 个再验 `0xD5`（共 7+1）  
3. 修复 arp_tx 多驱动 `st` 寄存器  

**结果：** ARP 表出现 `00-11-22-33-44-55`，ping 通。

---

## 10. ICMP ping 不通（ARP 已通）

**现象：** ARP 有条目，ping 超时。  
**根因：**  
1. **ICMP 载荷 FIFO 接错**：载荷写在专用 FIFO，发送却从 `eth_ctrl` 共享 FIFO 读（空）  
2. icmp_tx 启动过早，FIFO 未写完  

**修复：**  
- `icmp_tx` 直接读专用 `sync_fifo`  
- `icmp_tx_start_en` 延迟 20 拍再启动  
- ICMP 回包目的 MAC/IP 取自请求源（`icmp_rx` 导出 `src_mac/src_ip`）  

**结果：** `Reply from 192.168.1.10` 4/4 成功。

---

## 11. OSD 显示错误

**现象：**  
- `F` 消失，显示 `PS=59...`  
- 行尾大量 `0`（`PS=59000000`、`ANG=35900000`、`EN=000000000`）  

**根因：**  
1. 字母 **F 无字模**（索引 15 未定义）  
2. **空格被映射到字模「0」**（`glyph_idx` 默认返回 0）  

**修复：**  
- 补全 A–F 字模  
- 空格 → 空白字模（索引 31，全 0）  
- OSD 只保留三行：`FPS=xx` / `ANG=xxx` / `EN=xxxxx`  

---

## 12. 显示 4 幅画面 / 只占上半屏

**现象：** 红蓝测试图显示为每窗 4 段（红蓝红蓝），且只在上半屏。  
**根因：** **CDC FIFO 地址切片错误**

| | 错误 | 正确 |
|--|------|------|
| 写 | `{addr, data}` 35 位 | `{1'b0, addr, data}` 36 位 |
| 读 | `dout[35:17]` = `addr>>1` | `dout[34:16]` |

地址右移 1 位 → 512 宽画面压进 256 再绕回。  

**修复：** `pl_video_top` 与 `eth_udp_video_top` 两处改为正确切片。  
**结果：** 左右各「红|蓝」，竖直 2× 占满。

---

## 13. 拖影（人物移动留残影）

**现象：** 人走后原位置仍有颜色拖影。  
**原因：** UDP 边收边写显示 BRAM，旧像素未被覆盖。  
**尝试：** 双缓冲 `frame_buffer_db` — **7020 BRAM/LUT 爆资源**，实现失败。  
**尝试：** ETH 只写 DDR，显示整帧从 DDR 刷新 — 误关 `axi_frame_writer` 启动导致**全黑**；且 DDR 写路径未通时显示旧 FILL 图案。  
**现状：** 恢复 ETH 直写 BRAM（画面正确）；拖影可接受。  
**后续方案：** 收满帧后在消隐期写、降分辨率、或换更大 FPGA 做双缓冲。

---

## 14. 串口命令无效

**现象：** 发 `10000` 无反应。  
**原因：** 下载 bit 后 **PS 复位**，未重新下载 ELF。  
**修复：** 每次 program bit 后必须 **Vitis Run** PS 应用。  
**改进：** ETH 有包时自动 `src_use=1`，不依赖串口 `SRC1`。

---

## 15. 构建脚本覆盖 system_top.v

**现象：** 综合后 ETH 端口全部消失，约束报 No ports matched。  
**原因：** `build_system_axigpio.tcl` 用 Tcl 写入旧版 `system_top.v`。  
**修复：** TCL 只 `add_files`，不再生成/覆盖 `system_top.v`。

---

## 16. Vivado 2025.2 空语句语法错误

**现象：** 参考工程的 `else begin end` / 孤立 `;` 导致 xvlog 报错。  
**修复：** 迁入前用脚本只删「空 begin/end」，避免误删正常 `end;`。

---

## 快速对照表

| 症状 | 优先检查 |
|------|----------|
| 无 HDMI | 时钟、bitstream、显示器 1024×600 |
| 彩条正常、视频窄条 | AXI 拆包、行地址位宽 |
| 4 幅画面/上半屏 | CDC 地址切片 `dout[34:16]` |
| 拖影 | 边收边写 BRAM；双缓冲资源不够 |
| ping 不通 | ARP 表、网线是否 PL 口、arp_tx |
| ARP 通 ping 不通 | ICMP FIFO 接线、icmp_tx 启动延迟 |
| OSD 多 0 / 缺 F | 字模与空格映射 |
| 串口无响应 | bit 后是否 Vitis Run |
| PHY link_speed | CONFIG_LINKSPEED1000 |

# S6 · PL RGMII UDP 硬件卸载最小闭环

## 适用场景
Zynq PL 侧第二网口收 UDP 视频，PS 只做控制；完整实现 MAC/ARP/ICMP/UDP 逻辑，便于逐层定位与扩展。

## 使用方法
1. 原理图定位 PHY2 RGMII 封装脚（本板 BANK33，见 `constraints/rk_zynq7020.xdc`）
2. 链路：`rgmii_rx` → `udp_rx` / `arp_rx` / `icmp_rx` → `eth_ctrl` → `frame_reasm`
3. 发送：`arp_tx`（应答）/ `icmp_tx`（ping）/ `udp_tx`，经 `crc32_d8` 加 FCS
4. FIFO：自研 `sync_fifo`（同钟）、`dc_fifo`（跨钟）
5. 仿真：`tb_crc32` / `tb_sync_fifo` / `tb_eth_video` / `tb_udp_reasm`

## 已验证效果
- `sim/run_sim.tcl`：10/10 PASS（2025.2.1）
- 管脚来自原理图 BANK33
- 协议与上位机 offset 格式一致

## 失效条件 / 踩坑
- 综合需 `USE_IO_PRIMS=1`（IDDR/ODDR/IDELAY）+ 200 MHz IDELAYCTRL
- **前导码**：IDLE 吃掉 1 个 `0x55`，PRE 还要再数 6 个再验 `0xD5`
- **UDP 目的端口** 必须等于 `BOARD_PORT`（5001），环回测试 DES_PORT 也要 5001
- **TX 载荷握手**：`tx_req` 与当前 `tx_data` 同拍时，生产者需组合供数
- 网线必须插 **PL 口**；时钟跨域必须过 `dc_fifo`

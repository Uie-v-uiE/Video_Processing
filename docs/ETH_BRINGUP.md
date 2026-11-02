# 以太网 UDP 送视频

## 网络

| 端 | 设置 |
|----|------|
| 板卡 PS eth0 | **192.168.1.10/24**（程序写死） |
| PC 网卡 | 192.168.1.100/24（同一网段） |
| 协议 | UDP 端口 **5001** |
| 载荷 | RGB565 小端，**512×300**，一帧 307200 字节 |
| 分片 | 上位机 1400 字节/包 |

## Vitis

1. **新 Platform** ← 最新 `output\system.xsa`（已含 ENET0 + axi_gpio）  
2. BSP 勾选：**lwip**、**xuartps**（不必 xgpio）  
3. lwip 建议：  
   - `lwip_api_mode` = **RAW**  
   - `lwip_dhcp` = false（用静态 IP）  
   - `lwip_n_tx_desc` / `n_rx_desc` 可默认  
4. 源文件：当前 `sw/ps/main.c`  
5. Build → Launch  

串口应看到：

```
[NET] ip=192.168.1.10 udp=5001 frame=512x300
```

## 上位机

```bat
pip install -r sw\host\requirements.txt

:: PC 网卡设 192.168.1.100/24，网线连板卡 PS 网口

python sw\host\video_sender.py --ip 192.168.1.10 --image sim_out\src.png --fps 30
```

收满一帧后 PS 自动 `src_sel=1`，HDMI 左右应变为上位机画面。

串口 `STAT` 可看 `frames=` 计数。

## 串口命令（与以太网并行）

| 命令 | 作用 |
|------|------|
| `00111` | 效果使能（仍作用于 UDP 图） |
| `SRC0` / `SRC1` | 彩条 / DDR |
| `FILL` | 本地渐变测试 |
| `STAT` | 帧计数 |

## 排障

| 现象 | 处理 |
|------|------|
| 无 `[NET]` | lwip/BSP 未进 Platform；ENET0 未在 XSA |
| ping 不通 | IP/掩码、防火墙、是否 PS 口（非 PL eth1） |
| ping 通画面不变 | `STAT` 看 frames 是否增加；是否发满一帧 |
| 画面撕裂 | 降低 fps；确认 `Xil_DCacheFlushRange` 已调用 |
| 只有彩条 | 发 `SRC1` 或等第一帧自动切换 |

## PC 静态 IP（Windows）

设置 → 网络 → 以太网 → IPv4：`192.168.1.100` / `255.255.255.0`

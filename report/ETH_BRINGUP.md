# 以太网 UDP 送视频

## 网络（PL 卸载后）

| 端 | 设置 |
|----|------|
| **板卡 PL 网口（PHY2）** | 硬件收 UDP 5001，无需 PS IP |
| PC 网卡 | 192.168.1.100/24 |
| 协议 | UDP 端口 **5001** |
| 载荷 | RGB565 小端，**512×300**，一帧 307200 字节 |
| 包格式 | `[u32 LE offset][payload]`，payload ≤1396 B |
| **网线** | 插 **PL ETH**（不是 PS 口） |

> PS 网口可闲置，或仅作调试。应用固件已改为控制面。

## 上位机

```bat
pip install -r sw\host\requirements.txt
python sw\host\video_sender.py --ip 192.168.1.10 --image sim_out\src.png --fps 30
```

目的 IP/端口保持 192.168.1.10:5001，PL 侧按端口过滤（不强制校验目的 IP）。

## Vitis

1. Platform 可不启用 lwip（控制面无网络依赖）
2. 源码：`sw/ps/main.c`
3. UART：`00111` / `SRC1` / `STAT`

## 排障

| 现象 | 处理 |
|------|------|
| 无画面 | 是否插在 **PL 口**；`eth_rst_n` 复位完成；link 灯 |
| OSD NET 不涨 | 查 RGMII 管脚、时钟、端口 5001 |
| 画面撕裂 | 降低 fps；确认 eth 直写 BRAM 与显示 vsync |
| 仍走 PS 收包 | 旧 ELF/lwIP；改用新 `main.c` |

## PC 静态 IP（Windows）

设置 → 网络 → 以太网 → IPv4：`192.168.1.100` / `255.255.255.0`

# 以太网 UDP 送视频（第三版）

## 网络

| 端 | 设置 |
|----|------|
| **板卡 PL 网口（PHY2）** | 硬件收 UDP **5001**，无需 PS IP |
| PC 网卡 | 192.168.1.100/24 |
| 板卡 PL IP | 192.168.1.10（协议栈参数） |
| 载荷 | RGB565 小端，**512×300**，一帧 307200 B |
| 包格式 | `[u32 LE offset][payload]`，payload ≤1396 B |
| MAC | `00:11:22:33:44:55` |
| **网线** | 插 **PL ETH**，不是 PS 口 |

PS 网口可闲置。应用固件仅控制面。

---

## 协议要点

1. 每包带 **帧内字节偏移**（小端 u32），板端 `wr_addr = offset/2` 写 BRAM  
2. 乱序可拼对；丢包不重传，下一帧恢复  
3. 收满一帧后 `eth_has_frame=1`，自动切视频源（不依赖 `SRC1`）  
4. 跨钟：`dc_fifo`（eth_rxc 125M → axi_clk 100M），Gray 同步  

---

## 上位机

```bat
cd /d D:XilinxPrjproVideo_Processing\src\host
pip install -r requirements.txt
run_sender.bat
run_video.bat D:\Videos\demo.mp4
run_serial.bat COM5
```

或：

```bat
python video_sender.py --ip 192.168.1.10 --src 192.168.1.100 --fps 30 --anim
```

`--src` 绑定 PC 以太网地址，避免双网卡走 WLAN。  
详细说明：`src/host/HOST_GUIDE.md`。

---

## PS / Vitis

1. Platform：`build/system.xsa`  
2. 源码：`src/ps/main.c`（无 lwIP 依赖）  
3. UART 115200：效果位 / `SRC*` / `TH*` / `ZOOM*` / `FILL` / `STAT`  
4. **每次下载 bit 后必须再 Run ELF**（PS 被复位）

---

## 上板检查清单

1. `ping 192.168.1.10` 通  
2. 推流后 HDMI 出画  
3. OSD：`FPS` 有数；`EN` 随串口变化  
4. 右屏自动缩放循环；串口效果作用在右屏  
5. 按键改 `ANG`，左右同时旋转  

---

## 排障

| 现象 | 处理 |
|------|------|
| ping 不通 | 是否 PL 口；IP/mask；bit 是否含 ARP |
| ping 通无视频 | 端口 5001；offset 协议；`--src` 绑定 |
| 画面撕裂/拖影 | 单缓冲边写边读；降 fps 观察 |
| 右屏不缩放 | 见 ISSUES：zoom 参数 / inv 位宽 |
| 串口无效 | bit 后 Run ELF |
| 效果无效 | 确认 EN 位；效果在右窗 |

---

## PC 静态 IP（Windows）

设置 → 网络 → 以太网 → IPv4：`192.168.1.100` / `255.255.255.0`

# 上位机使用教程（UDP 视频推流 + 串口控制）

适用于 `Video_Pipeline-main` 工程，板卡 **RK-ZYNQ7020-F**，源分辨率 **512×300 RGB565**。

---

## 1. 环境准备

### 1.1 软件

| 软件 | 用途 | 安装 |
|------|------|------|
| Python 3.10+ | 推流 / 串口脚本 | 官网或 `winget install Python.Python.3.12` |
| 依赖库 | numpy / Pillow / pyserial | `pip install -r src\host\requirements.txt` |
| FFmpeg（可选） | 解码 mp4 等视频 | `winget install Gyan.FFmpeg` |
| OpenCV（可选） | 摄像头 | `pip install opencv-python` |

### 1.2 网络

1. 网线连接 **PC ↔ 板卡 PL 网口**（不是 PS 网口）
2. PC 网卡静态 IP：
   - 地址 `192.168.1.100`，子网掩码 `255.255.255.0`
3. 板卡 PL IP（RTL 固定参数）：`192.168.1.10`，UDP 端口 `5001`
4. 验证：

```bat
ping 192.168.1.10
```

能 ping 通（PL 内 ICMP 应答）再推流。

### 1.3 板卡侧

1. Vivado 下载 `build\system.bit`
2. Vitis Run 下载 PS ELF（串口命令需要；**仅看右屏自动缩放可不下载 ELF**）
3. HDMI 接 1024×600 显示器

---

## 2. 推流脚本 `video_sender.py`

路径：`src\host\video_sender.py`

### 2.1 一键脚本

| 脚本 | 作用 |
|------|------|
| `run_sender.bat` | 内置动画 @30fps |
| `run_video.bat 视频路径` | 播放本地视频 |
| `run_serial.bat COMx` | 打开串口控制台 |

```bat
cd /d D:\Xilinx\Prj\ADD\Video_Pipeline-main\src\host
run_sender.bat
run_video.bat D:\Videos\demo.mp4
run_serial.bat COM5
```

可选参数（bat）：`run_sender.bat [板卡IP] [PC_IP]`

### 2.2 命令行参数

```bat
python video_sender.py [选项]
```

| 参数 | 默认 | 说明 |
|------|------|------|
| `--ip` | 192.168.1.10 | 板卡 PL IP |
| `--port` | 5001 | UDP 端口 |
| `--src` | 192.168.1.100 | PC 网卡绑定 IP；传 `""` 走默认路由 |
| `--anim` | 自动 | 内置测试动画 |
| `--video 路径` | 无 | mp4/avi 或 `.mjpeg` |
| `--image 路径` | 无 | 静图 + 移动竖条 |
| `--webcam 序号` | 无 | 摄像头，如 `--webcam 0` |
| `--fps` | 30 | 发送帧率 |
| `--once` | 关 | 视频只播一遍 |
| `--count N` | 0 | 发送 N 帧后退出 |
| `--quiet` | 关 | 减少日志 |

### 2.3 常用示例

```bat
:: 测试动画
python video_sender.py --anim --fps 30

:: 真实视频
python video_sender.py --video D:\demo.mp4 --fps 30

:: 无 FFmpeg 时用 MJPEG
python video_sender.py --video test.mjpeg

:: 静态图
python video_sender.py --image logo.png --fps 25

:: 摄像头
python video_sender.py --webcam 0 --fps 30

:: 只发 90 帧（3 秒）
python video_sender.py --anim --count 90
```

### 2.4 生成测试 MJPEG（无需 FFmpeg）

```bat
python make_test_mjpeg.py
python video_sender.py --video test.mjpeg
```

---

## 3. UDP 协议（与 PL 对齐）

```
每包: [u32 小端 byte_offset][RGB565 载荷]
载荷长度 ≤ 1396 字节
一帧: 512 × 300 × 2 = 307200 字节 ≈ 221 包
```

- 板端 `frame_reasm` 按 offset 写入帧缓，**乱序可拼对**
- 坏包丢弃、不重传，下一帧自动恢复
- ETH 收到完整帧后自动切到视频源（不必发 `SRC1`）

---

## 4. 串口控制 `serial_ctrl.py`

| 项 | 值 |
|----|-----|
| 波特率 | 115200 8N1 |
| 结尾 | 命令后自动补 **CR+LF** |
| 查看端口 | 运行脚本不带 `--port`，或设备管理器 |

### 4.1 命令表

| 命令 | 作用 |
|------|------|
| `00000` | 关闭全部效果 |
| `10000` | 灰度 |
| `01000` | 二值化 |
| `00111` | 模糊 + Sobel + 反色 |
| `SRC0` / `SRC1` | 彩条 / 视频源 |
| `TH80` | 二值化阈值（0–255） |
| `ZOOM0` / `ZOOM1` | 右屏无极缩放 关/开（PL 侧默认常开） |
| `FILL` | PS 写 DDR 诊断色块 |
| `STAT` | 查询当前控制字 |
| `help` / `quit` | 帮助 / 退出 |

**效果位顺序（左起 bit0）：** `gray / binary / blur / sobel / invert`

### 4.2 示例

```bat
run_serial.bat COM5
> 10000
> TH120
> 00111
> SRC0
> STAT
> quit
```

单次命令：

```bat
python serial_ctrl.py --port COM5 --cmd 00111
```

---

## 5. 与右屏无极缩放配合

- 下载 bit 后右屏自动：**原始尺寸（最大）→ 缩小 → 回原始** 循环
- 左屏始终为原图（可旋转）
- 效果命令作用在**右屏缩放后的画面**上
- 选源、推流、按键旋转不受影响

推流动画时，右屏应能看到同样内容在缩放循环。

---

## 6. 故障排查

| 现象 | 处理 |
|------|------|
| ping 不通 192.168.1.10 | 检查是否插 **PL 网口**；PC IP 是否 192.168.1.100；bit 是否已下载 |
| 推流无画面 | 确认 ETH 有链路（LED1）；串口 `STAT`；降低 `--fps 15` 试 |
| 画面花屏/错位 | 网线质量；关杀软流量扫描；固定全双工 1G |
| 串口无响应 | 必须 Run PS ELF；核对 COM 号与 115200 |
| FFmpeg 报无 H.264 | `winget install Gyan.FFmpeg`，或先转 mjpeg |
| Python 找不到模块 | `pip install -r src\host\requirements.txt` |
| bat 提示 python not found | 安装 Python 并勾选 Add to PATH，或改 bat 内路径 |

---

## 7. 文件一览

```
src/host/
├── video_sender.py      UDP 推流主程序
├── serial_ctrl.py       串口控制台
├── make_test_mjpeg.py   生成 test.mjpeg
├── run_sender.bat       内置动画
├── run_video.bat        本地视频
├── run_serial.bat       串口
└── requirements.txt     Python 依赖
```

---

## 6. Node.js 工具集（第四版新增，无需 python/ffmpeg）

判据类工具用 Node 写，是因为验收 PC 上不一定有 python，而这些脚本要能直接跑在
`report/V6_BOARD_MEASUREMENT.md` 描述的复测流程里。全部走同一 UDP 协议。

| 脚本 | 作用 |
|------|------|
| `video_sender.mjs` | 推流。`--test bars\|grad\|edge\|blocks\|hold\|move\|wordid\|frameid`；`--fps` `--count` `--pace-mpbps` `--no-pace` `--dump <file>` |
| `measure_v63.mjs` | 一条命令复验：推 `frameid` → **发完** → JTAG 回读两个 bank → 打印相位判据 |
| `ddr_verify.mjs` | 只做回读与分析：`--frameid` / `--ref` / `--bank-only 0\|1`；落盘 `data/measured/ddr_dump.out` |
| `ddr_stale.mjs` | 判据核心：反解每个 16bit 字来自第几帧，输出「包内字节偏移→丢字率」「游程长度分布」「16bit 粒度错帧计数」 |
| `ddr_holemap.mjs` | 把回读结果按行段画空洞分布（早期定位用） |
| `ingress_probe.mjs` | 只灌 K 个包 + 回读，做定点注入实验 |
| `udp_sink_check.mjs` | 本机环回自检（确认协议/限速实现，不依赖板子） |

```bat
node src\host\measure_v63.mjs --fps 15 --count 200
node src\host\ddr_stale.mjs            :: 单独分析上一次落盘的 data/measured/ddr_dump.out
```

要点（都是踩过的）：
1. `--test frameid` 才能发现「逐帧丢字」；`wordid`/纯色等恒定图案只能验地址映射。
2. **发完再回读**：回读要几秒，边推边读会让每个地址段读到不同时刻的帧。
3. 回读脚本会 `rst -processor` 停住 A9（否则 `mrd` 读到 D-Cache），且**不会 `con`**；
   因此每轮复测前要重跑 `ps_jtag_boot → program_pl → set_src`。

### 6.1 分包长度：规律黑点的第一嫌疑（实测）

`MTU_PAYLOAD` 必须是 **8 的倍数**（本工程取 1392）。用 1396 时包边界落在 64bit 字中间，
打包器对同一个字分两次推送、后一次把前一次覆盖 ⇒ 每帧留下约每两个包一处的 4 字节洞，
洞里的值是 0x0000，**屏幕上就是均匀散布的黑点**。

同一块板、同一版 bit、同一次会话内的 A/B 实测（`--test frameid` 200 帧 @15fps，回读两个 bank）：

| 分包 | 最新帧 16bit 命中率 | 每帧空洞（16bit 字） | 说明 |
|---|---|---|---|
| 1396 B | 99.9% | **222（111 处 × 2）** | 规律黑点 |
| 1392 B | **100.0%** | 0~2（帧最后一个字的已知残留） | 干净 |

复现命令（`--mtu-payload` 只为做这个对照实验而存在，日常不要用非 8 倍数的值）：

```bat
node src/host/video_sender.mjs --test frameid --fps 15 --count 200 --mtu-payload 1396
node src/host/measure_v63.mjs --fps 15 --count 200        :: 1392 对照
```

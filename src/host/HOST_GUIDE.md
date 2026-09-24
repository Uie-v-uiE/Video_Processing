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
cd /d D:\Xilinx\Prj\pro\Video_Processing\src\host
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

### 4.1 命令表（V8 语法：动词 + 空格 + 参数，大小写不敏感）

固件里两套语法都收：新的是 spec §14 的写法，老写法是 `SRC0/TH80/ZOOM1/BILIN1/FRAME12/裸位串`，
`src/host/arb_handover_test.mjs` 与 `board/uart_cap_once.ps1` 这些既有工具在用它们，所以不能断。

| V8 写法 | 老写法 | 作用 |
|------|------|------|
| `pipe 11000` | `00111`（裸位串） | 效果链开关，**位序左起 bit0** = `gray / binary / blur / sobel / invert` |
| `th 80` | `TH80` | 二值化阈值（0–255） |
| `src 0` / `src 1` / `src 2` | `SRC0` / `SRC1` | 0=图卡 1=DDR(网络) 2=DDR 并起播 SD。**注意**：PS 写得动的只有 1 bit `src_sel`，"独占哪一路"仍由 PL 的 `src_mode` 四态 + 仲裁决定，模式覆盖位要到 V8-2 的控制字才有 |
| `zoom on` / `zoom off` | `ZOOM1` / `ZOOM0` | 右屏缩放开关（PL 侧默认常开）。`zoom 1.5` / `zoom auto` **语法已收、硬件未接**（缺缩放因子寄存器，V8-8） |
| `bilin on` / `bilin off` | `BILIN1` / `BILIN0` | 右屏双线性/最近邻 A-B 对照 |
| `frame 12` | `FRAME12` | 只显示第 n 帧（成功后自动切到 DDR 片源） |
| `sd` `play` `stop` `fill` | 同（大写） | 挂载 / 回放 / 停 / 写诊断色块 |
| `autoplay 0|1` | `AUTOPLAY0/1` | 关/开**上电自动挂载+播放**（只影响下一次上电，默认开） |
| `stat`（或 `status`） | `STAT` | 读回控制字与 SD 状态 |
| `help` | — | 打印三套语法 |
| `rot 45` `rot +15` `rot auto` `rot speed 1` | — | **语法已收、硬件未接**：`angle_ctrl` 现在只吃按键，PS 侧没有角度写入口（V8-2/V8-8） |
| `split 50` `split auto` `split range 20 80` `split speed 2` `split swap` | — | **语法已收、硬件未接**：整个 `split_ctrl` 是 V8-4 |
| `gamma 1.8` `gamma off` | — | **语法已收、硬件未接**：`gamma_lut` 与 LUT 写窗口是 V8-3 |
| `osd on` `osd off` | — | **语法已收、硬件未接**：OSD 现在是常显，行开关位是 V8-5 |

"语法已收、硬件未接"不是客套话：这几条命令敲下去会**明确打印缺哪个模块、规划在哪一步**，
不会静默收下。判据本身也有测试：`node src/host/uart_cmd_check.mjs`（28 条命令逐条对回声，
含 `THE`、`src 9` 这类**必须被拒**的反例，跑完还要求控制字回到初态；见 `board/uart_cmd_check_r44.txt`）。

**三个片源与"谁在屏幕上"**（#25 起的仲裁口径，别再用"拔网线"的老规矩）：
ETH 推流 > PS（SD 帧序列，PC 预转换 / FILL）> 会动的测试图卡。停流后 PL 会在几百毫秒内自动把屏幕交回 PS，
不必拔网线、不必重配 FPGA；`KEY1` **长按 0.6 s** 在 自动 → 锁 ETH → 锁 PS → 锁图卡 之间轮转
（r46 起：短按改在**松手**时发，所以长按不再顺带 +1°；按住 0.2 s 后 LED1 亮表示"正在计时"）。

### 4.2 示例

```bat
run_serial.bat COM5
> pipe 10000
> th 120
> 00111
> src 0
> stat
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
| `ingress_probe.mjs` | 只灌 K 个包 + 回读，做定点注入实验（`--packets/--pace/--tag/--dry`）。`--dry` 只算不发不碰 JTAG。**注意**：真跑时会 `rst -processor`，回放跑着之前先 `STOP`（见 ISSUES #50 的次生现象）。09-24 修好：这脚本此前一加载就 `ReferenceError`（用了没 import 的 `MEASURED`），所以 §5.4 那套方法一直没自动化 |
| `udp_sink_check.mjs` | 本机环回自检（确认协议/限速实现，不依赖板子） |
| `health_read.mjs` | JTAG 读健康快照 12 条 lane；`--json` 出机器可读对象；`--gapclr` 归零帧间隔统计 |
| `metrics.mjs` | 把两次 `health_read --json` 的差值算成抖动/丢包指标；`--selftest` 验算数本身 |
| `arb_handover_test.mjs` | **无人值守的仲裁交接判据**：静默→推流→停→再推，期间按 100 ms 密度采 lane30，输出七条 PASS/FAIL + 交回用时（毫秒）。`--selftest` 只验判据，不打板子 |

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

**v6.4 起这条不再是使用约束**：打包器按 16bit lane 驱动 `WSTRB`，上表的 1396 那一行
用 v6.4 的 bit 复测变成命中率 100.0%、空洞 0。默认仍建议 1392（少发约 0.3% 的重复 beat，
且保持「一个包不跨两个 64bit 字」，便于用包内相位分析定位问题）。

复现命令（`--mtu-payload` 只为做这个对照实验而存在）：

```bat
node src/host/video_sender.mjs --test frameid --fps 15 --count 200 --mtu-payload 1396
node src/host/measure_v63.mjs --fps 15 --count 200        :: 1392 对照
```

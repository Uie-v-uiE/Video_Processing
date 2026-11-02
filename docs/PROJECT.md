# Zynq7020 以太网视频流水线 — 工程总览

## 一句话

上位机经 PS 网口把 RGB565 帧写入 DDR，PL 做 0–359° 旋转 + 五级效果流水线，HDMI **1024×600** 左右分屏；PS 串口用 5 位 0/1 串使能效果，PL 按键改角度。

## 仓库路径

`D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline`

## 上板现象

| 阶段 | 现象 |
|------|------|
| `system.bit` + PS ELF | 串口 115200 打印 `[BOOT]` / `[NET] ip=192.168.1.10` |
| UDP 收满一帧 | 自动 `src_sel=1`，HDMI 变为上位机画面 |
| 串口 `00111` | 右半屏：模糊 + Sobel + 反色 |
| 串口 `10000` | 右半屏仅灰度 |
| KEY1 / KEY2 | 左右同步旋转 ±1°，0…359；角度≠0 时模糊/Sobel 自动旁路 |
| PL LED0 | 心跳 |
| PL LED1 | 效果非全 0 时常亮 |

## 上位机

```bat
sw\host\run_sender.bat
sw\host\run_video.bat D:\path\to\video.mp4
```

- 协议：UDP `192.168.1.10:5001`，**RGB565 小端**，**512×300**  
- 一帧 307200 字节，约 1400 字节/包  
- 源 IP 建议绑定 `192.168.1.100`  
- 真实视频需带 H.264 解码的完整 FFmpeg（scoop 路径已自动探测）

## 目录

```
docs/           架构、知识点、上板、赛事
rtl/            PL 源码
constraints/    XDC
tcl/            Vivado 2025.2 脚本
sim/            xsim TB
sw/ps/          裸机源码
sw/host/        上位机
scripts/        金标与 ROM 生成
output/         bit / 报告
```

更细的架构见 `docs/ARCHITECTURE.md`，学习要点见 `docs/KNOWLEDGE.md`。
